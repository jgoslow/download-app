---
name: project_integration_testing_plan
description: Future plan for full end-to-end integration tests using real audio files, diverse speakers, and fuzzy transcript matching
metadata:
  type: project
---

## Full Pipeline Integration Tests (HIGH PRIORITY — Jonas to pick up soon)

Current fixture tests cover `transcript text → HeuristicRouter/Castellum → ExecutionPlan`. The integration test layer must cover the full pipeline:

```
audio file → WhisperKit → transcript text → HeuristicRouter/Castellum → ExecutionPlan
```

**Why this is urgent:** During fixture capture work (2026-06-25), voice recordings produced significant transcription errors even with noise-cancelling headphones in a moderately noisy environment (café). "Auth bug" transcribed as "homework task"; captures were garbled enough for Castellum to return error responses. This is a real-world reliability risk, not a theoretical one.

**Fuzzy matching is non-negotiable.** WER (word-error-rate) threshold assertions, not exact string match. WhisperKit output will vary across model versions, hardware, and ambient conditions.

**Diverse speaker corpus is non-negotiable.** A single speaker's samples will miss real failure modes. Need: varied accents, native/non-native English, quiet/noisy environments, different mic setups (built-in Mac mic, AirPods, external mic).

**What the current JSON fixture layer tests (and does NOT test):**
- ✅ Parser correctly extracts tool_use blocks into PlannedActions
- ✅ HeuristicRouter correctly matches/rejects phrases
- ✅ Multi-intent captures fall through to Castellum
- ❌ Speech recognition accuracy
- ❌ End-to-end pipeline with real audio
- ❌ Regressions when switching WhisperKit/Parakeet model versions

**Storage:** Audio files in S3 or git-LFS — NOT main repo. JSON fixtures stay in-repo. Audio integration tests run in a separate CI job with a longer timeout.

**Two-layer test architecture:**
1. **Unit (current):** JSON fixtures, fast, offline, run on every commit
2. **Integration (to build):** Audio files, WhisperKit inference, fuzzy WER assertions, diverse speakers, run manually or in scheduled CI

**How to apply:** When designing the integration test infrastructure, plan for S3-hosted audio corpus, WER-based assertions, and a speaker diversity requirement from day one. Do not port the current exact-match approach to audio.

---

## Status (2026-06-27): infrastructure built

The audio integration layer now exists; what remains is populating the corpus.

- **WER scoring:** `WordErrorRate.compute(reference:hypothesis:)` in BasnCore (Levenshtein over normalized tokens). Used by the audio tests with a per-entry `werThreshold` (default 0.15). Never exact-match.
- **Test target:** `BasnTests/Integration/AudioPipelineTests.swift` (XCTest, app target — WhisperKit/Parakeet are not in BasnCore). Runs live transcription via the `AudioTestPipeline` seam, asserts WER, then routes (heuristic live; Castellum via recorded `rawContentBlocks` replay — deterministic, no API key). **XCTSkips** when the corpus or model is absent, so PR CI stays green.
- **Corpus:** `BasnTests/Fixtures/AudioCorpus/` — committed `manifest.json` (array of `CaptureScenario` entries with `audioFile`/`expectedTranscript`/`werThreshold`/`speaker`), `.wav` files git-LFS-tracked (`.gitattributes`) and currently `.gitignore`d until LFS is provisioned.
- **CI:** `.github/workflows/audio-integration.yml` — `workflow_dispatch` + weekly schedule, 60-min timeout, `git lfs pull` (+ optional S3 sync). Not on PRs.
- **Feeding the corpus — the debug capture archive:** the DebugBar "Archive captures" toggle saves each capture's `audio.wav` + `scenario.json` + `metadata.json` + `analysis.json`/`plan.json` + `grade.json` into a dated folder (`BasnCaptures/<date>/<time-id>/`). The **Review** sheet grades each capture (auto: action yield, audio quality; human: outcome accuracy, keep-as-fixture, notes → composite `testValue`). Promote with `bun run tools/scripts/archive-to-fixture.ts <folder> --corpus`; track quality trends with `bun run tools/scripts/capture-grades.ts` (mean testValue / accuracy by app version = improvement signal).

### Capturing on iOS for desktop assessment (2026-06-27)

The phone records; the Mac assesses. This avoids running transcription/routing/grading on-device.

- **iOS (`IOSCaptureArchive`, BasnCore-free, `#if DEBUG`):** the iOS Settings → Developer "Archive captures for debugging" toggle saves each capture's `audio.wav` + `metadata.json` (incl. the on-device transcript as a reference) into `<Documents>/BasnCaptures/<date>/<time-id>/`. `Info.plist` now sets `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`, so the folders are retrievable via **Files app › On My iPhone › Basn › BasnCaptures** (AirDrop / iCloud / Finder to the Mac).
- **Desktop ingest (`CaptureIngestor` + DebugBar "Import…"):** point it at the pulled audio files or capture folders. It runs the real desktop pipeline — transcribe (selected WhisperKit/Parakeet model) → route (heuristic, then Castellum if an API key is set) — and writes a full archive folder (audio + scenario + plan + metadata + auto-grade) into the desktop `BasnCaptures`. New folders appear in the **Review** sheet for grading, then promote to the corpus as usual. Uses toggle-independent `DebugCaptureArchive.ingestFolderURL`/`writeArtifact` so import works regardless of the live-capture toggle.
