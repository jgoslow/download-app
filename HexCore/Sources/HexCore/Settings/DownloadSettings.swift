import Foundation

/// Download app-specific settings — server endpoint, auth token, and routing behavior.
///
/// Stored as a single Codable field inside `HexSettings`. Defaults make the app
/// immediately useful in local-save-only mode without any configuration.
public struct DownloadSettings: Codable, Equatable, Sendable {
    /// The server endpoint to POST sessions to. Empty string = local-only mode.
    public var serverURL: String
    /// Bearer token for authenticating with the server.
    public var authToken: String
    /// The DownloadType ID to use when no type has been explicitly selected. Defaults to "open".
    public var defaultDownloadTypeID: String
    /// If true, also paste the transcript to the cursor after routing.
    /// Keep this on if you want Hex's original behavior alongside session routing.
    /// Default is false — the app routes to destinations, not your cursor.
    public var pasteAfterSession: Bool

    public init(
        serverURL: String = "",
        authToken: String = "",
        defaultDownloadTypeID: String = "open",
        pasteAfterSession: Bool = false
    ) {
        self.serverURL = serverURL
        self.authToken = authToken
        self.defaultDownloadTypeID = defaultDownloadTypeID
        self.pasteAfterSession = pasteAfterSession
    }
}
