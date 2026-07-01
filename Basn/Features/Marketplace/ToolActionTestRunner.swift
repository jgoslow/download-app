import Foundation

/// Validates a tool definition without making live API calls.
/// Checks that the definition is structurally correct — endpoints, parameters,
/// body template placeholders, auth fields — before the user submits to the marketplace.
enum ToolActionTestRunner {

    struct TestResult {
        let actionID: String
        let passed: Bool
        let message: String
    }

    /// Validate a single action within a spec. Returns immediately.
    static func validate(
        actionID: String,
        action: ToolDefinitionSpec.ActionSpec,
        spec: ToolDefinitionSpec
    ) -> TestResult {
        var issues: [String] = []

        // Endpoint must be non-empty and use the base_url placeholder (or be absolute)
        if action.endpoint.isEmpty {
            issues.append("Missing endpoint")
        } else if !action.endpoint.contains("{base_url}") && !action.endpoint.hasPrefix("http") {
            issues.append("Endpoint should start with {base_url} or be an absolute URL")
        }

        // Method must be a valid HTTP verb
        let validMethods = ["GET", "POST", "PUT", "PATCH", "DELETE"]
        if !validMethods.contains(action.method.uppercased()) {
            issues.append("Invalid HTTP method '\(action.method)'")
        }

        // Body template placeholders must all have matching parameter definitions
        if let template = action.bodyTemplate {
            let placeholders = extractPlaceholders(from: template.value)
            for placeholder in placeholders where placeholder != "base_url" {
                if action.parameters[placeholder] == nil {
                    issues.append("Template uses {\(placeholder)} but parameter not defined")
                }
            }
        }

        // Required parameters should not reference missing template slots
        for (paramID, param) in action.parameters {
            if param.required == true, let body = action.bodyTemplate {
                let placeholders = extractPlaceholders(from: body.value)
                if !placeholders.contains(paramID) && action.method != "GET" {
                    // GET requests encode params in the URL, so this is fine
                    // For POST/PUT/PATCH the required param should appear in body_template
                    if ["POST", "PUT", "PATCH"].contains(action.method.uppercased()) {
                        issues.append("Required parameter '\(paramID)' missing from body_template")
                    }
                }
            }
        }

        // Auth: spec must define at least one auth method
        if spec.auth.methods.isEmpty {
            issues.append("Auth methods are empty")
        }
        if spec.auth.methods.contains("api_key") {
            if spec.baseUrl?.apiKey?.isEmpty ?? true {
                issues.append("api_key auth requires base_url.api_key")
            }
        }

        if issues.isEmpty {
            return TestResult(actionID: actionID, passed: true, message: "Definition looks good")
        } else {
            return TestResult(actionID: actionID, passed: false, message: issues.joined(separator: " · "))
        }
    }

    // MARK: - Placeholder extraction

    private static func extractPlaceholders(from value: Any) -> [String] {
        if let str = value as? String {
            return extractPlaceholdersFromString(str)
        }
        if let dict = value as? [String: Any] {
            return dict.values.flatMap { extractPlaceholders(from: $0) }
        }
        if let arr = value as? [Any] {
            return arr.flatMap { extractPlaceholders(from: $0) }
        }
        return []
    }

    private static func extractPlaceholdersFromString(_ str: String) -> [String] {
        var result: [String] = []
        var i = str.startIndex
        while i < str.endIndex {
            if str[i] == "{" {
                let start = str.index(after: i)
                if start < str.endIndex, let end = str[start...].firstIndex(of: "}") {
                    let placeholder = String(str[start..<end])
                    if !placeholder.isEmpty { result.append(placeholder) }
                    i = str.index(after: end)
                    continue
                }
            }
            i = str.index(after: i)
        }
        return result
    }
}
