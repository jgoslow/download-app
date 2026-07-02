import AudioToolbox
import AVFoundation
import BasinShared
import Foundation
import Observation
import os
import SwiftData
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
    var isPaused = false
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
    /// The most recent routing result for a capture (presented for review/execution).
    var lastPlan: ExecutionPlan?

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
    private var recorderEventTask: Task<Void, Never>?
    /// Accumulated duration from completed segments before the current one (used during pause/resume).
    private var accumulatedDuration: TimeInterval = 0
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
        startRecorderEventObserver()
    }

    /// Observe autonomous recorder events (currently: input-device loss mid-recording).
    /// Started once; the recorder's event stream lives for the app's lifetime.
    private func startRecorderEventObserver() {
        guard recorderEventTask == nil else { return }
        recorderEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.recorder.observeEvents() {
                switch event {
                case .inputDeviceLost:
                    self.handleInputDeviceLost()
                }
            }
        }
    }

    /// The recorder auto-paused because its input device was removed (USB/car/Bluetooth
    /// unplug). Mirror the pause in app state (with correct duration accounting) and alert
    /// the user so they can resume on a valid input instead of silently losing the capture.
    private func handleInputDeviceLost() {
        guard isRecording, !isPaused else { return }
        accumulatedDuration += Date().timeIntervalSince(recordingStart ?? Date())
        recordingStart = nil
        timerTask?.cancel()
        timerTask = nil
        isPaused = true
        audioLevel = 0
        playFailureSound()
        appLogger.notice("Input device lost mid-recording — paused; awaiting resume")
        // TODO: when backgrounded/locked, post a local notification that deep-links back
        // to the record screen to resume (needs a notification-permission subsystem).
    }

    /// Short alert tone + error haptic so an interrupted or failed capture is noticeable.
    /// The system-sound id is tunable; the haptic fires regardless.
    private func playFailureSound() {
        AudioServicesPlaySystemSound(1073)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// True when the recorded audio is effectively silent (near-zero peak) — e.g. a dead
    /// input after a device disconnect. Reads up to ~600s; failures return false (don't
    /// falsely flag a capture we simply can't inspect).
    private func audioIsSilent(url: URL, threshold: Float = 0.001) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let capFrames = AVAudioFrameCount(min(file.length, 16_000 * 600))
        guard capFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capFrames),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0] else { return false }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])) }
        return peak < threshold
    }

    func startRecording() async {
        guard micPermissionGranted, !isTranscribing else {
            appLogger.warning("Cannot start recording: micPermission=\(self.micPermissionGranted) transcribing=\(self.isTranscribing)")
            return
        }
        await recorder.startRecording()
        isRecording = true
        isPaused = false
        recordingStart = Date()
        recordingDuration = 0
        accumulatedDuration = 0
        audioLevel = 0
        startTimerTask()
        startLevelTask()
    }

    func pauseRecording() async {
        guard isRecording, !isPaused else { return }
        accumulatedDuration += Date().timeIntervalSince(recordingStart ?? Date())
        recordingStart = nil
        timerTask?.cancel()
        timerTask = nil
        await recorder.pauseRecording()
        isPaused = true
        audioLevel = 0
    }

    func resumeRecording() async {
        guard isRecording, isPaused else { return }
        await recorder.resumeRecording()
        recordingStart = Date()
        isPaused = false
        startTimerTask()
    }

    func stopRecording() async {
        // Capture total duration across all segments (including any current segment).
        let duration = accumulatedDuration + (recordingStart.map { Date().timeIntervalSince($0) } ?? 0)
        timerTask?.cancel()
        levelTask?.cancel()
        timerTask = nil
        levelTask = nil
        let exportURL = await recorder.stopRecording()
        let capturedFlow = activeFlow
        isRecording = false
        isPaused = false
        accumulatedDuration = 0
        recordingDuration = 0
        audioLevel = 0
        recordingStart = nil

        // Empty path signals that recording never actually started (e.g. AVAudioSession setup failed).
        // Bail out to avoid transcribing a stale file from a prior session.
        guard !exportURL.path.isEmpty else {
            appLogger.warning("Recording aborted — no audio captured (session setup likely failed)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isTranscribing = false
            return
        }

        appLogger.notice("Recording stopped, file: \(exportURL.lastPathComponent, privacy: .public)")

        // Capture-for-debugging: persist the raw audio + metadata for later desktop
        // assessment. No-ops unless Developer mode is unlocked + the toggle is on
        // (see DeveloperMode / IOSCaptureArchive). No transcription/routing on phone.
        let archiveID = UUID().uuidString
        let archiveTimestamp = Date()
        let archiveAppVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        func archiveCapture(wordCount: Int, transcript: String?) {
            IOSCaptureArchive.archive(
                audioURL: exportURL,
                metadata: .init(
                    captureID: archiveID,
                    timestamp: archiveTimestamp,
                    device: UIDevice.current.name,
                    flowID: capturedFlow.id,
                    durationSeconds: duration,
                    wordCount: wordCount,
                    whisperModel: settings.selectedModel,
                    language: settings.outputLanguage,
                    sourceAppBundleID: nil,
                    sourceAppName: nil,
                    appVersion: archiveAppVersion,
                    connectedToolIDs: [],
                    platform: "ios",
                    onDeviceTranscript: transcript
                )
            )
        }

        // Detect a silent capture (e.g. input died mid-recording) and surface it with a
        // failure sound instead of quietly producing an empty session. Audio is still
        // archived for debugging.
        if audioIsSilent(url: exportURL) {
            appLogger.warning("Captured audio is silent — likely a lost/dead input mid-recording")
            playFailureSound()
            archiveCapture(wordCount: 0, transcript: nil)
            return
        }

        guard isModelDownloaded(variant: settings.selectedModel) else {
            appLogger.warning("No model downloaded — skipping transcription")
            archiveCapture(wordCount: 0, transcript: nil)  // still keep the audio
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
                playFailureSound()
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
            archiveCapture(wordCount: wordCount, transcript: text)
            await routeCapture(session: session, transcript: text)
        } catch {
            appLogger.error("Transcription failed: \(error.localizedDescription)")
        }
    }

    /// Route a finished capture into an action plan, natively (no server):
    /// heuristic first (offline), then Castellum (Claude, BYO key) with on-device
    /// flow context. Persists the capture + analysis locally so future captures
    /// build on it.
    func routeCapture(session: Session, transcript: String) async {
        let mc = BasnAppIOS.modelContainer.mainContext
        let tools = (try? mc.fetch(FetchDescriptor<Tool>())) ?? []
        // Route against ALL known tools so the plan surfaces relevant actions even
        // for tools that aren't connected yet; the plan UI flags those + offers a
        // connect link.
        let allToolIDs = Set(tools.map(\.id))
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

        // Persist the capture record (so it can carry analysis + feed future context).
        let record = CaptureRecord(
            id: session.id, timestamp: session.timestamp, device: session.device,
            platform: "ios", flowID: session.flowID, rawText: transcript,
            durationSeconds: session.durationSeconds, wordCount: session.wordCount,
            appVersion: appVersion, whisperModel: settings.selectedModel, language: settings.outputLanguage
        )
        mc.insert(record)
        try? mc.save()

        var plan: ExecutionPlan?
        var analysis: SessionAnalysis?

        if let actions = HeuristicRouter.route(transcript: transcript, connectedToolIDs: allToolIDs) {
            plan = ExecutionPlan(captureID: session.id, actions: actions, modelUsed: "heuristic")
            appLogger.notice("Heuristic routing: \(actions.count) action(s) for \(session.id, privacy: .public)")
        } else if let actions = await FoundationModelsRouter.route(transcript: transcript, connectedToolIDs: allToolIDs) {
            plan = ExecutionPlan(captureID: session.id, actions: actions, modelUsed: "on-device")
            appLogger.notice("On-device routing: \(actions.count) action(s) for \(session.id, privacy: .public)")
        } else if settings.lightweightCloudRoutingEnabled,
                  let actions = await LightweightRouter.route(
                      transcript: transcript,
                      connectedToolIDs: allToolIDs,
                      apiKey: settings.anthropicAPIKey) {
            plan = ExecutionPlan(captureID: session.id, actions: actions, modelUsed: "lightweight")
            appLogger.notice("Lightweight routing: \(actions.count) action(s) for \(session.id, privacy: .public)")
        } else if !settings.anthropicAPIKey.isEmpty {
            let capture = StructuredCapture.from(session: session)
            let context = recentContext(flowID: session.flowID, limit: 5)
            let workflows = (try? mc.fetch(FetchDescriptor<Workflow>())) ?? []
            do {
                let (a, p) = try await IOSCastellumClient.analyzeAndPlan(
                    capture: capture, promptTitles: [], context: context,
                    tools: tools, workflows: workflows, apiKey: settings.anthropicAPIKey
                )
                analysis = a
                plan = p
                appLogger.notice("Castellum: \(p.actions.count) action(s) for \(session.id, privacy: .public)")
            } catch {
                appLogger.error("iOS Castellum failed: \(error.localizedDescription)")
            }
        } else {
            appLogger.notice("No heuristic match and no API key — skipping routing for \(session.id, privacy: .public)")
        }

        // Always surface generic capability suggestions offline (no key/network),
        // for anything not already covered by a heuristic/Castellum action. This
        // is the pre-connection nudge — "this sounds like it wants to do X."
        // Exception: when the heuristic produced a confident single-intent match,
        // skip keyword suggestions — the transcript is already "claimed" and adding
        // generic nudges on top creates noise (e.g. "journals" → capture_note
        // appearing alongside a clearly-matched calendar action).
        var actions = plan?.actions ?? []
        let coveredCaps = Set(actions.compactMap { action -> String? in
            action.toolID.isEmpty
                ? action.actionType
                : CapabilityResolver.capability(forToolID: action.toolID, actionType: action.actionType)
        })
        let confidentModels: Set<String> = ["heuristic", "on-device", "lightweight"]
        if !confidentModels.contains(plan?.modelUsed ?? "") {
            for cap in CapabilityMatcher.match(transcript) where !coveredCaps.contains(cap) {
                actions.append(PlannedAction(
                    toolID: "", actionType: cap,
                    label: Capabilities.byID(cap)?.title ?? cap, parameters: [:]
                ))
            }
        }
        if !actions.isEmpty {
            plan = ExecutionPlan(captureID: session.id, actions: actions, modelUsed: plan?.modelUsed ?? "local")
        }

        // Persist analysis (links to the capture) for continuity + history.
        if let analysis {
            let ca = CaptureAnalysis(
                summary: analysis.summary, moodTag: analysis.moodTag,
                tasks: analysis.tasks, routing: analysis.routing.map(\.rawValue),
                delegations: analysis.delegations, integrations: analysis.integrations.map(\.rawValue),
                promptsAddressed: analysis.promptsAddressed
            )
            ca.capture = record
            record.analysis = ca
            mc.insert(ca)
            try? mc.save()
        }

        if let plan, let data = try? JSONEncoder().encode(plan) {
            record.executionPlanData = data
            try? mc.save()
        }

        lastPlan = plan
    }

    /// Assemble recent prior-session context for a flow from the local store —
    /// native continuity, mirroring macOS `fetchRecentContext`.
    private func recentContext(flowID: String, limit: Int) -> [SessionContext] {
        let mc = BasnAppIOS.modelContainer.mainContext
        var descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.flowID == flowID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let captures = (try? mc.fetch(descriptor)) ?? []
        let fmt = ISO8601DateFormatter()
        return captures.compactMap { cap -> SessionContext? in
            guard let a = cap.analysis else { return nil }
            return SessionContext(
                timestamp: fmt.string(from: cap.timestamp),
                summary: a.summary, moodTag: a.moodTag,
                tasks: a.tasks.isEmpty ? nil : a.tasks,
                routing: a.routing.isEmpty ? nil : a.routing,
                delegations: a.delegations.isEmpty ? nil : a.delegations
            )
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

    func submitTextCapture(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let wordCount = trimmed.split(separator: " ").count
        let session = Session(
            device: UIDevice.current.name,
            platform: .ios,
            flowID: activeFlow.id,
            rawText: trimmed,
            durationSeconds: 0,
            wordCount: wordCount,
            metadata: Session.Metadata(
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                whisperModel: "text-input",
                language: settings.outputLanguage
            )
        )
        try? await sessionStore.save(session)
        await reloadSessions()
        appLogger.notice("Text capture saved: \(session.id, privacy: .public)")
    }

    func deleteSession(_ session: Session) async {
        try? await sessionStore.delete(session.id)
        await reloadSessions()
    }

    /// Re-route an existing session through the full pipeline without re-persisting it.
    /// Sets lastPlan so the execution plan sheet appears, same as a fresh capture.
    func rerunCapture(session: Session) async {
        let mc = BasnAppIOS.modelContainer.mainContext
        let tools = (try? mc.fetch(FetchDescriptor<Tool>())) ?? []
        let allToolIDs = Set(tools.map(\.id))

        var plan: ExecutionPlan?

        if let actions = HeuristicRouter.route(transcript: session.rawText, connectedToolIDs: allToolIDs) {
            plan = ExecutionPlan(captureID: session.id, actions: actions, modelUsed: "heuristic")
            appLogger.notice("Rerun heuristic: \(actions.count) action(s) for \(session.id, privacy: .public)")
        } else if let actions = await FoundationModelsRouter.route(transcript: session.rawText, connectedToolIDs: allToolIDs) {
            plan = ExecutionPlan(captureID: session.id, actions: actions, modelUsed: "on-device")
            appLogger.notice("Rerun on-device: \(actions.count) action(s) for \(session.id, privacy: .public)")
        } else if settings.lightweightCloudRoutingEnabled,
                  let actions = await LightweightRouter.route(
                      transcript: session.rawText,
                      connectedToolIDs: allToolIDs,
                      apiKey: settings.anthropicAPIKey) {
            plan = ExecutionPlan(captureID: session.id, actions: actions, modelUsed: "lightweight")
            appLogger.notice("Rerun lightweight: \(actions.count) action(s) for \(session.id, privacy: .public)")
        } else if !settings.anthropicAPIKey.isEmpty {
            let capture = StructuredCapture.from(session: session)
            let context = recentContext(flowID: session.flowID, limit: 5)
            let workflows = (try? mc.fetch(FetchDescriptor<Workflow>())) ?? []
            do {
                let (_, p) = try await IOSCastellumClient.analyzeAndPlan(
                    capture: capture, promptTitles: [], context: context,
                    tools: tools, workflows: workflows, apiKey: settings.anthropicAPIKey
                )
                plan = p
                appLogger.notice("Rerun Castellum: \(p.actions.count) action(s) for \(session.id, privacy: .public)")
            } catch {
                appLogger.error("Rerun Castellum failed: \(error.localizedDescription)")
            }
        }

        var actions = plan?.actions ?? []
        let coveredCaps = Set(actions.compactMap { action -> String? in
            action.toolID.isEmpty
                ? action.actionType
                : CapabilityResolver.capability(forToolID: action.toolID, actionType: action.actionType)
        })
        let confidentModels: Set<String> = ["heuristic", "on-device", "lightweight"]
        if !confidentModels.contains(plan?.modelUsed ?? "") {
            for cap in CapabilityMatcher.match(session.rawText) where !coveredCaps.contains(cap) {
                actions.append(PlannedAction(
                    toolID: "", actionType: cap,
                    label: Capabilities.byID(cap)?.title ?? cap, parameters: [:]
                ))
            }
        }
        if !actions.isEmpty {
            plan = ExecutionPlan(captureID: session.id, actions: actions, modelUsed: plan?.modelUsed ?? "local")
        }

        if let plan, let data = try? JSONEncoder().encode(plan) {
            var desc = FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == session.id })
            desc.fetchLimit = 1
            if let existing = try? mc.fetch(desc).first {
                existing.executionPlanData = data
                try? mc.save()
            }
        }

        lastPlan = plan
    }

    private func startTimerTask() {
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let start = recordingStart else { break }
                recordingDuration = accumulatedDuration + Date().timeIntervalSince(start)
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
