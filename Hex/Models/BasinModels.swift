//
//  BasinModels.swift
//  Basin
//
//  SwiftData models for the Basin persistence layer.
//  All app data flows through these models: captures, analysis, flows, tools, and channels.
//

import Foundation
import SwiftData

// MARK: - Captures

/// A completed voice capture — the core data unit in Basin.
/// Created when a recording finishes transcription. Optionally linked to a CaptureAnalysis.
@Model final class CaptureRecord {
    @Attribute(.unique) var id: String
    var timestamp: Date
    var device: String
    var platform: String
    var flowID: String
    var rawText: String
    var durationSeconds: Double
    var wordCount: Int
    var scheduled: Bool
    var snoozeCount: Int
    var audioPath: String?
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var appVersion: String
    var whisperModel: String
    var language: String?

    @Relationship(deleteRule: .cascade, inverse: \CaptureAnalysis.capture)
    var analysis: CaptureAnalysis?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        device: String,
        platform: String = "macos",
        flowID: String = "open",
        rawText: String,
        durationSeconds: Double,
        wordCount: Int,
        scheduled: Bool = false,
        snoozeCount: Int = 0,
        audioPath: String? = nil,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        appVersion: String,
        whisperModel: String,
        language: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.platform = platform
        self.flowID = flowID
        self.rawText = rawText
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.scheduled = scheduled
        self.snoozeCount = snoozeCount
        self.audioPath = audioPath
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.appVersion = appVersion
        self.whisperModel = whisperModel
        self.language = language
    }
}

/// AI-generated analysis of a capture (Phase 2).
/// One-to-one with CaptureRecord. Created after the Anthropic API call completes.
@Model final class CaptureAnalysis {
    @Attribute(.unique) var id: String
    var summary: String
    var moodTag: String?
    var tasks: [String]
    var routing: [String]
    var delegations: [String]
    var integrations: [String]
    var promptsAddressed: [Int]
    var createdAt: Date

    var capture: CaptureRecord?

    init(
        id: String = UUID().uuidString,
        summary: String,
        moodTag: String? = nil,
        tasks: [String] = [],
        routing: [String] = [],
        delegations: [String] = [],
        integrations: [String] = [],
        promptsAddressed: [Int] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.moodTag = moodTag
        self.tasks = tasks
        self.routing = routing
        self.delegations = delegations
        self.integrations = integrations
        self.promptsAddressed = promptsAddressed
        self.createdAt = createdAt
    }
}

// MARK: - Flows

/// A named capture ritual — defines prompts, schedule, and routing for a class of recording.
/// Only "Open" exists by default. Users add flows from templates or create custom ones.
@Model final class FlowDefinition {
    @Attribute(.unique) var id: String
    var name: String
    var intro: String
    var cadence: String
    var domains: [String]
    var sortOrder: Int
    var isTemplate: Bool

    // Schedule (flattened for SwiftData/CloudKit compatibility)
    var scheduleDays: [String]
    var scheduleReminderTime: String?
    var scheduleReminderEnabled: Bool
    var scheduleSuggestedDurationMinutes: Int
    var scheduleNotificationTitle: String
    var scheduleNotificationBody: String
    var scheduleSnoozeOptionsMinutes: [Int]

    // Prompts stored as encoded JSON
    var promptsJSON: Data?

    // Which channels this flow routes to
    var channelIDs: [String]

    init(
        id: String,
        name: String,
        intro: String = "",
        cadence: String = "on-demand",
        domains: [String] = [],
        sortOrder: Int = 0,
        isTemplate: Bool = false,
        scheduleDays: [String] = [],
        scheduleReminderTime: String? = nil,
        scheduleReminderEnabled: Bool = false,
        scheduleSuggestedDurationMinutes: Int = 10,
        scheduleNotificationTitle: String = "",
        scheduleNotificationBody: String = "",
        scheduleSnoozeOptionsMinutes: [Int] = [5, 10, 60],
        promptsJSON: Data? = nil,
        channelIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.intro = intro
        self.cadence = cadence
        self.domains = domains
        self.sortOrder = sortOrder
        self.isTemplate = isTemplate
        self.scheduleDays = scheduleDays
        self.scheduleReminderTime = scheduleReminderTime
        self.scheduleReminderEnabled = scheduleReminderEnabled
        self.scheduleSuggestedDurationMinutes = scheduleSuggestedDurationMinutes
        self.scheduleNotificationTitle = scheduleNotificationTitle
        self.scheduleNotificationBody = scheduleNotificationBody
        self.scheduleSnoozeOptionsMinutes = scheduleSnoozeOptionsMinutes
        self.promptsJSON = promptsJSON
        self.channelIDs = channelIDs
    }

    // MARK: - Prompt helpers

    var prompts: [FlowPrompt] {
        get {
            guard let data = promptsJSON else { return [] }
            return (try? JSONDecoder().decode([FlowPrompt].self, from: data)) ?? []
        }
        set {
            promptsJSON = try? JSONEncoder().encode(newValue)
        }
    }
}

/// A single guided prompt within a flow.
struct FlowPrompt: Codable, Identifiable, Sendable, Equatable {
    var id: Int
    var title: String
    var detail: String
}

