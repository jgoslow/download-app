//
//  TranscriptionFeature.swift
//  Basn
//
//  Created by Kit Langton on 1/24/25.
//

import ComposableArchitecture
import CoreGraphics
import Foundation
import BasnCore
import Inject
import SwiftUI
import WhisperKit

private let transcriptionFeatureLogger = BasnLog.transcription
private let routerLogger = BasnLog.app

@Reducer
struct TranscriptionFeature {
  @ObservableState
  struct State {
    var isRecording: Bool = false
    var isTranscribing: Bool = false
    var isPrewarming: Bool = false
    var error: String?
    var recordingStartTime: Date?
    var meter: Meter = .init(averagePower: 0, peakPower: 0)
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var lastAnalysis: SessionAnalysis? = nil
    var selectedFlowID: String = "open"
    var promptTitles: [String] = []
    var livePromptsAddressed: Set<Int> = []
    var partialTranscript: String? = nil
    @Shared(.basnSettings) var basnSettings: BasnSettings
    @Shared(.isRemappingScratchpadFocused) var isRemappingScratchpadFocused: Bool = false
    @Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
  }

  enum Action {
    case task
    case audioLevelUpdated(Meter)

    // Hotkey actions
    case hotKeyPressed
    case hotKeyReleased

    // Recording flow
    case startRecording
    case stopRecording

    // Cancel/discard flow
    case cancel   // Explicit cancellation with sound
    case discard  // Silent discard (too short/accidental)

    // Transcription result flow
    case transcriptionResult(String, URL)
    case transcriptionError(Error, URL?)
    case analysisReceived(SessionAnalysis, captureID: String)
    /// Unified result from CastellumClient: analysis + plan in one call.
    case castellumResultReceived(SessionAnalysis, ExecutionPlan, captureID: String)
    case submitTextCapture(String)
    case periodicParseUpdate(partialText: String, promptsAddressed: [Int])
    case setFlow(String, promptTitles: [String])

    // Model availability
    case modelMissing
  }

  enum CancelID {
    case metering
    case transcription
  }

