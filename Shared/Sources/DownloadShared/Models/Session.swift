import Foundation

/// A completed Download session — the structured output saved locally and sent to the CNS server.
///
/// The JSON shape is the authoritative contract between the app and any server or downstream consumer.
/// All field names use snake_case in JSON via explicit CodingKeys.
public struct Session: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let device: String
    public let platform: Platform
    public let downloadTypeID: String
    public let rawText: String
    public let durationSeconds: Double
    public let wordCount: Int
    /// Whether this session was triggered by a scheduled reminder (vs. on-demand).
    public let scheduled: Bool
    /// How many times the reminder was snoozed before the session was started.
    public let snoozeCount: Int
    public let metadata: Metadata

    public enum Platform: String, Codable, Sendable {
        case macos
        case ios
        case watchos
    }

    public struct Metadata: Codable, Sendable {
        public let appVersion: String
        public let whisperModel: String
        public let language: String?

        public init(
            appVersion: String,
            whisperModel: String,
            language: String? = nil
        ) {
            self.appVersion = appVersion
            self.whisperModel = whisperModel
            self.language = language
        }

        enum CodingKeys: String, CodingKey {
            case appVersion = "app_version"
            case whisperModel = "whisper_model"
            case language
        }
    }

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        device: String,
        platform: Platform = .macos,
        downloadTypeID: String = "open",
        rawText: String,
        durationSeconds: Double,
        wordCount: Int,
        scheduled: Bool = false,
        snoozeCount: Int = 0,
        metadata: Metadata
    ) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.platform = platform
        self.downloadTypeID = downloadTypeID
        self.rawText = rawText
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.scheduled = scheduled
        self.snoozeCount = snoozeCount
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case device
        case platform
        case downloadTypeID = "download_type_id"
        case rawText = "raw_text"
        case durationSeconds = "duration_seconds"
        case wordCount = "word_count"
        case scheduled
        case snoozeCount = "snooze_count"
        case metadata
    }
}
