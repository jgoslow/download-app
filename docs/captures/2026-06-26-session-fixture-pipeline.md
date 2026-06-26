---
type: log
subtype: session
status: reference
created: 2026-06-26
updated: 2026-06-26
distilled: true
tags: [session, heuristic-router, fixtures, ios, testing]
---

# 2026-06-26 — Session: Fixture Pipeline, Heuristic Improvements, iOS Text Input

## What Was Decided

- **HeuristicRouter strips leading "for "** from description after trigger extraction. "start timer for X" now produces description "X" not "for X". Existing test expectation updated to match.
- **`saveTranscriptionHistory` gate removed for text captures.** The flag now only guards audio file persistence to disk. Text captures always go to history. Root cause of the bug: v1 settings migration persisted `false` for existing users, silently blocking text history insertion.
- **Duration parsing added to HeuristicRouter.** Natural language duration extracted from capture text and placed in `duration_minutes` parameter before Toggl actions. Defaults to 30 min if not found. Supports "2 hours", "30 minutes", "half an hour", "1.5 hours", etc.
- **HeuristicRouter single-match rule confirmed.** Fires only on exactly 1 unambiguous action match; competing matches (multi-intent) fall through to Castellum. This is intentional — ambiguity requires interpretation.
- **Two-layer test architecture established.** Layer 1: JSON fixture unit tests (fast, offline, deterministic — live in HexCore). Layer 2: future audio integration tests (S3/LFS corpus, WhisperKit inference, WER-based fuzzy assertions, diverse speakers). Layer 2 is HIGH PRIORITY but not yet built.
- **Heuristic scenario recorder added.** Heuristic path now writes JSON to sandbox Documents in `#if DEBUG` builds — same mechanism as Castellum recorder. Pre-populates `expected.actions` from actual matched actions (unlike Castellum recorder which needs manual fill-in).
- **Castellum→Toggl bug documented.** For multi-intent captures reaching Castellum with Toggl as a target, Claude returns prose ("I don't have a direct Toggl integration") instead of a `tool_use` block. Single-intent Toggl works via heuristic. Multi-intent Toggl+other silently fails.
- **iOS text input UI added (stub).** iOS `HomeView` now has "or type your flow" → TextField with autofocus → Cancel/Submit. `submitTextCapture()` added to `AppState`. No HeuristicRouter or Castellum wiring yet — pipeline is incomplete on iOS.

## What Was Built or Changed

| File | Change |
|------|--------|
| `HexCore/Sources/BasnCore/Logic/HeuristicRouter.swift` | `parseDurationMinutes()`, leading "for" strip, `duration_minutes` in action params |
| `Hex/Features/Transcription/TranscriptionFeature.swift` | Removed `saveTranscriptionHistory` gate for text; added `#if DEBUG` `recordHeuristicScenario` calls |
| `Hex/Clients/CastellumClient.swift` | `recordHeuristicScenario()` function in `#if DEBUG` block |
| `Hex/Features/Home/HomeView.swift` | `@FocusState` autofocus when "type your flow" is tapped |
| `iOS/HomeView.swift` | Full `textInputSection`: button → TextField (autofocus) → Cancel/Submit |
| `iOS/App/AppState.swift` | `submitTextCapture(_ text: String)` stub — saves session, reloads history |
| `HexCore/Sources/BasnCore/Logic/SessionComplexityClassifier.swift` | Made `public` to unblock new test suites |
| `Hex/Clients/ToolActions/JiraActionClient.swift` | `tokenLastRefreshedAt = Date()` after both token refresh paths |
| `HexCore/Tests/BasnCoreTests/CaptureScenarioTests.swift` | Full rewrite — 7 active fixture tests covering all current scenarios |
| `HexCore/Tests/BasnCoreTests/HeuristicRouterTests.swift` | Updated `"for deep work"` → `"deep work"` to match "for" strip fix |
| `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/toggl-simple-timer.json` | Updated: explicit duration (2 hours → 120 min), explicit description |
| `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/toggl-start-timer.json` | New: heuristic path, "start timer for Basn iOS work" |
| `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/jira-only-ticket.json` | New: castellum path, `jira_create_issue` |
| `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/jira-slack-standup.json` | New: castellum path, jira + slack |
| `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/toggl-jira-multi-intent.json` | New: castellum path, toggl + jira; verifies heuristic returns nil for same text |
| `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/no-actions-journal.json` | New: castellum path, empty actions (journaling) |
| `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/google-calendar-event.json` | New: castellum path, `google_create_event` |
| New test files (4) | `CastellumResponseParserTests`, `ModelPatternMatcherTests`, `RecordingDecisionEngineTests`, `SessionAnalysisTests` |
| `.claude/memory/*.md` | 4 memory files created/updated |

All changes committed in two commits: `3239fbc` (tests/API), `6812658` (pipeline/fixtures).

## Open Questions / Next Tasks

- [ ] **HIGH PRIORITY** — End-to-end speech integration tests: audio corpus in S3/LFS, WhisperKit inference, WER-based fuzzy assertions, diverse speaker capture across conditions
- [ ] Fix Castellum→Toggl `tool_use` bug — Claude returns prose for Toggl in multi-intent captures; root cause unknown (tool schema not passed, or Haiku declining to call it)
- [ ] Build full iOS capture pipeline — move `CastellumClient` to HexCore, wire `HeuristicRouter` + Castellum into iOS `AppState` post-transcription
- [ ] `BasnSettingsMigrationTests` pre-existing failure — `Fixtures/BasnSettings/v1.json` missing from repo; unrelated to this session's changes
- [ ] Toggl clarifying question UX — when heuristic matches but duration/project is absent, prompt user rather than defaulting to 30 min
- [ ] `wave-expense` fixture — commented out; re-enable when Wave is connected

## Context to Carry Forward

- `saveTranscriptionHistory` gates audio file persistence only — text captures are always added to history now
- iOS text capture UI exists but pipeline is NOT wired — no HeuristicRouter or Castellum call happens on iOS submit yet
- Castellum fixtures in HexCore are synthetic (parser-layer correctness testing) — replace with recorded fixtures as the pipeline matures and the Toggl bug is fixed
- `@AppStorage("BasnRecordScenarios")` must be toggled in-app (not via `defaults write`) due to sandbox isolation
- `toggl-jira-multi-intent` fixture tests the parser with a synthetic rawContentBlock — it does NOT prove Castellum can actually call Toggl for multi-intent captures (it can't, currently)
