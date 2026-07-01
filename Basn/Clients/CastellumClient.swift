//
//  CastellumClient.swift
//  Basn
//
//  Unified single-call client: analyze transcript + plan tool actions in one
//  API round trip. Replaces the separate AnthropicClient + CastellumPlannerClient.
//
//  Key properties:
//  - Generalized system prompt (no hardcoded user/company)
//  - Prompt caching on system block and tool schemas
//  - Model tiering via SessionComplexityClassifier (Haiku default, Sonnet escalation)
//  - Accepts StructuredCapture with prompt-tagged entries and chip selections
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import BasnCore

private let castellumLog = BasnLog.app

@DependencyClient
struct CastellumClient {
    var analyzeAndPlan: @Sendable (
        StructuredCapture,
        [String],           // promptTitles for the active flow
        [SessionContext],   // recent sessions for continuity
        [Tool],             // all tools (connected + disconnected)
        [Workflow],         // enabled workflows
        String              // Anthropic API key
    ) async throws -> (SessionAnalysis, ExecutionPlan) = { capture, _, _, _, _, _ in
        throw CastellumError.noAPIKey
    }
}

extension CastellumClient: DependencyKey {
    static var liveValue: Self {
        .init(analyzeAndPlan: { capture, promptTitles, sessionContext, tools, workflows, apiKey in
            guard !apiKey.isEmpty else { throw CastellumError.noAPIKey }

            let connectedTools = tools.filter(\.isAvailableForRouting)
            let connectedIDs = Set(connectedTools.map(\.id))

            // Chip selections are explicit routing signals — prefer those tool schemas.
            let chipToolIDs = chipSelectedToolIDs(from: capture)
            let candidateIDs = chipToolIDs.isEmpty ? connectedIDs : chipToolIDs.intersection(connectedIDs)
            let matchedIDs = candidateIDs.isEmpty ? connectedIDs : candidateIDs

            // Build tool schemas (JSON definitions first, registry fallback)
            var toolSchemas: [[String: Any]] = []
            for toolID in matchedIDs {
                if let spec = ToolDefinitionLoader.load(toolID) {
                    let tool = connectedTools.first { $0.id == toolID }
                    toolSchemas.append(contentsOf: ToolDefinitionLoader.claudeSchemas(for: spec, tool: tool))
                }
            }
            if toolSchemas.isEmpty {
                toolSchemas = ToolActionRegistry.claudeToolSchemas(for: matchedIDs)
            }

            // Select model based on session complexity
            let model = SessionComplexityClassifier.classify(
                wordCount: capture.wordCount,
                connectedToolCount: connectedTools.count,
                rawText: capture.rawText
            ).modelID

            let serviceContext = buildServiceContext(tools: connectedTools, matchedIDs: matchedIDs)
            let userMessage = buildUserMessage(
                capture: capture,
                promptTitles: promptTitles,
                sessionContext: sessionContext,
                serviceContext: serviceContext,
                workflows: workflows.filter(\.isEnabled)
            )

            let (rawData, content) = try await callClaude(
                model: model,
                tools: toolSchemas,
                userMessage: userMessage,
                apiKey: apiKey
            )

            #if DEBUG
            if DebugCaptureArchive.isEnabled {
                recordScenario(
                    capture: capture,
                    connectedToolIDs: connectedIDs,
                    responseData: rawData
                )
            }
            #endif

            let (analysis, actions) = parseResponse(content, captureID: capture.captureID)
            let plan = ExecutionPlan(captureID: capture.captureID, actions: actions, modelUsed: model)
            return (analysis, plan)
        })
    }
}

extension DependencyValues {
    var castellumClient: CastellumClient {
        get { self[CastellumClient.self] }
        set { self[CastellumClient.self] = newValue }
    }
}

// MARK: - Errors

enum CastellumError: LocalizedError {
    case noAPIKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Anthropic API key configured"
        case .apiError(let msg): return "Castellum API error: \(msg)"
        }
    }
}

// MARK: - System Prompt

