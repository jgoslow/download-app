# Vault Init — Basin

## Context

Setting up the vault scaffold for the Basin app repo. The goal is to give Claude Code agents a structured context layer alongside the codebase — active plans, distilled reference docs, and a captures log — following the vault ICM model. The existing `docs/plans/` folder and `docs/requirements.md` are being promoted into a proper layout. `.claude/memory/` project-knowledge files are being migrated into the vault structure.

---

## Confirmed Layout

| Vault Role | Path | Status |
|-----------|------|--------|
| `logs` | `docs/captures/` | create |
| `plans` | `docs/plans/` | exists |
| `plans-archive` | `docs/captures/plans/` | create |
| `requirements` / `resources` | `docs/reference/` | create |
| `summary` | `docs/reference/planning.md` | create |
| `templates` | `.claude/templates/` | create |

Viewer: none (plain Markdown / Cursor).
Sensitive content: no.

---

## Step 1 — Create Folder Structure

```
docs/captures/
docs/captures/plans/
docs/reference/
.claude/templates/
```

---

## Step 2 — Move `docs/` Root Files → `docs/reference/`

| From | To |
|------|----|
| `docs/hotkey-semantics.md` | `docs/reference/hotkey-semantics.md` |
| `docs/jonas-prompt-notes.md` | `docs/reference/jonas-prompt-notes.md` |
| `docs/oauth-setup.md` | `docs/reference/oauth-setup.md` |
| `docs/parakeet-short-audio-plan.md` | `docs/reference/parakeet-short-audio-plan.md` |
| `docs/release-pipeline-plan.md` | `docs/reference/release-pipeline-plan.md` |
| `docs/release-process.md` | `docs/reference/release-process.md` |
| `docs/requirements.md` | `docs/reference/REQ-global.md` (add frontmatter) |
| `docs/water-drop-animation.html` | skip (HTML, not markdown) |

---

## Step 3 — Migrate `.claude/memory/` → Vault

**Move to `docs/reference/`** (project knowledge, now lives in vault):

| Memory file | Vault destination |
|------------|------------------|
| `project_vision.md` | `docs/reference/vision.md` |
| `project_architecture.md` | `docs/reference/architecture.md` |
| `project_marketplace_vision.md` | `docs/reference/marketplace-vision.md` |
| `project_roadmap.md` | `docs/reference/roadmap.md` |
| `project_tool_permissions_plan.md` | `docs/reference/tool-permissions.md` |
| `project_castellum_action_vs_workflow.md` | `docs/reference/castellum-action-vs-workflow.md` |
| `project_heuristic_router_design.md` | `docs/reference/heuristic-router.md` |
| `project_fixture_strategy.md` | `docs/reference/fixture-strategy.md` |
| `project_integration_testing_plan.md` | `docs/reference/integration-testing-plan.md` |
| `reference_domain.md` | `docs/reference/domain.md` |

**Move to `docs/captures/`** (brainstorm / raw):

| Memory file | Vault destination |
|------------|------------------|
| `animation-ideas.md` | `docs/captures/animation-ideas.md` |
| `project_castellum_toggl_bug.md` | `docs/captures/castellum-toggl-bug.md` |

**Keep in `.claude/memory/`** (Claude-behavioral, not project docs):

- `feedback_tool_definitions.md` — coding rule for Claude, not a project doc
- `user_context.md` — user profile for Claude
- `project_naming_basin.md` — naming guidance for Claude sessions

Update `MEMORY.md` to reflect that project knowledge now lives in `docs/reference/`; keep only the three Claude-behavioral entries above plus a pointer to the vault.

---

## Step 4 — Add Frontmatter

All migrated files need frontmatter added (or updated):

```yaml
---
type: resource         # or: requirement, log, planning, etc.
status: reference
created: YYYY-MM-DD    # use file mtime or original date if known
updated: 2026-06-25
tags: []
---
```

`docs/reference/REQ-global.md` gets:
```yaml
type: requirement
subtype: global
req_id: REQ-global
status: active
```

---

## Step 5 — Scaffold CONTEXT.md Files

**`docs/plans/CONTEXT.md`** — pre-populate with plan lifecycle rule:
- Active / in-progress plans live here
- Completed plans move to `docs/captures/plans/`
- Session logs in `docs/captures/` link back to plan files

