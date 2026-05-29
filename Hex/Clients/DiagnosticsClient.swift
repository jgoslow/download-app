//
//  DiagnosticsClient.swift
//  Basin
//
//  Captures tool execution errors and optionally reports them
//  to a developer pipeline (BASN Jira project via Cloudflare Worker).
//  Opt-in via Settings → Basin → "Send diagnostics".
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import BasnCore

private let diagLogger = BasnLog.app

// MARK: - Diagnostic Event

struct DiagnosticEvent: Codable, Sendable {
    let id: String
    let timestamp: Date
    let category: Category
    let toolID: String?
    let actionType: String?
    let errorMessage: String
    let httpStatus: Int?
    let context: [String: String]
    let appVersion: String
    let buildNumber: String

    enum Category: String, Codable, Sendable {
        case toolExecution    // Jira 404, Slack auth failure, etc.
        case oauthFlow        // OAuth token exchange errors
        case transcription    // Model load or transcribe failures
        case castellumPlanner // Planner API errors
        case general          // Everything else
    }

    init(
        category: Category,
        toolID: String? = nil,
        actionType: String? = nil,
        errorMessage: String,
        httpStatus: Int? = nil,
        context: [String: String] = [:]
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.category = category
        self.toolID = toolID
        self.actionType = actionType
        self.errorMessage = errorMessage
        self.httpStatus = httpStatus
        self.context = context
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

// MARK: - Client

@DependencyClient
struct DiagnosticsClient {
    /// Record an error event. If diagnostics are enabled, it's queued for reporting.
    var report: @Sendable (DiagnosticEvent) async -> Void = { _ in }
    /// Flush any queued events to the reporting endpoint.
    var flush: @Sendable () async -> Void = {}
}

extension DiagnosticsClient: DependencyKey {
    static var liveValue: Self {
        let store = DiagnosticsStore()

        return .init(
            report: { event in
                await store.record(event)
            },
            flush: {
                await store.flush()
            }
        )
    }
}

extension DependencyValues {
    var diagnostics: DiagnosticsClient {
        get { self[DiagnosticsClient.self] }
        set { self[DiagnosticsClient.self] = newValue }
    }
}

// MARK: - Storage & Reporting

private actor DiagnosticsStore {
    private var queue: [DiagnosticEvent] = []
    private let maxQueueSize = 50
    private let endpointURL = "https://getbasin.ai/api/diagnostics"

    func record(_ event: DiagnosticEvent) {
        // Always log locally
        diagLogger.error("[\(event.category.rawValue)] \(event.toolID ?? "")/\(event.actionType ?? ""): \(event.errorMessage)")

        // Save to local file for debugging
        saveLocally(event)

        // Queue for remote reporting if enabled
        @Shared(.basnSettings) var basnSettings: BasnSettings
        guard basnSettings.basinSettings.diagnosticsEnabled else { return }

        queue.append(event)
        if queue.count > maxQueueSize {
            queue.removeFirst(queue.count - maxQueueSize)
        }

        // Auto-flush if we have enough events
        if queue.count >= 10 {
            Task { await self.flush() }
        }
    }

    func flush() async {
        guard !queue.isEmpty else { return }

        let events = queue
        queue.removeAll()

        guard let url = URL(string: endpointURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let body = try? encoder.encode(events) else { return }
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                diagLogger.info("Reported \(events.count) diagnostic events")
            } else {
                diagLogger.error("Diagnostics report failed: HTTP \(status)")
                self.queue.insert(contentsOf: events, at: 0)
            }
        } catch {
            diagLogger.error("Diagnostics report error: \(error.localizedDescription)")
            self.queue.insert(contentsOf: events, at: 0)
        }
    }

    private func saveLocally(_ event: DiagnosticEvent) {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return }

        let diagDir = appSupport.appendingPathComponent("Basin/diagnostics")
        try? FileManager.default.createDirectory(at: diagDir, withIntermediateDirectories: true)

        let file = diagDir.appendingPathComponent("\(event.id).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(event) {
            try? data.write(to: file)
        }
    }
}
