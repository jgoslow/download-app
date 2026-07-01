import Foundation

/// iOS-specific user settings. Persisted to UserDefaults as JSON.
/// Mirrors the relevant subset of BasnSettings from BasnCore without
/// pulling in the macOS-only dependencies (Sauce, IOKit).
struct IOSAppSettings: Codable, Equatable {
    var selectedModel: String = "openai_whisper-base"
    var soundEffectsEnabled: Bool = true
    var soundEffectsVolume: Double = 1.0
    var outputLanguage: String? = nil
    var saveTranscriptionHistory: Bool = true
    var maxHistoryEntries: Int? = nil

    // AI + server
    var anthropicAPIKey: String = ""
    var serverURL: String = ""
    var authToken: String = ""
    var defaultFlowID: String = "open"
    var notificationsEnabled: Bool = false
    var diagnosticsEnabled: Bool = false

    /// When enabled, ambiguous captures on devices without Apple Intelligence are routed
    /// through a lightweight cloud model (Claude Haiku) for intent classification before
    /// falling through to full Castellum analysis. Only transcript text is transmitted.
    var lightweightCloudRoutingEnabled: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedModel         = try c.decodeIfPresent(String.self, forKey: .selectedModel)         ?? "openai_whisper-base"
        soundEffectsEnabled   = try c.decodeIfPresent(Bool.self,   forKey: .soundEffectsEnabled)   ?? true
        soundEffectsVolume    = try c.decodeIfPresent(Double.self, forKey: .soundEffectsVolume)    ?? 1.0
        outputLanguage        = try c.decodeIfPresent(String.self, forKey: .outputLanguage)
        saveTranscriptionHistory = try c.decodeIfPresent(Bool.self, forKey: .saveTranscriptionHistory) ?? true
        maxHistoryEntries     = try c.decodeIfPresent(Int.self,    forKey: .maxHistoryEntries)
        anthropicAPIKey       = try c.decodeIfPresent(String.self, forKey: .anthropicAPIKey)       ?? ""
        serverURL             = try c.decodeIfPresent(String.self, forKey: .serverURL)             ?? ""
        authToken             = try c.decodeIfPresent(String.self, forKey: .authToken)             ?? ""
        defaultFlowID         = try c.decodeIfPresent(String.self, forKey: .defaultFlowID)        ?? "open"
        notificationsEnabled  = try c.decodeIfPresent(Bool.self,   forKey: .notificationsEnabled)  ?? false
        diagnosticsEnabled    = try c.decodeIfPresent(Bool.self,   forKey: .diagnosticsEnabled)    ?? false
        lightweightCloudRoutingEnabled = try c.decodeIfPresent(Bool.self, forKey: .lightweightCloudRoutingEnabled) ?? false
    }
}
