# Fixture-Based Capture Testing

## Context

Testing the full capture pipeline currently requires recording live audio. This blocks iteration when you can't speak. The goal is a layered test system where:

1. Pure logic (recording decisions, model routing, complexity classification) is covered by fast inline unit tests
2. Castellum's response-parsing pipeline is covered by fixture tests that replay real captured Claude responses — no mic, no API key, no network at test time
3. A debug recorder lets you export any real capture as a fixture to grow the suite over time

Most of the foundation is already there. `HeuristicRouter`, `SessionComplexityClassifier`, and `StructuredCapture` are all in HexCore with tests. The gaps are: `RecordingDecisionEngine` (safety-critical, zero tests), `ModelPatternMatcher` (zero tests), `SessionAnalysis` Codable correctness (zero tests), and Castellum response parsing (not extractable yet).

---

## Phase 1 — Quick Inline Tests (no new infrastructure)

These are pure functions with no dependencies. Each can be written and run with `cd HexCore && swift test` in under 30 minutes total.

### 1a. `RecordingDecisionEngineTests`

**New file:** `HexCore/Tests/BasnCoreTests/RecordingDecisionEngineTests.swift`

Key cases to cover — all are pure `RecordingDecisionEngine.decide(_:)` calls:

| Test | hotkey.key | minimumKeyTime | elapsed | Expected |
|---|---|---|---|---|
| Modifier-only, below 0.3s floor | nil | 0.2s | 0.1s | `.discardShortRecording` |
| Modifier-only, exactly at 0.3s floor | nil | 0.2s | 0.3s | `.proceedToTranscription` |
| Modifier-only, above 0.3s floor | nil | 0.2s | 0.5s | `.proceedToTranscription` |
| Modifier-only, user minimumKeyTime > 0.3s floor | nil | 0.5s | 0.4s | `.discardShortRecording` |
| Modifier-only, meets user minimumKeyTime (above floor) | nil | 0.5s | 0.6s | `.proceedToTranscription` |
| Key+modifier, 0s duration (always proceeds) | "a" | 0.2s | 0.0s | `.proceedToTranscription` |
| Key+modifier, very short | "a" | 0.2s | 0.05s | `.proceedToTranscription` |
| No `recordingStartTime` (elapsed → 0) | nil | 0.2s | n/a | `.discardShortRecording` |

Uses `Date(timeIntervalSince1970:)` arithmetic — no real time, fully deterministic.

### 1b. `ModelPatternMatcherTests`

**New file:** `HexCore/Tests/BasnCoreTests/ModelPatternMatcherTests.swift`

Key cases to cover — all are pure `ModelPatternMatcher.matches/resolvePattern` calls:

- Exact string match (no wildcards) → `true`
- Exact string non-match → `false`
- Wildcard `"distil*large-v3"` matches `"distil-whisper-large-v3"` → `true`
- Wildcard doesn't match unrelated string → `false`
- `resolvePattern`: no wildcards → returns pattern as-is
- `resolvePattern`: one match, not downloaded → returns it
- `resolvePattern`: multiple matches, prefers downloaded
- `resolvePattern`: downloaded turbo and downloaded non-turbo → returns non-turbo
- `resolvePattern`: no downloaded, non-turbo available → returns non-turbo
- `resolvePattern`: no matches → returns `nil`

---

## Phase 2 — `SessionAnalysis` Codable Tests (no new infrastructure)

**New file:** `HexCore/Tests/BasnCoreTests/SessionAnalysisTests.swift`

`SessionAnalysis` is decoded from Claude's raw JSON response. It uses snake_case CodingKeys (`mood_tag`, `prompts_addressed`) — a subtle rename in the system prompt or a key typo would silently produce empty/nil fields with no crash. These tests pin that contract.

Key cases — all are inline JSON strings decoded via `JSONDecoder()`:

- Full roundtrip: all fields populated, encode → decode → equality
- `mood_tag` absent in JSON → `moodTag == nil` (not a decode failure)
- `tasks`, `routing`, `integrations`, `delegations`, `prompts_addressed` all absent → decode succeeds with empty arrays
- Unknown top-level key → decode succeeds (ignored)
- `routing` includes unknown raw value → decode still succeeds for known values (requires `@unknown` or decoding with `[RoutingDestination?]` filtering)
- `integrations` roundtrips all 8 cases (`jira`, `toggl`, `slack`, `email`, `calendar`, `docs`, `wave`, `github`)
- `prompts_addressed` decodes from `[0, 2]` to `[Int]` correctly
- Minimal case: only `summary` key present → decodes cleanly