  @Dependency(\.transcription) var transcription
  @Dependency(\.recording) var recording
  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.soundEffects) var soundEffect
  @Dependency(\.sleepManagement) var sleepManagement
  @Dependency(\.date.now) var now
  @Dependency(\.transcriptPersistence) var transcriptPersistence
  @Dependency(\.destinationRouter) var destinationRouter
  @Dependency(\.castellumClient) var castellumClient
  @Dependency(\.modelContext) var basinDB

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // MARK: - Lifecycle / Setup

      case .task:
        // Starts two concurrent effects:
        // 1) Observing audio meter
        // 2) Monitoring hot key events
        // 3) Priming the recorder for instant startup
        return .merge(
          startMeteringEffect(),
          startHotKeyMonitoringEffect()
        )

      // MARK: - Metering

      case let .audioLevelUpdated(meter):
        state.meter = meter
        return .none

      // MARK: - HotKey Flow

      case .hotKeyPressed:
        // If we're transcribing, send a cancel first. Otherwise start recording immediately.
        // We'll decide later (on release) whether to keep or discard the recording.
        return handleHotKeyPressed(isTranscribing: state.isTranscribing)

      case .hotKeyReleased:
        // If we're currently recording, then stop. Otherwise, just cancel
        // the delayed "startRecording" effect if we never actually started.
        return handleHotKeyReleased(isRecording: state.isRecording)

      // MARK: - Recording Flow

      case .startRecording:
        return handleStartRecording(&state)

      case .stopRecording:
        return handleStopRecording(&state)

      // MARK: - Transcription Results

      case let .transcriptionResult(result, audioURL):
        return handleTranscriptionResult(&state, result: result, audioURL: audioURL)

      case let .transcriptionError(error, audioURL):
        return handleTranscriptionError(&state, error: error, audioURL: audioURL)

      case let .analysisReceived(analysis, _):
        state.lastAnalysis = analysis
        return .none

      case let .castellumResultReceived(analysis, _, _):
        state.lastAnalysis = analysis
        return .none

      case let .submitTextCapture(text):
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        let flowID = state.selectedFlowID
        let promptTitles = state.promptTitles
        let transcriptionHistory = state.$transcriptionHistory

        return .run { [basinDB = self.basinDB, router = self.destinationRouter, castellum = self.castellumClient] send in
          @Shared(.basnSettings) var basnSettings: BasnSettings
          let basinSettings = basnSettings.basinSettings

          let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

          let session = Session(
            device: Host.current().localizedName ?? "mac",
            platform: .macos,
            flowID: flowID,
            rawText: trimmed,
            durationSeconds: 0,
            wordCount: trimmed.split(separator: " ").count,
            metadata: .init(appVersion: appVersion, whisperModel: "text-input", language: nil)
          )

          let captureRecord = CaptureRecord(
            id: session.id,
            device: Host.current().localizedName ?? "mac",
            flowID: flowID,
            rawText: trimmed,
            durationSeconds: 0,
            wordCount: trimmed.split(separator: " ").count,
            appVersion: appVersion,
            whisperModel: "text-input"
          )
          try? await basinDB.saveCapture(captureRecord)
          _ = await router.route(session)

          // Always add to transcript history so HomeView "Last transcript" section updates.
          // (saveTranscriptionHistory only gates audio-file persistence, not text captures.)
          let textTranscript = Transcript(timestamp: Date(), text: trimmed, audioPath: nil, duration: 0)
          transcriptionHistory.withLock { $0.history.insert(textTranscript, at: 0) }

          // Heuristic bypass: same single-intent check as the voice path.
          let tools = (try? await basinDB.fetchTools()) ?? []
          let connectedToolIDs = Set(tools.filter(\.isConnected).map(\.id))
          if let heuristicActions = HeuristicRouter.route(transcript: trimmed, connectedToolIDs: connectedToolIDs) {
            let plan = ExecutionPlan(captureID: session.id, actions: heuristicActions, modelUsed: "heuristic")
            let minimalAnalysis = SessionAnalysis(summary: String(trimmed.prefix(100)))
            #if DEBUG
            recordHeuristicScenario(rawText: trimmed, connectedToolIDs: connectedToolIDs, actions: heuristicActions)
            #endif
            await send(.castellumResultReceived(minimalAnalysis, plan, captureID: session.id))
            transcriptionFeatureLogger.info("Heuristic bypass (text) for capture \(session.id)")
            return
          }

          guard !basinSettings.anthropicAPIKey.isEmpty else { return }
          let workflows = (try? await basinDB.fetchWorkflows()) ?? []
          let sessionContext = await router.fetchContext(flowID)
          let structuredCapture = StructuredCapture.from(session: session)

          do {
            let (analysis, plan) = try await castellum.analyzeAndPlan(
              structuredCapture, promptTitles, sessionContext, tools, workflows, basinSettings.anthropicAPIKey
            )
            await send(.castellumResultReceived(analysis, plan, captureID: session.id))
            await router.postAnalysis(session.id, analysis)
            let captureAnalysis = CaptureAnalysis(
              summary: analysis.summary,
              moodTag: analysis.moodTag,
              tasks: analysis.tasks,
              routing: analysis.routing.map(\.rawValue),
              delegations: analysis.delegations,
              integrations: analysis.integrations.map(\.rawValue),
              promptsAddressed: analysis.promptsAddressed
            )
            try? await basinDB.saveAnalysis(captureAnalysis, captureRecord)
          } catch {
            BasnLog.app.error("Castellum error (text capture): \(error.localizedDescription)")
          }
        }


      case let .periodicParseUpdate(partialText, promptsAddressed):
        state.partialTranscript = partialText
        state.livePromptsAddressed = Set(promptsAddressed)
        return .none

      case let .setFlow(typeID, promptTitles):
        state.selectedFlowID = typeID
        state.promptTitles = promptTitles
        state.livePromptsAddressed = []
        state.partialTranscript = nil
        return .none

      case .modelMissing:
        return .none

      // MARK: - Cancel/Discard Flow

      case .cancel:
        // Only cancel if we're in the middle of recording, transcribing, or post-processing
        guard state.isRecording || state.isTranscribing else {
          return .none
        }
        return handleCancel(&state)

      case .discard:
        // Silent discard for quick/accidental recordings
        guard state.isRecording else {
          return .none
        }
        return handleDiscard(&state)
      }
    }
  }
}

