# How to Create a Scenario Fixture

A scenario fixture is a JSON file that captures a real pipeline run (either a heuristic match or a live Castellum response) so it can be replayed in tests. Once it's in `Fixtures/Scenarios/`, CI can run the full parsing pipeline without a mic or API key.

---

## Two fixture types

| Type | When | What it tests |
|---|---|---|
| **Heuristic** (`routedVia: "heuristic"`) | Single-intent trigger (e.g. "log time for X") | `HeuristicRouter.route` — no Claude call involved |
| **Castellum** (`routedVia: "castellum"`) | Any multi-intent or unrecognized capture | `CastellumResponseParser.parse` against a real response |

Heuristic fixtures are written by hand. Castellum fixtures are recorded from the running app.

---

## Heuristic fixture — write by hand

Copy this template into `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/<name>.json`:

```json
{
  "name": "Short human name",
  "description": "What this fixture tests and why.",
  "rawText": "the exact spoken text",
  "connectedToolIDs": ["toggl"],
  "routedVia": "heuristic",
  "rawContentBlocks": null,
  "expected": {
    "actions": [
      {
        "toolID": "toggl",
        "actionType": "create_time_entry",
        "parameters": {
          "description": "expected description"
        }
      }
    ]
  }
}
```

`parameters` is a partial match — only the keys you list are checked. You don't need to predict every field Claude or the router produces; just the ones that matter for this test.

Then add a test in `CaptureScenarioTests.swift`:

```swift
@Test func togglSimpleTimer() throws {
    let scenario = try CaptureScenario.load(named: "toggl-simple-timer")
    let actions = HeuristicRouter.route(
        transcript: scenario.rawText,
        connectedToolIDs: Set(scenario.connectedToolIDs)
    )
    #expect(actions != nil)
    assertActions(actions ?? [], match: scenario.expected.actions)
}
```

---

## Castellum fixture — record from the app

### Step 1 — Enable the recorder in the app

Open the debug build. At the bottom of the home screen you'll see an orange **DEBUG** bar. Toggle **Record scenarios** on.

> **Why the in-app toggle, not `defaults write`?** The app is sandboxed. `defaults write` from Terminal writes to `~/Library/Preferences/`, but the sandboxed app reads from its own container. The in-app toggle writes to the correct location automatically.

### Step 2 — Make a capture

Say (or type) the phrase you want to turn into a fixture. Use the connected tools you want the fixture to exercise — if you want a Jira fixture, make sure Jira is connected.

After Castellum responds, check the Xcode console for:

```
[ScenarioRecorder] Exported to /Users/<you>/Library/Containers/com.lyra.basn.debug/Data/Documents/basin-scenario-XXXXXXXX.json
```

### Step 3 — Retrieve the file

Open that path in Finder (Cmd+Shift+G in Finder, paste the path). The file looks like:

```json
{
  "name": "Recorded XXXXXXXX",
  "description": "Auto-exported. Edit name/description and fill in expected.actions.",
  "rawText": "log an hour on the Castellum work and create a Jira ticket...",
  "connectedToolIDs": ["jira", "toggl"],
  "routedVia": "castellum",
  "rawContentBlocks": [
    { "type": "text", "text": "{ \"summary\": \"...\", ... }" },
    { "type": "tool_use", "name": "toggl_create_time_entry", "input": { ... } },
    { "type": "tool_use", "name": "jira_create_issue", "input": { ... } }
  ],
  "expected": { "actions": [] }
}
```

### Step 4 — Fill in `expected.actions`

Look at the `rawContentBlocks` array. For each `tool_use` block, add an entry to `expected.actions` with:

- `toolID` — everything before the first underscore in `name` (e.g. `"toggl_create_time_entry"` → `"toggl"`)
- `actionType` — everything after the first underscore (e.g. `"create_time_entry"`)
- `parameters` — copy only the params you want to assert (partial match)

Example for the `toggl_create_time_entry` block with `"input": { "description": "Castellum work", "duration_minutes": 60 }`:

```json
{
  "toolID": "toggl",
  "actionType": "create_time_entry",
  "parameters": { "description": "Castellum work" }
}
```

Also edit `name` and `description` to something human-readable.

### Step 5 — Move to Fixtures and add a test

```bash
mv ~/Library/Containers/com.lyra.basn.debug/Data/Documents/basin-scenario-XXXXXXXX.json \
   HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/toggl-jira-multi-intent.json
```

Add a test in `CaptureScenarioTests.swift`:

```swift
@Test func togglJiraMultiIntent() throws {
    let scenario = try CaptureScenario.load(named: "toggl-jira-multi-intent")
    let blocks = scenario.toContentBlocks()
    let (analysis, actions) = CastellumResponseParser.parse(blocks, captureID: "test")
    #expect(!analysis.summary.isEmpty)
    assertActions(actions, match: scenario.expected.actions)
}
```

### Step 6 — Run the tests

```bash
cd HexCore && swift test --filter CaptureScenarioTests
```

---

## Turn off recording

When you're done, toggle **Record scenarios** off in the debug bar. The flag persists across app launches so leaving it on will dump a file on every capture.

---

## Scenarios to record

See [2026-06-09-fixture-based-capture-testing.md](2026-06-09-fixture-based-capture-testing.md) (Phase 5) for the full list of target fixtures with suggested phrases and expected action shapes.

| Fixture | `routedVia` | Status |
|---|---|---|
| `toggl-simple-timer.json` | heuristic | Done |
| `jira-only-ticket.json` | castellum | — |
| `jira-slack-standup.json` | castellum | — |
| `toggl-jira-multi-intent.json` | castellum | — |
| `no-actions-journal.json` | castellum | — |
| `google-calendar-event.json` | castellum | — |
| `guided-flow-morning-kickoff.json` | castellum | — |
| `wave-expense.json` | castellum | — |
