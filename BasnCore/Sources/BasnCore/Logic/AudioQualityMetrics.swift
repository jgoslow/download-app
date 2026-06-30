import Foundation

/// Objective audio-quality measures for a recording, used to grade a capture's
/// value as a test recording (see `CaptureGrade`).
///
/// Pure and AVFoundation-free: the app target reads float PCM samples from the
/// recorded WAV (via `AVAudioFile`) and passes them to `estimate(samples:sampleRate:)`.
public struct AudioQualityMetrics: Codable, Sendable, Equatable {
    /// Root-mean-square amplitude of the whole signal, in `[0, 1]`.
    public let rms: Float
    /// Peak absolute amplitude, in `[0, 1]`.
    public let peak: Float
    /// Rough signal-to-noise ratio in dB: speech-frame energy over noise-floor
    /// energy (energy of the quietest frames). Higher is cleaner.
    public let estimatedSNR: Float
    /// Fraction of samples at or near full scale (|x| >= 0.99), in `[0, 1]`.
    public let clippingRatio: Float
    /// Normalized noisiness in `[0, 1]` derived from `estimatedSNR`
    /// (0 = clean, 1 = very noisy). Convenient for grading/diversity bucketing.
    public let noiseScore: Float

    public init(rms: Float, peak: Float, estimatedSNR: Float, clippingRatio: Float, noiseScore: Float) {
        self.rms = rms
        self.peak = peak
        self.estimatedSNR = estimatedSNR
        self.clippingRatio = clippingRatio
        self.noiseScore = noiseScore
    }

    /// Estimate quality metrics from float PCM samples.
    ///
    /// SNR is estimated by splitting the signal into short frames (~20ms),
    /// taking the loudest ~25% as "speech" and the quietest ~10% as the noise
    /// floor, then comparing their mean energies.
    public static func estimate(samples: [Float], sampleRate: Double) -> AudioQualityMetrics {
        guard !samples.isEmpty else {
            return AudioQualityMetrics(rms: 0, peak: 0, estimatedSNR: 0, clippingRatio: 0, noiseScore: 1)
        }

        var sumSquares: Double = 0
        var peak: Float = 0
        var clipped = 0
        for sample in samples {
            let abs = Swift.abs(sample)
            sumSquares += Double(sample) * Double(sample)
            if abs > peak { peak = abs }
            if abs >= 0.99 { clipped += 1 }
        }
        let rms = Float((sumSquares / Double(samples.count)).squareRoot())
        let clippingRatio = Float(clipped) / Float(samples.count)

        // Frame the signal and compute per-frame energy.
        let frameLength = max(1, Int(sampleRate * 0.02))  // ~20ms
        var energies: [Double] = []
        energies.reserveCapacity(samples.count / frameLength + 1)
        var index = 0
        while index < samples.count {
            let end = min(index + frameLength, samples.count)
            var energy: Double = 0
            for i in index..<end { energy += Double(samples[i]) * Double(samples[i]) }
            energies.append(energy / Double(end - index))
            index = end
        }
        energies.sort()

        let snr = estimateSNR(sortedFrameEnergies: energies)
        // Map SNR (dB) to a 0–1 noise score: 30dB+ ≈ clean (0), 0dB ≈ noisy (1).
        let noiseScore = Float(min(1.0, max(0.0, 1.0 - Double(snr) / 30.0)))

        return AudioQualityMetrics(
            rms: rms,
            peak: peak,
            estimatedSNR: snr,
            clippingRatio: clippingRatio,
            noiseScore: noiseScore
        )
    }

    private static func estimateSNR(sortedFrameEnergies energies: [Double]) -> Float {
        guard !energies.isEmpty else { return 0 }

        let noiseCount = max(1, energies.count / 10)          // quietest ~10%
        let speechCount = max(1, energies.count / 4)          // loudest ~25%
        let noiseEnergy = mean(energies.prefix(noiseCount))
        let speechEnergy = mean(energies.suffix(speechCount))

        let floor = max(noiseEnergy, 1e-12)
        let ratio = speechEnergy / floor
        guard ratio > 0 else { return 0 }
        return Float(10.0 * log10(ratio))
    }

    private static func mean<S: Sequence>(_ values: S) -> Double where S.Element == Double {
        var sum: Double = 0
        var count = 0
        for v in values { sum += v; count += 1 }
        return count == 0 ? 0 : sum / Double(count)
    }
}
