//
//  AudioTestPipeline.swift
//  Basn
//
//  Thin seam for the end-to-end audio integration tests (BasnTests target).
//  Wraps the live TranscriptionClient so the test target can run real on-device
//  transcription via `@testable import Basn` WITHOUT importing WhisperKit /
//  FluidAudio directly. Not debug-gated — it must be available to release tests.
//

import Foundation
import WhisperKit
import BasnCore

enum AudioTestPipeline {

    /// Whether the given transcription model is downloaded and ready.
    static func isModelDownloaded(_ model: String) async -> Bool {
        await TranscriptionClient.liveValue.isModelDownloaded(model)
    }

    /// Run live transcription on an audio file using the same decode options the
    /// app uses (VAD chunking). `language` nil → auto-detect.
    static func transcribe(audioURL: URL, model: String, language: String? = nil) async throws -> String {
        let options = DecodingOptions(
            language: language,
            detectLanguage: language == nil,
            chunkingStrategy: .vad
        )
        return try await TranscriptionClient.liveValue.transcribe(audioURL, model, options) { _ in }
    }
}
