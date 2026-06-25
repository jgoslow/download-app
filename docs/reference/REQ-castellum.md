---
type: requirement
subtype: feature
status: active
created: 2026-06-25
updated: 2026-06-25
req_id: REQ-castellum
tags: [requirement, castellum, routing]
---

# REQ-castellum: Castellum Routing & Tool Integration
<!-- Maintained by /vault distill. Last distilled: 2026-06-25 -->

## Invariants

- [2026-03-22] **Workflows are emergent, never pre-configured.** Castellum reads the capture and decides what workflows are possible given connected tools. Never seed `Workflow` records by default. Never show a pre-configured workflow list that users maintain. — source: [architecture.md](architecture.md)
- [2026-05-22] **HeuristicRouter fires only on exactly one unambiguous match.** `guard actions.count == 1 else { return nil }` — competing or ambiguous matches (e.g. Toggl + Jira) fall through to Castellum. Do not coin-flip between matched intents. — source: [heuristic-router.md](heuristic-router.md)
- [2026-05-22] **Ambiguous intent → ask for clarification, don't pick silently.** When Castellum sees intent that could map to multiple tools/workflows (e.g. "remind me" → Reminders, Calendar, Toggl, Day One), it should surface the alternatives or ask the user rather than picking one silently. — source: [castellum-action-vs-workflow.md](castellum-action-vs-workflow.md)
- [2026-05-22] **Tool definitions must be declarative JSON, not per-file Swift.** Tool integrations belong in `Hex/Resources/Data/tool-definitions/*.json`. Do not add per-tool Swift files for standard HTTP integrations. — source: [REQ-global.md](REQ-global.md)
- [2026-05-22] **Castellum tool schema generation must only emit schemas for enabled actions.** `ToolDefinitionLoader.claudeSchemas` should respect `tool.enabledActionKeys` so Castellum never attempts a disabled action. — source: [tool-permissions.md](tool-permissions.md)

## Rules & Decisions

- [2026-05-22] **Tool_use name format: `<toolID>_<actionType>`.** Parser splits on first `_` only. Example: `jira_create_issue` → toolID `"jira"`, actionType `"create_issue"`. This is the canonical format — never change it without updating both the fixture JSON and the parser. — source: [fixture-strategy.md](fixture-strategy.md)
- [2026-05-22] **Tool seeding must use upsert-by-ID.** Any tool in `Tool.allDefaults` not in the database must be inserted on each launch. Never use "insert only if table is empty." — source: [REQ-global.md](REQ-global.md)
- [2026-06-25] **HeuristicRouter workaround covers single-intent Toggl.** Triggers: `"start timer"`, `"log time for"`, `"track time for"`, etc. Duration defaults to 30 min if not mentioned. This bypasses the Castellum Toggl bug for the common case. — source: [heuristic-router.md](heuristic-router.md)

## Open Requirements

- [ ] **Fix Castellum → Toggl tool_use bug.** Castellum returns prose ("I don't have a Toggl tool") instead of a `tool_use` block for time-logging requests that reach it (multi-intent captures). Two suspects: (1) Toggl tool schema not passed correctly to `analyzeAndPlan`, (2) Haiku declining to call Toggl. Multi-intent Toggl captures silently fail until fixed. The `toggl-jira-multi-intent` fixture is synthetic for this reason. — observed: 2026-06-25
- [ ] **Implement action-level permissions (tier 2).** After OAuth scope selection, show a second tier of toggleable action checkboxes per service. Persist as `enabledActionKeys: [String]?` on `Tool` model. `GenericToolExecutor.execute()` checks before running. — source: [tool-permissions.md](tool-permissions.md)
