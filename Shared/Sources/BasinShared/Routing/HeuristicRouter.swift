import Foundation

/// Local pattern-matching router that runs before any Claude call.
///
/// For clear single-intent captures with a connected tool match, returns
/// pre-built actions so the Anthropic call is skipped entirely.
/// Returns nil for anything ambiguous — falls through to CastellumClient.
///
/// On iOS, this is called on each `onSentenceComplete` callback during recording.
/// On macOS (current), it runs once on the full transcript at recording end.
/// Both paths use the same API; only the timing differs.
public struct HeuristicRouter {

    public static func route(transcript: String, connectedToolIDs: Set<String>) -> [PlannedAction]? {
        let lower = transcript.lowercased()
        var actions: [PlannedAction] = []

        if connectedToolIDs.contains("toggl") {
            if let action = checkToggl(lower, original: transcript) {
                actions.append(action)
            }
        }

        // Only bypass Claude when exactly one clear action is found.
        // Multi-intent or ambiguous captures go through Castellum.
        guard actions.count == 1 else { return nil }
        return actions
    }

    // MARK: - Pattern matchers (extend as native tools are added)

    private static func checkToggl(_ lower: String, original: String) -> PlannedAction? {
        let triggers = ["start timer", "start a timer", "log time for", "track time for", "track time on"]
        guard let trigger = triggers.first(where: { lower.contains($0) }) else { return nil }

        var description = original
        if let range = lower.range(of: trigger) {
            var after = String(original[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Strip a leading "for" left over from triggers that don't include it (e.g. "start timer for X")
            if after.lowercased().hasPrefix("for ") {
                after = String(after.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }
            if !after.isEmpty { description = after }
        }

        let minutes = parseDurationMinutes(from: lower)

        return PlannedAction(
            toolID: "toggl",
            actionType: "create_time_entry",
            label: "Log time: \(description.prefix(60))",
            parameters: [
                "description": String(description.prefix(200)),
                "duration_minutes": "\(minutes)"
            ]
        )
    }

    /// Extract a duration in minutes from natural-language text.
    /// Falls back to 30 if no duration is found.
    private static func parseDurationMinutes(from lower: String) -> Int {
        // "half an hour" / "half hour"
        if lower.contains("half an hour") || lower.contains("half hour") { return 30 }
        // "an hour" / "a hour" / "one hour"
        if lower.contains("an hour") || lower.contains("a hour") || lower.contains("one hour") { return 60 }

        // "[N] hour(s)" — supports integers and simple decimals like 1.5
        let hourPattern = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*hours?"#)
        if let m = hourPattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(m.range(at: 1), in: lower),
           let value = Double(lower[r]) {
            return Int((value * 60).rounded())
        }

        // "[N] minute(s) / min(s)"
        let minPattern = try? NSRegularExpression(pattern: #"(\d+)\s*(?:minutes?|mins?)"#)
        if let m = minPattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(m.range(at: 1), in: lower),
           let value = Int(lower[r]) {
            return value
        }

        return 30 // default when no duration mentioned
    }
}
