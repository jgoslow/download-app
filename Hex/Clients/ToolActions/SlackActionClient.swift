//
//  SlackActionClient.swift
//  Basin
//
//  Executes Slack actions via Slack Web API.
//  Supports: send_message
//

import Foundation
import HexCore

private let slackLogger = HexLog.app

enum SlackActionClient {

    static func execute(action: PlannedAction, tool: Tool) async -> ActionResult {
        switch action.actionType {
        case "send_message":
            return await sendMessage(action: action, tool: tool)
        default:
            return ActionResult(actionID: action.id, success: false, error: "Unknown Slack action: \(action.actionType)")
        }
    }

    // MARK: - Send Message

    private static func sendMessage(action: PlannedAction, tool: Tool) async -> ActionResult {
        guard let token = tool.oauthAccessToken ?? tool.apiKey, !token.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "Slack not authenticated. Connect in Settings.")
        }

        let channel = action.parameters["channel"] ?? "#general"
        let text = action.parameters["text"] ?? ""

        guard !text.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "No message text provided")
        }

        guard let url = URL(string: "https://slack.com/api/chat.postMessage") else {
            return ActionResult(actionID: action.id, success: false, error: "Invalid Slack URL")
        }

        var body: [String: Any] = [
            "channel": channel,
            "text": text,
        ]

        if let threadTs = action.parameters["thread_ts"], !threadTs.isEmpty {
            body["thread_ts"] = threadTs
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ActionResult(actionID: action.id, success: false, error: "Invalid Slack response")
            }

            let ok = json["ok"] as? Bool ?? false

            if ok {
                slackLogger.info("Sent Slack message to \(channel)")
                return ActionResult(actionID: action.id, success: true, message: "Sent to \(channel)")
            } else {
                let error = json["error"] as? String ?? "unknown"
                slackLogger.error("Slack send_message failed: \(error)")
                return ActionResult(actionID: action.id, success: false, error: "Slack error: \(error)")
            }
        } catch {
            return ActionResult(actionID: action.id, success: false, error: error.localizedDescription)
        }
    }
}
