//
//  OAuthClient.swift
//  Basin
//
//  Handles OAuth 2.0 + PKCE flows for external tool connections.
//  Opens the user's browser for authorization, handles the basin:// callback,
//  exchanges codes for tokens, and manages refresh.
//

import CryptoKit
import Foundation
import os
#if os(macOS)
import AppKit
#endif

private let oauthLogger = Logger(subsystem: "com.lyra.basn", category: "oauth")

// MARK: - Provider Configuration

struct OAuthProviderConfig {
    let authorizationURL: String
    let tokenURL: String
    let clientID: String
    let clientSecret: String?
    let scopes: [String]
    let usePKCE: Bool
    /// Slack requires HTTPS redirect URIs — use the Cloudflare passthrough page
    let requiresHTTPSRedirect: Bool

    /// Read a string from Info.plist (populated from Secrets.xcconfig at build time)
    private static func bundleString(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }

    static let github = OAuthProviderConfig(
        authorizationURL: "https://github.com/login/oauth/authorize",
        tokenURL: "https://github.com/login/oauth/access_token",
        clientID: bundleString("GitHubClientID"),
        clientSecret: bundleString("GitHubClientSecret"),
        scopes: ["repo", "read:user"],
        usePKCE: false,
        requiresHTTPSRedirect: false
    )

    static let google = OAuthProviderConfig(
        authorizationURL: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenURL: "https://oauth2.googleapis.com/token",
        clientID: bundleString("GoogleClientID"),
        clientSecret: bundleString("GoogleClientSecret"),
        scopes: [
            "https://www.googleapis.com/auth/calendar",
            "https://www.googleapis.com/auth/gmail.send",
            "https://www.googleapis.com/auth/documents",
            "https://www.googleapis.com/auth/drive.file",
        ],
        usePKCE: true,
        requiresHTTPSRedirect: true
    )

    static let atlassian = OAuthProviderConfig(
        authorizationURL: "https://auth.atlassian.com/authorize",
        tokenURL: "https://auth.atlassian.com/oauth/token",
        clientID: bundleString("AtlassianClientID"),
        clientSecret: bundleString("AtlassianClientSecret"),
        scopes: ["read:jira-work", "write:jira-work", "read:jira-user", "offline_access"],
        usePKCE: true,
        requiresHTTPSRedirect: false
    )

    static let slack = OAuthProviderConfig(
        authorizationURL: "https://slack.com/oauth/v2/authorize",
        tokenURL: "https://slack.com/api/oauth.v2.access",
        clientID: bundleString("SlackClientID"),
        clientSecret: bundleString("SlackClientSecret"),
        scopes: ["chat:write", "channels:read", "users:read"],
        usePKCE: false,
        requiresHTTPSRedirect: true
    )

    static func config(for provider: String) -> OAuthProviderConfig? {
        switch provider {
        case "github": return .github
        case "google": return .google
        case "atlassian": return .atlassian
        case "slack": return .slack
        default: return nil
        }
    }
}

// MARK: - PKCE

struct PKCEChallenge {
    let verifier: String
    let challenge: String
    let method: String = "S256"

