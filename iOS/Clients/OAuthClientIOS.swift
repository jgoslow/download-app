// iOS OAuth flow using ASWebAuthenticationSession.
// ASWebAuthenticationSession handles the full browser round-trip internally —
// no URL scheme app-delegate callback needed on iOS.

#if os(iOS)
import AuthenticationServices
import Foundation
import UIKit

// MARK: - Presentation Context

/// Provides the key window as the presentation anchor for ASWebAuthenticationSession.
@MainActor
private final class OAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow) ?? UIWindow()
    }
}

// MARK: - iOS startFlow

extension OAuthClient {
    /// iOS implementation: opens an in-app Safari session and intercepts the basin:// callback.
    func startFlowIOS(authURL: URL, state: String, provider: String, pkce: PKCEChallenge?) async throws -> OAuthTokenResponse {
        let callbackURL = try await runASWAS(url: authURL)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw OAuthError.callbackError("Invalid callback URL: \(callbackURL)")
        }

        let params = Dictionary(
            queryItems.compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { _, last in last }
        )

        guard params["state"] == state else {
            throw OAuthError.callbackError("State mismatch — possible CSRF attack")
        }

        if let error = params["error"] {
            throw OAuthError.callbackError(params["error_description"] ?? error)
        }

        guard let code = params["code"] else {
            throw OAuthError.callbackError("No authorization code in callback")
        }

        return try await exchangeCode(code: code, provider: provider, pkceVerifier: pkce?.verifier)
    }

    /// Presents an ASWebAuthenticationSession and returns the callback URL.
    /// Must hop to MainActor because ASWebAuthenticationSession requires a presentation anchor.
    @MainActor
    private func runASWAS(url: URL) async throws -> URL {
        let context = OAuthPresentationContext.shared
        return try await withCheckedThrowingContinuation { continuation in
            // session is captured by the closure and stays alive until the completion handler fires.
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "basin") { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: OAuthError.callbackError("Session completed without a callback URL"))
                }
            }
            session.presentationContextProvider = context
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}
#endif
