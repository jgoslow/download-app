import ComposableArchitecture
import Foundation
import os
#if os(iOS)
import UIKit
#endif
#if canImport(BasnCore)
import BasnCore
private let log = BasnLog.app
#else
private let log = Logger(subsystem: "com.lyra.basn", category: "marketplace-submission")
#endif

// MARK: - Request / response types

struct ToolSubmissionRequest: Encodable {
    let toolDefinition: [String: AnyCodable]
    let testResults: [ActionTestResult]
    let submitterDevice: String?

    struct ActionTestResult: Encodable {
        let actionId: String
        let statusCode: Int
        let passed: Bool
        let errorSummary: String?
    }
}

struct ToolSubmissionResponse: Decodable {
    let prUrl: String

    enum CodingKeys: String, CodingKey {
        case prUrl = "prUrl"
    }
}

struct ToolValidationResponse: Decodable {
    let valid: Bool
    let errors: [String]?
}

// MARK: - Client interface

struct MarketplaceSubmissionClient {
    /// Validates a tool definition against the marketplace schema.
    var validate: @Sendable (_ definition: [String: Any]) async throws -> ToolValidationResponse
    /// Submits a tested tool definition — creates a PR in basn-marketplace.
    /// Returns the URL of the created pull request.
    var submit: @Sendable (_ definition: [String: Any], _ testResults: [ToolSubmissionRequest.ActionTestResult]) async throws -> String
}

// MARK: - Live implementation

extension MarketplaceSubmissionClient: DependencyKey {
    static let serviceBaseURL = URL(string: "https://marketplace.basn.app")!

    static let liveValue = MarketplaceSubmissionClient(
        validate: { definition in
            let url = serviceBaseURL.appendingPathComponent("/validate")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let wrapped = ["toolDefinition": definition]
            request.httpBody = try JSONSerialization.data(withJSONObject: wrapped)

            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(ToolValidationResponse.self, from: data)
        },

        submit: { definition, testResults in
            let url = serviceBaseURL.appendingPathComponent("/submit")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Build anonymized device fingerprint (no PII)
            let deviceID = await UIDeviceFingerprint.anonymized()

            let payload: [String: Any] = [
                "toolDefinition": definition,
                "testResults": testResults.map { r in [
                    "actionId": r.actionId,
                    "statusCode": r.statusCode,
                    "passed": r.passed,
                    "errorSummary": r.errorSummary as Any
                ] as [String: Any] },
                "submitterDevice": deviceID
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                if let errBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errBody["error"] as? String {
                    throw SubmissionError.serverError(message)
                }
                throw SubmissionError.serverError("HTTP \(http.statusCode)")
            }

            let decoded = try JSONDecoder().decode(ToolSubmissionResponse.self, from: data)
            log.info("Tool submitted; PR: \(decoded.prUrl)")
            return decoded.prUrl
        }
    )

    enum SubmissionError: LocalizedError {
        case serverError(String)
        var errorDescription: String? {
            switch self {
            case .serverError(let msg): return "Submission failed: \(msg)"
            }
        }
    }
}

// MARK: - Anonymous device fingerprint

private enum UIDeviceFingerprint {
    @MainActor
    static func anonymized() -> String {
        // Hash the machine UUID so the service can detect duplicate submissions
        // without storing any identifying information.
        #if os(macOS)
        let raw = Host.current().localizedName ?? "mac"
        #else
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? "ios"
        #endif
        return String(raw.hashValue, radix: 16)
    }
}

// MARK: - Test value

extension MarketplaceSubmissionClient: TestDependencyKey {
    static let testValue = MarketplaceSubmissionClient(
        validate: { _ in ToolValidationResponse(valid: true, errors: nil) },
        submit: { _, _ in "https://github.com/LyraDesigns/basn-marketplace/pull/1" }
    )
}

extension DependencyValues {
    var marketplaceSubmissionClient: MarketplaceSubmissionClient {
        get { self[MarketplaceSubmissionClient.self] }
        set { self[MarketplaceSubmissionClient.self] = newValue }
    }
}