// MARK: - Effects: Metering & HotKey

private extension TranscriptionFeature {
  /// Effect to begin observing the audio meter.
  func startMeteringEffect() -> Effect<Action> {
    .run { send in
      for await meter in await recording.observeAudioLevel() {
        await send(.audioLevelUpdated(meter))
      }
    }
    .cancellable(id: CancelID.metering, cancelInFlight: true)
  }

  /// Effect to start monitoring hotkey events through the `keyEventMonitor`.
  func startHotKeyMonitoringEffect() -> Effect<Action> {
    .run { send in
      var hotKeyProcessor: HotKeyProcessor = .init(hotkey: HotKey(key: nil, modifiers: [.option]))
      @Shared(.isSettingHotKey) var isSettingHotKey: Bool
      @Shared(.basnSettings) var basnSettings: BasnSettings

      // Handle incoming input events (keyboard and mouse)
      let token = keyEventMonitor.handleInputEvent { inputEvent in
        // Skip if the user is currently setting a hotkey
        if isSettingHotKey {
          return false
        }

        // Always keep hotKeyProcessor in sync with current user hotkey preference
        hotKeyProcessor.hotkey = basnSettings.hotkey
        let useDoubleTapOnly = basnSettings.doubleTapLockEnabled && basnSettings.useDoubleTapOnly
        hotKeyProcessor.doubleTapLockEnabled = basnSettings.doubleTapLockEnabled
        hotKeyProcessor.useDoubleTapOnly = useDoubleTapOnly
        hotKeyProcessor.minimumKeyTime = basnSettings.minimumKeyTime

        switch inputEvent {
        case .keyboard(let keyEvent):
          // If Escape is pressed with no modifiers while idle, let's treat that as `cancel`.
          if keyEvent.key == .escape, keyEvent.modifiers.isEmpty,
             hotKeyProcessor.state == .idle
          {
            Task { await send(.cancel) }
            return false
          }

          // Process the key event
          switch hotKeyProcessor.process(keyEvent: keyEvent) {
          case .startRecording:
            // If double-tap lock is triggered, we start recording immediately
            if hotKeyProcessor.state == .doubleTapLock {
              Task { await send(.startRecording) }
            } else {
              Task { await send(.hotKeyPressed) }
            }
            // If the hotkey is purely modifiers, return false to keep it from interfering with normal usage
            // But if useDoubleTapOnly is true, always intercept the key
            return useDoubleTapOnly || keyEvent.key != nil

          case .stopRecording:
            Task { await send(.hotKeyReleased) }
            return false // or `true` if you want to intercept

          case .cancel:
            Task { await send(.cancel) }
            return true

          case .discard:
            Task { await send(.discard) }
            return false // Don't intercept - let the key chord reach other apps

          case .none:
            // If we detect repeated same chord, maybe intercept.
            if let pressedKey = keyEvent.key,
               pressedKey == hotKeyProcessor.hotkey.key,
               keyEvent.modifiers == hotKeyProcessor.hotkey.modifiers
            {
              return true
            }
            return false
          }

        case .mouseClick:
          // Process mouse click - for modifier-only hotkeys, this may cancel/discard
          switch hotKeyProcessor.processMouseClick() {
          case .cancel:
            Task { await send(.cancel) }
            return false // Don't intercept the click itself
          case .discard:
            Task { await send(.discard) }
            return false // Don't intercept the click itself
          case .startRecording, .stopRecording, .none:
            return false
          }
        }
      }

      defer { token.cancel() }

      await withTaskCancellationHandler {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(60))
        }
      } onCancel: {
        token.cancel()
      }
    }
  }

}

