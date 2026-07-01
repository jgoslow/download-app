# "Connect Another App" — Post-Connection CTA with Action Filter

**Status:** Planning only — no implementation yet  
**Context:** Discussed 2026-07-01 after noticing execution plan shows only one "Connect" CTA per action

## Problem

When an action in the execution plan requires a tool that isn't connected, Basn shows one or more "Connect [tool]" buttons. Once the user connects one tool for that action type, there's no way to discover that *other* tools could also handle the same action. And if the user's first connection doesn't work as expected, there's no path back to "try a different app."

## Requirement

After the user connects a tool from the execution plan's "Connect a tool" prompt, and the action is now executable, show a secondary CTA:

> "Connect another app for [action type] →"

This links to the Tools page. In the future, when the Tools page supports action-type filters, the link should deep-link with the filter pre-applied so the user sees only tools relevant to that action type (e.g., calendar tools if the action is `schedule_event`).

## Implementation Notes

**Phase 1 (now):** The CTA links to the Tools tab / Tools settings page without a filter. The user can browse and connect another tool manually.

**Phase 2 (when action filter UI exists):** The link should append an action type query to the navigation path, e.g. `toolsPath.append(.filtered(by: "schedule_event"))`. The Tools page would then show only tools offering that capability.

## Where to Add It

- `IOSExecutionPlanView.ActionRow` — after the existing "Connect a tool to run this action:" block, add a conditional row: shown only when `connected == true` (i.e., at least one tool is now connected for this action) and `providers.count > 1`.
- Alternatively, show it always after a connect action succeeds (post-sheet dismiss), but only if alternative providers exist.

## Action-Type to Tool Filter Mapping

Use `CapabilityResolver.providers(for: actionType)` — already exists — to know which tools could theoretically serve a given action. The "connect another app" CTA should be gated behind `providers.count > 1`.

## UX Copy

- "Looking for a different app? Connect another →" (links to Tools)
- Or shorter: "Connect another app for this →"

Keep it subtle (small, secondary style) — it should not compete with the primary "Execute" button.
