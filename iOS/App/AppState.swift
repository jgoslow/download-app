import AVFoundation
import BasinShared
import Foundation
import Observation
import os
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
    var downloadingModelVariant: String? = nil
    var modelDownloadProgress: Double = 0

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
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let path = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(variant)")
        return FileManager.default.fileExists(atPath: path.path)
    }

    func downloadModel(variant: String) async {
        if isModelDownloaded(variant: variant) {
            settings.selectedModel = variant
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
        } catch {
            appLogger.error("Model download failed: \(error.localizedDescription)")
        }
        downloadingModelVariant = nil
    }

    func downloadDefaultModelIfNeeded() async {
        await downloadModel(variant: settings.selectedModel)
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
    }

    func startRecording() async {
        guard micPermissionGranted else {
            appLogger.warning("Mic permission denied — cannot start recording")
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
        timerTask?.cancel()
        levelTask?.cancel()
        timerTask = nil
        levelTask = nil
        let exportURL = await recorder.stopRecording()
        isRecording = false
        recordingDuration = 0
        audioLevel = 0
        recordingStart = nil
        appLogger.notice("Recording stopped, file: \(exportURL.lastPathComponent, privacy: .public)")
        // Phase 7: transcribe exportURL and save Session
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
