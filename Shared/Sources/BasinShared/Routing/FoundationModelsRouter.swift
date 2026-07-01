import Foundation

#if canImport(FoundationModels)
import FoundationModels

// @Generable requires a compile-time import of FoundationModels, so the struct
// lives inside the canImport block. The public enum is defined unconditionally
// below so call sites need no conditional compilation of their own.
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct _IntentResult {
    @Guide(description: "Primary action type. One of: schedule_event, create_task, log_time, send_message, send_email, create_document, capture_note, unknown")
    var capability: String

    @Guide(description: "Short, human-readable title — not the raw transcript. E.g. 'Review journals', 'Call with Sarah', 'Fix login bug'.")
    var title: String

    @Guide(description: "ISO 8601 start datetime if a specific time was mentioned, otherwise empty string. Infer from 'tomorrow between 3 and 5', 'at 2pm next Tuesday', etc.")
    var startTimeISO: String

    @Guide(description: "ISO 8601 end datetime if a time range was mentioned, otherwise empty string.")
    var endTimeISO: String

    @Guide(description: "True when the intent is unambiguous. False for vague transcripts or multiple unrelated requests.")
    var highConfidence: Bool
}
#endif

// MARK: - Public Router

/// On-device intent classifier backed by Apple Intelligence (FoundationModels, iOS 26+/macOS 26+).
/// Inserted between HeuristicRouter and Castellum in the routing pipeline.
/// Always available to callers — returns nil when the device or OS doesn't support
/// Apple Intelligence, keeping the fallthrough to Castellum transparent.
public enum FoundationModelsRouter {

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

    /// Route a transcript through the on-device language model.
    /// Returns a single-element array on success, nil on failure or fallthrough.
    public static func route(
        transcript: String,
        connectedToolIDs: Set<String>
    ) async -> [PlannedAction]? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return await _route(transcript: transcript, connectedToolIDs: connectedToolIDs)
        }
#endif
        return nil
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func _route(
        transcript: String,
        connectedToolIDs: Set<String>
    ) async -> [PlannedAction]? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let now = ISO8601DateFormatter().string(from: Date())
        let tz = TimeZone.current.identifier

        // List connected tools so the model can make grounded capability decisions.
        let toolList = connectedToolIDs.sorted().joined(separator: ", ")

        let systemPrompt = """
            You are the intent router for Basn, a voice-capture productivity app on Apple platforms. \
            Your job: given a raw voice transcript, extract the single most likely action the user wants to perform.

            Connected tools available to the user: \(toolList.isEmpty ? "none" : toolList)

            Capability vocabulary (use exactly these values):
            - schedule_event   → create a calendar event (use when user wants to block time, schedule a meeting, add something to their calendar)
            - create_task      → create a reminder or task (use when user says "remind me", "don't forget", "add a task")
            - log_time         → log time to a timer (use when user mentions tracking hours, starting a timer, logging work)
            - send_message     → send a chat message (Slack, iMessage)
            - send_email       → compose/send an email
            - capture_note     → save a free-form note (use when user explicitly says "take a note", "jot this down", "write this down")
            - create_document  → create a document or doc
            - unknown          → anything that doesn't clearly fit the above

            Rules:
            1. The capability is determined by what the user wants to DO, not by the objects they mention. \
               "look over my journals tomorrow at 3" → the action is schedule_event, not capture_note, \
               because the user is scheduling a review session, not creating a note.
            2. For time references ("tomorrow between 3 and 5", "next Tuesday at 2", "in an hour"), \
               compute concrete ISO 8601 datetimes in the user's timezone. \
               Assume PM for unqualified hours 1–7 in personal/professional scheduling contexts.
            3. AM/PM disambiguation for unqualified hours (no "am"/"pm" spoken):
               - Hours 7–12 → AM (morning)
               - Hours 1–6  → PM (afternoon/evening)
               If scheduling for TODAY (same date as current date/time), the resolved time must \
               be AFTER the current time — advance to the next qualifying slot if needed.
            4. The title should be a short phrase describing the event/task — not the raw transcript. \
               Strip all relative time references from the title. \
               E.g. "tomorrow between 3 and 5 to look over my journals" → title: "Review journals"
            5. Set highConfidence to false if: the transcript is very short (< 5 words), \
               it contains multiple distinct requests, or the capability is genuinely ambiguous.
            6. If no tool is connected for the matched capability, still return the correct capability — \
               the caller will show a "connect a tool" prompt.
            """
        let userPrompt = """
            Current date/time (ISO 8601): \(now)
            User timezone: \(tz)
            Voice transcript: "\(transcript)"
            """

        do {
            let session = LanguageModelSession(instructions: systemPrompt)
            let response = try await session.respond(to: userPrompt, generating: _IntentResult.self)
            let result = response.content

            guard result.highConfidence, result.capability != "unknown" else { return nil }

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
        } catch {
            // Swallow all errors — caller falls through to Castellum
            return nil
        }
    }
#endif

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
