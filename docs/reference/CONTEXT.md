---
type: meta
status: reference
created: 2026-06-25
updated: 2026-06-25
tags: [context]
---

# Context: docs/reference/

Stable, distilled project knowledge — architecture, requirements, ops docs. This is what agents should read before making changes in a given area. Nothing here is raw or dated; raw intake goes in `docs/captures/`.

## Routing table

| Task | Read first |
|------|-----------|
| Any structural change | `REQ-global.md` |
| Castellum routing / planning | `castellum-action-vs-workflow.md`, `heuristic-router.md` |
| Tool integrations (JSON definitions) | `REQ-global.md` § Tool System |
| Audio capture / transcription pipeline | `fixture-strategy.md`, `integration-testing-plan.md` |
| Hotkey behavior | `hotkey-semantics.md` |
| Auth / OAuth | `oauth-setup.md` |
| Release process | `release-process.md`, `release-pipeline-plan.md` |
| Roadmap / vision | `roadmap.md`, `vision.md` |
| Active plans (in-progress features) | `planning/CONTEXT.md` |

## What belongs here

- REQ-*.md distilled invariants and decisions
- Architecture reference docs
- How-to and ops guides (release process, OAuth setup)
- Distilled design decisions from planning sessions
- `planning/` subfolder — active/in-progress plans

## What does NOT belong here

- Dated session files (`YYYY-MM-DD-*.md`) → `docs/captures/`
- Completed plans → `docs/captures/plans/`
- Raw brainstorm logs → `docs/captures/`
