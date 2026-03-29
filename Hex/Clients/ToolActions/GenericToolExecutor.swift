//
//  GenericToolExecutor.swift
//  Basin
//
//  Data-driven tool executor that reads action definitions from JSON
//  and makes HTTP calls based on templates. Replaces per-tool Swift files.
//

import Foundation
import HexCore

private let executorLogger = HexLog.app

enum GenericToolExecutor {

    /// Execute an action using the tool's JSON definition.
    /// Returns nil if no definition exists (caller should fall back to legacy client).
    static func execute(action: PlannedAction, tool: Tool) async -> ActionResult? {
        guard let spec = ToolDefinitionLoader.load(action.toolID) else {
            return nil // No definition — caller uses legacy Swift client
        }

        guard let actionSpec = spec.actions[action.actionType] else {
            return ActionResult(
                actionID: action.id,
                success: false,
                error: "Unknown action '\(action.actionType)' for tool '\(action.toolID)'"
            )
        }

        // Resolve auth
        guard let (authHeader, baseURL) = resolveAuth(tool: tool, spec: spec) else {
            return ActionResult(
                actionID: action.id,
                success: false,
                error: "\(spec.name) not authenticated. Connect in Settings."
            )
        }

        // Build the URL
        let endpoint = interpolate(actionSpec.endpoint, params: action.parameters, baseURL: baseURL, tool: tool)
        guard let url = URL(string: endpoint) else {
            return ActionResult(actionID: action.id, success: false, error: "Invalid URL: \(endpoint)")
        }

        // Build the request
        var request = URLRequest(url: url)
        request.httpMethod = actionSpec.method
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        for (key, value) in actionSpec.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build body from template
        if let bodyTemplate = actionSpec.bodyTemplate, actionSpec.method != "GET" {
            let bodyDict = interpolateTemplate(bodyTemplate.value, params: action.parameters)
            if let bodyData = try? JSONSerialization.data(withJSONObject: bodyDict) {
                request.httpBody = bodyData
            }
        }

        request.timeoutInterval = 30

        // Execute
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

            if (200...299).contains(httpStatus) {
                var resultMessage = actionSpec.successMessage ?? "Success"

                // Extract result value if specified
                if let extractPath = actionSpec.successExtract,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let key = extractPath.replacingOccurrences(of: "$.", with: "")
                    if let value = json[key] as? String {
                        resultMessage = resultMessage.replacingOccurrences(of: "{result}", with: value)
                    }
                }

                executorLogger.info("\(spec.name) \(action.actionType) succeeded: \(resultMessage)")
                return ActionResult(actionID: action.id, success: true, message: resultMessage)
            } else {
                let errorBody = String(data: data.prefix(300), encoding: .utf8) ?? "unknown"
                executorLogger.error("\(spec.name) \(action.actionType) failed (\(httpStatus)): \(errorBody)")
                return ActionResult(actionID: action.id, success: false, error: "\(spec.name) error (\(httpStatus)): \(errorBody)")
            }
        } catch {
            return ActionResult(actionID: action.id, success: false, error: error.localizedDescription)
        }
    }

    // MARK: - Auth Resolution

    private static func resolveAuth(tool: Tool, spec: ToolDefinitionSpec) -> (authHeader: String, baseURL: String)? {
        // OAuth path
        if let token = tool.oauthAccessToken, !token.isEmpty {
            let baseTemplate = spec.baseUrl?.oauth ?? ""
            let baseURL = tool.baseURL ?? baseTemplate
            return ("Bearer \(token)", baseURL)
        }

        // API key path
        if let apiKey = tool.apiKey, !apiKey.isEmpty {
            let format = spec.auth.apiKeyFormat ?? "bearer"
            let authHeader: String
            switch format {
            case "basic":
                authHeader = "Basic \(Data(apiKey.utf8).base64EncodedString())"
            case "basic_token_only":
                authHeader = "Basic \(Data("\(apiKey):api_token".utf8).base64EncodedString())"
            default:
                authHeader = "Bearer \(apiKey)"
            }
            let baseURL = tool.baseURL ?? spec.baseUrl?.apiKey ?? ""
            return (authHeader, baseURL)
        }

        return nil
    }

    // MARK: - Template Interpolation

    /// Replace {param_name} placeholders in a string with actual parameter values.
    private static func interpolate(_ template: String, params: [String: String], baseURL: String, tool: Tool) -> String {
        var result = template.replacingOccurrences(of: "{base_url}", with: baseURL)

        // Replace service metadata references
        if let metadata = tool.serviceMetadata,
           let json = try? JSONSerialization.jsonObject(with: metadata) as? [String: Any] {
            if let workspaces = json["workspaces"] as? [[String: Any]],
               let firstWorkspace = workspaces.first,
               let wsID = firstWorkspace["id"] {
                result = result.replacingOccurrences(of: "{workspace_id}", with: "\(wsID)")
            }
        }

        for (key, value) in params {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    /// Recursively interpolate a JSON body template, replacing {param} placeholders.
    private static func interpolateTemplate(_ template: Any, params: [String: String]) -> Any {
        if let str = template as? String {
            // Check if it's a pure placeholder like "{summary}"
            if str.hasPrefix("{") && str.hasSuffix("}") {
                let key = String(str.dropFirst().dropLast())
                return params[key] ?? str
            }
            // Otherwise do string replacement
            var result = str
            for (key, value) in params {
                result = result.replacingOccurrences(of: "{\(key)}", with: value)
            }
            return result
        }

        if let dict = template as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = interpolateTemplate(value, params: params)
            }
            return result
        }

        if let arr = template as? [Any] {
            return arr.map { interpolateTemplate($0, params: params) }
        }

        return template
    }
}
