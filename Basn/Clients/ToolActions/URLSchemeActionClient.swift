import Foundation
import BasinShared
import os

private let log = Logger(subsystem: "com.lyra.basn", category: "url-scheme")

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Executes actions that open native apps via URL schemes (Mail, Messages, Maps).
/// These open the target app with pre-filled content — they don't make HTTP calls.
enum URLSchemeActionClient {

    static func execute(action: PlannedAction, handler: String) async -> ActionResult {
        switch handler {
        case "url_scheme_mailto":
            return await handleMailto(action: action)
        case "url_scheme_sms":
            return await handleSMS(action: action)
        case "url_scheme_maps":
            return await handleMaps(action: action)
        default:
            return ActionResult(actionID: action.id, success: false, error: "Unknown URL scheme handler: \(handler)")
        }
    }

    // MARK: - mailto:

    private static func handleMailto(action: PlannedAction) async -> ActionResult {
        let params = action.parameters
        guard let to = params["to"] as? String, !to.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "Recipient email is required")
        }

        var components = URLComponents(string: "mailto:\(to)")!
        var queryItems: [URLQueryItem] = []
        if let subject = params["subject"] as? String { queryItems.append(URLQueryItem(name: "subject", value: subject)) }
        if let body    = params["body"]    as? String { queryItems.append(URLQueryItem(name: "body",    value: body)) }
        if let cc      = params["cc"]      as? String { queryItems.append(URLQueryItem(name: "cc",      value: cc)) }
        if !queryItems.isEmpty { components.queryItems = queryItems }

        guard let url = components.url else {
            return ActionResult(actionID: action.id, success: false, error: "Failed to build mailto URL")
        }

        return await open(url: url, actionID: action.id, success: "Mail compose window opened")
    }

    // MARK: - sms:

    private static func handleSMS(action: PlannedAction) async -> ActionResult {
        let params = action.parameters
        guard let recipient = params["recipient"] as? String, !recipient.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "Recipient is required")
        }

        var urlString = "sms:\(recipient)"
        if let body = params["body"] as? String,
           let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&body=\(encoded)"
        }

        guard let url = URL(string: urlString) else {
            return ActionResult(actionID: action.id, success: false, error: "Failed to build sms URL")
        }

        return await open(url: url, actionID: action.id, success: "Messages opened")
    }

    // MARK: - maps:

    private static func handleMaps(action: PlannedAction) async -> ActionResult {
        let params = action.parameters
        var components = URLComponents(string: "maps://")!
        var queryItems: [URLQueryItem] = []

        if let address = params["address"] as? String {
            queryItems.append(URLQueryItem(name: "address", value: address))
        } else if let query = params["query"] as? String {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }

        if let dirTo = params["directions_to"] as? String {
            queryItems.append(URLQueryItem(name: "daddr", value: dirTo))
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            return ActionResult(actionID: action.id, success: false, error: "Failed to build maps URL")
        }

        return await open(url: url, actionID: action.id, success: "Maps opened")
    }

    // MARK: - Open helper

    @MainActor
    private static func open(url: URL, actionID: String, success: String) async -> ActionResult {
        #if canImport(AppKit)
        let opened = NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        guard await UIApplication.shared.canOpenURL(url) else {
            return ActionResult(actionID: actionID, success: false, error: "Cannot open URL: \(url.scheme ?? "?")")
        }
        let opened = await UIApplication.shared.open(url)
        #else
        let opened = false
        #endif

        if opened {
            log.info("Opened URL: \(url.absoluteString)")
            return ActionResult(actionID: actionID, success: true, message: success)
        } else {
            return ActionResult(actionID: actionID, success: false, error: "Failed to open \(url.scheme ?? "unknown") URL")
        }
    }
}