private let castellumSystemPrompt = """
You are Castellum, Basn's action planner. Basn is a voice capture app that turns spoken \
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
- Only call tools that appear in the provided tool schema — NEVER suggest connecting other services
- Tools prefixed with "apple-" are native device integrations (Calendar, Reminders, Notes, etc.) — \
use them when available for their respective action types
- For calendar events (apple-calendar_create_event): infer start_time from natural language \
("tomorrow" = next day 09:00, "next Monday" = that Monday 09:00, "this afternoon" = today 14:00). \
Set end_time to 1 hour after start_time unless stated otherwise
- Fill parameters as specifically as possible from what was said
- For Jira, match tasks to the most relevant project (fuzzy match — voice may misspell names)
- For Slack, use #general unless a specific channel is mentioned
- For Toggl, estimate duration from context (default 30 minutes if unclear)
- Do not speculate — if something is unclear, skip that action
"""

// MARK: - HTTP

private func callClaude(
    model: String,
    tools: [[String: Any]],
    userMessage: String,
    apiKey: String
) async throws -> (data: Data, content: [[String: Any]]) {
    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
        throw CastellumError.apiError("Invalid URL")
    }

    // Cache the static system prompt across sessions
    let systemBlock: [String: Any] = [
        "type": "text",
        "text": castellumSystemPrompt,
        "cache_control": ["type": "ephemeral"]
    ]

    // Cache the tool schema list (last tool carries the cache_control marker)
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
        "messages": [["role": "user", "content": userMessage]]
    ]
    if !cachedTools.isEmpty {
        requestBody["tools"] = cachedTools
    }

    let body = try JSONSerialization.data(withJSONObject: requestBody)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
    request.httpBody = body
    request.timeoutInterval = 45

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
        castellumLog.error("Castellum API error: \(preview)")
        throw CastellumError.apiError(preview)
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let content = json["content"] as? [[String: Any]] else {
        throw CastellumError.apiError("Unexpected response shape")
    }

    if let usage = json["usage"] as? [String: Any] {
        let input = usage["input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
        castellumLog.info("Castellum [\(model)] input=\(input) cache_read=\(cacheRead) cache_write=\(cacheWrite)")
    }

    return (data, content)
}

// MARK: - Response parsing

private func parseResponse(_ content: [[String: Any]], captureID: String) -> (SessionAnalysis, [PlannedAction]) {
    let result = CastellumResponseParser.parse(content, captureID: captureID) { toolID, actionType in
        ToolActionRegistry.action(toolID: toolID, actionType: actionType)?.displayName
    }
    castellumLog.info("Castellum planned \(result.1.count) actions for capture \(captureID)")
    return result
}

// MARK: - User message

private func buildUserMessage(
    capture: StructuredCapture,
    promptTitles: [String],
    sessionContext: [SessionContext],
    serviceContext: String,
    workflows: [Workflow]
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
        for (i, title) in promptTitles.enumerated() { msg += "\n  \(i). \(title)" }
    }

    if !workflows.isEmpty {
        msg += "\n\nActive workflow instructions:"
        for w in workflows { msg += "\n- \(w.name): \(w.instruction)" }
    }

    if !serviceContext.isEmpty { msg += "\n\nService context:\(serviceContext)" }

    msg += "\n\nCapture:\n\(formatEntries(capture.entries))"
    return msg
}

private func formatEntries(_ entries: [CaptureEntry]) -> String {
    var out = ""
    var currentPromptIndex: Int? = -1  // sentinel so first entry always prints header

    for entry in entries {
        if entry.promptIndex != currentPromptIndex {
            currentPromptIndex = entry.promptIndex
            if let title = entry.promptTitle {
                out += "\n[\(title)]"
            } else {
                out += "\n[no prompt]"
            }
        }
        if !entry.chips.isEmpty { out += "\n  chips: \(entry.chips.joined(separator: ", "))" }
        if !entry.sentence.isEmpty { out += "\n  \"\(entry.sentence)\"" }
    }
    return out
}

// MARK: - Helpers

