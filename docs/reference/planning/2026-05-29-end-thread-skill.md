# Plan: `/end-thread` Skill — Capture Requirements from Conversation

## Context

Development conversations frequently surface non-obvious constraints, architectural decisions, and "never do X" rules that need to live in `docs/requirements.md` to prevent future AI agents from unknowingly undoing them. Right now there's no mechanism to capture these — they either get lost or require the user to manually update the doc after every session.

This plan adds a `/end-thread` skill that, at the close of a session, scans the conversation for requirement-worthy content and adds it to `docs/requirements.md` with conflict detection.

---

## Implementation

**File to create:** `~/.claude/skills/end-thread/SKILL.md`

Global skill (not project-level) — useful across any project that maintains a requirements doc. Location of the requirements file is discovered per project, not hardcoded.

---

## Skill Workflow

When invoked, the skill instructs Claude to run this sequence:

### Step 0 — Locate the requirements file

Requirements may live in different places per project. Check in this order:

1. **CLAUDE.md declaration** — scan project `CLAUDE.md` (and global `~/.claude/CLAUDE.md`) for a line like `requirements: path/to/file.md` or any explicit mention of a requirements doc location.
2. **Common paths** — check for existence of:
   - `docs/requirements.md`
   - `REQUIREMENTS.md`
   - `requirements.md`
   - `.claude/requirements.md`
3. **Multiple found** — if more than one candidate exists, list them and ask the user which to use.
4. **None found** — ask: "No requirements file found. Where should I save captured requirements?" Accept a path or offer to create `docs/requirements.md`.

After resolving the location, offer to remember it for this project by suggesting the user add a line to their project `CLAUDE.md`:
```
requirements: path/to/requirements.md
```
This way future `/end-thread` invocations skip the discovery step. The skill does **not** write to CLAUDE.md itself — it surfaces the suggestion.

### Step 1 — Extract candidates from the conversation

Scan the conversation for anything that qualifies as a requirement:
- Explicit decisions: "must always", "never", "do not", "must not", "should always"
- Non-obvious constraints explained in the thread (the **WHY** is what matters — if the reason is in the code, skip it)
- Architecture decisions with rationale
- Features deliberately removed and why
- Bug fixes that revealed a hidden invariant
- "Don't re-introduce this" warnings
- Behavior that would surprise a future reader of the code

Skip obvious or derivable things: naming conventions visible in code, trivial implementation details, in-session debugging steps.

### Step 2 — Read existing `docs/requirements.md`

Read the full file so the skill can identify:
- Which section each candidate belongs in
- Whether the candidate already appears (skip)
- Whether the candidate conflicts with an existing entry (flag)

### Step 3 — Categorize

For each candidate:
- **Already covered** → skip silently, note in summary
- **Conflict** → hold for explicit approval (Step 4)
- **New** → queue for addition (Step 5)

A conflict is when the candidate makes a claim that directly contradicts an existing requirement (e.g., existing says "always use X", conversation says "don't use X anymore").

### Step 4 — Resolve conflicts first

For each conflict, show a side-by-side before proceeding:

```
CONFLICT: [section name]

Existing:
> [current text from requirements.md]

This thread says:
> [candidate text]

Keep existing / Use new / Merge?
```

Wait for approval on each before continuing.

### Step 5 — Present new requirements for confirmation

Show all new (non-conflicting) candidates as a preview of the exact text that will be added, grouped by target section. One confirmation ("looks good" / specific edits) before writing.

Format must match the existing style in `docs/requirements.md`:
- Lead with **bold subject phrase**, then explanation
- Lead with the WHY, not just the what — the constraint is usually obvious; the reason is not
- Reference specific file paths and function names when relevant
- Use `[REMOVED]` with rationale for deliberately removed features
- Do not invent section headers; place candidates under the closest existing section, or propose a new one if no section fits

### Step 6 — Write

Apply all approved additions/edits to `docs/requirements.md`. Update (don't delete) conflicting entries — mark superseded text with `[SUPERSEDED: see below]` and add the new entry immediately after so history is preserved in the file.

Report what was added, what was skipped (already covered), and what conflicts were resolved.

---

## Skill File Structure

```
~/.claude/skills/end-thread/
  SKILL.md     ← the only file needed
```

The `SKILL.md` frontmatter:

```yaml
---
name: end-thread
description: Capture requirements from the current conversation into docs/requirements.md.
  Use when the user invokes /end-thread, asks to "close out this thread", "capture
  requirements from this session", or "sync requirements".
---
```

---

## Critical Constraints in the Skill

- **Never overwrite or delete existing requirements** — only append or mark superseded
- **Never add trivially derivable facts** (naming, code patterns visible from reading the source)
- **Always get approval on conflicts** — never silently pick one side
- **Match the WHY-first style** of the existing doc — a requirement without a reason is just noise
- The skill confirms the full list before writing, not line by line (to avoid exhausting the user)

---

## Verification

1. Run `/end-thread` at the end of this planning session
2. Confirm Claude scans the conversation and surfaces the candidates from this thread (e.g., the `/end-thread` skill itself should _not_ be added as a requirement; any Basin-specific context from the conversation should be)
3. Confirm no existing requirements in `docs/requirements.md` are modified without going through the conflict flow
4. Check the file diff after writing — requirements should be formatted consistently with the existing entries
