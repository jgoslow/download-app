import Foundation

/// A single entry in a structured voice capture.
///
/// Entries are ordered by capture time. Both chip selections and voice/text
/// are co-equal responses to a prompt — merge them in the same entry.
/// `promptIndex` and `promptTitle` are nil when no guided prompt was active.
public struct CaptureEntry: Codable, Sendable, Equatable {
    public let sentence: String
    public let promptIndex: Int?
    public let promptTitle: String?
    public let chips: [String]

    public init(
        sentence: String,
        promptIndex: Int? = nil,
        promptTitle: String? = nil,
        chips: [String] = []
    ) {
        self.sentence = sentence
        self.promptIndex = promptIndex
        self.promptTitle = promptTitle
        self.chips = chips
    }
}

/// A structured capture with prompt-tagged sentences and chip selections.
///
/// The canonical input to Castellum. Use `StructuredCapture.from(session:)` to
/// bridge from flat Session transcripts (desktop batch path).
public struct StructuredCapture: Sendable {
    public let captureID: String
    public let flowID: String
    public let timestamp: Date
    public let durationSeconds: Double
    public let entries: [CaptureEntry]

    public var rawText: String {
        entries.map(\.sentence).joined(separator: " ")
    }

    public var wordCount: Int {
        entries.reduce(0) { $0 + $1.sentence.split(separator: " ").count }
    }

    public init(
        captureID: String,
        flowID: String,
        timestamp: Date = Date(),
        durationSeconds: Double,
        entries: [CaptureEntry]
    ) {
        self.captureID = captureID
        self.flowID = flowID
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.entries = entries
    }

    /// Bridge from a flat Session (desktop batch path). Splits on sentence boundaries
    /// to produce unprompted entries. iOS callers should construct directly from
    /// FlowSessionViewModel.transcriptEntries instead.
    public static func from(session: Session) -> StructuredCapture {
        let sentences = session.rawText
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let entries = sentences.isEmpty
            ? [CaptureEntry(sentence: session.rawText)]
            : sentences.map { CaptureEntry(sentence: $0) }
        return StructuredCapture(
            captureID: session.id,
            flowID: session.flowID,
            timestamp: session.timestamp,
            durationSeconds: session.durationSeconds,
            entries: entries
        )
    }
}
