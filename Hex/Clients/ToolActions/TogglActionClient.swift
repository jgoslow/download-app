//
//  TogglActionClient.swift
//  Basin
//
//  Executes Toggl actions via Toggl Track API v9.
//  Supports: create_time_entry
//

import Foundation
import BasnCore

private let togglLogger = BasnLog.app

enum TogglActionClient {

    static func execute(action: PlannedAction, tool: Tool) async -> ActionResult {
        switch action.actionType {
        case "create_time_entry":
            return await createTimeEntry(action: action, tool: tool)
        default:
            return ActionResult(actionID: action.id, success: false, error: "Unknown Toggl action: \(action.actionType)")
        }
    }

    // MARK: - Create Time Entry

    private static func createTimeEntry(action: PlannedAction, tool: Tool) async -> ActionResult {
        guard let apiToken = KeychainClient.load(toolID: tool.id, key: .apiKey), !apiToken.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "Toggl not authenticated. Add API token in Settings.")
        }

        let description = action.parameters["description"] ?? "Basin capture"
        let durationMinutes = Int(action.parameters["duration_minutes"] ?? "30") ?? 30

        // First, get workspace ID
        guard let workspaceID = await fetchDefaultWorkspaceID(apiToken: apiToken) else {
            return ActionResult(actionID: action.id, success: false, error: "Could not determine Toggl workspace")
        }

        // Look up project by name if provided
        let projectName = action.parameters["project_name"]
        var projectID: Int?
        if let name = projectName, !name.isEmpty {
            projectID = await findProjectID(name: name, workspaceID: workspaceID, apiToken: apiToken)
        }

        // Build time entry
        let now = Date()
        let start = ISO8601DateFormatter().string(from: now)
        let durationSeconds = durationMinutes * 60

        var body: [String: Any] = [
            "description": description,
            "start": start,
            "duration": durationSeconds,
            "workspace_id": workspaceID,
            "created_with": "Basin",
        ]

        if let pid = projectID {
            body["project_id"] = pid
        }

        if let tags = action.parameters["tags"], !tags.isEmpty {
            body["tags"] = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        guard let url = URL(string: "https://api.track.toggl.com/api/v9/workspaces/\(workspaceID)/time_entries") else {
            return ActionResult(actionID: action.id, success: false, error: "Invalid Toggl URL")
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(basicAuth(apiToken), forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ActionResult(actionID: action.id, success: false, error: "No HTTP response")
            }

            if (200...299).contains(httpResponse.statusCode) {
                togglLogger.info("Created Toggl time entry: \(description) (\(durationMinutes)m)")
                let projectLabel = projectName.map { " on \($0)" } ?? ""
                return ActionResult(actionID: action.id, success: true, message: "Logged \(durationMinutes)m\(projectLabel)")
            } else {
                let errorBody = String(data: data.prefix(300), encoding: .utf8) ?? "unknown"
                togglLogger.error("Toggl create entry failed (\(httpResponse.statusCode)): \(errorBody)")
                return ActionResult(actionID: action.id, success: false, error: "Toggl API error \(httpResponse.statusCode)")
            }
        } catch {
            return ActionResult(actionID: action.id, success: false, error: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func fetchDefaultWorkspaceID(apiToken: String) async -> Int? {
        guard let url = URL(string: "https://api.track.toggl.com/api/v9/workspaces") else { return nil }

        var request = URLRequest(url: url)
        request.setValue(basicAuth(apiToken), forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let workspaces = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = workspaces.first,
              let id = first["id"] as? Int else {
            return nil
        }
        return id
    }

    private static func findProjectID(name: String, workspaceID: Int, apiToken: String) async -> Int? {
        guard let url = URL(string: "https://api.track.toggl.com/api/v9/workspaces/\(workspaceID)/projects") else { return nil }

        var request = URLRequest(url: url)
        request.setValue(basicAuth(apiToken), forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let projects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        let lowered = name.lowercased()
        if let match = projects.first(where: { ($0["name"] as? String)?.lowercased() == lowered }) {
            return match["id"] as? Int
        }
        return nil
    }

    private static func basicAuth(_ token: String) -> String {
        let encoded = Data("\(token):api_token".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}
