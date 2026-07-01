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
    private var interruptionTask: Task<Void, Never>?
    private var routeChangeTask: Task<Void, Never>?
    private(set) var isPaused = false
    private var wasInterrupted = false

    func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording() async {
        do {
            let session = AVAudioSession.sharedInstance()
            // `.default` mode keeps AGC; `.measurement` produced near-silent recordings.
            // `.allowBluetooth` enables HFP Bluetooth mics so Watch/AirPods route changes
            // don't kill the session. `.allowBluetoothA2DP` is output-only and only valid
            // with `.playAndRecord` — using it with `.record` throws OSStatus -50 (paramErr).
            try session.setCategory(
                .record,
                mode: .default,
                options: [.allowBluetooth]
            )
            try session.setActive(true)
            let r = try AVAudioRecorder(url: recordingURL, settings: recorderSettings)
            r.isMeteringEnabled = true
            r.prepareToRecord()
            r.record()
            recorder = r
            isPaused = false
            wasInterrupted = false
            startMeterTask()
            startInterruptionObserver()
            startRouteChangeObserver()
            recordingLogger.notice("iOS recording started")
        } catch {
            recordingLogger.error("Failed to start iOS recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() async -> URL {
        // Guard: if recorder is nil (start failed), don't copy a stale file from a prior session.
        guard recorder != nil else {
            recordingLogger.warning("stopRecording called with no active recorder — returning empty URL")
            return URL(fileURLWithPath: "")
        }
        recorder?.stop()
        stopMeterTask()
        interruptionTask?.cancel()
        routeChangeTask?.cancel()
        interruptionTask = nil
        routeChangeTask = nil
        recorder = nil
        isPaused = false
        wasInterrupted = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let exportURL = recordingURL
            .deletingLastPathComponent()
            .appendingPathComponent("basn-recording-\(UUID().uuidString).wav")
        try? FileManager.default.copyItem(at: recordingURL, to: exportURL)
        recordingLogger.notice("iOS recording stopped")
        return exportURL
    }

    func pauseRecording() {
        guard let r = recorder, r.isRecording, !isPaused else { return }
        r.pause()
        isPaused = true
        stopMeterTask()
        recordingLogger.notice("iOS recording paused")
    }

    func resumeRecording() {
        guard let r = recorder, isPaused else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            recordingLogger.error("Failed to reactivate session on resume: \(error.localizedDescription)")
        }
        r.record()
        isPaused = false
        startMeterTask()
        recordingLogger.notice("iOS recording resumed")
    }

    func getCurrentRecordingURL() -> URL? {
        recorder?.isRecording == true ? recordingURL : nil
    }

    func observeAudioLevel() -> AsyncStream<Meter> { meterStream }

    func getAvailableInputDevices() -> [AudioInputDevice] { [] }
    func getDefaultInputDeviceName() -> String? { nil }
    func cleanup() {}

    // MARK: - Metering

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

    // MARK: - Interruption handling
    // Fitness workouts, phone calls, and alarms can interrupt the audio session.
    // When the system signals `.ended` with `.shouldResume`, we reactivate and continue.

    private func startInterruptionObserver() {
        interruptionTask = Task {
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                if Task.isCancelled { break }
                let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                await self.handleInterruption(typeValue: typeValue, optionValue: optionValue)
            }
        }
    }

    private func handleInterruption(typeValue: UInt?, optionValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            recordingLogger.notice("Audio interruption began")
            wasInterrupted = true
        case .ended:
            wasInterrupted = false
            let options = AVAudioSession.InterruptionOptions(rawValue: optionValue ?? 0)
            guard options.contains(.shouldResume), !isPaused else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                recorder?.record()
                startMeterTask()
                recordingLogger.notice("Resumed after audio interruption")
            } catch {
                recordingLogger.error("Failed to resume after interruption: \(error.localizedDescription)")
            }
        @unknown default:
            break
        }
    }

    // MARK: - Route change handling
    // Watch workouts and headphone connects/disconnects can silently stop AVAudioRecorder.
    // Re-check isRecording after route changes and restart if unexpectedly stopped.

    private func startRouteChangeObserver() {
        routeChangeTask = Task {
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                if Task.isCancelled { break }
                let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                await self.handleRouteChange(reasonValue: reasonValue)
            }
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        switch reason {
        case .oldDeviceUnavailable, .override, .wakeFromSleep, .noSuitableRouteForCategory:
            guard let r = recorder, !r.isRecording, !isPaused, !wasInterrupted else { return }
            recordingLogger.notice("Route change (\(reasonValue)), attempting to continue recording")
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                r.record()
                startMeterTask()
            } catch {
                recordingLogger.error("Failed to reactivate after route change: \(error.localizedDescription)")
            }
        default:
            break
        }
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
