# Debug Capture Archive + End-to-End Audio Tests

## Context

Two related needs:

1. **Dev capture archive.** Today, raw recordings are saved to `Application Support/com.lyra.basn/Recordings/<epoch>.wav` (transient, epoch-named, audio-only) and a debug-only JSON recorder ([`CastellumClient.swift:309`](../../Basn/Clients/CastellumClient.swift#L309)) drops flat `basin-scenario-<id>.json` files into the sandbox Documents — **with no audio attached and no per-capture grouping**. To build a real audio test corpus and to debug transcription failures, we need each debug capture saved *together* — audio + all derived JSON — in a dated, per-capture folder that can later be lifted into a separate repo or turned into a test fixture.

2. **End-to-end audio tests.** [`docs/reference/integration-testing-plan.md`](../reference/integration-testing-plan.md) and [`REQ-testing.md`](../reference/REQ-testing.md) commit to a second test layer covering the *full* pipeline — `audio → WhisperKit/Parakeet → transcript → HeuristicRouter/Castellum → ExecutionPlan` — with **WER (word-error-rate) fuzzy matching** (never exact-match), a **diverse-speaker corpus**, audio stored **outside the main repo** (S3 / git-LFS), and a **separate CI job**. The current JSON fixture layer ([`CaptureScenarioTests.swift`](../../BasnCore/Tests/BasnCoreTests/CaptureScenarioTests.swift)) only tests `transcript → router → plan`; it never exercises speech recognition. Real-world garbling ("auth bug" → "homework task") makes this urgent.

The archive is the bridge: a real capture archived in debug mode converts directly into an audio corpus entry. **Decisions for this plan:** build both layers now; the archive is **opt-in via a DebugBar toggle** (default OFF); it **supersedes** the existing JSON-only recorder; folders land in the **sandbox container Documents** at `BasnCaptures/<date>/<time-id>/`.

## Architectural constraints (important)

- **WhisperKit / FluidAudio are imported only in the `Basn` app target**, never in the `BasnCore` SwiftPM package (verified: imports live in [`TranscriptionClient.swift`](../../Basn/Clients/TranscriptionClient.swift), [`ParakeetClient.swift`](../../Basn/Clients/ParakeetClient.swift), [`TranscriptionFeature.swift`](../../Basn/Features/Transcription/TranscriptionFeature.swift)). Real-audio tests therefore **cannot** run under `cd HexCore && swift test`; they must live in the **`BasnTests`** XCTest target (`xcodebuild test -scheme Basn`).
- Pure, offline helpers (WER, scenario model) belong in **`BasnCore`** so they stay unit-testable under `swift test`.
- The raw Anthropic response blocks are only visible inside `CastellumClient`; the audio URL is only visible inside `TranscriptionFeature`. The archive coordinates the two via a **deterministic folder path keyed by `captureID`** so both call sites write into the same folder without threading state.

---

## Part A — Debug Capture Archive

### A1. Shared archive writer — `BasnCore`

**New file:** `BasnCore/Sources/BasnCore/DebugCaptureArchive.swift`

A platform-agnostic helper (no WhisperKit dependency) that owns folder layout and artifact writing. All methods no-op unless the toggle is on.

```swift
public enum DebugCaptureArchive {
    public static let toggleKey = "BasnRecordScenarios"   // reuse existing key (supersede)
    public static var isEnabled: Bool { UserDefaults.standard.bool(forKey: toggleKey) }

    /// Deterministic per-capture folder, same for every call site in a capture.
    ///   <Documents>/BasnCaptures/2026-06-27/14-32-07-ab12cd34/
    public static func folderURL(captureID: String, timestamp: Date) -> URL?

    public static func writeAudio(from sourceURL: URL, captureID: String, timestamp: Date)
    public static func writeScenario(_ scenario: CaptureScenario, captureID: String, timestamp: Date)
    public static func writeMetadata(_ metadata: CaptureArchiveMetadata, captureID: String, timestamp: Date)
    public static func writeAnalysis(_ analysis: SessionAnalysis, captureID: String, timestamp: Date)
    public static func writePlan(_ plan: ExecutionPlan, captureID: String, timestamp: Date)
}
```

- Base dir = `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first` (same sandbox Documents the current recorder uses), then `BasnCaptures/<yyyy-MM-dd>/<HH-mm-ss>-<captureID prefix 8>/`. Use a fixed-format `DateFormatter` (`en_US_POSIX`, UTC) so names are stable.
- `folderURL` creates the directory (`withIntermediateDirectories: true`) and returns `nil` when disabled — every writer guards on it.

**Resulting folder per capture:**

```
BasnCaptures/2026-06-27/14-32-07-ab12cd34/
├── audio.wav        # copied from the recording (16kHz mono PCM)
├── scenario.json    # CaptureScenario — ready-to-use fixture (heuristic: actions pre-filled)
├── metadata.json    # device, model, flowID, duration, wordCount, source app, app version, timestamp
├── analysis.json    # SessionAnalysis (Castellum path only)
├── plan.json        # ExecutionPlan with PlannedActions
└── grade.json       # auto + human test-value grades (Part C); mutable, written/updated separately
```

`scenario.json` is the existing [`CaptureScenario`](../../BasnCore/Sources/BasnCore/Logic/CaptureScenario.swift) shape (so it drops straight into `Fixtures/Scenarios/`), extended per **A4** with audio/transcript/WER/speaker fields for the corpus layer.

### A2. Extend `CaptureScenario` for the corpus — `BasnCore`

**Edit:** [`BasnCore/Sources/BasnCore/Logic/CaptureScenario.swift`](../../BasnCore/Sources/BasnCore/Logic/CaptureScenario.swift)

Add **optional** (backward-compatible — existing fixtures decode unchanged) fields so one scenario file serves both the parse-layer tests and the audio-layer tests:

```swift
public let audioFile: String?          // "audio.wav" — relative to the scenario folder
public let expectedTranscript: String? // reference transcript for WER scoring
public let werThreshold: Double?       // max acceptable WER (default 0.15 if nil)
public let speaker: SpeakerProfile?    // accent, nativeEnglish, environment, mic
```

Add `public struct SpeakerProfile: Codable, Sendable { accent; nativeEnglish: Bool; environment; mic }`. Keep the memberwise init's new params defaulted to `nil`.

### A3. Wire the two call sites — `Basn` app target

**Edit:** [`Basn/Features/Transcription/TranscriptionFeature.swift`](../../Basn/Features/Transcription/TranscriptionFeature.swift) (the `.run` effect at [L593–680](../../Basn/Features/Transcription/TranscriptionFeature.swift#L593))
- After `finalizeRecordingAndStoreTranscript`, call `DebugCaptureArchive.writeAudio(from: audioURL, …)` and `writeMetadata(…)` using `session.id` + `session.timestamp`. (Copies the WAV *before* any history-based deletion runs.)
- **Heuristic branch** ([L651–660](../../Basn/Features/Transcription/TranscriptionFeature.swift#L651)): replace the `recordHeuristicScenario(...)` call with `DebugCaptureArchive.writeScenario(heuristicScenario, …)` + `writePlan(plan, …)`. Build the `CaptureScenario` (routedVia `.heuristic`, `expected.actions` from `heuristicActions`, `audioFile: "audio.wav"`, `expectedTranscript: modifiedResult`).
- **Castellum branch** ([L666–680](../../Basn/Features/Transcription/TranscriptionFeature.swift#L666)): after the result, call `writeAnalysis(analysis, …)` + `writePlan(plan, …)`.

**Edit:** [`Basn/Clients/CastellumClient.swift`](../../Basn/Clients/CastellumClient.swift) ([`recordScenario` L316–349](../../Basn/Clients/CastellumClient.swift#L316))
- Replace the flat-file write with `DebugCaptureArchive.writeScenario(...)` into the same `captureID`-keyed folder, preserving `rawContentBlocks` (needed by parse-layer fixtures) and setting `expectedTranscript: rawText`, `audioFile: "audio.wav"`. `captureID`/`timestamp` come from the `StructuredCapture` already in scope.
- Delete `recordHeuristicScenario` (moved to `TranscriptionFeature` via the archive). Keep the whole thing under `#if DEBUG`.

### A4. DebugBar toggle — `Basn` app target

**Edit:** [`Basn/Features/Home/DebugBar.swift`](../../Basn/Features/Home/DebugBar.swift)
- Relabel the existing `@AppStorage("BasnRecordScenarios")` toggle to **"Archive captures (audio + JSON)"** and update the hint to `→ Documents/BasnCaptures/<date>/`. Keep the **same UserDefaults key** so no migration is needed. Add a small "Show in Finder" button opening the `BasnCaptures` dir (debug convenience).

---

## Part B — End-to-End Audio Test Layer

### B1. WER utility — `BasnCore`

**New file:** `BasnCore/Sources/BasnCore/Logic/WordErrorRate.swift`
- `public enum WordErrorRate { public static func compute(reference: String, hypothesis: String) -> Double }` — Levenshtein edit distance over normalized word tokens (lowercase, strip punctuation), `distance / referenceWordCount`. Pure and offline.
- **New unit test:** `BasnCore/Tests/BasnCoreTests/WordErrorRateTests.swift` — identical strings → 0.0; one substitution in five words → 0.2; empty reference handled.

### B2. Audio corpus convention (outside main repo)

- **Location:** `BasnTests/Fixtures/AudioCorpus/` with a `manifest.json` listing entries. Audio `.wav` files are **git-LFS-tracked** (add `BasnTests/Fixtures/AudioCorpus/**/*.wav` to `.gitattributes`) and **excluded from the normal repo** via `.gitignore` until LFS is provisioned; `manifest.json` and a `README.md` are committed.
- **Manifest entry** = the extended `CaptureScenario` (A2): `audioFile`, `expectedTranscript`, `werThreshold`, `speaker`, `routedVia`, `expected.actions`, optional `rawContentBlocks`. The archive's `scenario.json` + `audio.wav` convert directly into an entry.
- **Diversity matrix** (from REQ-testing): README documents required coverage — varied accents, native/non-native English, quiet/noisy, built-in mic / AirPods / external. Manifest `speaker` fields make gaps visible.

### B3. E2E test harness — `BasnTests` target

**New file:** `BasnTests/Integration/AudioPipelineTests.swift` (XCTest)
- Resolve corpus dir from env `BASN_AUDIO_CORPUS` else `BasnTests/Fixtures/AudioCorpus`. **`XCTSkip` if the dir/manifest is absent** so the suite stays green before the corpus exists and in PR CI.
- For each manifest entry:
  1. Run **live transcription** via `TranscriptionClient` (WhisperKit or Parakeet) on `audioFile`. `XCTSkip` (with a clear message) if the required model isn't downloaded — keep model bootstrap explicit, no silent network in unit CI.
  2. Assert `WordErrorRate.compute(reference: expectedTranscript, hypothesis: actual) <= werThreshold` (default 0.15). **Never exact-match.**
  3. Route the transcript: heuristic entries → `HeuristicRouter.route` → assert `ExecutionPlan` actions via the existing `assertActions` partial matcher. Castellum entries → replay recorded `rawContentBlocks` through `CastellumResponseParser` (offline, deterministic — no live API key needed in CI).
- **Decision:** the audio layer asserts *transcription accuracy + heuristic routing*; live Castellum (nondeterministic, needs API key) stays at the recorded-fixture layer. Documented in the test file header.

### B4. Archive → fixture converter

**New script:** `tools/src/archive-to-fixture.ts` (bun, matches existing `tools/`)
- `bun run tools/src/archive-to-fixture.ts <archive-folder> [--corpus|--scenario]`
- `--scenario`: copies `scenario.json` into `BasnCore/Tests/BasnCoreTests/Fixtures/Scenarios/` (parse-layer fixture).
- `--corpus`: copies `audio.wav` + appends/merges the entry into `BasnTests/Fixtures/AudioCorpus/manifest.json` (audio-layer fixture).
- Prompts to fill `speaker` metadata if missing.

### B5. CI

- **New workflow** `.github/workflows/audio-integration.yml` (or job): manual `workflow_dispatch` + scheduled, **not** on every PR. Longer timeout. Steps: `git lfs pull` the corpus (or `aws s3 sync` from the S3 bucket), pre-download required WhisperKit/Parakeet models, then `xcodebuild test -scheme Basn -only-testing:BasnTests/AudioPipelineTests`.
- Per spec, audio files never enter the main repo history outside LFS; the manifest is the committed source of truth.

---

## Part C — Capture grading & test-value scoring

Goal: grade each archived capture for its value as a test recording, so we can (a) pick the best captures to promote into the corpus, and (b) track an aggregate grade trend over time as **tangible evidence the app is improving**. Grades are split into **auto-computed** (free, written at archive time) and **human feedback** (the debug review step).

### C1. `CaptureGrade` model — `BasnCore`

**New file:** `BasnCore/Sources/BasnCore/Logic/CaptureGrade.swift`

```swift
public struct CaptureGrade: Codable, Sendable, Equatable {
    // Auto-computed at archive time
    public var actionCount: Int           // ExecutionPlan.actions.count
    public var routedVia: String          // "heuristic" | "castellum"
    public var castellumErrored: Bool     // Castellum returned an error / empty plan
    public var durationSeconds: Double
    public var wordCount: Int
    public var audio: AudioQualityMetrics? // RMS / peak / estimated SNR / clipping (C2)
    public var transcriptionConfidence: Double?  // optional, best-effort (see note)

    // Human feedback (debug review step) — nil until graded
    public var outcomeAccuracy: Accuracy?  // .correct / .partial / .incorrect / .errored
    public var keepAsFixture: Bool?        // promote into the audio corpus?
    public var notes: String?

    // Composite, recomputed on write
    public var testValue: Int              // 0–100, see C5

    public var appVersion: String          // mirror of metadata for trend grouping
    public var gradedAt: Date?
}
public enum Accuracy: String, Codable, Sendable { case correct, partial, incorrect, errored }
```

**Decision (adjustable):** outcome accuracy is **categorical** (correct/partial/incorrect/errored) rather than a 1–5 scale — less bikeshedding, maps cleanly to a score. Easy to swap later.

### C2. Audio quality metrics — `BasnCore`

**New file:** `BasnCore/Sources/BasnCore/Logic/AudioQualityMetrics.swift`
- `public struct AudioQualityMetrics: Codable, Sendable, Equatable { rms; peak; estimatedSNR; clippingRatio; noiseScore }`.
- `public static func estimate(samples: [Float], sampleRate: Double) -> AudioQualityMetrics` — pure, operates on float PCM: RMS/peak energy, noise-floor estimate (energy of the quietest ~10% of frames) → `estimatedSNR`, fraction of samples near ±1.0 → `clippingRatio`, and a normalized 0–1 `noiseScore`. Unit-testable with synthetic tones + white noise.
- The **app target** reads samples from `audio.wav` (via `AVAudioFile`/`AVAudioPCMBuffer`, already available there) and passes `[Float]` in — `BasnCore` stays AVFoundation-free.
- **New unit test:** `BasnCore/Tests/BasnCoreTests/AudioQualityMetricsTests.swift`.

> **`transcriptionConfidence`** is *optional/best-effort*. WhisperKit segments expose `avgLogprob`/`noSpeechProb`, but `TranscriptionClient.transcribe` currently returns only `String`. Surfacing it is a small but separate refactor — leave the field, populate it only if cheap; otherwise defer. Parakeet may not expose it at all.

### C3. Auto-grade at archive time — `BasnCore` + `Basn`

- Extend `DebugCaptureArchive` with `writeGrade(_ grade: CaptureGrade, …)`.
- In [`TranscriptionFeature`](../../Basn/Features/Transcription/TranscriptionFeature.swift), after the plan is known (both branches), build the auto portion of `CaptureGrade` (action count, routedVia, errored flag, duration, wordCount, app version, audio metrics from C2) and `writeGrade(...)`. `castellumErrored` is set in the `catch`/empty-plan paths.

### C4. Human grading UI (debug only) — `Basn`

- Add a **debug-only** grading affordance on capture rows in the History detail view (and/or a "grade last capture" control in [`DebugBar`](../../Basn/Features/Home/DebugBar.swift)): pick `outcomeAccuracy`, toggle `keepAsFixture`, add `notes`. Wrapped in `#if DEBUG`.
- On submit, load the capture's `grade.json`, merge human fields, recompute `testValue` (C5), and re-write. Keyed by `captureID` so it finds the right archive folder.

### C5. Composite score + trend report

- `CaptureGrade.testValue` (recomputed on every write): weighted blend favouring captures that are *useful as tests* — e.g. produces actions (+), routes via Castellum (+, exercises more), clean audio (+) **or** usefully noisy for robustness coverage (the corpus needs both — `noiseScore` contributes via the diversity matrix, not as pure penalty), human `outcomeAccuracy == .correct` (+), `keepAsFixture` (+). Pure function in `CaptureGrade`, unit-tested.
- **New script:** `tools/src/capture-grades.ts` — scans the corpus `manifest.json` (which carries each entry's grade) and prints **aggregate grade trends grouped by `appVersion` / date**: mean `testValue`, accuracy distribution, action-yield, noise spread. Rising mean accuracy across versions on a fixed corpus = the tangible improvement signal.
- The audio corpus `manifest.json` entries (B2) embed `grade`; `archive-to-fixture.ts --corpus` (B4) carries `grade.json` into the manifest and **warns/refuses** to promote captures with `keepAsFixture == false`.

---

## Files at a glance

**New**
- `BasnCore/Sources/BasnCore/DebugCaptureArchive.swift`
- `BasnCore/Sources/BasnCore/Logic/WordErrorRate.swift`
- `BasnCore/Sources/BasnCore/Logic/CaptureGrade.swift`
- `BasnCore/Sources/BasnCore/Logic/AudioQualityMetrics.swift`
- `BasnCore/Tests/BasnCoreTests/WordErrorRateTests.swift`
- `BasnCore/Tests/BasnCoreTests/AudioQualityMetricsTests.swift` (+ `CaptureGradeTests.swift` for the score)
- `BasnTests/Integration/AudioPipelineTests.swift`
- `BasnTests/Fixtures/AudioCorpus/{manifest.json,README.md}`
- `tools/src/archive-to-fixture.ts`
- `tools/src/capture-grades.ts`
- `.github/workflows/audio-integration.yml`

**Edit**
- [`BasnCore/Sources/BasnCore/Logic/CaptureScenario.swift`](../../BasnCore/Sources/BasnCore/Logic/CaptureScenario.swift) — optional audio/transcript/WER/speaker fields
- [`Basn/Clients/CastellumClient.swift`](../../Basn/Clients/CastellumClient.swift) — route recorder through `DebugCaptureArchive`
- [`Basn/Features/Transcription/TranscriptionFeature.swift`](../../Basn/Features/Transcription/TranscriptionFeature.swift) — archive audio + metadata + scenario/plan + auto-grade
- [`Basn/Features/Home/DebugBar.swift`](../../Basn/Features/Home/DebugBar.swift) — relabel toggle, "Show in Finder", debug grading control
- History detail view (debug `#if DEBUG` section) — human grading affordance (C4)
- [`BasnCore/Tests/BasnCoreTests/CaptureScenarioTests.swift`](../../BasnCore/Tests/BasnCoreTests/CaptureScenarioTests.swift) — update header "how to add a scenario" comment to the new folder location
- `.gitattributes` / `.gitignore` — LFS + ignore rules for corpus audio
- [`docs/reference/integration-testing-plan.md`](../reference/integration-testing-plan.md) & [`REQ-testing.md`](../reference/REQ-testing.md) — mark audio layer built; document archive→corpus workflow
- `.changeset/*.md` — `bun run changeset:add-ai minor "Debug capture archive + end-to-end audio tests"`

---

## Verification

1. **Unit (offline, every commit):** `cd BasnCore && swift test` — WER, `AudioQualityMetrics`, and `CaptureGrade` score tests pass; existing `CaptureScenarioTests` still pass (optional fields decode cleanly).
2. **Archive (manual, debug build):** Build/run debug app, enable **Archive captures** in DebugBar. Record a heuristic capture ("log time for 2 hours…") and a multi-intent (Castellum) capture. Confirm `~/Library/Containers/com.lyra.basn.debug/Data/Documents/BasnCaptures/<today>/<time-id>/` contains `audio.wav` + `scenario.json` + `grade.json` (+ `analysis.json`/`plan.json` for the Castellum one), `grade.json` has sensible auto fields (actionCount, audio metrics), and `audio.wav` plays back. Toggle OFF → no folder written.
3. **Grading:** In the debug History detail, grade a capture (accuracy + keepAsFixture + notes); confirm `grade.json` updates and `testValue` recomputes.
4. **Converter & trends:** `bun run tools/src/archive-to-fixture.ts <folder> --corpus` adds the clip + grade to `manifest.json` (refuses if `keepAsFixture == false`); `--scenario` lands a fixture in `Fixtures/Scenarios/`. `bun run tools/src/capture-grades.ts` prints aggregate test-value/accuracy trends grouped by app version.
5. **E2E audio (manual / scheduled CI):** With at least one corpus entry and the model downloaded, `xcodebuild test -scheme Basn -only-testing:BasnTests/AudioPipelineTests` runs live transcription, asserts WER ≤ threshold, and asserts the routed `ExecutionPlan`. With no corpus present, the suite **skips** cleanly (no failure).