Also test `ExecutionPlan` and `PlannedAction` Codable roundtrips here — they're simpler but currently untested:
- `ExecutionPlan` roundtrip with 2 actions
- `PlannedAction` roundtrip with full parameters dict
- `hasActionableItems`: true when ≥1 `.pending` action, false when empty or all `.succeeded`

---

## Phase 3 — Extract `CastellumResponseParser` to HexCore

This is the prerequisite for Phase 4. The `parseResponse` function in [CastellumClient.swift](Hex/Clients/CastellumClient.swift) (lines 223–276) is pure parsing logic trapped in the app target.

### 3a. New source file

**New file:** `HexCore/Sources/BasnCore/Logic/CastellumResponseParser.swift`

Extract the function body verbatim, then remove the `ToolActionRegistry` dependency (used only for display labels) by accepting an optional closure:

```swift
public struct CastellumResponseParser {
    public static func parse(
        _ content: [[String: Any]],
        captureID: String,
        labelLookup: ((String, String) -> String?)? = nil
    ) -> (SessionAnalysis, [PlannedAction])
}
```

The label line (`actionDef?.displayName`) is replaced with `labelLookup?(toolID, actionType)`, defaulting to a plain capitalized string when nil. In tests, `labelLookup` is omitted — labels are never asserted in tests (only `toolID`, `actionType`, `parameters`).

### 3b. Update `CastellumClient`

In [CastellumClient.swift](Hex/Clients/CastellumClient.swift), `parseResponse` becomes a one-liner:

```swift
private func parseResponse(_ content: [[String: Any]], captureID: String) -> (SessionAnalysis, [PlannedAction]) {
    CastellumResponseParser.parse(content, captureID: captureID) { toolID, actionType in
        ToolActionRegistry.action(toolID: toolID, actionType: actionType)?.displayName
    }
}
```

Also change `callClaude` to return `(data: Data, content: [[String: Any]])` (currently returns only `content`). The extra `Data` is only used `#if DEBUG` by the recorder in Phase 4 — no behavior change in release builds.

### 3c. Inline parser tests (no fixtures yet)

**New file:** `HexCore/Tests/BasnCoreTests/CastellumResponseParserTests.swift`

These use inline `[[String: Any]]` literals to cover the parsing logic:

- Text block with clean JSON → `SessionAnalysis` decoded correctly
- Text block with surrounding prose before/after JSON → JSON still extracted
- `"jira_create_issue"` → `toolID: "jira"`, `actionType: "create_issue"`
- `"toggl_create_time_entry"` → splits on first underscore only
- `NSNumber` param value → coerced to String
- `[String]` param value → joined with `", "`
- No `tool_use` blocks → empty actions, no crash
- Only `tool_use` blocks (no text block) → fallback `SessionAnalysis(summary: "Capture processed")`
- Malformed text block (not parseable JSON) → fallback analysis, no crash
- Multiple `tool_use` blocks → all actions returned in order

---

## Phase 4 — Fixture Infrastructure + Scenario Tests

### 4a. `CaptureScenario` type

**New file:** `HexCore/Sources/BasnCore/Logic/CaptureScenario.swift`

```swift
public struct CaptureScenario: Codable {
    public let name: String
    public let description: String
    public let routedVia: RoutingPath       // "heuristic" | "castellum"
    public let connectedToolIDs: [String]
    public let rawText: String              // Human-readable reference only
    /// The `content` array from the raw Anthropic response.
    /// Nil for heuristic-only scenarios.
    public let rawContentBlocks: [RawBlock]?
    public let expected: Expected

    public enum RoutingPath: String, Codable { case heuristic, castellum }

    public struct RawBlock: Codable {
        public let type: String
        public let text: String?
        public let name: String?
        public let input: [String: RawValue]?
    }

    public struct Expected: Codable {
        public let actions: [ExpectedAction]
        public let analysisSummaryIsNonEmpty: Bool
    }

    public struct ExpectedAction: Codable {
        public let toolID: String
        public let actionType: String
        public let parameters: [String: String]  // partial — only listed keys asserted
    }
}
```

`RawValue` is a minimal local `Codable` union (Bool / Int / Double / String / array / object) defined in the same file — no external dependency.

### 4b. Fixture loading helper

**New file:** `HexCore/Tests/BasnCoreTests/CaptureScenarioFixture.swift`

```swift
extension CaptureScenario {
    static func load(named name: String) throws -> CaptureScenario {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "json",
            subdirectory: "Fixtures/Scenarios"
        ) else { throw FixtureError.notFound(name) }
        return try JSONDecoder().decode(CaptureScenario.self, from: Data(contentsOf: url))
    }

    func toContentBlocks() -> [[String: Any]] { /* convert RawBlock → [[String: Any]] */ }
}
```