private func buildServiceContext(tools: [Tool], matchedIDs: Set<String>) -> String {
    var ctx = ""
    if matchedIDs.contains("jira"), let jiraTool = tools.first(where: { $0.id == "jira" }) {
        let projects = JiraActionClient.cachedProjects(tool: jiraTool)
        if !projects.isEmpty {
            ctx += "\nJira projects:\n"
            for p in projects { ctx += "- \(p.key): \(p.name)\n" }
        }
    }
    return ctx
}

#if DEBUG
// MARK: - Scenario recorder
//
// Toggle via the DebugBar "Archive captures" switch (debug builds only). Each
// capture's scenario.json lands in its dated archive folder under:
//   ~/Library/Containers/com.lyra.basn.debug/Data/Documents/BasnCaptures/<date>/<time-id>/
// alongside audio.wav and the other artifacts written by TranscriptionFeature.
// See docs/plans/2026-06-27-debug-capture-archive-and-audio-e2e-tests.md.
private func recordScenario(
    capture: StructuredCapture,
    connectedToolIDs: Set<String>,
    responseData: Data
) {
    guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
          let content = json["content"] as? [[String: Any]],
          let folder = DebugCaptureArchive.folderURL(
              captureID: capture.captureID, timestamp: capture.timestamp
          )
    else { return }

    let blocks: [[String: Any]] = content.compactMap { block in
        guard let type = block["type"] as? String else { return nil }
        var out: [String: Any] = ["type": type]
        if let text = block["text"] as? String { out["text"] = text }
        if let name = block["name"] as? String { out["name"] = name }
        if let input = block["input"] as? [String: Any] { out["input"] = input }
        return out
    }

    // Built as a dictionary (not CaptureScenario) to preserve the heterogeneous
    // tool_use `input` values verbatim for parse-layer fixtures.
    let scenario: [String: Any] = [
        "name": "Recorded \(capture.captureID.prefix(8))",
        "description": "Auto-exported. Edit name/description and fill in expected.actions.",
        "rawText": capture.rawText,
        "connectedToolIDs": Array(connectedToolIDs).sorted(),
        "routedVia": "castellum",
        "rawContentBlocks": blocks,
        "audioFile": "audio.wav",
        "expectedTranscript": capture.rawText,
        "expected": ["actions": [[String: Any]]()]
    ]

    let url = folder.appendingPathComponent("scenario.json")
    if let data = try? JSONSerialization.data(withJSONObject: scenario, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: url)
        castellumLog.info("[ScenarioRecorder] Exported to \(url.path)")
    }
}

/// Record a heuristic-path capture into its archive folder. Unlike Castellum
/// recordings, `expected.actions` is pre-populated from the matched actions —
/// no manual fill-in needed. Called from TranscriptionFeature's heuristic branch.
func recordHeuristicScenario(
    captureID: String,
    timestamp: Date,
    rawText: String,
    connectedToolIDs: Set<String>,
    actions: [PlannedAction]
) {
    guard DebugCaptureArchive.isEnabled else { return }

    let scenario = CaptureScenario(
        name: "Recorded \(captureID.prefix(8))",
        description: "Auto-exported heuristic capture. Edit name/description as needed.",
        rawText: rawText,
        connectedToolIDs: Array(connectedToolIDs).sorted(),
        routedVia: .heuristic,
        rawContentBlocks: nil,
        expected: .init(actions: actions.map {
            .init(toolID: $0.toolID, actionType: $0.actionType, parameters: $0.parameters)
        }),
        audioFile: "audio.wav",
        expectedTranscript: rawText
    )
    DebugCaptureArchive.writeScenario(scenario, captureID: captureID, timestamp: timestamp)
}
#endif

private func chipSelectedToolIDs(from capture: StructuredCapture) -> Set<String> {
    let knownToolChipIDs: Set<String> = ["jira", "github", "slack", "toggl", "google", "wave"]
    return capture.entries.reduce(into: Set<String>()) { result, entry in
        entry.chips.forEach { if knownToolChipIDs.contains($0) { result.insert($0) } }
    }
}
