# Plan: Add Plan File Naming Convention to Global CLAUDE.md

## Context

Plan files currently get auto-generated names derived from the first few words of the user's message plus a random adjective-noun suffix (e.g., `basn-is-going-to-quizzical-snail.md`). This makes plan directories hard to browse — files don't communicate what they're about or when they were created. The user wants plan files to follow a `yyyy-mm-dd-descriptive-name.md` pattern so directories are scannable and self-documenting. This should be a global rule (applies across all projects), so it goes in `~/.claude/CLAUDE.md`.

## Change

**File:** `/Users/jonasgoslow/.claude/CLAUDE.md`

Append a new `## Plan Files` section at the end of the file:

```markdown
## Plan Files

When creating plan files, first look for an existing plan directory in the project (e.g., `docs/plans/`, `plans/`, `.claude/plans/`). Use it if found. If no designated plan folder exists, create one at `docs/plans/` in the project root. Name plan files `yyyy-mm-dd-short-description.md` where the date is today's date and the description is a 2–5 word kebab-case slug describing the plan's subject (e.g., `2026-05-30-hotkey-refactor.md`). Never use random word suffixes.
```

## Verification

After editing, confirm:
1. The new section appears at the end of `~/.claude/CLAUDE.md` with correct formatting.
2. No other sections were accidentally modified.
