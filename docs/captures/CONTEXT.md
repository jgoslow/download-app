---
type: meta
status: reference
created: 2026-06-25
updated: 2026-06-25
tags: [context]
---

# Context: docs/captures/

Raw intake — dated captures, session summaries, meeting notes, brainstorm logs. Append-only; nothing here is distilled. Distillation outputs belong in `docs/reference/`.

## What belongs here

- Session summary files (`YYYY-MM-DD-session-*.md`)
- Slack/Jira/GitHub/calendar captures
- Meeting notes
- Brainstorm / idea logs (raw)
- Bug observations that haven't been actioned

## What does NOT belong here

- Distilled architecture or requirements docs → `docs/reference/`
- Active plans → `docs/reference/planning/`
- Completed/archived plans → `docs/captures/plans/` (this folder's sub-directory)

## Subfolders

- `plans/` — Completed/executed plans, moved here after the work is done. Always linked from the session log that executed them.

## Frontmatter convention

All captures should include `distilled: false` until `/vault distill` has processed them. Set `distilled: true` after distillation.