// MARK: - Tools (mechanisms)

/// An external service that does the work at the end of a channel.
/// In the waterworks metaphor, tools are the mechanisms — fountains, baths, clocks.
@Model final class Tool {
    @Attribute(.unique) var id: String
    var name: String
    var iconSystemName: String
    var isConnected: Bool
    var autoExecute: Bool

    /// Which auth method the user has chosen: "oauth" or "api_key". Nil = "oauth" (default).
    var activeAuthMethod: String?

    /// Whether OAuth is available for this tool. Nil = true (default).
    var supportsOAuth: Bool?
    /// Whether API key auth is available for this tool. Nil = true (default).
    var supportsAPIKey: Bool?

    // OAuth fields — tokens stored in iCloud Keychain via KeychainClient
    var oauthScopes: String?

    // API key fields — key stored in iCloud Keychain via KeychainClient
    var apiKeyLabel: String?
    var baseURL: String?

    /// Scope keys the user has enabled for this tool (e.g. ["calendar", "docs"]).
    /// Nil means use the tool definition's defaults.
    var selectedScopeKeys: [String]?

    /// Action keys the user has explicitly disabled. Nil means all actions enabled.
    var enabledActionKeys: [String]?

    /// When the tool was last successfully connected (OAuth or API key).
    // TODO: Use this to send a system notification N days before token expiry (via KeychainClient.loadExpiry), and
    //       surface a "Reconnect [Tool]" inline link in workflow summaries when an action fails due to auth.
    var connectedAt: Date?

    /// When Basin last successfully executed an action using this tool.
    var lastUsedAt: Date?

    /// Cached service metadata (e.g., Jira project list, Slack channels).
    /// Stored as JSON. Fetched after OAuth connect and refreshed periodically.
    var serviceMetadata: Data?

    /// Legacy field — migration only
    var authType: String
    var authToken: String?
    var authMetadata: Data?

    init(
        id: String,
        name: String,
        iconSystemName: String,
        isConnected: Bool = false,
        autoExecute: Bool = false,
        activeAuthMethod: String? = "oauth",
        supportsOAuth: Bool? = true,
        supportsAPIKey: Bool? = true,
        apiKeyLabel: String? = "API Token",
        baseURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.isConnected = isConnected
        self.autoExecute = autoExecute
        self.activeAuthMethod = activeAuthMethod
        self.supportsOAuth = supportsOAuth
        self.supportsAPIKey = supportsAPIKey
        self.apiKeyLabel = apiKeyLabel
        self.baseURL = baseURL
        // Legacy defaults
        self.authType = activeAuthMethod ?? "oauth"
        self.authToken = nil
        self.authMetadata = nil
    }

    var effectiveAuthMethod: String { activeAuthMethod ?? "oauth" }
    var effectiveSupportsOAuth: Bool { supportsOAuth ?? true }
    var effectiveSupportsAPIKey: Bool { supportsAPIKey ?? true }

    /// OAuth provider identifier used to look up the OAuth config
    var oauthProvider: String? {
        switch id {
        case "github": return "github"
        case "jira": return "atlassian"
        case "google", "calendar", "email": return "google"
        case "slack": return "slack"
        default: return nil
        }
    }

    static let allDefaults: [Tool] = [
        Tool(id: "jira", name: "Jira", iconSystemName: "ticket",
             supportsOAuth: true, supportsAPIKey: true,
             apiKeyLabel: "API Token (email:token)"),
        Tool(id: "github", name: "GitHub", iconSystemName: "chevron.left.forwardslash.chevron.right",
             supportsOAuth: true, supportsAPIKey: true,
             apiKeyLabel: "Personal Access Token"),
        Tool(id: "slack", name: "Slack", iconSystemName: "bubble.left.and.bubble.right",
             supportsOAuth: true, supportsAPIKey: true,
             apiKeyLabel: "Bot Token"),
        Tool(id: "toggl", name: "Toggl", iconSystemName: "clock",
             activeAuthMethod: "api_key", supportsOAuth: false, supportsAPIKey: true,
             apiKeyLabel: "API Token"),
        Tool(id: "google", name: "Google", iconSystemName: "globe",
             supportsOAuth: true, supportsAPIKey: false),
        Tool(id: "wave", name: "Wave", iconSystemName: "dollarsign.circle",
             supportsOAuth: true, supportsAPIKey: false),
    ]
}

// MARK: - Workflows

/// A named automation with an English-language instruction that guides Castellum.
/// Workflows are not predefined — they emerge from connected tools and capture context,
/// or are created during onboarding. The instruction is what makes each workflow unique.
@Model final class Workflow {
    @Attribute(.unique) var id: String
    var name: String
    var iconSystemName: String
    var isEnabled: Bool
    var sortOrder: Int
    /// Plain-English instruction fed to Castellum alongside the capture transcript.
    /// e.g. "When tasks are mentioned, create a Jira card in the most relevant project."
    var instruction: String
    /// Optional: scope this workflow to a specific Flow ID. Nil = active in all flows.
    var flowID: String?

    init(
        id: String,
        name: String,
        iconSystemName: String,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        instruction: String,
        flowID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.instruction = instruction
        self.flowID = flowID
    }
}
