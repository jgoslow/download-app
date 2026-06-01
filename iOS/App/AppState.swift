import AVFoundation
import BasinShared
import Foundation
import Observation
import os
import UIKit
import WhisperKit

private let appLogger = Logger(subsystem: "com.lyra.basn", category: "ios-app")

private let settingsKey = "com.lyra.basn.ios-settings"

@MainActor
@Observable
final class AppState {
    var flows: [Flow] = [.openDefault]
    var activeFlow: Flow = .openDefault
    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var audioLevel: Double = 0
    var sessions: [Session] = []
    var micPermissionGranted = false
    var isLoadingFlows = true
    var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    var showSetupFlow: Bool = !UserDefaults.standard.bool(forKey: "hasCompletedSetupFlow")
    var downloadingModelVariant: String? = nil
    var modelDownloadProgress: Double = 0
    var isTranscribing = false

    private var whisperKit: WhisperKit?
    private var loadedModelVariant: String?

    var settings: IOSAppSettings = AppState.loadSettings() {
        didSet { AppState.saveSettings(settings) }
    }

    private static func loadSettings() -> IOSAppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(IOSAppSettings.self, from: data) else {
            return IOSAppSettings()
        }
        return decoded
    }

    private static func saveSettings(_ s: IOSAppSettings) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private let recorder = RecordingClientLiveIOS()
    private let sessionStore = SessionStore.live
    private let flowStore = FlowStore.live(bundle: .main)
    private var timerTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var recordingStart: Date?

    func isModelDownloaded(variant: String) -> Bool {
        return FileManager.default.fileExists(atPath: modelFolder(for: variant).path)
    }

    func downloadModel(variant: String) async {
        if isModelDownloaded(variant: variant) {
            settings.selectedModel = variant
            try? await ensureWhisperKitLoaded(variant: variant)
            return
        }
        guard downloadingModelVariant == nil else { return }
        downloadingModelVariant = variant
        modelDownloadProgress = 0
        do {
            _ = try await WhisperKit.download(
                variant: variant,
                downloadBase: nil,
                useBackgroundSession: false,
                progressCallback: { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in self.modelDownloadProgress = fraction }
                }
            )
            modelDownloadProgress = 1.0
            settings.selectedModel = variant
            excludeModelFromBackup(variant: variant)
            try? await ensureWhisperKitLoaded(variant: variant)
        } catch {
            appLogger.error("Model download failed: \(error.localizedDescription)")
        }
        downloadingModelVariant = nil
    }

    func downloadDefaultModelIfNeeded() async {
        await downloadModel(variant: settings.selectedModel)
    }

    func ensureWhisperKitLoaded(variant: String? = nil) async throws {
        let target = variant ?? settings.selectedModel
        guard isModelDownloaded(variant: target) else { return }
        guard loadedModelVariant != target else { return }
        let folder = modelFolder(for: target)
        let config = WhisperKitConfig(
            model: target,
            modelFolder: folder.path,
            prewarm: false,
            load: true
        )
        whisperKit = try await WhisperKit(config)
        loadedModelVariant = target
        appLogger.notice("WhisperKit loaded model=\(target, privacy: .public)")
    }

    private func modelFolder(for variant: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(variant)")
    }

    private func excludeModelFromBackup(variant: String) {
        var url = modelFolder(for: variant)
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? url.setResourceValues(rv)
    }

    func load() async {
        async let loadedFlows = flowStore.loadAll()
        async let loadedSessions: [Session] = (try? sessionStore.loadAll()) ?? []
        // Check current permission status without triggering the system prompt — onboarding handles the actual request.
        micPermissionGranted = AVAudioApplication.shared.recordPermission == .granted
        flows = await loadedFlows
        sessions = await loadedSessions
        if let first = flows.first { activeFlow = first }
        isLoadingFlows = false
        appLogger.notice("Loaded \(self.flows.count) flows, \(self.sessions.count) sessions")
        // Pre-load WhisperKit in the background so the first recording doesn't wait.
        Task { try? await ensureWhisperKitLoaded() }
    }

    func startRecording() async {
        guard micPermissionGranted, !isTranscribing else {
            appLogger.warning("Cannot start recording: micPermission=\(self.micPermissionGranted) transcribing=\(self.isTranscribing)")
            return
        }
        await recorder.startRecording()
        isRecording = true
        recordingStart = Date()
        recordingDuration = 0
        audioLevel = 0
        startTimerTask()
        startLevelTask()
    }

    func stopRecording() async {
        let duration = recordingDuration
        timerTask?.cancel()
        levelTask?.cancel()
        timerTask = nil
        levelTask = nil
        let exportURL = await recorder.stopRecording()
        let capturedFlow = activeFlow
        isRecording = false
        recordingDuration = 0
        audioLevel = 0
        recordingStart = nil
        appLogger.notice("Recording stopped, file: \(exportURL.lastPathComponent, privacy: .public)")

        guard isModelDownloaded(variant: settings.selectedModel) else {
            appLogger.warning("No model downloaded — skipping transcription")
            return
        }
        isTranscribing = true
        defer { isTranscribing = false }
        do {
            try await ensureWhisperKitLoaded()
            guard let wk = whisperKit else { return }
            var options = DecodingOptions()
            if let lang = settings.outputLanguage { options.language = lang }
            let results = try await wk.transcribe(audioPath: exportURL.path, decodeOptions: options)
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                appLogger.notice("Empty transcription — skipping session save")
                return
            }
            let wordCount = text.split(whereSeparator: \.isWhitespace).count
            let session = Session(
                device: UIDevice.current.name,
                platform: .ios,
                flowID: capturedFlow.id,
                rawText: text,
                durationSeconds: duration,
                wordCount: wordCount,
                metadata: Session.Metadata(
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                    whisperModel: settings.selectedModel,
                    language: settings.outputLanguage
                )
            )
            try await sessionStore.save(session)
            await reloadSessions()
            appLogger.notice("Session saved: \(session.id, privacy: .public) words=\(wordCount)")
        } catch {
            appLogger.error("Transcription failed: \(error.localizedDescription)")
        }
    }

    func selectFlow(_ flow: Flow) {
        guard !isRecording else { return }
        activeFlow = flow
    }

    func reloadSessions() async {
        sessions = (try? await sessionStore.loadAll()) ?? []
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showOnboarding = false
        micPermissionGranted = AVAudioApplication.shared.recordPermission == .granted
    }

    func completeSetupFlow() {
        UserDefaults.standard.set(true, forKey: "hasCompletedSetupFlow")
        showSetupFlow = false
    }

    func deleteSession(_ session: Session) async {
        try? await sessionStore.delete(session.id)
        await reloadSessions()
    }

    private func startTimerTask() {
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let start = recordingStart else { break }
                recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func startLevelTask() {
        levelTask = Task { @MainActor in
            for await meter in await recorder.observeAudioLevel() {
                audioLevel = meter.averagePower
            }
        }
    }
}
