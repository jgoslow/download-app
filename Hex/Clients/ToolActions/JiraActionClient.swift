//
//  JiraActionClient.swift
//  Basin
//
//  Executes Jira actions via Atlassian REST API v3.
//  Supports: create_issue
//

import Foundation
import HexCore

private let jiraLogger = HexLog.app

enum JiraActionClient {

    static func execute(action: PlannedAction, tool: Tool) async -> ActionResult {
        switch action.actionType {
        case "create_issue":
            return await createIssue(action: action, tool: tool)
        default:
            return ActionResult(actionID: action.id, success: false, error: "Unknown Jira action: \(action.actionType)")
        }
    }

    // MARK: - Create Issue

    private static func createIssue(action: PlannedAction, tool: Tool) async -> ActionResult {
        // Get auth — prefer OAuth, fall back to API key
        guard let (authHeader, baseURL) = resolveAuth(tool: tool) else {
            return ActionResult(actionID: action.id, success: false, error: "Jira not authenticated. Connect in Settings.")
        }

        let projectKey = action.parameters["project_key"] ?? "LYRA"
        let summary = action.parameters["summary"] ?? "Untitled task"
        let description = action.parameters["description"] ?? ""
        let issueType = action.parameters["issue_type"] ?? "Task"

        // Build Atlassian Document Format for description
        let descriptionADF: [String: Any] = [
            "type": "doc",
            "version": 1,
            "content": [
                [
                    "type": "paragraph",
                    "content": [
                        ["type": "text", "text": description]
                    ]
                ]
            ]
        ]

        var fields: [String: Any] = [
            "project": ["key": projectKey],
            "summary": summary,
            "issuetype": ["name": issueType],
        ]

        if !description.isEmpty {
            fields["description"] = descriptionADF
        }

        // Assignee (if provided) — requires account ID, not username
        // For now we skip assignee since it requires a user lookup

        let body: [String: Any] = ["fields": fields]

        guard let url = URL(string: "\(baseURL)/rest/api/3/issue") else {
            return ActionResult(actionID: action.id, success: false, error: "Invalid Jira URL")
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ActionResult(actionID: action.id, success: false, error: "No HTTP response")
            }

            if (200...299).contains(httpResponse.statusCode) {
                // Parse the created issue key
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let key = json["key"] as? String {
                    jiraLogger.info("Created Jira issue \(key)")
                    return ActionResult(actionID: action.id, success: true, message: "Created \(key)")
                }
                return ActionResult(actionID: action.id, success: true, message: "Issue created")
            } else {
                let errorBody = String(data: data.prefix(300), encoding: .utf8) ?? "unknown"
                jiraLogger.error("Jira create issue failed (\(httpResponse.statusCode)): \(errorBody)")
                return ActionResult(actionID: action.id, success: false, error: "Jira API error \(httpResponse.statusCode)")
            }
        } catch {
            return ActionResult(actionID: action.id, success: false, error: error.localizedDescription)
        }
    }

    // MARK: - Auth

    private static func resolveAuth(tool: Tool) -> (authHeader: String, baseURL: String)? {
        // OAuth path — need to fetch accessible resources first for cloud ID
        if let oauthToken = tool.oauthAccessToken, !oauthToken.isEmpty {
            // Atlassian cloud: base URL is https://api.atlassian.com/ex/jira/{cloudId}
            // For now, use the stored baseURL if available, otherwise default
            let base = tool.baseURL ?? "https://api.atlassian.com"
            return ("Bearer \(oauthToken)", base)
        }

        // API key path: email:token → Basic auth
        if let apiKey = tool.apiKey, !apiKey.isEmpty,
           let baseURL = tool.baseURL, !baseURL.isEmpty {
            let encoded = Data(apiKey.utf8).base64EncodedString()
            return ("Basic \(encoded)", baseURL)
        }

        return nil
    }
}
