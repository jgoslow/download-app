import Foundation

/// Basin app-specific settings — server endpoint, auth token, and routing behavior.
///
/// Stored as a single Codable field inside `HexSettings`. Defaults make the app
/// immediately useful in local-save-only mode without any configuration.
public struct BasinSettings: Codable, Equatable, Sendable {
    /// The server endpoint to POST sessions to. Empty string = local-only mode.
    public var serverURL: String
    /// Bearer token for authenticating with the server.
    public var authToken: String
    /// The Flow ID to use when no type has been explicitly selected. Defaults to "open".
    public var defaultFlowID: String
    /// If true, also paste the transcript to the cursor after routing.
    /// Keep this on if you want Hex's original behavior alongside session routing.
    /// Default is false — the app routes to destinations, not your cursor.
    public var pasteAfterSession: Bool
    /// Anthropic API key for Phase 2+ AI routing. Empty = Phase 1 (local save only).
    public var anthropicAPIKey: String
    /// Whether daily capture reminders are enabled.
    public var notificationsEnabled: Bool

    public init(
        serverURL: String = "",
        authToken: String = "",
        defaultFlowID: String = "open",
        pasteAfterSession: Bool = false,
        anthropicAPIKey: String = "",
        notificationsEnabled: Bool = false
    ) {
        self.serverURL = serverURL
        self.authToken = authToken
        self.defaultFlowID = defaultFlowID
        self.pasteAfterSession = pasteAfterSession
        self.anthropicAPIKey = anthropicAPIKey
        self.notificationsEnabled = notificationsEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
        authToken = try container.decodeIfPresent(String.self, forKey: .authToken) ?? ""
        defaultFlowID = try container.decodeIfPresent(String.self, forKey: .defaultFlowID) ?? "open"
        pasteAfterSession = try container.decodeIfPresent(Bool.self, forKey: .pasteAfterSession) ?? false
        anthropicAPIKey = try container.decodeIfPresent(String.self, forKey: .anthropicAPIKey) ?? ""
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case serverURL, authToken, pasteAfterSession, anthropicAPIKey, notificationsEnabled
        case defaultFlowID
    }
}
