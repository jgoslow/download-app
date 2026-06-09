# Unit Tests for Castellum Refactoring

## Context

The Castellum refactoring added three pure-logic components — `SessionComplexityClassifier`, `HeuristicRouter`, and `StructuredCapture` — that currently have no tests. These components make routing decisions (which Claude model to use, whether to bypass Claude entirely, how to structure transcript data) that directly affect correctness and cost. They should be tested.

The existing test infrastructure lives entirely in `HexCore/Tests/BasnCoreTests/` and uses Swift's `Testing` framework (`@Test`, `#expect`). `CastellumClient` makes real HTTP calls and is out of scope for unit tests; only the response-parsing helpers are testable without network access.

## Approach

### 1. Move two files to HexCore

`SessionComplexityClassifier` and `HeuristicRouter` are currently in `Hex/Clients/` but have zero UI or AppKit dependencies. Moving them to HexCore makes them testable via the existing `BasnCoreTests` target without creating a new Xcode test target.

- Move `Hex/Clients/SessionComplexityClassifier.swift` → `HexCore/Sources/BasnCore/Logic/SessionComplexityClassifier.swift`
- Move `Hex/Clients/HeuristicRouter.swift` → `HexCore/Sources/BasnCore/Logic/HeuristicRouter.swift`
- Update imports in `Hex/Clients/CastellumClient.swift` and `Hex/Features/Transcription/TranscriptionFeature.swift` (both already `import BasnCore` so only the file references change, not import lines)
- Both files are picked up automatically by the `PBXFileSystemSynchronizedRootGroup` in Hex and by SwiftPM in HexCore — no manifest edits needed

### 2. Write three test files

All go in `HexCore/Tests/BasnCoreTests/`, following the existing `Testing` framework pattern.

---

#### `SessionComplexityClassifierTests.swift`

Key cases to cover:

| Input | Expected |
|---|---|
| 100 words, 2 tools, no names, no dates | `.simple` → Haiku |
| 501 words, 2 tools | `.complex` → Sonnet (word count threshold) |
| 100 words, 5+ connected tools | `.complex` → Sonnet (tool count threshold) |
| Text with 3+ mid-sentence capitalized words (e.g. "Tell Alice and Bob and Carol") | `.complex` → Sonnet (person names) |
| Text with "next Tuesday" / "tomorrow" | `.complex` → Sonnet (relative dates) |
| `complexity.modelID` returns correct model ID strings |

---

#### `HeuristicRouterTests.swift`

Key cases to cover:

| Input | Toggl connected? | Expected |
|---|---|---|
| "start timer for deep work" | yes | returns 1 `PlannedAction` with `toolID == "toggl"` |
| "log time for the design review" | yes | returns action, description = "the design review" |
| "track time on the weekly sync" | yes | returns action |
| Toggl trigger phrase, Toggl NOT connected | no | returns nil |
| Multi-intent: "start timer and create a Jira ticket" | yes | returns nil (count != 1) |
| Unrelated capture: "reminder to call mom" | yes | returns nil |
| Empty string | yes | returns nil |

---

#### `StructuredCaptureTests.swift`

Key cases to cover:

| Test | What it checks |
|---|---|
| `from(session:)` with multi-sentence text | Entries created, sentences split correctly |
| `rawText` joins all sentences with space | Backwards compat computed property |
| `wordCount` sums across entries | Used by classifier |
| Entry with `promptIndex` and `promptTitle` preserved | Structured path (direct construction) |
| Entry with `chips` preserved | Chip routing signals |
| Entry with no active prompt (`promptIndex == nil`) | Positional context preserved in order |
| Codable roundtrip for `CaptureEntry` and `StructuredCapture` | Serialization correctness |

---

### 3. No test for CastellumClient

The HTTP call is not worth mocking — the response parser (`parseResponse`) is a private function and would require making it internal or extracting it. Skip for now; the integration is covered by running the app.

## Files to create/modify

- **Move** `Hex/Clients/SessionComplexityClassifier.swift` → `HexCore/Sources/BasnCore/Logic/SessionComplexityClassifier.swift`
- **Move** `Hex/Clients/HeuristicRouter.swift` → `HexCore/Sources/BasnCore/Logic/HeuristicRouter.swift`
- **Create** `HexCore/Tests/BasnCoreTests/SessionComplexityClassifierTests.swift`
- **Create** `HexCore/Tests/BasnCoreTests/HeuristicRouterTests.swift`
- **Create** `HexCore/Tests/BasnCoreTests/StructuredCaptureTests.swift`

No changes needed to `Package.swift`, `Hex/Clients/CastellumClient.swift`, or `TranscriptionFeature.swift` — import paths stay the same since both already `import BasnCore`.

## Verification

```bash
cd HexCore && swift test
# Should show: Test Suite 'All tests' passed
# Expect ~25–30 new test cases across the three files

xcodebuild -scheme Basn -configuration Debug -destination "platform=macOS" build
# Should still BUILD SUCCEEDED after the file moves
```
