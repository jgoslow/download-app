//
//  CastellumPlannerClient+Live.swift
//  Basin
//
//  Live implementation of the Castellum planner. Takes a SessionAnalysis,
//  matches it against connected tools, and calls Claude with tool_use
//  to fill in action parameters.
//

import Foundation
import HexCore

private let plannerLogger = HexLog.app

extension CastellumPlannerClient {

    static func live() -> Self {
        .init(createPlan: { analysis, captureID, connectedTools, enabledChannels, apiKey in
            guard !apiKey.isEmpty else {
                throw PlannerError.noAPIKey
            }

            // 1. Match analysis integrations to connected tools
            let connectedIDs = Set(connectedTools.filter(\.isConnected).map(\.id))
            let matchedIntegrations = analysis.integrations.filter { connectedIDs.contains($0.rawValue) }

            guard !matchedIntegrations.isEmpty else {
                plannerLogger.info("Castellum: no connected tools match integrations \(analysis.integrations.map(\.rawValue))")
                return ExecutionPlan(captureID: captureID, actions: [])
            }

            // 2. Build tool schemas for matched integrations
            //    Try JSON definitions first, fall back to hardcoded registry
            let matchedToolIDs = Set(matchedIntegrations.map(\.rawValue))
            var toolSchemas: [[String: Any]] = []
            for toolID in matchedToolIDs {
                if let spec = ToolDefinitionLoader.load(toolID) {
                    toolSchemas.append(contentsOf: ToolDefinitionLoader.claudeSchemas(for: spec))
                }
            }
            if toolSchemas.isEmpty {
                toolSchemas = ToolActionRegistry.claudeToolSchemas(for: matchedToolIDs)
            }

            guard !toolSchemas.isEmpty else {
                return ExecutionPlan(captureID: captureID, actions: [])
            }

            // 3. Gather service context from connected tools (e.g., Jira projects)
            let serviceContext = buildServiceContext(tools: connectedTools, matchedIDs: matchedToolIDs)

            // 4. Build the planning prompt
            let planningPrompt = buildPlanningPrompt(analysis: analysis, serviceContext: serviceContext)

            // 5. Call Claude with tool_use
            let actions = try await callClaudeWithTools(
                prompt: planningPrompt,
                tools: toolSchemas,
                apiKey: apiKey
            )

            plannerLogger.info("Castellum planned \(actions.count) actions for capture \(captureID)")

            return ExecutionPlan(captureID: captureID, actions: actions)
        })
    }
}

// MARK: - Errors

enum PlannerError: LocalizedError {
    case noAPIKey
    case apiError(String)
    case noToolCalls

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Anthropic API key configured"
        case .apiError(let msg): return "Planning API error: \(msg)"
        case .noToolCalls: return "Claude did not suggest any actions"
        }
    }
}

// MARK: - Claude API Call

