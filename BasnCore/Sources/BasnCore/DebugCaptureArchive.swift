import Foundation
import CryptoKit

/// Side-channel archive for debug builds: saves the audio and all derived JSON
/// for a capture into a dated, per-capture folder so recordings can be kept for
/// development and promoted into test fixtures / the audio corpus.
///
/// Layout (under the app container's Documents):
/// ```
/// BasnCaptures/2026-06-27/14-32-07-ab12cd34/
///   audio.wav  scenario.json  metadata.json  analysis.json  plan.json  grade.json
/// ```
///
/// Opt-in: gated by the `BasnRecordScenarios` UserDefaults flag (the DebugBar
/// "Archive captures" toggle). Every writer no-ops when disabled. The folder is
/// keyed deterministically by `captureID` so the two natural write sites — audio
/// in `TranscriptionFeature`, raw Castellum blocks in `CastellumClient` — land in
/// the same folder without sharing state.
public enum DebugCaptureArchive {

    /// UserDefaults key for the opt-in toggle. Reused from the legacy scenario
    /// recorder this supersedes, so no migration is needed.
    public static let toggleKey = "BasnRecordScenarios"

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: toggleKey)
    }

    /// Root folder for all archived captures: `<Documents>/BasnCaptures`.
    public static var rootURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BasnCaptures", isDirectory: true)
    }

    // MARK: - Folder resolution

    /// Deterministic per-capture folder. Returns `nil` when archiving is disabled
    /// or the Documents directory is unavailable. Creates the directory on demand.
    @discardableResult
    public static func folderURL(captureID: String, timestamp: Date, create: Bool = true) -> URL? {
        guard isEnabled, let root = rootURL else { return nil }
        let day = dayFormatter.string(from: timestamp)
        let time = timeFormatter.string(from: timestamp)
        let shortID = captureID.replacingOccurrences(of: "-", with: "").prefix(8)
        let folder = root
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("\(time)-\(shortID)", isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    // MARK: - Writers

    public static func writeAudio(from sourceURL: URL, captureID: String, timestamp: Date) {
        guard let folder = folderURL(captureID: captureID, timestamp: timestamp) else { return }
        let dest = folder.appendingPathComponent("audio.wav")
        FileManager.default.removeItemIfExists(at: dest)
        try? FileManager.default.copyItem(at: sourceURL, to: dest)
    }

    public static func writeScenario(_ scenario: CaptureScenario, captureID: String, timestamp: Date) {
        write(scenario, named: "scenario.json", captureID: captureID, timestamp: timestamp)
    }

    public static func writeMetadata(_ metadata: CaptureArchiveMetadata, captureID: String, timestamp: Date) {
        write(metadata, named: "metadata.json", captureID: captureID, timestamp: timestamp)
    }

    public static func writeAnalysis(_ analysis: SessionAnalysis, captureID: String, timestamp: Date) {
        write(analysis, named: "analysis.json", captureID: captureID, timestamp: timestamp)
    }

    public static func writePlan(_ plan: ExecutionPlan, captureID: String, timestamp: Date) {
        write(plan, named: "plan.json", captureID: captureID, timestamp: timestamp)
    }

    public static func writeGrade(_ grade: CaptureGrade, captureID: String, timestamp: Date) {
        write(grade, named: "grade.json", captureID: captureID, timestamp: timestamp)
    }

    /// Load an existing grade so human feedback can be merged. Returns `nil` if
    /// none was written yet. Ignores the enabled flag so grading still works if
    /// the toggle was flipped off after capture.
    public static func loadGrade(captureID: String, timestamp: Date) -> CaptureGrade? {
        guard let root = rootURL else { return nil }
        let day = dayFormatter.string(from: timestamp)
        let time = timeFormatter.string(from: timestamp)
        let shortID = captureID.replacingOccurrences(of: "-", with: "").prefix(8)
        let url = root
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("\(time)-\(shortID)", isDirectory: true)
            .appendingPathComponent("grade.json")
        return decode(url)
    }

    // MARK: - Review (debug grading UI)

    /// One archived capture on disk, with its decoded metadata and grade.
    public struct ArchivedCapture: Identifiable, Sendable {
        public let id: String          // folder path
        public let folder: URL
        public let metadata: CaptureArchiveMetadata?
        public var grade: CaptureGrade?
        public var hasAudio: Bool
        /// Best-effort transcript for previews: scenario rawText, else the
        /// on-device transcript from metadata.
        public let transcript: String?

        public init(folder: URL, metadata: CaptureArchiveMetadata?, grade: CaptureGrade?, hasAudio: Bool, transcript: String? = nil) {
            self.id = folder.path
            self.folder = folder
            self.metadata = metadata
            self.grade = grade
            self.hasAudio = hasAudio
            self.transcript = transcript
        }

        public var audioURL: URL? {
            hasAudio ? folder.appendingPathComponent("audio.wav") : nil
        }
    }

    /// The full contents of a capture folder, for the review detail pane.
    public struct CaptureDetail {
        public let transcript: String
        public let summary: String?
        public let routedVia: String?
        public let actions: [PlannedAction]
        public let expectedActions: [CaptureScenario.ExpectedAction]
        /// Raw pretty-printed file contents, for side-by-side comparison.
        public let scenarioJSON: String?
        public let planJSON: String?
        public let analysisJSON: String?
        public let metadataJSON: String?
    }

    /// Load everything needed to review a single capture folder.
    public static func loadDetail(for folder: URL) -> CaptureDetail {
        let scenario: CaptureScenario? = decode(folder.appendingPathComponent("scenario.json"))
        let plan: ExecutionPlan? = decode(folder.appendingPathComponent("plan.json"))
        let analysis: SessionAnalysis? = decode(folder.appendingPathComponent("analysis.json"))
        let metadata: CaptureArchiveMetadata? = decode(folder.appendingPathComponent("metadata.json"))

        let transcript = scenario?.rawText
            ?? scenario?.expectedTranscript
            ?? metadata?.onDeviceTranscript
            ?? ""

        return CaptureDetail(
            transcript: transcript,
            summary: analysis?.summary,
            routedVia: scenario?.routedVia.rawValue ?? plan?.modelUsed,
            actions: plan?.actions ?? [],
            expectedActions: scenario?.expected.actions ?? [],
            scenarioJSON: rawString(folder.appendingPathComponent("scenario.json")),
            planJSON: rawString(folder.appendingPathComponent("plan.json")),
            analysisJSON: rawString(folder.appendingPathComponent("analysis.json")),
            metadataJSON: rawString(folder.appendingPathComponent("metadata.json"))
        )
    }

    private static func rawString(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// Enumerate archived captures, newest first. Reads `metadata.json` /
    /// `grade.json` from each `<root>/<day>/<time-id>/` folder.
    public static func listArchivedCaptures() -> [ArchivedCapture] {
        guard let root = rootURL,
              let days = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil
              )
        else { return [] }

        var captures: [ArchivedCapture] = []
        for day in days where day.hasDirectoryPath {
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: day, includingPropertiesForKeys: nil
            )) ?? []
            for folder in folders where folder.hasDirectoryPath {
                let metadata: CaptureArchiveMetadata? = decode(folder.appendingPathComponent("metadata.json"))
                let grade: CaptureGrade? = decode(folder.appendingPathComponent("grade.json"))
                let scenario: CaptureScenario? = decode(folder.appendingPathComponent("scenario.json"))
                let hasAudio = FileManager.default.fileExists(
                    atPath: folder.appendingPathComponent("audio.wav").path
                )
                let transcript = scenario?.rawText ?? metadata?.onDeviceTranscript
                captures.append(ArchivedCapture(
                    folder: folder, metadata: metadata, grade: grade,
                    hasAudio: hasAudio, transcript: transcript
                ))
            }
        }
        return captures.sorted {
            ($0.metadata?.timestamp ?? .distantPast) > ($1.metadata?.timestamp ?? .distantPast)
        }
    }

    /// Write a grade into an explicit folder (used by the review UI, which works
    /// off enumerated folders rather than a captureID/timestamp key).
    public static func writeGrade(_ grade: CaptureGrade, to folder: URL) {
        writeArtifact(grade, named: "grade.json", to: folder)
    }

    /// Load a grade from an explicit folder.
    public static func loadGrade(in folder: URL) -> CaptureGrade? {
        decode(folder.appendingPathComponent("grade.json"))
    }

    // MARK: - Ingest (explicit-folder, toggle-independent)
    //
    // Used by the desktop ingest flow, which assesses audio pulled from another
    // device. These create/write regardless of the "Archive captures" toggle —
    // the user explicitly chose to import.

    /// Create (if needed) and return a dated capture folder, ignoring the toggle.
    /// Returns nil only if the Documents directory is unavailable.
    public static func ingestFolderURL(captureID: String, timestamp: Date) -> URL? {
        guard let root = rootURL else { return nil }
        let day = dayFormatter.string(from: timestamp)
        let time = timeFormatter.string(from: timestamp)
        let shortID = captureID.replacingOccurrences(of: "-", with: "").prefix(8)
        let folder = root
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("\(time)-\(shortID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public static func copyAudio(from sourceURL: URL, to folder: URL) {
        let dest = folder.appendingPathComponent("audio.wav")
        FileManager.default.removeItemIfExists(at: dest)
        try? FileManager.default.copyItem(at: sourceURL, to: dest)
    }

    // MARK: - Import de-duplication

    /// SHA-256 of a file's bytes, lowercase hex. The content identity used to
    /// recognize a re-imported capture even when its `captureID` differs (e.g. a
    /// loose `.wav` with no metadata, which gets a fresh random id each import).
    public static func audioHash(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Find an already-ingested capture matching either the given `captureID` or
    /// the given audio content hash, so a duplicate import can be skipped. Returns
    /// the existing capture's folder, or nil if this capture is new. Existing
    /// captures compare by their stored `audioSHA256`; folders imported before
    /// hashing existed are hashed on demand as a fallback.
    public static func findExistingCapture(captureID: String, audioSHA256: String?) -> URL? {
        for capture in listArchivedCaptures() {
            guard let metadata = capture.metadata else { continue }
            if metadata.captureID == captureID { return capture.folder }
            if let incoming = audioSHA256 {
                let existing = metadata.audioSHA256 ?? capture.audioURL.flatMap { audioHash(for: $0) }
                if existing == incoming { return capture.folder }
            }
        }
        return nil
    }

    /// Write any Codable artifact to a named file in an explicit folder.
    public static func writeArtifact<T: Encodable>(_ value: T, named: String, to folder: URL) {
        guard let data = try? makeEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(named))
    }

    // MARK: - Internals

    private static func write<T: Encodable>(_ value: T, named: String, captureID: String, timestamp: Date) {
        guard let folder = folderURL(captureID: captureID, timestamp: timestamp) else { return }
        guard let data = try? makeEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(named))
    }

    private static func decode<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "HH-mm-ss"
        return f
    }()
}

