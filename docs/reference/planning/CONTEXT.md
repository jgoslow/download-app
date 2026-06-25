---
type: meta
status: reference
created: 2026-06-25
updated: 2026-06-25
tags: [context]
---

# Context: docs/reference/planning/

Active and in-progress plans — ADRs, feature plans, and initiatives that have not yet been fully executed. Agents load files here when planning work in a given area.

## What belongs here

- Feature plans being actively referenced during implementation
- Architecture decision records (ADRs) for undecided or recently decided questions
- Strategic plans with work still outstanding
- The current session's plan file (moves to archive after execution)

## What does NOT belong here

- Session capture files (`YYYY-MM-DD-session-*.md`) → `docs/captures/`
- Completed/archived plans → `docs/captures/plans/`
- Distilled reference knowledge (architecture docs, REQ-*.md) → `docs/reference/` root

## Plan lifecycle

1. Plan is created here and actively referenced during work.
2. When `/vault close` runs, the session log in `docs/captures/` links back to the plan file here.
3. When the plan is fully executed, it moves to `docs/captures/plans/` (archive) and the session log link is updated.

**Active / in-progress → `docs/reference/planning/`**
**Executed / completed → `docs/captures/plans/`, linked from session log**

## Active plans (read before touching these areas)

| Plan | Area |
|------|------|
| `2026-05-27-architecture-system-model.md` | Core system model — Flows/Castellum/Workflows/Tools |
| `2026-05-27-workflow-behavior.md` | Workflow emergence and instruction model |
| `2026-05-30-integration-master-plan.md` | Tool marketplace, extended integrations, server/infra |
| `2026-05-31-setup-flow-onboarding.md` | Setup flow + flow session screen |
| `2026-06-04-phone-call-mode.md` | Phone Call Mode feature |
| `2026-05-29-end-thread-skill.md` | `/end-thread` skill for capturing requirements |
