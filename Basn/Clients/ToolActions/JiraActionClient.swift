//
//  JiraActionClient.swift
//  Basin
//
//  Executes Jira actions via Atlassian REST API v3.
//  Supports: create_issue
//

import Foundation
import BasnCore

private let jiraLogger = BasnLog.app

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
        guard let (authHeader, baseURL) = await resolveAuth(tool: tool) else {
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

    private static func resolveAuth(tool: Tool) async -> (authHeader: String, baseURL: String)? {
        // OAuth path — fetch cloud ID from Atlassian, then build the base URL
        if var oauthToken = KeychainClient.load(toolID: tool.id, key: .accessToken), !oauthToken.isEmpty {
            // Check if token is expired and refresh if needed
            if let expiresAt = KeychainClient.loadExpiry(toolID: tool.id), expiresAt < Date(),
               let refreshToken = KeychainClient.load(toolID: tool.id, key: .refreshToken) {
                jiraLogger.info("Atlassian token expired, refreshing...")
                if let refreshed = await refreshAtlassianToken(tool: tool, refreshToken: refreshToken) {
                    oauthToken = refreshed
                    await MainActor.run { tool.tokenLastRefreshedAt = Date() }
                } else {
                    jiraLogger.error("Failed to refresh Atlassian token")
                    return nil
                }
            }

            // If we already have a baseURL with the cloud ID, use it
            if let base = tool.baseURL, base.contains("/ex/jira/") {
                return ("Bearer \(oauthToken)", base)
            }

            // Fetch accessible resources to get the cloud ID
            if let cloudBase = await fetchAtlassianCloudBaseURL(token: oauthToken) {
                await MainActor.run { tool.baseURL = cloudBase }
                return ("Bearer \(oauthToken)", cloudBase)
            }

            // Token might be expired even if expiry wasn't stored — try refresh
            if let refreshToken = KeychainClient.load(toolID: tool.id, key: .refreshToken) {
                jiraLogger.info("Cloud ID fetch failed (possible expired token), trying refresh...")
                if let refreshed = await refreshAtlassianToken(tool: tool, refreshToken: refreshToken) {
                    if let cloudBase = await fetchAtlassianCloudBaseURL(token: refreshed) {
                        await MainActor.run {
                            tool.baseURL = cloudBase
                            tool.tokenLastRefreshedAt = Date()
                        }
                        return ("Bearer \(refreshed)", cloudBase)
                    }
                }
            }

            return nil
        }

        // API key path: email:token → Basic auth
        if let apiKey = KeychainClient.load(toolID: tool.id, key: .apiKey), !apiKey.isEmpty,
           let baseURL = tool.baseURL, !baseURL.isEmpty {
            let encoded = Data(apiKey.utf8).base64EncodedString()
            return ("Basic \(encoded)", baseURL)
        }

        return nil
    }

    // MARK: - Service Discovery

    /// Fetches Jira projects and caches them on the tool as serviceMetadata.
    /// Called after OAuth connect and periodically to keep the list fresh.
    static func fetchAndCacheProjects(tool: Tool) async {
        guard let (authHeader, baseURL) = await resolveAuth(tool: tool) else { return }

        guard let url = URL(string: "\(baseURL)/rest/api/3/project/search?maxResults=50&orderBy=name") else { return }

        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                jiraLogger.error("Failed to fetch Jira projects: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = json["values"] as? [[String: Any]] else {
                return
            }

            // Extract just key + name for each project
            let projects: [[String: String]] = values.compactMap { proj in
                guard let key = proj["key"] as? String,
                      let name = proj["name"] as? String else { return nil }
                return ["key": key, "name": name]
            }

            let metadata: [String: Any] = ["projects": projects, "fetched_at": ISO8601DateFormatter().string(from: Date())]
            let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

            await MainActor.run { tool.serviceMetadata = metadataJSON }
            jiraLogger.info("Cached \(projects.count) Jira projects")
        } catch {
            jiraLogger.error("Jira project fetch error: \(error.localizedDescription)")
        }
    }

    /// Returns cached project keys and names for use in the Castellum planner.
    static func cachedProjects(tool: Tool) -> [(key: String, name: String)] {
        guard let data = tool.serviceMetadata,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [[String: String]] else {
            return []
        }
        return projects.compactMap { proj in
            guard let key = proj["key"], let name = proj["name"] else { return nil }
            return (key: key, name: name)
        }
    }

    /// Fetches the cloud ID from Atlassian's accessible-resources endpoint.
    private static func fetchAtlassianCloudBaseURL(token: String) async -> String? {
        guard let url = URL(string: "https://api.atlassian.com/oauth/token/accessible-resources") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                jiraLogger.error("Failed to fetch Atlassian resources: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }

            // Response is an array of sites: [{"id": "cloud-id", "name": "site-name", ...}]
            guard let sites = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let firstSite = sites.first,
                  let cloudId = firstSite["id"] as? String else {
                jiraLogger.error("No accessible Atlassian sites found")
                return nil
            }

            let baseURL = "https://api.atlassian.com/ex/jira/\(cloudId)"
            jiraLogger.info("Resolved Atlassian cloud ID: \(cloudId)")
            return baseURL
        } catch {
            jiraLogger.error("Atlassian cloud ID fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Refresh an expired Atlassian OAuth token and update the tool.
    private static func refreshAtlassianToken(tool: Tool, refreshToken: String) async -> String? {
        do {
            let response = try await OAuthClient.shared.refreshToken(
                provider: "atlassian",
                refreshToken: refreshToken,
                clientID: Bundle.main.infoDictionary?["AtlassianClientID"] as? String ?? ""
            )
            // Store refreshed tokens in Keychain
            try? KeychainClient.save(response.accessToken, toolID: tool.id, key: .accessToken)
            if let newRefresh = response.refreshToken {
                try? KeychainClient.save(newRefresh, toolID: tool.id, key: .refreshToken)
            }
            if let expiresIn = response.expiresIn {
                try? KeychainClient.saveExpiry(Date().addingTimeInterval(TimeInterval(expiresIn)), toolID: tool.id)
            }
            jiraLogger.info("Atlassian token refreshed successfully")
            return response.accessToken
        } catch {
            jiraLogger.error("Atlassian token refresh failed: \(error.localizedDescription)")
            return nil
        }
    }
}
