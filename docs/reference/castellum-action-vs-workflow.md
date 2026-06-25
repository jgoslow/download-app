---
name: project_castellum_action_vs_workflow
description: "Distinction between direct tool actions and workflows in Castellum, and how ambiguity should be resolved"
metadata: 
  node_type: memory
  type: project
  originSessionId: 89a4fa2f-e560-48fa-a2cd-38cb4dd899f4
---

Castellum must distinguish between two routing modes when planning from a capture:

**Direct tool action** — a single, unambiguous API call against one connected tool. E.g., "add a note" → Apple Notes API call. Use when the capture maps cleanly to one tool and there's no meaningful alternative.

**Workflow** — a multi-step or multi-tool sequence that emerges from the capture content. E.g., "remind me about XYZ" could mean: Reminders app, Google Calendar event, Toggl timer, or a Day One journal entry — depending on context and connected tools.

**Why:** The right action is highly situation-specific. The same intent ("write me a note", "remind me") can route differently depending on connected tools, flow context, and user phrasing.

**How to apply:** When Castellum sees ambiguous intent that could map to multiple tools/workflows, it should ask for clarification rather than pick silently. Only call a direct tool action when the capture clearly implies one specific tool. If multiple plausible options exist across connected tools, surface them or prompt the user. This also informs future UI work: the execution plan view could show alternatives when Castellum is uncertain.