// MARK: - HotKey Press/Release Handlers

private extension TranscriptionFeature {
  func handleHotKeyPressed(isTranscribing: Bool) -> Effect<Action> {
    // If already transcribing, cancel first. Otherwise start recording immediately.
    let maybeCancel = isTranscribing ? Effect.send(Action.cancel) : .none
    let startRecording = Effect.send(Action.startRecording)
    return .merge(maybeCancel, startRecording)
  }

  func handleHotKeyReleased(isRecording: Bool) -> Effect<Action> {
    // Always stop recording when hotkey is released
    return isRecording ? .send(.stopRecording) : .none
  }
}

// MARK: - Recording Handlers

private extension TranscriptionFeature {
  func handleStartRecording(_ state: inout State) -> Effect<Action> {
    guard state.modelBootstrapState.isModelReady else {
      return .merge(
        .send(.modelMissing),
        .run { _ in soundEffect.play(.cancel) }
      )
    }
    state.isRecording = true
    let startTime = Date()
    state.recordingStartTime = startTime
    
    // Capture the active application
    if let activeApp = NSWorkspace.shared.frontmostApplication {
      state.sourceAppBundleID = activeApp.bundleIdentifier
      state.sourceAppName = activeApp.localizedName
    }
    transcriptionFeatureLogger.notice("Recording started at \(startTime.ISO8601Format())")

    // Prevent system sleep during recording
    let promptTitles = state.promptTitles
    let apiKey = state.basnSettings.basinSettings.anthropicAPIKey
    let model = state.basnSettings.selectedModel

    return .run { [sleepManagement, preventSleep = state.basnSettings.preventSystemSleep] send in
      // Play sound immediately for instant feedback
      soundEffect.play(.startRecording)

      if preventSleep {
        await sleepManagement.preventSleep(reason: "Basn Voice Recording")
      }
      await recording.startRecording()

      // Start periodic parsing if this flow has prompts
      if !promptTitles.isEmpty, !apiKey.isEmpty {
        // Small delay to let the recording URL be established
        try? await Task.sleep(for: .seconds(1))
        if let audioURL = await recording.getCurrentRecordingURL() {
          await PeriodicParsingController.shared.start(
            audioURL: audioURL,
            promptTitles: promptTitles,
            apiKey: apiKey,
            transcribe: { url in
              try await transcription.transcribe(url, model, DecodingOptions(chunkingStrategy: .vad)) { _ in }
            },
            onUpdate: { update in
              Task { @MainActor in
                send(.periodicParseUpdate(partialText: update.partialText, promptsAddressed: update.promptsAddressed))
              }
            }
          )
        }
      }
    }
  }

