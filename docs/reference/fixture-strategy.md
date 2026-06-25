---
name: project_fixture_strategy
description: How to create and classify Basn capture fixtures — heuristic (hand-authored) vs Castellum (recorded or synthetic)
metadata:
  type: project
---

## Fixture Strategy

Fixtures live in `HexCore/Tests/BasnCoreTests/Fixtures/Scenarios/`. Tests in `CaptureScenarioTests.swift`.

### Two fixture types

**Heuristic fixtures** (`routedVia: "heuristic"`)
- Hand-authored — inputs and outputs are fully deterministic
- `rawContentBlocks: null` — no API response to capture
- `expected.actions` populated directly (or auto-populated by the in-app heuristic recorder)
- Test via `HeuristicRouter.route(transcript:connectedToolIDs:)`

**Castellum fixtures** (`routedVia: "castellum"`)
- Ideally recorded from real app captures (toggle "Record scenarios" in DebugBar → JSON deposited in sandbox Documents folder)
- Can be synthetic for parser-layer tests — use realistic tool_use block format
- `rawContentBlocks` stores the real (or realistic synthetic) Anthropic API `content` array
- `expected.actions` filled in manually after reviewing the blocks
- Test via `CastellumResponseParser.parse(scenario.toContentBlocks(), captureID:)`

### Tool_use name convention (critical)
`<toolID>_<actionType>` — parser splits on first `_` only.
Example: `jira_create_issue` → toolID: `"jira"`, actionType: `"create_issue"`

### Synthetic vs recorded Castellum fixtures
- Synthetic is fine for testing the **parser** (does it correctly extract tool calls?)
- Recorded is better for testing **Claude's actual behavior** (does it call the right tool for this prompt?)
- Current fixtures (as of 2026-06-25) are all synthetic — acceptable for now, should be replaced with real recordings as the pipeline matures

### In-app scenario recorder
- Toggle: DebugBar → "Record scenarios" (`@AppStorage("BasnRecordScenarios")`)
- Castellum captures → `basin-scenario-<id>.json` in sandbox Documents folder
- Heuristic captures → same, with `expected.actions` pre-populated automatically
- Workflow: record in app → retrieve from `~/Library/Containers/com.lyra.basn.debug/Data/Documents/` → fill `expected.actions` (Castellum only) → rename → move to `Fixtures/Scenarios/` → add `@Test`

### Known gap
Castellum currently does NOT produce `tool_use` blocks for Toggl in live captures — responds with text instead. The `toggl-jira-multi-intent` fixture is synthetic for this reason. Needs investigation. See [[project_castellum_toggl_bug]].
