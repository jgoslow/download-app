import Testing
import Foundation
@testable import BasnCore

struct AudioQualityMetricsTests {

    private let sampleRate = 16_000.0

    /// A pure sine tone at the given amplitude.
    private func tone(amplitude: Float, seconds: Double = 1.0, freq: Double = 440) -> [Float] {
        let count = Int(sampleRate * seconds)
        return (0..<count).map { i in
            amplitude * Float(sin(2.0 * Double.pi * freq * Double(i) / sampleRate))
        }
    }

    @Test
    func emptySamplesAreMaximallyNoisy() {
        let m = AudioQualityMetrics.estimate(samples: [], sampleRate: sampleRate)
        #expect(m.rms == 0)
        #expect(m.noiseScore == 1)
    }

    @Test
    func loudToneHasHigherPeakAndRMSThanQuietTone() {
        let loud = AudioQualityMetrics.estimate(samples: tone(amplitude: 0.8), sampleRate: sampleRate)
        let quiet = AudioQualityMetrics.estimate(samples: tone(amplitude: 0.1), sampleRate: sampleRate)
        #expect(loud.peak > quiet.peak)
        #expect(loud.rms > quiet.rms)
    }

    @Test
    func clippingIsDetected() {
        // Full-scale square-ish signal: every sample at +/- 1.0.
        let clipped = (0..<16_000).map { i in i % 2 == 0 ? Float(1.0) : Float(-1.0) }
        let m = AudioQualityMetrics.estimate(samples: clipped, sampleRate: sampleRate)
        #expect(m.clippingRatio > 0.9)
        #expect(m.peak >= 0.99)
    }

    @Test
    func cleanSpeechLikeSignalScoresLowerNoiseThanWhiteNoise() {
        // "Speech-like": loud tone bursts separated by near-silence -> high SNR.
        var speechLike = [Float]()
        let burst = tone(amplitude: 0.7, seconds: 0.2)
        let silence = [Float](repeating: 0.0005, count: Int(sampleRate * 0.2))
        for _ in 0..<3 { speechLike += burst; speechLike += silence }

        // Uniform white noise -> low SNR, high noise score.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func nextNoise() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Float(seed >> 40) / Float(1 << 24)) * 2 - 1  // [-1, 1)
        }
        let noise = (0..<Int(sampleRate)).map { _ in nextNoise() * 0.3 }

        let clean = AudioQualityMetrics.estimate(samples: speechLike, sampleRate: sampleRate)
        let noisy = AudioQualityMetrics.estimate(samples: noise, sampleRate: sampleRate)

        #expect(clean.noiseScore < noisy.noiseScore)
        #expect(clean.estimatedSNR > noisy.estimatedSNR)
    }
}
