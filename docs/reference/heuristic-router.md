---
name: project_heuristic_router_design
description: HeuristicRouter design decisions — when it fires, when it falls through to Castellum, and how ambiguity is handled
metadata:
  type: project
---

## HeuristicRouter Design

`HeuristicRouter` runs before any Castellum (Claude) call. It returns a `[PlannedAction]?` — nil means "fall through to Castellum."

**Rule: only bypass Castellum when exactly one clear action is matched.**
If zero or more than one action matches, return nil and let Castellum interpret. This is already enforced in code (`guard actions.count == 1 else { return nil }`).

**Why:** Competing or ambiguous heuristic matches (e.g. a capture that could be both a Toggl entry AND a Jira ticket) need Castellum for interpretation — the heuristic can't safely pick one intent over another.

**Current triggers (Toggl):** `"start timer"`, `"start a timer"`, `"log time for"`, `"track time for"`, `"track time on"`. Duration is parsed from natural language (hours/minutes); defaults to 30 min if not mentioned.

**How to apply:** When adding new heuristic patterns, keep them narrow and unambiguous. If there's any overlap with another tool's trigger patterns, the right answer is Castellum, not a heuristic coin-flip.
