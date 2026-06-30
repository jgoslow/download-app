//
//  IOSCastellumClient.swift
//  Basn iOS
//
//  Native, serverless Castellum on the phone: builds the Claude request (system
//  prompt + tool schemas + context-injected user message), calls the API with
//  the user's own key, and parses the response. Reuses the shared
//  CastellumResponseParser / SessionComplexityClassifier / models from
//  BasinShared and the tool-definition loaders already compiled into iOS.
//
//  No custom backend involved — see docs/reference/castellum-native-architecture.md.
//

import Foundation
import BasinShared
import os

enum IOSCastellumClient {

    enum CastellumError: LocalizedError {
        case noAPIKey
        case apiError(String)
        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No Anthropic API key configured"
            case .apiError(let m): return "Castellum API error: \(m)"
            }
        }
    }

    private static let log = Logger(subsystem: "com.lyra.basn", category: "ios-castellum")

    static func analyzeAndPlan(
        capture: StructuredCapture,
        promptTitles: [String],
        context: [SessionContext],
        tools: [Tool],
        workflows: [Workflow],
        apiKey: String
    ) async throws -> (SessionAnalysis, ExecutionPlan) {
        guard !apiKey.isEmpty else { throw CastellumError.noAPIKey }

        // Hybrid routing: connected tools contribute their REAL (high-fidelity)
        // schemas; every capability NOT covered by a connected tool contributes a
        // GENERIC function so the capture can still surface "you could do X —
        // connect a tool." The prompt scales with the connected set + the fixed
        // capability vocabulary, never the full catalog.
        let connectedTools = tools.filter(\.isConnected)
        let connectedIDs = Set(connectedTools.map(\.id))

        var toolSchemas: [[String: Any]] = []
        for toolID in connectedIDs {
            if let spec = ToolDefinitionLoader.load(toolID) {
                let tool = connectedTools.first { $0.id == toolID }
                toolSchemas.append(contentsOf: ToolDefinitionLoader.claudeSchemas(for: spec, tool: tool))
            }
        }
        let covered = CapabilityResolver.coveredCapabilities(connectedToolIDs: connectedIDs)
        let uncovered = Capabilities.all.map(\.id).filter { !covered.contains($0) }
        toolSchemas += Capabilities.claudeSchemas(for: uncovered)

        let model = SessionComplexityClassifier.classify(
            wordCount: capture.wordCount,
            connectedToolCount: connectedTools.count,
            rawText: capture.rawText
        ).modelID

        let userMessage = buildUserMessage(
            capture: capture, promptTitles: promptTitles,
            sessionContext: context, workflows: workflows.filter(\.isEnabled)
        )

        let content = try await callClaude(model: model, tools: toolSchemas, userMessage: userMessage, apiKey: apiKey)

        // Split generic capability calls (cap_*) from tool-scoped ones. Generic
        // calls become unresolved actions (empty toolID) that the plan UI renders
        // with a "connect a tool" link; tool-scoped calls parse as executable.
        var toolScopedContent: [[String: Any]] = []
        var genericActions: [PlannedAction] = []
        for block in content {
            if (block["type"] as? String) == "tool_use",
               let name = block["name"] as? String,
               let capID = Capabilities.capabilityID(fromFunctionName: name) {
                let params = (block["input"] as? [String: Any])?.mapValues { "\($0)" } ?? [:]
                genericActions.append(PlannedAction(
                    toolID: "", actionType: capID,
                    label: Capabilities.byID(capID)?.title ?? capID,
                    parameters: params
                ))
            } else {
                toolScopedContent.append(block)
            }
        }

        let (analysis, connectedActions) = CastellumResponseParser.parse(toolScopedContent, captureID: capture.captureID) { toolID, actionType in
            ToolActionRegistry.action(toolID: toolID, actionType: actionType)?.displayName
        }
        let actions = connectedActions + genericActions
        log.info("iOS Castellum planned \(connectedActions.count) executable + \(genericActions.count) generic action(s) for \(capture.captureID, privacy: .public)")
        return (analysis, ExecutionPlan(captureID: capture.captureID, actions: actions, modelUsed: model))
    }

    // MARK: - HTTP

    private static func callClaude(model: String, tools: [[String: Any]], userMessage: String, apiKey: String) async throws -> [[String: Any]] {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw CastellumError.apiError("Invalid URL")
        }
        let systemBlock: [String: Any] = [
            "type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]
        ]
        var cachedTools = tools
        if !cachedTools.isEmpty {
            var last = cachedTools[cachedTools.count - 1]
            last["cache_control"] = ["type": "ephemeral"]
            cachedTools[cachedTools.count - 1] = last
        }
        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": [systemBlock],
            "messages": [["role": "user", "content": userMessage]],
        ]
        if !cachedTools.isEmpty { requestBody["tools"] = cachedTools }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
            log.error("iOS Castellum API error: \(preview, privacy: .public)")
            throw CastellumError.apiError(preview)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw CastellumError.apiError("Unexpected response shape")
        }
        return content
    }

    // MARK: - Prompt

    private static func buildUserMessage(
        capture: StructuredCapture, promptTitles: [String],
        sessionContext: [SessionContext], workflows: [Workflow]
    ) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        var msg = "Flow: \(capture.flowID)\nRecorded: \(fmt.string(from: capture.timestamp))\nDuration: \(Int(capture.durationSeconds))s"

        if !sessionContext.isEmpty {
            msg += "\n\nRecent sessions (for continuity):"
            for ctx in sessionContext {
                msg += "\n- [\(ctx.timestamp ?? "unknown")] \(ctx.summary ?? "no summary")"
                if let mood = ctx.moodTag { msg += " (mood: \(mood))" }
                if let tasks = ctx.tasks, !tasks.isEmpty { msg += " | tasks: \(tasks.joined(separator: ", "))" }
            }
        }
        if !promptTitles.isEmpty {
            msg += "\n\nGuided prompts:"
            for (i, t) in promptTitles.enumerated() { msg += "\n  \(i). \(t)" }
        }
        if !workflows.isEmpty {
            msg += "\n\nActive workflow instructions:"
            for w in workflows { msg += "\n- \(w.name): \(w.instruction)" }
        }
        msg += "\n\nCapture:\n\(formatEntries(capture.entries))"
        return msg
    }

    private static func formatEntries(_ entries: [CaptureEntry]) -> String {
        var out = ""
        var current: Int? = -1
        for entry in entries {
            if entry.promptIndex != current {
                current = entry.promptIndex
                out += entry.promptTitle.map { "\n[\($0)]" } ?? "\n[no prompt]"
            }
            if !entry.chips.isEmpty { out += "\n  chips: \(entry.chips.joined(separator: ", "))" }
            if !entry.sentence.isEmpty { out += "\n  \"\(entry.sentence)\"" }
        }
        return out
    }

    private static let systemPrompt = """
    You are Castellum, Basin's action planner. Basin is a voice capture app that turns spoken \
    ideas, tasks, and notes into actions across connected tools.

    Given a voice capture (which may include per-prompt context and chip selections from a guided \
    flow), do two things in one response:

    1. Return a JSON analysis as the FIRST content block (text type):
    {
      "summary": "one sentence capturing the main point",
      "mood_tag": "one word for emotional tone, or null",
      "tasks": ["actionable item 1", "actionable item 2"],
      "routing": ["jira", "calendar", "notes", "slack", "email"],
      "delegations": ["Person: specific thing to delegate"],
      "integrations": ["jira", "toggl", "slack", "email", "calendar", "docs", "wave", "github"],
      "prompts_addressed": [0, 2]
    }

    2. Call tool_use functions for each concrete action to take.

    Rules:
    - Return ONLY valid JSON in the text block, no markdown or explanation
    - integrations: only list services directly relevant to the capture content
    - tasks: concrete and actionable
    - delegations: name the person when possible
    - prompts_addressed: 0-based indices of guided prompts clearly addressed
    - Chip selections in the capture are confirmed user intent — treat as explicit routing signals
    - Only call tools clearly warranted by the content
    - Fill parameters as specifically as possible from what was said
    - For Jira, match tasks to the most relevant project (fuzzy match — voice may misspell names)
    - For Slack, use #general unless a specific channel is mentioned
    - For Toggl, estimate duration from context (default 30 minutes if unclear)
    - Do not speculate — if something is unclear, skip that action
    """
}
