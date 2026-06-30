//
//  AudioPipelineTests.swift
//  BasnTests — end-to-end audio integration layer
//
//  Exercises the FULL pipeline that the JSON fixture tests cannot reach:
//      audio file → WhisperKit/Parakeet → transcript → router → ExecutionPlan
//
//  Design decisions (see docs/reference/integration-testing-plan.md):
//   • Transcription accuracy is asserted with a fuzzy WER threshold, NEVER an
//     exact string match — model/hardware/ambient variation is expected.
//   • The audio corpus lives OUTSIDE the main repo (git-LFS / S3). When it's
//     absent, every test XCTSkips so PR CI stays green; the heavy run happens in
//     a dedicated scheduled/manual CI job after `git lfs pull`.
//   • Routing for Castellum entries replays recorded `rawContentBlocks` through
//     the parser (deterministic, no live API key). Heuristic entries route live.
//
//  Corpus location: $BASN_AUDIO_CORPUS, else <repo>/BasnTests/Fixtures/AudioCorpus.
//  Transcription model: $BASN_TEST_MODEL, else "parakeet".

import XCTest
import BasnCore
@testable import Basn

final class AudioPipelineTests: XCTestCase {

    private var corpusDir: URL {
        if let env = ProcessInfo.processInfo.environment["BASN_AUDIO_CORPUS"] {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        // <thisFile>/../Fixtures/AudioCorpus
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Integration/
            .deletingLastPathComponent()          // BasnTests/
            .appendingPathComponent("Fixtures/AudioCorpus", isDirectory: true)
    }

    private var modelName: String {
        ProcessInfo.processInfo.environment["BASN_TEST_MODEL"] ?? "parakeet"
    }

    /// Decode the corpus manifest (array of scenarios with audio fields).
    private func loadManifest() throws -> [CaptureScenario] {
        let manifestURL = corpusDir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw XCTSkip("No audio corpus at \(corpusDir.path) — skipping. Run `git lfs pull` and populate the corpus.")
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode([CaptureScenario].self, from: data)
    }

    func testAudioCorpusEndToEnd() async throws {
        let entries = try loadManifest()
        let audioEntries = entries.filter { $0.audioFile != nil && $0.expectedTranscript != nil }
        guard !audioEntries.isEmpty else {
            throw XCTSkip("Manifest has no audio entries yet.")
        }

        guard await AudioTestPipeline.isModelDownloaded(modelName) else {
            throw XCTSkip("Transcription model '\(modelName)' not downloaded — skipping. Set BASN_TEST_MODEL or download it in-app.")
        }

        for entry in audioEntries {
            try await runEntry(entry)
        }
    }

    private func runEntry(_ entry: CaptureScenario) async throws {
        let audioURL = corpusDir.appendingPathComponent(entry.audioFile!)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            XCTFail("Audio file missing for '\(entry.name)': \(audioURL.path) (git-lfs not pulled?)")
            return
        }

        // 1. Live transcription.
        let transcript = try await AudioTestPipeline.transcribe(audioURL: audioURL, model: modelName)

        // 2. Fuzzy WER assertion — never exact match.
        let threshold = entry.werThreshold ?? 0.15
        let wer = WordErrorRate.compute(reference: entry.expectedTranscript!, hypothesis: transcript)
        XCTAssertLessThanOrEqual(
            wer, threshold,
            """
            WER \(String(format: "%.3f", wer)) exceeded threshold \(threshold) for '\(entry.name)'.
            expected: \(entry.expectedTranscript!)
            got:      \(transcript)
            """
        )

        // 3. Route → ExecutionPlan and assert actions.
        let actions = route(transcript: transcript, entry: entry)
        assertActions(actions, match: entry.expected.actions, entry: entry.name)
    }

    private func route(transcript: String, entry: CaptureScenario) -> [PlannedAction] {
        let toolIDs = Set(entry.connectedToolIDs)
        switch entry.routedVia {
        case .heuristic:
            return HeuristicRouter.route(transcript: transcript, connectedToolIDs: toolIDs) ?? []
        case .castellum:
            // Deterministic replay of the recorded response — no live API call.
            let (_, actions) = CastellumResponseParser.parse(entry.toContentBlocks(), captureID: "test")
            return actions
        }
    }

    /// Partial match: only the listed parameter keys are asserted.
    private func assertActions(
        _ actual: [PlannedAction],
        match expected: [CaptureScenario.ExpectedAction],
        entry: String
    ) {
        XCTAssertEqual(actual.count, expected.count, "Action count mismatch for '\(entry)'")
        for (i, (act, exp)) in zip(actual, expected).enumerated() {
            XCTAssertEqual(act.toolID, exp.toolID, "[\(entry)] action[\(i)] toolID")
            XCTAssertEqual(act.actionType, exp.actionType, "[\(entry)] action[\(i)] actionType")
            for (key, value) in exp.parameters {
                XCTAssertEqual(act.parameters[key], value, "[\(entry)] action[\(i)] param '\(key)'")
            }
        }
    }
}
