//
//  AnthropicClient.swift
//  Basin
//
//  Phase 2: one post-session call to Claude that reads the transcript and
//  returns a structured SessionAnalysis (summary, tasks, routing, mood).
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let anthropicLogger = HexLog.app

@DependencyClient
struct AnthropicClient {
    /// Analyze a completed session transcript. Returns nil if no API key is configured.
    /// promptTitles: ordered list of prompt titles for the flow, used to determine which were addressed.
    /// sessionContext: summaries of recent sessions of the same type, for continuity.
    var analyze: @Sendable (Session, String, [String], [SessionContext]) async -> SessionAnalysis? = { _, _, _, _ in nil }
}

extension AnthropicClient: DependencyKey {
    static var liveValue: Self {
        .init(analyze: { session, apiKey, promptTitles, sessionContext in
            guard !apiKey.isEmpty else { return nil }

            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

            let prompt = buildPrompt(for: session, promptTitles: promptTitles, context: sessionContext)

            let requestBody: [String: Any] = [
                "model": "claude-sonnet-4-6",
                "max_tokens": 1024,
                "system": systemPrompt,
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]

            do {
                let body = try JSONSerialization.data(withJSONObject: requestBody)

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "content-type")
                request.httpBody = body
                request.timeoutInterval = 30

                let (data, response) = try await URLSession.shared.data(for: request)

                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
                    anthropicLogger.error("Anthropic API error: \(preview)")
                    return nil
                }

                // Extract the text content from the Anthropic response envelope
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = json["content"] as? [[String: Any]],
                      let text = content.first?["text"] as? String else {
                    anthropicLogger.error("Unexpected Anthropic response shape")
                    return nil
                }

                // Parse the JSON that Claude returned
                let analysisData = text.data(using: .utf8) ?? Data()
                let decoder = JSONDecoder()
                let analysis = try decoder.decode(SessionAnalysis.self, from: analysisData)
                anthropicLogger.info("Session analysis complete: \(analysis.summary)")
                return analysis
            } catch {
                anthropicLogger.error("AnthropicClient error: \(error.localizedDescription)")
                return nil
            }
        })
    }
}

extension DependencyValues {
    var anthropic: AnthropicClient {
        get { self[AnthropicClient.self] }
        set { self[AnthropicClient.self] = newValue }
    }
}

// MARK: - Prompts

private let systemPrompt = """
You are a personal assistant for Jonas, a developer and founder of Lyra Designs. \
You analyze voice transcripts from his Basin app — a personal voice capture tool — \
and return structured JSON.

Return ONLY valid JSON with exactly these fields, no markdown, no explanation:
{
  "summary": "one sentence capturing the main point",
  "mood_tag": "one word for emotional tone, or null if neutral/work-focused",
  "tasks": ["actionable item 1", "actionable item 2"],
  "routing": ["jira", "calendar", "notes", "slack", "email", "cns"],
  "delegations": ["Diego: specific thing to delegate"],
  "integrations": ["jira", "toggl", "slack", "email", "calendar", "wave", "github"],
  "prompts_addressed": [0, 2, 4]
}

routing should only include relevant destinations. tasks should be concrete and actionable. \
delegations should name the person when possible (Diego or Josh for work items). \
integrations should list external services that would be needed to act on the session content — \
only include ones that are clearly relevant (e.g. "jira" if tickets are mentioned, \
"toggl" if time tracking is discussed, "email" if emails need sending). \
prompts_addressed should list the indices (0-based) of guided prompts that the user addressed \
in their transcript. Only include prompts that were clearly covered. If no prompt titles \
are provided, return an empty array.
"""

private func buildPrompt(for session: Session, promptTitles: [String], context: [SessionContext]) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
    let timeStr = formatter.string(from: session.timestamp)

    var prompt = """
    Flow: \(session.flowID)
    Recorded: \(timeStr)
    Duration: \(Int(session.durationSeconds))s
    """

    if !context.isEmpty {
        prompt += "\n\nRecent sessions of this type (for continuity):"
        for ctx in context {
            prompt += "\n- [\(ctx.timestamp ?? "unknown")] \(ctx.summary ?? "no summary")"
            if let mood = ctx.moodTag { prompt += " (mood: \(mood))" }
            if let tasks = ctx.tasks, !tasks.isEmpty {
                prompt += " | tasks: \(tasks.joined(separator: ", "))"
            }
        }
    }

    if !promptTitles.isEmpty {
        prompt += "\n\nGuided prompts for this session type:"
        for (i, title) in promptTitles.enumerated() {
            prompt += "\n  \(i). \(title)"
        }
    }

    prompt += "\n\nTranscript:\n\(session.rawText)"

    return prompt
}