private func callClaudeWithTools(
    prompt: String,
    tools: [[String: Any]],
    apiKey: String
) async throws -> [PlannedAction] {
    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
        throw PlannerError.apiError("Invalid API URL")
    }

    let requestBody: [String: Any] = [
        "model": "claude-sonnet-4-6",
        "max_tokens": 2048,
        "system": planningSystemPrompt,
        "tools": tools,
        "messages": [
            ["role": "user", "content": prompt]
        ]
    ]

    let body = try JSONSerialization.data(withJSONObject: requestBody)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpBody = body
    request.timeoutInterval = 30

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
        plannerLogger.error("Castellum planner API error: \(preview)")
        throw PlannerError.apiError(preview)
    }

    // Parse response — look for tool_use content blocks
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let content = json["content"] as? [[String: Any]] else {
        throw PlannerError.apiError("Unexpected response shape")
    }

    var actions: [PlannedAction] = []

    for block in content {
        guard let type = block["type"] as? String, type == "tool_use",
              let toolCallName = block["name"] as? String,
              let input = block["input"] as? [String: Any] else {
            continue
        }

        // Parse tool call name: "jira_create_issue" → toolID: "jira", actionType: "create_issue"
        let parts = toolCallName.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { continue }

        let toolID = String(parts[0])
        let actionType = String(parts[1])

        // Convert input to [String: String] for storage
        var parameters: [String: String] = [:]
        for (key, value) in input {
            if let str = value as? String {
                parameters[key] = str
            } else if let num = value as? NSNumber {
                parameters[key] = "\(num)"
            } else if let arr = value as? [String] {
                parameters[key] = arr.joined(separator: ", ")
            }
        }

        // Build a human-readable label
        let actionDef = ToolActionRegistry.action(toolID: toolID, actionType: actionType)
        let toolName = actionDef?.displayName ?? actionType.replacingOccurrences(of: "_", with: " ").capitalized
        let summary = parameters["summary"] ?? parameters["title"] ?? parameters["text"] ?? parameters["description"] ?? ""
        let label = summary.isEmpty ? toolName : "\(toolName): \(summary.prefix(60))"

        actions.append(PlannedAction(
            toolID: toolID,
            actionType: actionType,
            label: label,
            parameters: parameters
        ))
    }

    // If Claude responded with text only (no tool calls), check if it explained why
    if actions.isEmpty {
        if let textBlock = content.first(where: { $0["type"] as? String == "text" }),
           let text = textBlock["text"] as? String {
            plannerLogger.info("Castellum: Claude responded with text instead of tools: \(text.prefix(100))")
        }
    }

    return actions
}

// MARK: - Prompts

private let planningSystemPrompt = """
You are the Castellum — Basin's action execution engine. Given a voice capture analysis, \
use the available tools to create concrete actions the user can execute.

Rules:
- Only call tools that are directly relevant to the tasks and integrations identified.
- Fill in parameters as specifically as possible based on the analysis.
- If a task mentions a person (e.g., "Diego"), set them as the assignee.
- Use the service context provided to select the correct project, channel, etc.
- For Jira, match the task to the most relevant project from the project list. \
  Use fuzzy matching — voice transcription may misspell project names \
  (e.g., "Taka" likely means project "TACA").
- For Slack, use #general unless a specific channel is mentioned.
- For Toggl, estimate duration from context (default 30 minutes if unclear).
- Do NOT call tools speculatively — only when the analysis clearly indicates the action.
- You may call multiple tools in a single response.
"""

/// Build service context string from cached tool metadata (projects, channels, etc.)
private func buildServiceContext(tools: [Tool], matchedIDs: Set<String>) -> String {
    var context = ""

    if matchedIDs.contains("jira"), let jiraTool = tools.first(where: { $0.id == "jira" }) {
        let projects = JiraActionClient.cachedProjects(tool: jiraTool)
        if !projects.isEmpty {
            context += "\nJira projects available:\n"
            for proj in projects {
                context += "- \(proj.key): \(proj.name)\n"
            }
        }
    }

    // TODO: Add Slack channels, Toggl projects, etc. as we cache them

    return context
}

private func buildPlanningPrompt(analysis: SessionAnalysis, serviceContext: String = "") -> String {
    var prompt = "Voice capture analysis:\n"
    prompt += "Summary: \(analysis.summary)\n"

    if !analysis.tasks.isEmpty {
        prompt += "\nTasks identified:\n"
        for task in analysis.tasks {
            prompt += "- \(task)\n"
        }
    }

    if !analysis.delegations.isEmpty {
        prompt += "\nDelegations:\n"
        for delegation in analysis.delegations {
            prompt += "- \(delegation)\n"
        }
    }

    if !analysis.routing.isEmpty {
        prompt += "\nRouting: \(analysis.routing.map(\.rawValue).joined(separator: ", "))\n"
    }

    if !analysis.integrations.isEmpty {
        prompt += "Integrations needed: \(analysis.integrations.map(\.rawValue).joined(separator: ", "))\n"
    }

    if let mood = analysis.moodTag {
        prompt += "Mood: \(mood)\n"
    }

    if !serviceContext.isEmpty {
        prompt += "\nService context:\(serviceContext)"
    }

    prompt += "\nPlease create the appropriate actions using the available tools."
    return prompt
}
