import AVFoundation
import ComposableArchitecture
import Dependencies
import Foundation

#if os(iOS)
import os

private let recordingLogger = Logger(subsystem: "com.lyra.basn", category: "recording")

actor RecordingClientLiveIOS {
    private var recorder: AVAudioRecorder?
    private let recordingURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("basn-recording.wav")
    private let recorderSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    private let (meterStream, meterContinuation) = AsyncStream<Meter>.makeStream()
    private var meterTask: Task<Void, Never>?

    func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording() async {
        do {
            let session = AVAudioSession.sharedInstance()
            // NOTE: `.measurement` mode disables input gain/AGC, which produced
            // near-silent recordings (peak ~0.09, rms ~0.008) that Whisper
            // transcribed as a single hallucinated token. `.default` mode keeps
            // the standard input processing chain so speech is at a usable level.
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let r = try AVAudioRecorder(url: recordingURL, settings: recorderSettings)
            r.isMeteringEnabled = true
            r.prepareToRecord()
            r.record()
            recorder = r
            startMeterTask()
            recordingLogger.notice("iOS recording started")
        } catch {
            recordingLogger.error("Failed to start iOS recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() async -> URL {
        recorder?.stop()
        stopMeterTask()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let exportURL = recordingURL
            .deletingLastPathComponent()
            .appendingPathComponent("basn-recording-\(UUID().uuidString).wav")
        try? FileManager.default.copyItem(at: recordingURL, to: exportURL)
        recordingLogger.notice("iOS recording stopped")
        return exportURL
    }

    func getCurrentRecordingURL() -> URL? {
        recorder?.isRecording == true ? recordingURL : nil
    }

    func observeAudioLevel() -> AsyncStream<Meter> { meterStream }

    func getAvailableInputDevices() -> [AudioInputDevice] { [] }
    func getDefaultInputDeviceName() -> String? { nil }
    func cleanup() {}

    private func startMeterTask() {
        meterTask = Task {
            while !Task.isCancelled, let r = recorder, r.isRecording {
                r.updateMeters()
                let avg = Double(pow(10, r.averagePower(forChannel: 0) / 20.0))
                let peak = Double(pow(10, r.peakPower(forChannel: 0) / 20.0))
                meterContinuation.yield(Meter(averagePower: avg, peakPower: peak))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopMeterTask() {
        meterTask?.cancel()
        meterTask = nil
    }
}

extension RecordingClient: DependencyKey {
    static var liveValue: Self {
        let live = RecordingClientLiveIOS()
        return Self(
            startRecording: { await live.startRecording() },
            stopRecording: { await live.stopRecording() },
            getCurrentRecordingURL: { await live.getCurrentRecordingURL() },
            requestMicrophoneAccess: { await live.requestMicrophoneAccess() },
            observeAudioLevel: { await live.observeAudioLevel() },
            getAvailableInputDevices: { await live.getAvailableInputDevices() },
            getDefaultInputDeviceName: { await live.getDefaultInputDeviceName() },
            cleanup: { await live.cleanup() }
        )
    }
}
#endif
