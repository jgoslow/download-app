//
//  GenericToolExecutor.swift
//  Basin
//
//  Data-driven tool executor that reads action definitions from JSON
//  and makes HTTP calls based on templates. Replaces per-tool Swift files.
//

import Foundation
import BasinShared
import os

private let executorLogger = Logger(subsystem: "com.lyra.basn", category: "tool-executor")

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

        if let disabledKeys = tool.enabledActionKeys, disabledKeys.contains(action.actionType) {
            return ActionResult(
                actionID: action.id,
                success: false,
                error: "'\(actionSpec.displayName)' is disabled for \(spec.name). Enable it in Settings → Tools."
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

        // Special handlers — native platform integrations bypass HTTP entirely
        if let handler = actionSpec.specialHandler {
            // EventKit (Reminders / Calendar) — cross-platform
            if handler.hasPrefix("eventkit_") {
                return await EventKitActionClient.execute(action: action, handler: handler)
            }
            // URL schemes (Mail, Messages, Maps)
            if handler.hasPrefix("url_scheme_") {
                return await URLSchemeActionClient.execute(action: action, handler: handler)
            }
            // Notes — AppleScript on macOS, share sheet on iOS
            if handler.hasPrefix("applescript_") {
                return await NotesAppleScriptClient.execute(action: action, handler: handler)
            }
            // Files (iCloud Drive)
            if handler.hasPrefix("files_") {
                return await FilesActionClient.execute(action: action, handler: handler)
            }
            // HTTP-level special handlers (modify the URLRequest before sending)
            switch handler {
            case "gmail_send":
                guard let mimeRequest = buildGmailSendRequest(baseRequest: request, params: action.parameters) else {
                    return ActionResult(actionID: action.id, success: false, error: "Gmail send: missing required parameter (to, subject, or body)")
                }
                request = mimeRequest
            default:
                break
            }
        }

        if let bodyTemplate = actionSpec.bodyTemplate, actionSpec.method != "GET" {
            // Build body from template
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
                tool.lastUsedAt = Date()
                return ActionResult(actionID: action.id, success: true, message: resultMessage)
            } else {
                let errorBody = String(data: data.prefix(500), encoding: .utf8) ?? "unknown"
                executorLogger.error("\(spec.name) \(action.actionType) failed (\(httpStatus)): \(errorBody)")
                let friendlyError = friendlyErrorMessage(toolName: spec.name, status: httpStatus, body: errorBody)
                return ActionResult(actionID: action.id, success: false, error: friendlyError)
            }
        } catch {
            return ActionResult(actionID: action.id, success: false, error: error.localizedDescription)
        }
    }

    // MARK: - Auth Resolution

    private static func resolveAuth(tool: Tool, spec: ToolDefinitionSpec) -> (authHeader: String, baseURL: String)? {
        // OAuth path
        if let token = KeychainClient.load(toolID: tool.id, key: .accessToken), !token.isEmpty {
            let baseTemplate = spec.baseUrl?.oauth ?? ""
            let baseURL = tool.baseURL ?? baseTemplate
            return ("Bearer \(token)", baseURL)
        }

        // API key path
        if let apiKey = KeychainClient.load(toolID: tool.id, key: .apiKey), !apiKey.isEmpty {
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

    // MARK: - Error Messages

    private static func friendlyErrorMessage(toolName: String, status: Int, body: String) -> String {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
        let errorObj = json?["error"] as? [String: Any]
        let reason = (errorObj?["errors"] as? [[String: Any]])?.first?["reason"] as? String
        let status_str = errorObj?["status"] as? String

        switch status {
        case 401:
            return "\(toolName): Authentication expired. Reconnect in Settings → Tools."
        case 403:
            if reason == "insufficientPermissions" || status_str == "PERMISSION_DENIED" {
                return "\(toolName): Missing permission for this action. Disconnect and reconnect in Settings → Tools, making sure the required access is enabled."
            }
            return "\(toolName): Access denied (\(status))."
        case 404:
            return "\(toolName): Resource not found. Check your configuration."
        case 429:
            return "\(toolName): Rate limit reached. Try again in a moment."
        case 500...599:
            return "\(toolName): Server error (\(status)). Try again later."
        default:
            let message = errorObj?["message"] as? String ?? body.prefix(120).description
            return "\(toolName) error (\(status)): \(message)"
        }
    }

    // MARK: - Connection Verification

    /// Fires the tool's health check endpoint and returns whether it responds with 2xx.
    /// Used by the "Verify connection" button in Settings → Tools.
    static func verify(tool: Tool, spec: ToolDefinitionSpec) async -> Bool {
        guard let healthCheck = spec.healthCheck else { return false }
        guard let (authHeader, baseURL) = resolveAuth(tool: tool, spec: spec) else { return false }

        let endpointStr = healthCheck.endpoint.replacingOccurrences(of: "{base_url}", with: baseURL)
        guard let url = URL(string: endpointStr) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = healthCheck.method
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200...299).contains(status)
        } catch {
            return false
        }
    }

    // MARK: - Gmail Special Handler

    /// Builds the Gmail send request by constructing a base64url-encoded RFC 2822 MIME message.
    /// Gmail's API requires {"raw": "<base64url>"} rather than plain field interpolation.
    private static func buildGmailSendRequest(baseRequest: URLRequest, params: [String: String]) -> URLRequest? {
        guard let to = params["to"], let subject = params["subject"], let body = params["body"] else {
            return nil
        }

        let mimeMessage = [
            "To: \(to)",
            "Subject: \(subject)",
            "Content-Type: text/plain; charset=UTF-8",
            "",
            body
        ].joined(separator: "\r\n")

        let encoded = Data(mimeMessage.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["raw": encoded]) else {
            return nil
        }

        var request = baseRequest
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        return request
    }
}
