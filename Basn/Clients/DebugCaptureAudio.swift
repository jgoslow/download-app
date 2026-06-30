#if DEBUG
import Foundation
import AVFoundation
import BasnCore

/// Reads recorded audio into float samples and computes objective quality
/// metrics for capture grading. Debug-only — keeps AVFoundation out of BasnCore,
/// which owns only the pure `AudioQualityMetrics` math.
enum DebugCaptureAudio {

    /// Estimate audio-quality metrics for the WAV at `url`. Returns `nil` if the
    /// file can't be read.
    static func metrics(forFileAt url: URL) -> AudioQualityMetrics? {
        guard let samples = monoSamples(forFileAt: url) else { return nil }
        return AudioQualityMetrics.estimate(samples: samples.0, sampleRate: samples.1)
    }

    /// Decode the first channel of the audio file to `[Float]` plus its sample rate.
    private static func monoSamples(forFileAt url: URL) -> ([Float], Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channelData = buffer.floatChannelData
        else { return nil }

        let frames = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frames))
        return (samples, format.sampleRate)
    }
}
#endif
