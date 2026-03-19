import Foundation
import Logging

private let logger = Logger(label: "com.download.destination-router")

/// The outcome of routing a session.
public enum RoutingResult: Sendable {
    /// Saved to disk only — no server URL configured.
    case savedOnly
    /// Saved locally and successfully sent to server.
    case sent(statusCode: Int)
    /// Saved locally but the server POST failed.
    case serverFailed(error: String)
    /// Failed to save locally (disk write error).
    case saveFailed(error: String)

    public var savedLocally: Bool {
        switch self {
        case .savedOnly, .sent: return true
        case .serverFailed: return true  // local save succeeded, server failed
        case .saveFailed: return false
        }
    }
}

/// Routes a completed Session to configured destinations.
///
/// Phase 1: local JSON file + optional HTTP POST.
/// Phase 2+: additional routing via CNS server, Apple Notes, calendar, etc.
public struct DestinationRouter: Sendable {
    public var route: @Sendable (Session, RouterConfig) async -> RoutingResult

    public init(route: @escaping @Sendable (Session, RouterConfig) async -> RoutingResult) {
        self.route = route
    }
}

/// Configuration the router reads at call time (from app settings).
public struct RouterConfig: Sendable {
    public let serverURL: String
    public let authToken: String

    public init(serverURL: String = "", authToken: String = "") {
        self.serverURL = serverURL
        self.authToken = authToken
    }

    public var hasServer: Bool { !serverURL.isEmpty }
}

extension DestinationRouter {
    public static let live = DestinationRouter { session, config in
        // 1. Save locally — always
        do {
            try await SessionStore.live.save(session)
        } catch {
            logger.error("Failed to save session \(session.id): \(error)")
            return .saveFailed(error: error.localizedDescription)
        }
        logger.info("Saved session \(session.id) locally")

        // 2. POST to server — only if configured
        guard config.hasServer else {
            return .savedOnly
        }

        guard let serverURL = URL(string: config.serverURL) else {
            logger.error("Invalid server URL: \(config.serverURL)")
            return .serverFailed(error: "Invalid server URL")
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let body = try encoder.encode(session)

            var request = URLRequest(url: serverURL.appendingPathComponent("transcript"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !config.authToken.isEmpty {
                request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = body
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            logger.info("Session \(session.id) sent to server — HTTP \(statusCode)")
            return .sent(statusCode: statusCode)
        } catch {
            logger.error("Server POST failed for session \(session.id): \(error)")
            return .serverFailed(error: error.localizedDescription)
        }
    }
}