**`docs/captures/CONTEXT.md`** — raw intake:
- Dated captures, meeting notes, session summaries
- Nothing distilled; distillation outputs go to `docs/reference/`
- `docs/captures/plans/` = archived (completed) plans

**`docs/reference/CONTEXT.md`** — distilled knowledge:
- Stable reference: architecture, requirements, roadmap, ops docs
- Read `REQ-global.md` before any structural change
- Dated files (YYYY-MM-DD-*.md) don't belong here → use `docs/captures/`

---

## Step 6 — Add Vault Templates

Create `.claude/templates/` with these files (no frontmatter interaction with Xcode):
- `capture.md`
- `session-summary.md`
- `adr.md`
- `meeting-note.md`
- `requirement.md`
- `prd.md`

---

## Step 7 — Update CLAUDE.md

Add three sections to the existing CLAUDE.md:

### `## Vault Layout` (agents resolve paths from this table)

```markdown
| Role | Path | What goes here |
|------|------|---------------|
| logs | `docs/captures/` | Captures, meeting notes, session summaries |
| plans | `docs/plans/` | Active / in-progress plans |
| plans-archive | `docs/captures/plans/` | Completed plans — linked from session log |
| requirements | `docs/reference/` | REQ-*.md and distilled project knowledge |
| summary | `docs/reference/planning.md` | Distilled planning overview |
| resources | `docs/reference/` | Architecture, ops, integration docs |
| templates | `.claude/templates/` | Document templates |
```

### `## Requirements`

> Read `docs/reference/REQ-global.md` before any structural change. Read relevant files in `docs/reference/` before changes in a given area (e.g. `heuristic-router.md` before touching HeuristicRouter).

### `## Related Vaults`

```markdown
| Slug | Relationship | Description |
|------|-------------|-------------|
| basin-planning | source | Product vision, architecture, flow definitions, pathway specs. Distills into this repo. |
```

Also update the Memory section: note that project knowledge moved to `docs/reference/`; `.claude/memory/` retains only Claude-behavioral files.

---

## Step 8 — Register in `~/.claude/vault-map.json`

Add two entries:

```json
"basin": {
  "path": "/Users/jonasgoslow/localhost/basin",
  "type": "code-repo",
  "viewer": "none",
  "description": "Basin macOS/iOS app — voice capture, Castellum routing, tool integrations",
  "layout": {
    "logs": "docs/captures",
    "plans": "docs/plans",
    "plans-archive": "docs/captures/plans",
    "requirements": "docs/reference",
    "summary": "docs/reference/planning.md",
    "resources": "docs/reference",
    "templates": ".claude/templates"
  },
  "relationships": {
    "basin-planning": "source"
  }
},
"basin-planning": {
  "path": "/Users/jonasgoslow/localhost/basin-planning",
  "type": "product-context",
  "viewer": "none",
  "description": "Basin product planning — architecture, flow definitions, pathway specs, server prototype",
  "relationships": {
    "basin": "distills-into"
  }
}
```

---

## Open Decision: Does Castellum Need a Server?

`basin-planning/server/` already has a Node.js prototype. The question is when it becomes necessary:

**Server is needed for:**
- Scheduled / triggered flows running when app is closed ("run Day's End at 6pm")
- Multi-step pathway execution that runs async across tool calls
- OAuth refresh token management (server-side is more secure)
- Multi-device session continuity

**Server is NOT needed for:**
- Basic capture → Castellum → tool action (on-device works fine)
- Single-step tool actions via direct API calls from the app
- MVP

**Recommendation:** Treat `basin-planning` as a `source` repo that eventually distills into both `basin` (app) and a future `basin-server` repo. Keep the server prototype in `basin-planning` until you're ready to split it off. No need to restructure now — just register the relationship and add the open decision to CLAUDE.md.

---

## Verification

After execution:
1. `ls docs/captures/ docs/reference/ docs/plans/ .claude/templates/` — all four exist
2. `ls docs/` — only `plans/`, `captures/`, `reference/` remain (no loose .md files except any intentionally left)
3. `head docs/reference/REQ-global.md` — shows frontmatter
4. `head docs/plans/CONTEXT.md` — shows plan lifecycle rule
5. `cat ~/.claude/vault-map.json | grep basin` — both entries present
6. CLAUDE.md has `## Vault Layout` and `## Related Vaults` sections
7. `.claude/memory/MEMORY.md` reflects reduced set (3 Claude-behavioral files + vault pointer)