  func handleStopRecording(_ state: inout State) -> Effect<Action> {
    state.isRecording = false
    state.livePromptsAddressed = []
    state.partialTranscript = nil

    // Stop periodic parsing
    Task { await PeriodicParsingController.shared.stop() }
    
    let stopTime = now
    let startTime = state.recordingStartTime
    let duration = startTime.map { stopTime.timeIntervalSince($0) } ?? 0

    let decision = RecordingDecisionEngine.decide(
      .init(
        hotkey: state.basnSettings.hotkey,
        minimumKeyTime: state.basnSettings.minimumKeyTime,
        recordingStartTime: state.recordingStartTime,
        currentTime: stopTime
      )
    )

    let startStamp = startTime?.ISO8601Format() ?? "nil"
    let stopStamp = stopTime.ISO8601Format()
    let minimumKeyTime = state.basnSettings.minimumKeyTime
    let hotkeyHasKey = state.basnSettings.hotkey.key != nil
    transcriptionFeatureLogger.notice(
      "Recording stopped duration=\(String(format: "%.3f", duration))s start=\(startStamp) stop=\(stopStamp) decision=\(String(describing: decision)) minimumKeyTime=\(String(format: "%.2f", minimumKeyTime)) hotkeyHasKey=\(hotkeyHasKey)"
    )

    guard decision == .proceedToTranscription else {
      // If the user recorded for less than minimumKeyTime and the hotkey is modifier-only,
      // discard the audio to avoid accidental triggers.
      transcriptionFeatureLogger.notice("Discarding short recording per decision \(String(describing: decision))")
      return .run { _ in
        let url = await recording.stopRecording()
        try? FileManager.default.removeItem(at: url)
      }
    }

    // Otherwise, proceed to transcription
    state.isTranscribing = true
    state.error = nil
    let model = state.basnSettings.selectedModel
    let language = state.basnSettings.outputLanguage

    state.isPrewarming = true

    return .run { [sleepManagement] send in
      // Allow system to sleep again
      await sleepManagement.allowSleep()

      var audioURL: URL?
      do {
        soundEffect.play(.stopRecording)
        let capturedURL = await recording.stopRecording()
        audioURL = capturedURL

        // Create transcription options with the selected language
        // Note: cap concurrency to avoid audio I/O overloads on some Macs
        let decodeOptions = DecodingOptions(
          language: language,
          detectLanguage: language == nil, // Only auto-detect if no language specified
          chunkingStrategy: .vad,
        )
        
        let result = try await transcription.transcribe(capturedURL, model, decodeOptions) { _ in }
        
        transcriptionFeatureLogger.notice("Transcribed audio from \(capturedURL.lastPathComponent) to text length \(result.count)")
        await send(.transcriptionResult(result, capturedURL))
      } catch {
        transcriptionFeatureLogger.error("Transcription failed: \(error.localizedDescription)")
        await send(.transcriptionError(error, audioURL))
      }
    }
    .cancellable(id: CancelID.transcription)
  }
}

// MARK: - Transcription Handlers