/// Lightweight metadata describing the capture environment, written alongside
/// the audio. A superset of what fixtures need; trimmed during promotion.
public struct CaptureArchiveMetadata: Codable, Sendable, Equatable {
    public let captureID: String
    public let timestamp: Date
    public let device: String
    public let flowID: String
    public let durationSeconds: Double
    public let wordCount: Int
    public let whisperModel: String
    public let language: String?
    public let sourceAppBundleID: String?
    public let sourceAppName: String?
    public let appVersion: String
    public let connectedToolIDs: [String]
    /// Platform that produced the capture, e.g. "macos" / "ios".
    public let platform: String?
    /// Transcript produced on the capturing device (iOS), kept as a reference
    /// for desktop ingest (labeling + WER comparison). Nil on the macOS path,
    /// where the transcript lives in scenario.json.
    public let onDeviceTranscript: String?
    /// SHA-256 (lowercase hex) of the capture's audio bytes, used to de-duplicate
    /// re-imports by content. Nil for captures archived before hashing existed.
    public let audioSHA256: String?

    public init(
        captureID: String,
        timestamp: Date,
        device: String,
        flowID: String,
        durationSeconds: Double,
        wordCount: Int,
        whisperModel: String,
        language: String?,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        appVersion: String,
        connectedToolIDs: [String],
        platform: String? = nil,
        onDeviceTranscript: String? = nil,
        audioSHA256: String? = nil
    ) {
        self.captureID = captureID
        self.timestamp = timestamp
        self.device = device
        self.flowID = flowID
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.whisperModel = whisperModel
        self.language = language
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.appVersion = appVersion
        self.connectedToolIDs = connectedToolIDs
        self.platform = platform
        self.onDeviceTranscript = onDeviceTranscript
        self.audioSHA256 = audioSHA256
    }
}
