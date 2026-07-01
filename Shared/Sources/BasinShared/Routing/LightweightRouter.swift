import Foundation

/// Lightweight cloud-backed intent classifier for devices that don't support
/// Apple Intelligence (FoundationModels). Uses Claude Haiku via the user's existing
/// Anthropic API key — the same key as Castellum, but a cheaper/faster model and
/// a much narrower task (intent type + time extraction, not full analysis).
///
/// Privacy characteristics:
/// - Only transcript TEXT is sent. No audio, no account data, no identifiers.
/// - Uses the user's own Anthropic API key (their account, their data policy).
/// - Intended as a bridge until an on-device model replaces this entirely.
public enum LightweightRouter {

    /// The model used for lightweight routing. Haiku is the cheapest Claude tier —
    /// a single routing call costs roughly $0.000025 (a fraction of a cent).
    public static let modelID = "claude-haiku-4-5-20251001"

    // Capability → candidate tools in preference order (first connected wins).
    private static let capabilityToolMap: [String: [(toolID: String, actionType: String)]] = [
        "schedule_event":  [("apple-calendar", "create_event"),    ("google", "create_event")],
        "create_task":     [("apple-reminders", "create_reminder"), ("jira", "create_issue")],
        "log_time":        [("toggl", "create_time_entry")],
        "send_message":    [("apple-messages", "send_message"),    ("slack", "send_message")],
        "send_email":      [("apple-mail", "compose_email"),       ("google", "send_email")],
        "capture_note":    [("apple-notes", "create_note")],
        "create_document": [("google", "create_document")],
    ]

    /// Route a transcript through Claude Haiku.
    /// Returns nil if the key is empty, the network fails, or intent is ambiguous.
    public static func route(
        transcript: String,
        connectedToolIDs: Set<String>,
        apiKey: String
    ) async -> [PlannedAction]? {
        guard !apiKey.isEmpty,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let now = ISO8601DateFormatter().string(from: Date())
        let tz = TimeZone.current.identifier
        let toolList = connectedToolIDs.sorted().joined(separator: ", ")

        let systemPrompt = """
            You are the intent router for Basn, a voice-capture productivity app. \
            Given a raw voice transcript, extract the user's primary intended action and return ONLY a JSON object.

            Connected tools: \(toolList.isEmpty ? "none" : toolList)

            Capability vocabulary (exact values only):
            schedule_event | create_task | log_time | send_message | send_email | create_document | capture_note | unknown

            Rules:
            1. Capability = what the user wants to DO, not the objects they mention. \
               "look over my journals at 3pm" → schedule_event (scheduling a review), not capture_note.
            2. AM/PM for unqualified hours: 7–12 = AM, 1–6 = PM. \
               If scheduling for TODAY, the time must be after the current time.
            3. Compute concrete ISO 8601 datetimes from relative expressions \
               using the current date/time and timezone provided.
            4. Title: short phrase, strip all time references. \
               "tomorrow at 3pm to look over my journals" → "Review journals"
            5. Set highConfidence=false for: short transcripts (<5 words), \
               multiple unrelated requests, or genuinely ambiguous intent.

            Return ONLY this JSON, no prose, no markdown:
            {"capability":"<string>","title":"<string>","startTimeISO":"<ISO8601 or empty>","endTimeISO":"<ISO8601 or empty>","highConfidence":<bool>}
            """

        let userMessage = """
            Current date/time (ISO 8601): \(now)
            User timezone: \(tz)
            Transcript: "\(transcript)"
            """

        guard let result = try? await callHaiku(system: systemPrompt, user: userMessage, apiKey: apiKey),
              result.highConfidence,
              result.capability != "unknown"
        else { return nil }

        let (toolID, actionType) = resolvedTool(capability: result.capability, connectedToolIDs: connectedToolIDs)

        var params: [String: String] = [:]
        if !result.title.isEmpty        { params["title"]      = result.title }
        if !result.startTimeISO.isEmpty { params["start_time"] = result.startTimeISO }
        if !result.endTimeISO.isEmpty   { params["end_time"]   = result.endTimeISO }

        let action = PlannedAction(
            toolID: toolID,
            actionType: actionType,
            label: result.title.isEmpty ? result.capability : result.title,
            parameters: params
        )
        return [action]
    }

    // MARK: - Internal

    private struct HaikuResult: Decodable {
        var capability: String
        var title: String
        var startTimeISO: String
        var endTimeISO: String
        var highConfidence: Bool
    }

    private static func callHaiku(system: String, user: String, apiKey: String) async throws -> HaikuResult? {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 256,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        // Extract text content from Anthropic response envelope
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (envelope["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String,
              let jsonData = text.data(using: .utf8)
        else { return nil }

        return try? JSONDecoder().decode(HaikuResult.self, from: jsonData)
    }

    private static func resolvedTool(
        capability: String,
        connectedToolIDs: Set<String>
    ) -> (toolID: String, actionType: String) {
        guard let candidates = capabilityToolMap[capability] else {
            return ("", capability)
        }
        return candidates.first { connectedToolIDs.contains($0.toolID) } ?? ("", capability)
    }
}
