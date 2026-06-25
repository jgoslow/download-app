import Foundation

/// Parses the `content` array from a Castellum (Anthropic) API response into
/// a `SessionAnalysis` and a list of `PlannedAction`s.
///
/// Extracted here so the parsing logic can be unit-tested against recorded
/// fixture responses without making real API calls or importing the app target.
public struct CastellumResponseParser {

    /// Parse raw Anthropic response content blocks.
    ///
    /// - Parameters:
    ///   - content: The `content` array from the Anthropic JSON response body.
    ///   - captureID: Used only for logging; has no effect on the parsed output.
    ///   - labelLookup: Optional closure returning a display name for a tool action.
    ///     Pass `nil` in tests — labels are not asserted. Pass `ToolActionRegistry`
    ///     lookup in the app target to get human-readable labels.
    /// - Returns: A `(SessionAnalysis, [PlannedAction])` tuple. Never throws —
    ///   malformed blocks are skipped and a fallback analysis is returned if no
    ///   valid text block is found.
    public static func parse(
        _ content: [[String: Any]],
        captureID: String,
        labelLookup: ((String, String) -> String?)? = nil
    ) -> (SessionAnalysis, [PlannedAction]) {
        var analysis: SessionAnalysis?
        var actions: [PlannedAction] = []

        for block in content {
            guard let type = block["type"] as? String else { continue }

            if type == "text", let text = block["text"] as? String {
                // Extract JSON object from text — Claude may include surrounding prose
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let start = trimmed.firstIndex(of: "{"),
                   let end = trimmed.lastIndex(of: "}") {
                    let jsonStr = String(trimmed[start...end])
                    if let data = jsonStr.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(SessionAnalysis.self, from: data) {
                        analysis = decoded
                    }
                }

            } else if type == "tool_use",
                      let name = block["name"] as? String,
                      let input = block["input"] as? [String: Any] {
                // Tool function names are formatted as "<toolID>_<actionType>"
                // Split on the first underscore only.
                let parts = name.split(separator: "_", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let toolID = String(parts[0])
                let actionType = String(parts[1])

                var params: [String: String] = [:]
                for (k, v) in input {
                    if let s = v as? String {
                        params[k] = s
                    } else if let n = v as? NSNumber {
                        params[k] = "\(n)"
                    } else if let a = v as? [String] {
                        params[k] = a.joined(separator: ", ")
                    }
                }

                let displayName = labelLookup?(toolID, actionType)
                    ?? actionType.replacingOccurrences(of: "_", with: " ").capitalized
                let summary = params["summary"] ?? params["title"] ?? params["text"]
                    ?? params["description"] ?? ""
                let label = summary.isEmpty ? displayName : "\(displayName): \(summary.prefix(60))"

                actions.append(PlannedAction(
                    toolID: toolID,
                    actionType: actionType,
                    label: label,
                    parameters: params
                ))
            }
        }

        let finalAnalysis = analysis ?? SessionAnalysis(summary: "Capture processed")
        return (finalAnalysis, actions)
    }
}