    static func generate() -> PKCEChallenge {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncoded()

        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = challengeData.base64URLEncoded()

        return PKCEChallenge(verifier: verifier, challenge: challenge)
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - OAuth Client

actor OAuthClient {
    static let shared = OAuthClient()

    private let redirectURI = "basin://oauth/callback"
    /// HTTPS redirect for providers that don't support custom schemes (e.g., Slack).
    /// Cloudflare page at this URL passes query params through to basin://oauth/callback.
    private let httpsRedirectURI = "https://getbasin.ai/oauth/callback"

    #if os(macOS)
    private var pendingFlows: [String: PendingFlow] = [:]

    struct PendingFlow {
        let provider: String
        let toolID: String
        let pkce: PKCEChallenge?
        let state: String
        let continuation: CheckedContinuation<OAuthTokenResponse, Error>
    }
    #endif

    struct OAuthTokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        let scope: String?
    }

    enum OAuthError: LocalizedError {
        case noConfig(String)
        case noClientID(String)
        case noMatchingFlow
        case callbackError(String)
        case tokenExchangeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noConfig(let p): return "No OAuth config for provider: \(p)"
            case .noClientID(let p): return "No client ID configured for \(p). Register at the provider's developer console."
            case .noMatchingFlow: return "Received callback for unknown OAuth flow"
            case .callbackError(let e): return "OAuth error: \(e)"
            case .tokenExchangeFailed(let e): return "Token exchange failed: \(e)"
            }
        }
    }

    /// Start an OAuth flow: opens the browser and returns tokens when complete.
    /// Pass `scopes` to override the provider's default scopes (e.g. user-selected subset).
    func startFlow(provider: String, toolID: String, scopes: [String]? = nil) async throws -> OAuthTokenResponse {
        guard let config = OAuthProviderConfig.config(for: provider) else {
            throw OAuthError.noConfig(provider)
        }

        guard !config.clientID.isEmpty else {
            throw OAuthError.noClientID(provider)
        }

        let state = UUID().uuidString
        let pkce = config.usePKCE ? PKCEChallenge.generate() : nil

        // Slack requires HTTPS redirect — use the Cloudflare passthrough page
        let effectiveRedirectURI = config.requiresHTTPSRedirect ? httpsRedirectURI : redirectURI
        let effectiveScopes = scopes ?? config.scopes

        var components = URLComponents(string: config.authorizationURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: effectiveRedirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: effectiveScopes.joined(separator: " ")),
        ]

        if let pkce {
            components.queryItems?.append(URLQueryItem(name: "code_challenge", value: pkce.challenge))
            components.queryItems?.append(URLQueryItem(name: "code_challenge_method", value: pkce.method))
        }

        // Atlassian requires audience parameter
        if provider == "atlassian" {
            components.queryItems?.append(URLQueryItem(name: "audience", value: "api.atlassian.com"))
            components.queryItems?.append(URLQueryItem(name: "prompt", value: "consent"))
        }

        // Google requires offline access to receive a refresh_token
        if provider == "google" {
            components.queryItems?.append(URLQueryItem(name: "access_type", value: "offline"))
            components.queryItems?.append(URLQueryItem(name: "prompt", value: "consent"))
        }

        let authURL = components.url!
        oauthLogger.info("Opening OAuth flow for \(provider, privacy: .public) tool=\(toolID, privacy: .public)")

        #if os(macOS)
        return try await withCheckedThrowingContinuation { continuation in
            pendingFlows[state] = PendingFlow(
                provider: provider,
                toolID: toolID,
                pkce: pkce,
                state: state,
                continuation: continuation
            )

            DispatchQueue.main.async {
                NSWorkspace.shared.open(authURL)
            }
        }
        #elseif os(iOS)
        return try await startFlowIOS(authURL: authURL, state: state, provider: provider, pkce: pkce)
        #endif
    }

    /// Called from the app delegate when basin://oauth/callback is received. macOS only.
    #if os(macOS)
    func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            oauthLogger.error("Invalid OAuth callback URL")
            return
        }

        let params = Dictionary(queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        }, uniquingKeysWith: { _, last in last })

        guard let state = params["state"],
              let flow = pendingFlows.removeValue(forKey: state) else {
            oauthLogger.error("No pending OAuth flow for state")
            return
        }

        // Check for error response
        if let error = params["error"] {
            let desc = params["error_description"] ?? error
            flow.continuation.resume(throwing: OAuthError.callbackError(desc))
            return
        }

        guard let code = params["code"] else {
            flow.continuation.resume(throwing: OAuthError.callbackError("No authorization code in callback"))
            return
        }

        // Exchange code for tokens
        do {
            let tokens = try await exchangeCode(
                code: code,
                provider: flow.provider,
                pkceVerifier: flow.pkce?.verifier
            )
            oauthLogger.info("OAuth token exchange successful for \(flow.provider, privacy: .public)")
            flow.continuation.resume(returning: tokens)
        } catch {
            oauthLogger.error("OAuth token exchange failed: \(error.localizedDescription, privacy: .public)")
            flow.continuation.resume(throwing: error)
        }
    }
    #endif // os(macOS)

    func exchangeCode(code: String, provider: String, pkceVerifier: String?) async throws -> OAuthTokenResponse {
        guard let config = OAuthProviderConfig.config(for: provider) else {
            throw OAuthError.noConfig(provider)
        }

        let effectiveRedirectURI = config.requiresHTTPSRedirect ? httpsRedirectURI : redirectURI

        var body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": effectiveRedirectURI,
            "client_id": config.clientID,
        ]

        if let secret = config.clientSecret, !secret.isEmpty {
            body["client_secret"] = secret
        }

        if let verifier = pkceVerifier {
            body["code_verifier"] = verifier
        }

        var request = URLRequest(url: URL(string: config.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthError.tokenExchangeFailed(body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let accessToken = json["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed("No access_token in response")
        }

        return OAuthTokenResponse(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: json["expires_in"] as? Int,
            scope: json["scope"] as? String
        )
    }

    /// Refresh an expired token.
    func refreshToken(provider: String, refreshToken: String, clientID: String) async throws -> OAuthTokenResponse {
        guard let config = OAuthProviderConfig.config(for: provider) else {
            throw OAuthError.noConfig(provider)
        }

        var body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]

        // Include client_secret if the provider requires it
        if let secret = config.clientSecret, !secret.isEmpty {
            body["client_secret"] = secret
        }

        var request = URLRequest(url: URL(string: config.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthError.tokenExchangeFailed(body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let accessToken = json["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed("No access_token in refresh response")
        }

        return OAuthTokenResponse(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String ?? refreshToken,
            expiresIn: json["expires_in"] as? Int,
            scope: json["scope"] as? String
        )
    }
}