`Package.swift` already has `.copy("Fixtures")` — no change needed.

### 4c. Scenario test file

**New file:** `HexCore/Tests/BasnCoreTests/CaptureScenarioTests.swift`

One `@Test` per fixture file — the pattern for each:

```swift
@Test func togglSimpleTimer() throws {
    let scenario = try CaptureScenario.load(named: "toggl-simple-timer")
    // heuristic path
    let actions = HeuristicRouter.route(
        transcript: scenario.rawText,
        connectedToolIDs: Set(scenario.connectedToolIDs)
    )
    #expect(actions != nil)
    assertActions(actions ?? [], match: scenario.expected.actions)
}

@Test func jiraSlackStandup() throws {
    let scenario = try CaptureScenario.load(named: "jira-slack-standup")
    let blocks = scenario.toContentBlocks()
    let (analysis, actions) = CastellumResponseParser.parse(blocks, captureID: "test")
    #expect(!analysis.summary.isEmpty)
    assertActions(actions, match: scenario.expected.actions)
}
```

Helper `assertActions(_:match:)` does partial parameter matching — only keys listed in `expected` are checked.

### 4d. Debug recorder

**New file:** `Hex/Debug/CaptureScenarioRecorder.swift` (entire file wrapped in `#if DEBUG`)

Called from `CastellumClient` after `callClaude` returns, passing the raw `Data` before parsing. Writes a JSON scaffold to `~/Desktop/basin-scenario-<captureID>.json`. You fill in `expected.actions` by reading the `rawContentBlocks`, then move to `Fixtures/Scenarios/` and add a `@Test`.

---

## Phase 5 — Fixtures You Need to Record

These are the real captures to make in the app. For each: trigger a capture in debug build, look for the JSON on your Desktop, fill in `expected.actions`, commit to `Fixtures/Scenarios/`.

The first fixture (toggl-simple-timer) is hand-written — no recording needed.

---

### Fixture 1 — `toggl-simple-timer.json` (hand-written, no recording needed)

**Say:** *(not required — write this by hand)*
**Path:** HeuristicRouter bypass — no API call
**Connected tools:** `toggl` only
**Expected actions:** 1 × `toggl / create_time_entry`
**Purpose:** Baseline for heuristic routing; verifies the bypass path works end-to-end

---

### Fixture 2 — `jira-only-ticket.json`

**Say:** *"Need to create a Jira ticket for the onboarding bug — users are getting stuck on the microphone permission screen"*
**Path:** Castellum (Haiku)
**Connected tools:** `jira`
**Expected actions:** 1 × `jira / create_issue` with `summary` or `title` param containing something about onboarding or microphone
**What it exercises:**
- Single `tool_use` block parsing
- `toolID`/`actionType` split from `"jira_create_issue"`
- Param extraction from Jira input schema

---

### Fixture 3 — `jira-slack-standup.json`

**Say:** *"Quick standup update: I'm working on the Castellum refactor today, blocked on the API key issue. Can someone post this in the eng channel on Slack?"*
**Path:** Castellum (Haiku)
**Connected tools:** `jira`, `slack`
**Expected actions:** 2 actions — one `slack / send_message` (standup update), possibly one `jira / create_issue` or `jira / add_comment`
**What it exercises:**
- Multiple `tool_use` blocks in order
- Action count > 1
- Slack param extraction (`channel`, `text`)
- `SessionAnalysis.routing` includes both `jira` and `slack`

---

### Fixture 4 — `toggl-jira-multi-intent.json`

**Say:** *"Log an hour on the Castellum work and create a Jira ticket to track the response parsing refactor"*
**Path:** Castellum (Haiku) — HeuristicRouter sees Toggl trigger but also Jira intent → returns nil → falls through
**Connected tools:** `jira`, `toggl`
**Expected actions:** 2 — `toggl / create_time_entry` + `jira / create_issue`
**What it exercises:**
- HeuristicRouter multi-intent fallthrough (critical boundary)
- Both tools in one Castellum response
- `durationMinutes` or similar numeric param in Toggl block

---

### Fixture 5 — `no-actions-journal.json`

