---
type: planning
status: active
created: 2026-06-26
updated: 2026-06-26
tags: [vault, close, session]
---

# Vault Close Plan — 2026-06-26 (fixture pipeline + heuristic improvements)

## Context

Closing the capture-pipeline fixture-testing session. Session covered: duration parsing in HeuristicRouter, "for" stripping fix, text capture history fix, heuristic scenario recorder, iOS text input UI, synthetic fixtures for all 7 test scenarios, and expanded test suite. All code committed in two commits (6812658, 3239fbc). No code changes remain unstaged — only Xcode scheme state and Localizable.xcstrings (both intentionally skipped). Closing to persist session knowledge to the vault.

---

## Step 1 — Write Session Log

**Destination:** `docs/captures/2026-06-26-session-fixture-pipeline.md`

**Content to include:**

### What Was Decided
- HeuristicRouter strips leading "for " from description after trigger extraction (fixes "start timer for X" → "X" not "for X")
- `saveTranscriptionHistory` gate removed for text captures — text always goes to history, audio guarded separately
- Duration parsing added to HeuristicRouter: natural language → `duration_minutes` param; defaults to 30 min when absent
- HeuristicRouter fires only on exactly 1 unambiguous match; competing matches fall through to Castellum (confirmed rule)
- Two-layer test architecture: unit tests (JSON fixtures, fast, offline) + future integration tests (audio corpus, WhisperKit inference, WER fuzzy matching)
- Heuristic captures write JSON to sandbox Documents in `#if DEBUG` builds — same flow as Castellum recorder
- Castellum→Toggl bug documented: Claude returns prose instead of `tool_use` blocks for multi-intent captures; single-intent Toggl works via heuristic

### What Was Built or Changed

| File | Change |
|------|--------|
| `HexCore/Sources/BasnCore/Logic/HeuristicRouter.swift` | `parseDurationMinutes()`, "for" strip, duration param in actions |
| `Hex/Features/Transcription/TranscriptionFeature.swift` | Removed `saveTranscriptionHistory` gate; added `recordHeuristicScenario` calls |
| `Hex/Clients/CastellumClient.swift` | `recordHeuristicScenario()` function in `#if DEBUG` |
| `Hex/Features/Home/HomeView.swift` | `@FocusState` autofocus on "type your flow" click |
| `iOS/HomeView.swift` | Full `textInputSection` with autofocus |
| `iOS/App/AppState.swift` | `submitTextCapture()` stub |
| `HexCore/Sources/BasnCore/Logic/SessionComplexityClassifier.swift` | `public` API exposure |
| `Hex/Clients/ToolActions/JiraActionClient.swift` | `tokenLastRefreshedAt` fix on both refresh paths |
| `HexCore/Tests/BasnCoreTests/CaptureScenarioTests.swift` | Full rewrite, 7 active fixture tests |
| `HexCore/Tests/BasnCoreTests/HeuristicRouterTests.swift` | Updated "for deep work" expectation to "deep work" |
| `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/*.json` | 7 fixture files created (6 new + 1 updated) |
| New test files | `CastellumResponseParserTests`, `ModelPatternMatcherTests`, `RecordingDecisionEngineTests`, `SessionAnalysisTests` |
| `.claude/memory/*.md` | 4 memory files created/updated |

### Open Questions / Next Tasks
- [ ] **HIGH PRIORITY** — End-to-end speech integration tests: audio corpus in S3/LFS, WhisperKit inference, WER-based fuzzy matching, diverse speaker capture
- [ ] Fix Castellum→Toggl `tool_use` bug (Claude returns prose for multi-intent captures)
- [ ] Build full iOS pipeline: move `CastellumClient` to HexCore, wire `HeuristicRouter` + Castellum into iOS `AppState`
- [ ] `BasnSettingsMigrationTests` pre-existing failure — `Fixtures/BasnSettings/v1.json` missing from repo
- [ ] Toggl clarifying question UX — when duration/project unspecified, prompt user before submitting
- [ ] `wave-expense` fixture — re-enable when Wave is connected

### Context to Carry Forward
- `saveTranscriptionHistory` now only gates audio file persistence; text captures are always added to history
- iOS has stub text capture UI but no HeuristicRouter/Castellum wiring — DO NOT assume iOS pipeline is complete
- Castellum fixtures are synthetic (parser-layer correctness) — replace with recorded fixtures as pipeline matures
- `@AppStorage("BasnRecordScenarios")` must be toggled in-app (not via `defaults write`) due to sandbox isolation

---

## Step 2 — Update planning-summary.md

**File:** `docs/reference/planning-summary.md`

Changes:
1. Add session to **Recent Plans** table:
   ```
   | 2026-06-26 | [fixture-pipeline](../captures/2026-06-26-session-fixture-pipeline.md) | complete | Duration parsing, text capture fix, iOS text input, 7 synthetic fixtures |
   ```
2. Ensure **Outstanding** items include:
   - Speech integration tests (HIGH PRIORITY marker already present — verify)
   - Castellum→Toggl bug (already present — verify)
   - iOS pipeline wiring (may need to add or update)
3. Add to **Key Decisions Log**:
   ```
   - [2026-06-26] HeuristicRouter strips leading "for " from descriptions; adds duration_minutes param (defaults 30 min) — source: session-fixture-pipeline
   - [2026-06-26] saveTranscriptionHistory gates audio file persistence only; text captures always reach history — source: session-fixture-pipeline
   ```

---

## Step 3 — Check Undistilled Captures

Read `docs/captures/castellum-toggl-bug.md` and `docs/captures/animation-ideas.md` to check `distilled:` frontmatter. If `distilled: false`, extract signal:
- `castellum-toggl-bug.md` → update `docs/reference/REQ-castellum.md` § Open Requirements (if not already there)
- `animation-ideas.md` → update planning-summary.md § Visual Identity Notes (if not already there)
- Set `distilled: true` and update `updated:` on each processed file

---

## Step 4 — Privacy Check

Scan all new/modified `.md` files in `docs/` for:
- `$NNN/hr` patterns
- compensation, salary, payroll, markup, rate ceiling, negotiation

Expected result: no matches (no commercial content this session).

---

## Step 5 — Commit Context Files

Proposed commit message:
```
docs: session close — fixture pipeline, heuristic improvements, iOS text input

- Session log: 2026-06-26 fixture pipeline session
- Planning summary updated with session decisions and tasks
- Distilled castellum-toggl-bug and animation-ideas captures if undistilled
```

Files to stage:
- `docs/captures/2026-06-26-session-fixture-pipeline.md` (new)
- `docs/reference/planning-summary.md` (updated)
- `docs/captures/castellum-toggl-bug.md` (updated distilled: true, if applicable)
- `docs/captures/animation-ideas.md` (updated distilled: true, if applicable)
- `docs/reference/REQ-castellum.md` (if updated)

Wait for explicit user approval before committing.

---

## Step 6 — Code Check (optional)

Ask: run `cd HexCore && swift test` to verify fixture tests still pass after this session?
