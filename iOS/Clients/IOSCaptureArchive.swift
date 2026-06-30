//
//  IOSCaptureArchive.swift
//  Basn iOS
//
//  Lightweight, BasnCore-free capture archive for the phone. The phone only
//  RECORDS — it saves the raw audio + minimal metadata into a dated per-capture
//  folder in the app's Documents (retrievable via the Files app). All
//  assessment (desktop transcription, routing, grading) happens later on the
//  Mac after the folders are pulled across; see the desktop "Import captures"
//  flow (DebugBar) which reads exactly this layout.
//
//  NOTE: this ships in ALL builds (not #if DEBUG) so it can run on a real device
//  / TestFlight, but it is INERT unless the hidden Developer mode is unlocked AND
//  the archive toggle is on — see DeveloperMode + SettingsView.
//
//  Layout mirrors macOS DebugCaptureArchive:
//    <Documents>/BasnCaptures/<yyyy-MM-dd>/<HH-mm-ss>-<shortid>/
//      audio.wav  metadata.json
//
//  metadata.json keys match BasnCore.CaptureArchiveMetadata (ISO-8601 dates) so
//  the desktop decoder reads it directly.
//

import Foundation

enum IOSCaptureArchive {

    /// Same UserDefaults key as the macOS DebugBar toggle.
    static let toggleKey = "BasnRecordScenarios"

    /// Archiving runs only when Developer mode is unlocked AND the toggle is on.
    static var isEnabled: Bool {
        DeveloperMode.isUnlocked && UserDefaults.standard.bool(forKey: toggleKey)
    }

    static var rootURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BasnCaptures", isDirectory: true)
    }

    /// Mirror of BasnCore.CaptureArchiveMetadata (key names must match).
    struct Metadata: Encodable {
        let captureID: String
        let timestamp: Date
        let device: String
        let flowID: String
        let durationSeconds: Double
        let wordCount: Int
        let whisperModel: String
        let language: String?
        let sourceAppBundleID: String?
        let sourceAppName: String?
        let appVersion: String
        let connectedToolIDs: [String]
        let platform: String?
        let onDeviceTranscript: String?
    }

    /// Archive a capture's audio + metadata. No-ops unless the toggle is on.
    static func archive(audioURL: URL, metadata: Metadata) {
        guard isEnabled, let root = rootURL else { return }
        let day = dayFormatter.string(from: metadata.timestamp)
        let time = timeFormatter.string(from: metadata.timestamp)
        let shortID = metadata.captureID.replacingOccurrences(of: "-", with: "").prefix(8)
        let folder = root
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("\(time)-\(shortID)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent("audio.wav")
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: audioURL, to: dest)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metadata)
            try data.write(to: folder.appendingPathComponent("metadata.json"))
        } catch {
            // Best-effort; archiving must never disrupt capture.
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH-mm-ss"
        return f
    }()
}
