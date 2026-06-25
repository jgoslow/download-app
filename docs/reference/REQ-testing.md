---
type: requirement
subtype: feature
status: active
created: 2026-06-25
updated: 2026-06-25
req_id: REQ-testing
tags: [requirement, testing, fixtures]
---

# REQ-testing: Fixture Strategy & Testing Pipeline
<!-- Maintained by /vault distill. Last distilled: 2026-06-25 -->

## Invariants

- [2026-06-09] **Two fixture tiers, always.** Unit fixtures (JSON, offline, every commit) + audio integration tests (real audio, WhisperKit, fuzzy WER assertions, separate CI job). Never port exact-match assertions to the audio layer. — source: [integration-testing-plan.md](integration-testing-plan.md)
- [2026-06-09] **Fuzzy matching on audio integration tests is non-negotiable.** WER (word-error-rate) threshold assertions, not exact string match. WhisperKit output varies across model versions, hardware, and ambient conditions. — source: [integration-testing-plan.md](integration-testing-plan.md)
- [2026-06-09] **Diverse speaker corpus is non-negotiable.** Audio fixtures must cover varied accents, native/non-native English, quiet/noisy environments, different mic setups. A single speaker's samples will miss real failure modes. — source: [integration-testing-plan.md](integration-testing-plan.md)
- [2026-06-25] **Current fixture suite is all synthetic.** Acceptable for parser-layer testing. Synthetic is fine for testing whether the parser correctly extracts tool calls; recorded is needed for testing whether Claude actually calls the right tool. Replace with real recordings as pipeline matures. — source: [fixture-strategy.md](fixture-strategy.md)

## Rules & Decisions

- [2026-06-09] **Audio files go in S3 or git-LFS, not the main repo.** JSON fixtures stay in-repo. Audio integration tests run in a separate CI job with a longer timeout. — source: [integration-testing-plan.md](integration-testing-plan.md)
- [2026-06-25] **Fixture location:** `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/`. Tests in `CaptureScenarioTests.swift`. — source: [fixture-strategy.md](fixture-strategy.md)
- [2026-06-25] **In-app scenario recorder:** DebugBar → "Record scenarios" (`@AppStorage("BasnRecordScenarios")`). Captures → `basin-scenario-<id>.json` in sandbox Documents. Heuristic fixtures auto-populate `expected.actions`. Workflow for Castellum fixtures: record → retrieve → fill expected.actions → rename → move to Fixtures/Scenarios/ → add `@Test`. — source: [fixture-strategy.md](fixture-strategy.md)
- [2026-06-25] **Castellum fixtures with Toggl are synthetic only.** Castellum does not produce tool_use blocks for Toggl in live captures (active bug). Do not record Castellum+Toggl fixtures until the bug is fixed. — source: [REQ-castellum.md](REQ-castellum.md)

## Open Requirements

- [ ] **Build the audio integration test layer.** Audio files → WhisperKit inference → fuzzy WER assertions. S3-hosted corpus. Diverse speaker requirement from day one. Separate CI job. HIGH PRIORITY — real-world transcription errors observed during fixture capture (café, noise-cancelling headphones: "auth bug" → "homework task"). — due: next sprint after Castellum Toggl bug fixed
