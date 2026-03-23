//
//  DestinationRouterClient.swift
//  Download
//
//  Routes completed Download sessions to configured destinations:
//  Phase 1 — local JSON file + optional HTTP POST to CNS server.
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let routerLogger = HexLog.app

/// A summary of a previous session, used as pre-session context.
public struct SessionContext: Codable, Sendable {
    public let timestamp: String?
    public let summary: String?
    public let moodTag: String?
    public let tasks: [String]?
    public let routing: [String]?
    public let delegations: [String]?

    enum CodingKeys: String, CodingKey {
        case timestamp, summary, tasks, routing, delegations
        case moodTag = "mood_tag"
    }
}

/// The outcome of routing a session.
public enum RoutingStatus: Sendable, Equatable {
    /// Saved to disk only — no server URL configured.
    case savedOnly
    /// Saved locally and successfully sent to server (HTTP status code included).
    case sent(statusCode: Int)
    /// Saved locally but the server POST failed.
    case serverFailed(error: String)
    /// Failed to save locally (disk write error).
    case saveFailed(error: String)

    public var savedLocally: Bool {
        switch self {
        case .savedOnly, .sent, .serverFailed: return true
        case .saveFailed: return false
        }
    }
}

@DependencyClient
struct DestinationRouterClient {
    /// Route a session to all configured destinations and return the result.
    var route: @Sendable (Session) async -> RoutingStatus = { _ in .savedOnly }
    /// Post analysis back to the server for a given session ID.
    var postAnalysis: @Sendable (String, SessionAnalysis) async -> Void = { _, _ in }
    /// Fetch pre-session context (recent session summaries) for a download type.
    var fetchContext: @Sendable (String) async -> [SessionContext] = { _ in [] }
}

extension DestinationRouterClient: DependencyKey {
    static var liveValue: Self {
        .init(route: { session in
            @Shared(.hexSettings) var hexSettings: HexSettings
            let config = hexSettings.basinSettings

            // 1. Save locally — always
            do {
                try await saveSessionLocally(session)
                routerLogger.info("Session \(session.id) saved locally")
            } catch {
                routerLogger.error("Failed to save session \(session.id): \(error.localizedDescription)")
                return .saveFailed(error: error.localizedDescription)
            }

            // 2. POST to server if configured
            guard !config.serverURL.isEmpty else {
                return .savedOnly
            }

            guard let serverURL = URL(string: config.serverURL) else {
                routerLogger.error("Invalid server URL: \(config.serverURL)")
                return .serverFailed(error: "Invalid server URL")
            }

            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let body = try encoder.encode(session)

                var request = URLRequest(url: serverURL.appendingPathComponent("sessions"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !config.authToken.isEmpty {
                    request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
                }
                request.httpBody = body
                request.timeoutInterval = 10

                let (_, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                routerLogger.info("Session \(session.id) sent to server — HTTP \(statusCode)")
                return .sent(statusCode: statusCode)
            } catch {
                routerLogger.error("Server POST failed for session \(session.id): \(error.localizedDescription)")
                return .serverFailed(error: error.localizedDescription)
            }
        }, postAnalysis: { sessionID, analysis in
            @Shared(.hexSettings) var hexSettings: HexSettings
            let config = hexSettings.basinSettings
            guard !config.serverURL.isEmpty,
                  let serverURL = URL(string: config.serverURL) else { return }

            do {
                let encoder = JSONEncoder()
                let body = try encoder.encode(analysis)

                var request = URLRequest(url: serverURL.appendingPathComponent("sessions/\(sessionID)/analysis"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !config.authToken.isEmpty {
                    request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
                }
                request.httpBody = body
                request.timeoutInterval = 10

                let (_, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                routerLogger.info("Analysis for \(sessionID) posted — HTTP \(statusCode)")
            } catch {
                routerLogger.error("Analysis POST failed for \(sessionID): \(error.localizedDescription)")
            }
        }, fetchContext: { typeID in
            @Shared(.hexSettings) var hexSettings: HexSettings
            let config = hexSettings.basinSettings
            guard !config.serverURL.isEmpty,
                  let serverURL = URL(string: config.serverURL) else { return [] }

            do {
                let contextURL = serverURL.appendingPathComponent("sessions/context/\(typeID)")
                var request = URLRequest(url: contextURL)
                request.timeoutInterval = 5
                if !config.authToken.isEmpty {
                    request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
                }

                let (data, _) = try await URLSession.shared.data(for: request)

                struct ContextResponse: Codable {
                    let recent_sessions: [SessionContext]
                }

                let response = try JSONDecoder().decode(ContextResponse.self, from: data)
                routerLogger.info("Fetched \(response.recent_sessions.count) session contexts for \(typeID)")
                return response.recent_sessions
            } catch {
                routerLogger.error("Context fetch failed for \(typeID): \(error.localizedDescription)")
                return []
            }
        })
    }
}

extension DependencyValues {
    var destinationRouter: DestinationRouterClient {
        get { self[DestinationRouterClient.self] }
        set { self[DestinationRouterClient.self] = newValue }
    }
}

// MARK: - Local storage

private func saveSessionLocally(_ session: Session) async throws {
    let dir = try sessionsDirectory()
    let fileURL = dir.appendingPathComponent("\(session.id).json")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(session)
    try data.write(to: fileURL, options: .atomic)
}

private func sessionsDirectory() throws -> URL {
    let appSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let dir = appSupport.appendingPathComponent("Download/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
