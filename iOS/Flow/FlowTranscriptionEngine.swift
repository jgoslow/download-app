import AVFoundation
import Foundation
import Speech

/// Drives real-time on-device speech recognition during a flow session.
///
/// Streams audio through SFSpeechRecognizer and surfaces two event streams:
/// - Partial updates: raw in-progress text shown in the live transcript strip
/// - Sentence completions: final segments appended to the permanent transcript
/// - "next" command: fires when the user says "next" or "next prompt" in isolation
///
/// Automatically restarts the recognition task on timeout (Apple's ~1 min limit).
@MainActor
final class FlowTranscriptionEngine {
    var onPartialUpdate: ((String) -> Void)?
    var onSentenceComplete: ((String) -> Void)?
    var onNextCommand: (() -> Void)?

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var lastFinalText = ""
    private(set) var isRunning = false

    init() {
        speechRecognizer =
            SFSpeechRecognizer(locale: .current) ??
            SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Permission

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        isRunning = true
        lastFinalText = ""
        try beginSession(recognizer: speechRecognizer)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        teardown()
    }

    // MARK: - Session management

    private func beginSession(recognizer: SFSpeechRecognizer) throws {
        // Activate the audio session BEFORE querying the input node.
        // inputNode.outputFormat returns 0 Hz if the session isn't active yet,
        // which causes installTap to throw IsFormatSampleRateAndChannelCountValid.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in self.handleResult(result) }
            }
            if let error, self.isRunning {
                let code = (error as NSError).code
                // 1110 = no speech; 301 = recognition request cancelled — both are benign
                guard code != 1110, code != 301 else { return }
                // Restart after Apple's ~1-minute time limit or unexpected errors
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    if self.isRunning { try? self.restartSession(recognizer: recognizer) }
                }
            }
        }

        let inputNode = audioEngine.inputNode
        // Pass nil so AVAudioEngine picks up the hardware's native format automatically.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func restartSession(recognizer: SFSpeechRecognizer) throws {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest = nil
        recognitionTask = nil
        try beginSession(recognizer: recognizer)
    }

    private func teardown() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Result handling

    private func handleResult(_ result: SFSpeechRecognitionResult) {
        let fullText = result.bestTranscription.formattedString

        // Extract the new segment since the last completed sentence
        let newSegment: String
        if fullText.hasPrefix(lastFinalText) {
            newSegment = String(fullText.dropFirst(lastFinalText.count))
                .trimmingCharacters(in: .whitespaces)
        } else {
            // Recognizer rebuilt the transcript from scratch (restart) — show it whole
            newSegment = fullText.trimmingCharacters(in: .whitespaces)
        }

        if !newSegment.isEmpty {
            onPartialUpdate?(newSegment)
        }

        if result.isFinal {
            let sentence = newSegment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                if isNextCommand(sentence) {
                    onNextCommand?()
                } else {
                    onSentenceComplete?(sentence)
                }
            }
            lastFinalText = fullText
        }
    }

    // MARK: - "next" command detection

    /// Returns true when the utterance is "next" used as a standalone navigation command,
    /// not embedded mid-sentence ("what comes next", "the next item").
    private func isNextCommand(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespaces)

        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 3 else { return false }

        // All words must be navigation/filler words AND "next" must be present.
        // Allows: "next", "next prompt", "go next", "ok next", "hey next"
        // Rejects: "what's next", "comes next", "the next thing"
        let navigationWords: Set<String> = ["next", "prompt", "go", "to", "the", "ok", "hey", "basn"]
        let nonNavigation = words.filter { !navigationWords.contains($0) }
        return words.contains("next") && nonNavigation.isEmpty
    }
}

// MARK: - Errors

extension FlowTranscriptionEngine {
    enum TranscriptionError: Error {
        case recognizerUnavailable
    }
}