**Say:** *"Just a note to myself — really good conversation with the design team today. Feeling good about the direction. No action items."*
**Path:** Castellum (Haiku)
**Connected tools:** any (none will be triggered)
**Expected actions:** 0 (empty actions array)
**What it exercises:**
- `parseResponse` with zero `tool_use` blocks — no crash
- `SessionAnalysis` still populated (summary, possibly `moodTag`)
- `hasActionableItems == false` on the resulting `ExecutionPlan`
- `moodTag` is non-nil (tests the snake_case `mood_tag` key decoding)

---

### Fixture 6 — `google-calendar-event.json`

**Say:** *"Schedule a design review with the team for next Thursday at 2pm — about an hour"*
**Path:** Castellum (Sonnet — date arithmetic triggers complex classification)
**Connected tools:** `google`
**Expected actions:** 1 × `google / create_event` with `title`, `start_time`, `duration` params
**What it exercises:**
- `SessionComplexityClassifier` date arithmetic → `.complex` → Sonnet used (verify via `plan.modelUsed`)
- Google Calendar tool schema parsing
- Date/time param extraction

---

### Fixture 7 — `guided-flow-morning-kickoff.json`

**Say:** *(Use the "Morning Kickoff" flow or any guided flow with 2–3 prompts)*
*Prompt 1 (Goal): "Ship the onboarding refactor"*
*Prompt 2 (Blockers): "Waiting on design sign-off"*
*Prompt 3 (Time tracking): "Log 2 hours on the onboarding work"*
**Path:** Castellum (Haiku)
**Connected tools:** `jira`, `toggl`
**Expected actions:** `jira / create_issue` (for the goal) + `toggl / create_time_entry`
**What it exercises:**
- `StructuredCapture.entries` with non-nil `promptIndex` and `promptTitle`
- `SessionAnalysis.promptsAddressed` populated
- `prompts_addressed` snake_case key decoding
- Chip-influenced routing (if any chips were selected)

---

### Fixture 8 — `wave-expense.json`

**Say:** *"Add an expense to Wave — $45 for the conference dinner last night, category meals and entertainment"*
**Path:** Castellum (Haiku)
**Connected tools:** `wave`
**Expected actions:** 1 × `wave / create_expense` with `amount`, `description`, `category` params
**What it exercises:**
- Wave tool schema (less-common integration)
- Numeric param coercion (`$45` → amount string)
- A less-tested tool end-to-end

---

## File Summary

| File | Phase | Status |
|---|---|---|
| `HexCore/Tests/…/RecordingDecisionEngineTests.swift` | 1a | New |
| `HexCore/Tests/…/ModelPatternMatcherTests.swift` | 1b | New |
| `HexCore/Tests/…/SessionAnalysisTests.swift` | 2 | New |
| `HexCore/Sources/…/Logic/CastellumResponseParser.swift` | 3a | New |
| `Hex/Clients/CastellumClient.swift` | 3b | Modify (delegate + expose raw Data) |
| `HexCore/Tests/…/CastellumResponseParserTests.swift` | 3c | New |
| `HexCore/Sources/…/Logic/CaptureScenario.swift` | 4a | New |
| `HexCore/Tests/…/CaptureScenarioFixture.swift` | 4b | New |
| `HexCore/Tests/…/CaptureScenarioTests.swift` | 4c | New |
| `Hex/Debug/CaptureScenarioRecorder.swift` | 4d | New |
| `Fixtures/Scenarios/toggl-simple-timer.json` | 4 | Hand-write |
| `Fixtures/Scenarios/jira-only-ticket.json` | 4 | Record (Fixture 2) |
| `Fixtures/Scenarios/jira-slack-standup.json` | 4 | Record (Fixture 3) |
| `Fixtures/Scenarios/toggl-jira-multi-intent.json` | 4 | Record (Fixture 4) |
| `Fixtures/Scenarios/no-actions-journal.json` | 4 | Record (Fixture 5) |
| `Fixtures/Scenarios/google-calendar-event.json` | 4 | Record (Fixture 6) |
| `Fixtures/Scenarios/guided-flow-morning-kickoff.json` | 4 | Record (Fixture 7) |
| `Fixtures/Scenarios/wave-expense.json` | 4 | Record (Fixture 8) |

Not changed: `Package.swift`, all existing test files, `HotKeyProcessorTests`, `HeuristicRouterTests`, `StructuredCaptureTests`.

## Verification

Each phase is independently runnable:

```bash
cd HexCore && swift test
```

- After Phase 1: 2 new suites pass, all existing tests still pass
- After Phase 2: `SessionAnalysisTests` passes — Codable contract pinned
- After Phase 3: `CastellumResponseParserTests` passes with inline fixtures; app builds with delegation
- After Phase 4 + recordings: each `CaptureScenarioTests` test passes as its JSON fixture is added
