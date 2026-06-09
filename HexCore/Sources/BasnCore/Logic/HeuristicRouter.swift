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
struct HeuristicRouter {

    static func route(transcript: String, connectedToolIDs: Set<String>) -> [PlannedAction]? {
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
            let after = String(original[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { description = after }
        }

        return PlannedAction(
            toolID: "toggl",
            actionType: "create_time_entry",
            label: "Log time: \(description.prefix(60))",
            parameters: ["description": String(description.prefix(200))]
        )
    }
}
