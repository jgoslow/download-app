---
name: project_tool_permissions_plan
description: "Planned action-level permission model for Basin tools — two-tier: OAuth scopes (service-level) then action keys (operation-level)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 3f3bf9d1-edae-44c8-847e-cacd6174dc98
---

## Tool Connection & Permission Model — Planned Architecture

### Current state (as of 2026-05-22)
- Tools connect via OAuth or API key
- Google has scope-level toggles (Calendar, Docs, Gmail, Drive) shown before signing in
- Selected scopes stored as `Tool.selectedScopeKeys: [String]?`
- `GenericToolExecutor` runs any action the tool definition defines, no action-level gating

### Planned: Action-level permissions (tier 2)
- After picking which Google services (Calendar / Docs / Gmail) to enable at OAuth scope level, show a second tier of toggleable actions within each service
- e.g. Google Docs: ✅ Create document, ✅ Append text, ❌ Delete document
- Enforced in `GenericToolExecutor` — refuses to run any action not in `enabledActionKeys`
- Tool model needs `enabledActionKeys: [String]?` (nil = all actions allowed by default)
- JSON action definitions already have discrete named keys (`create_document`, `append_text`, etc.) — data model is ready

### Why
- Google's OAuth scopes aren't granular enough (documents = read+write, no separate create vs. delete)
- Basin enforces permitted operations at the app layer, independent of what OAuth technically allows
- Users should be able to trust that Basin won't perform actions they didn't explicitly permit

### How to apply
- Design the connect sheet UI to show action checkboxes grouped by service/scope after scope selection
- Persist `enabledActionKeys` on `Tool` model
- `GenericToolExecutor.execute()` checks `tool.enabledActionKeys` before proceeding
- Castellum tool schema generation (`ToolDefinitionLoader.claudeSchemas`) should only emit schemas for enabled actions — so Claude doesn't even attempt disabled ones