private extension TranscriptionFeature {
  func handleTranscriptionResult(
    _ state: inout State,
    result: String,
    audioURL: URL
  ) -> Effect<Action> {
    state.isTranscribing = false
    state.isPrewarming = false

    // Check for force quit command (emergency escape hatch)
    if ForceQuitCommandDetector.matches(result) {
      transcriptionFeatureLogger.fault("Force quit voice command recognized; terminating Basn.")
      return .run { _ in
        try? FileManager.default.removeItem(at: audioURL)
        await MainActor.run {
          NSApp.terminate(nil)
        }
      }
    }

    // If empty text, nothing else to do
    guard !result.isEmpty else {
      return .none
    }

    let duration = state.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

    transcriptionFeatureLogger.info("Raw transcription: '\(result)'")
    let remappings = state.basnSettings.wordRemappings
    let removalsEnabled = state.basnSettings.wordRemovalsEnabled
    let removals = state.basnSettings.wordRemovals
    let modifiedResult: String
    if state.isRemappingScratchpadFocused {
      modifiedResult = result
      transcriptionFeatureLogger.info("Scratchpad focused; skipping word modifications")
    } else {
      var output = result
      if removalsEnabled {
        let removedResult = WordRemovalApplier.apply(output, removals: removals)
        if removedResult != output {
          let enabledRemovalCount = removals.filter(\.isEnabled).count
          transcriptionFeatureLogger.info("Applied \(enabledRemovalCount) word removal(s)")
        }
        output = removedResult
      }
      let remappedResult = WordRemappingApplier.apply(output, remappings: remappings)
      if remappedResult != output {
        transcriptionFeatureLogger.info("Applied \(remappings.count) word remapping(s)")
      }
      modifiedResult = remappedResult
    }

    guard !modifiedResult.isEmpty else {
      return .none
    }

    let sourceAppBundleID = state.sourceAppBundleID
    let sourceAppName = state.sourceAppName
    let transcriptionHistory = state.$transcriptionHistory
    let basinSettings = state.basnSettings.basinSettings
    let flowID = state.selectedFlowID
    let promptTitlesForAI = state.promptTitles
    let selectedModel = state.basnSettings.selectedModel
    let outputLanguage = state.basnSettings.outputLanguage
    let router = destinationRouter
    let castellum = castellumClient

    return .run { send in
      do {
        try await finalizeRecordingAndStoreTranscript(
          result: modifiedResult,
          duration: duration,
          sourceAppBundleID: sourceAppBundleID,
          sourceAppName: sourceAppName,
          audioURL: audioURL,
          transcriptionHistory: transcriptionHistory
        )
      } catch {
        await send(.transcriptionError(error, audioURL))
        return
      }

      // Route capture to configured destinations
      let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
      let wordCount = modifiedResult.split(separator: " ").count

      let session = Session(
        device: Host.current().localizedName ?? "mac",
        platform: .macos,
        flowID: flowID,
        rawText: modifiedResult,
        durationSeconds: duration,
        wordCount: wordCount,
        metadata: Session.Metadata(
          appVersion: appVersion,
          whisperModel: selectedModel,
          language: outputLanguage
        )
      )
      let status = await router.route(session)
      routerLogger.info("Session routed: \(String(describing: status))")

      // Save to SwiftData
      let capture = CaptureRecord(
        id: session.id,
        device: Host.current().localizedName ?? "mac",
        flowID: flowID,
        rawText: modifiedResult,
        durationSeconds: duration,
        wordCount: wordCount,
        sourceAppBundleID: sourceAppBundleID,
        sourceAppName: sourceAppName,
        appVersion: appVersion,
        whisperModel: selectedModel,
        language: outputLanguage
      )
      try? await basinDB.saveCapture(capture)

      guard !basinSettings.anthropicAPIKey.isEmpty else { return }
      let tools = (try? await basinDB.fetchTools()) ?? []
      let enabledWorkflows = (try? await basinDB.fetchWorkflows())?.filter(\.isEnabled) ?? []
      let connectedTools = tools.filter(\.isConnected)
      let connectedToolIDs = Set(connectedTools.map(\.id))

      // Heuristic bypass: skip Claude for clear single-intent captures
      if let heuristicActions = HeuristicRouter.route(transcript: modifiedResult, connectedToolIDs: connectedToolIDs) {
        let plan = ExecutionPlan(captureID: session.id, actions: heuristicActions, modelUsed: "heuristic")
        let minimalAnalysis = SessionAnalysis(summary: String(modifiedResult.prefix(100)))
        #if DEBUG
        recordHeuristicScenario(rawText: modifiedResult, connectedToolIDs: connectedToolIDs, actions: heuristicActions)
        #endif
        await send(.castellumResultReceived(minimalAnalysis, plan, captureID: session.id))
        transcriptionFeatureLogger.info("Heuristic bypass for capture \(session.id)")
        return
      }

      let sessionContext = await router.fetchContext(flowID)
      let structuredCapture = StructuredCapture.from(session: session)

      do {
        let (analysis, plan) = try await castellum.analyzeAndPlan(
          structuredCapture, promptTitlesForAI, sessionContext, tools, enabledWorkflows, basinSettings.anthropicAPIKey
        )
        await send(.castellumResultReceived(analysis, plan, captureID: session.id))
        await router.postAnalysis(session.id, analysis)
        let captureAnalysis = CaptureAnalysis(
          summary: analysis.summary,
          moodTag: analysis.moodTag,
          tasks: analysis.tasks,
          routing: analysis.routing.map(\.rawValue),
          delegations: analysis.delegations,
          integrations: analysis.integrations.map(\.rawValue),
          promptsAddressed: analysis.promptsAddressed
        )
        try? await basinDB.saveAnalysis(captureAnalysis, capture)
      } catch {
        transcriptionFeatureLogger.error("Castellum error: \(error.localizedDescription)")
      }
    }
    .cancellable(id: CancelID.transcription)
  }

