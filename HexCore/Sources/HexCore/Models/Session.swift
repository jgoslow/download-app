import Foundation

/// A completed capture — the structured output saved to disk and sent to the server.
///
/// This mirrors `BasinShared.Session` but lives in HexCore so the macOS app target
/// can use it without requiring the Shared package to be linked first.
/// When iOS/watchOS targets are added, the Shared package's Session becomes authoritative
/// and this type can be removed.
public struct Session: Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let device: String
    public let platform: Platform
    public let flowID: String
    public let rawText: String
    public let durationSeconds: Double
    public let wordCount: Int
    public let scheduled: Bool
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

        public init(appVersion: String, whisperModel: String, language: String? = nil) {
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
        flowID: String = "open",
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
        self.flowID = flowID
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
        case flowID = "flow_id"
        case rawText = "raw_text"
        case durationSeconds = "duration_seconds"
        case wordCount = "word_count"
        case scheduled
        case snoozeCount = "snooze_count"
        case metadata
    }
}
