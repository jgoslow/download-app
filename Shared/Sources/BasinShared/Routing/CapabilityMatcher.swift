import Foundation

/// Offline, key-free detection of which generic capabilities a transcript implies.
/// Lower recall than Castellum (keywords vs. understanding) but free + private +
/// instant — the baseline that powers pre-connection suggestions ("this sounds
/// like it wants to create a task — connect a tool") when no Anthropic key or
/// connected tool is available. Castellum, when present, supplements this.
public enum CapabilityMatcher {

    /// Keyword/phrase triggers per capability id. Kept reasonably specific to
    /// limit false positives; suggestions, so some over-matching is acceptable.
    private static let triggers: [(capability: String, keywords: [String])] = [
        ("create_task",     ["task", "ticket", "todo", "to-do", "bug", "issue", "follow up", "follow-up", "backlog", "jira", "card"]),
        ("log_time",        ["log time", "track time", "time entry", "hours", "spent", "worked on", "logged", "toggl", "billable"]),
        ("send_message",    ["message", "ping", "slack", "dm", "tell ", "let them know", "notify", "post to", "channel"]),
        ("schedule_event",  ["schedule", "meeting", "calendar", "appointment", "invite", "book ", "set up a call", "event"]),
        ("send_email",      ["email", "e-mail", "send a note to", "reach out to"]),
        ("create_document", ["document", "doc", "write up", "write-up", "draft", "google doc", "spec", "memo"]),
        ("capture_note",    ["note", "remember", "journal", "jot", "for the record"]),
    ]

    /// Capabilities implied by the transcript, in vocabulary order, deduped.
    public static func match(_ transcript: String) -> [String] {
        let text = transcript.lowercased()
        let hits = triggers
            .filter { _, keywords in keywords.contains { hit(text, keyword: $0) } }
            .map(\.capability)
        // Preserve the canonical vocabulary order.
        let hitSet = Set(hits)
        return Capabilities.all.map(\.id).filter { hitSet.contains($0) }
    }

    /// Match a keyword against text. Single words require word boundaries to avoid false
    /// positives like "to do" matching inside "want to document something".
    private static func hit(_ text: String, keyword: String) -> Bool {
        if keyword.contains(" ") {
            // Multi-word phrase — plain contains is fine (phrase is specific enough)
            return text.contains(keyword)
        }
        // Single word — require word boundaries so "issue" doesn't match "tissue"
        // and "to do" doesn't match "want to document"
        return text.range(
            of: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