  func handleTranscriptionError(
    _ state: inout State,
    error: Error,
    audioURL: URL?
  ) -> Effect<Action> {
    state.isTranscribing = false
    state.isPrewarming = false
    state.error = error.localizedDescription
    
    if let audioURL {
      try? FileManager.default.removeItem(at: audioURL)
    }

    return .none
  }

  /// Move file to permanent location, create a transcript record, optionally paste text, and play sound.
  func finalizeRecordingAndStoreTranscript(
    result: String,
    duration: TimeInterval,
    sourceAppBundleID: String?,
    sourceAppName: String?,
    audioURL: URL,
    transcriptionHistory: Shared<TranscriptionHistory>
  ) async throws {
    @Shared(.basnSettings) var basnSettings: BasnSettings

    if basnSettings.saveTranscriptionHistory {
      let transcript = try await transcriptPersistence.save(
        result,
        audioURL,
        duration,
        sourceAppBundleID,
        sourceAppName
      )

      transcriptionHistory.withLock { history in
        history.history.insert(transcript, at: 0)

        if let maxEntries = basnSettings.maxHistoryEntries, maxEntries > 0 {
          while history.history.count > maxEntries {
            if let removedTranscript = history.history.popLast() {
              Task {
                 try? await transcriptPersistence.deleteAudio(removedTranscript)
              }
            }
          }
        }
      }
    } else {
      try? FileManager.default.removeItem(at: audioURL)
    }

    soundEffect.play(.transcriptComplete)
  }
}

// MARK: - Cancel/Discard Handlers

private extension TranscriptionFeature {
  func handleCancel(_ state: inout State) -> Effect<Action> {
    state.isTranscribing = false
    state.isRecording = false
    state.isPrewarming = false

    return .merge(
      .cancel(id: CancelID.transcription),
      .run { [sleepManagement] _ in
        // Allow system to sleep again
        await sleepManagement.allowSleep()
        // Stop the recording to release microphone access
        let url = await recording.stopRecording()
        try? FileManager.default.removeItem(at: url)
        soundEffect.play(.cancel)
      }
    )
  }

  func handleDiscard(_ state: inout State) -> Effect<Action> {
    state.isRecording = false
    state.isPrewarming = false

    // Silently discard - no sound effect
    return .run { [sleepManagement] _ in
      // Allow system to sleep again
      await sleepManagement.allowSleep()
      let url = await recording.stopRecording()
      try? FileManager.default.removeItem(at: url)
    }
  }
}

// MARK: - View

struct TranscriptionView: View {
  @Bindable var store: StoreOf<TranscriptionFeature>
  @ObserveInjection var inject

  var status: TranscriptionIndicatorView.Status {
    if store.isTranscribing {
      return .transcribing
    } else if store.isRecording {
      return .recording
    } else if store.isPrewarming {
      return .prewarming
    } else {
      return .hidden
    }
  }

  var body: some View {
    TranscriptionIndicatorView(
      status: status,
      meter: store.meter
    )
    .task {
      await store.send(.task).finish()
    }
    .enableInjection()
  }
}

// MARK: - Force Quit Command

private enum ForceQuitCommandDetector {
  static func matches(_ text: String) -> Bool {
    let normalized = normalize(text)
    return normalized == "force quit hex now" || normalized == "force quit hex"
  }

  private static func normalize(_ text: String) -> String {
    text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
