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
