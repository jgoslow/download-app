# Plan: Expandable Tool Rows in Settings

## What
Replace flat tool rows in Settings → Tools with expandable disclosure rows. Each tool expands to show its full integration detail and controls.

## Motivation
The row currently surfaces almost nothing about a connected integration — just "Connected via OAuth". Users need to understand what Basin can do with a tool and explicitly permit those actions.

## Expanded Row Contents

### Connection
- **Connected as** — show the account identifier where possible (e.g., "Connected as jonas@gmail.com"). Requires a lightweight `/userinfo` or `/me` fetch post-connect and storing it on `Tool.connectedAccountLabel`.
- **Auth method badge** — OAuth / API Key chip
- **Token health** — "Expires in 45 days" / "Expiring soon" / "Refresh needed" derived from `oauthExpiresAt`

### Permissions (scope-level)
- Scope toggles already built for Google (Calendar, Docs, Gmail, Drive)
- Changing a scope toggle requires reconnecting — show a "Reconnect to apply" nudge when selection changes

### Actions (action-level) — *core of this plan*
- List every action from the tool's JSON definition with a toggle (enabled by default)
- Grouped by scope/service where applicable (e.g., under Google: Calendar → create_event; Docs → create_document, append_text, read_document; Gmail → send_email)
- Toggled-off actions: stored in `Tool.enabledActionKeys: [String]?` (nil = all on)
- `GenericToolExecutor` refuses disabled actions
- `ToolDefinitionLoader.claudeSchemas` only emits schemas for enabled actions (so Claude never attempts them)

### Controls
- **Auto-execute toggle** (move here from the row header, keep label visible)
- **Disconnect button** (move here from the subtitle line)
- **Test connection** — fire a cheap read endpoint to confirm the token is still valid (e.g., Calendar calendarList for Google); show ✅ / ❌

## What stays in the collapsed row header
- Tool icon + name
- Green ✅ or "Connect" button
- Nothing else — clean

---

# Plan: Channel ↔ Tool Scope Binding

## Problem
A channel like "Create a calendar event" requires the Google tool — but Google may be connected with only Docs/Gmail scopes enabled, not Calendar. The channel shouldn't be available in that case. Similarly, "Write an email" should only be available when the Gmail scope is enabled on Google.

Currently channels only know *which tool* they need, not *which scope within that tool*.

## Proposed model
Add `requiredScopeKey: String?` to `ChannelDefinition` — the scope key (matching `available_scopes` in the tool definition) that must be enabled on the tool.

```swift
// BasinModels.swift
var requiredScopeKey: String?   // e.g. "calendar", "gmail", "docs"
```

```swift
// allDefaults entries
ChannelDefinition(id: "create-event", ..., requiredToolIDs: ["google"], requiredScopeKey: "calendar")
ChannelDefinition(id: "write-email", ..., requiredToolIDs: ["google"], requiredScopeKey: "gmail")
```

Channel availability check in `ChannelsSectionView`:
```swift
let canEnable = missingTools.isEmpty && requiredScopeIsSatisfied(channel)

func requiredScopeIsSatisfied(_ channel: ChannelDefinition) -> Bool {
    guard let scopeKey = channel.requiredScopeKey,
          let toolID = channel.requiredToolIDs.first,
          let tool = tools.first(where: { $0.id == toolID }) else { return true }
    return tool.selectedScopeKeys?.contains(scopeKey) ?? true  // nil = all scopes on
}
```

## Implemented (2026-05-22)
- `ToolDefinitionSpec.channels: [String: String]?` — tool declares which channels it handles and via which action
- `ChannelDefinition.toolBinding: String?` — persisted binding to the executing tool; nil = auto-resolve
- `ChannelsSectionView` derives availability from `ToolDefinitionLoader.loadAll()` — `requiredToolIDs` is no longer the source of truth for display
- Auto-binds when exactly one connected capable tool exists; persists binding on first enable

## Longer-term: multi-tool channels
Some channels may need multiple tools (e.g., a channel that logs time in Toggl *and* creates a Jira card). Eventually a channel could also let the user pick *which* connected tool of the right type to use — e.g., two Google accounts, pick which one to use for calendar. When multiple capable tools are connected, the UI should offer a picker rather than auto-binding.

## Files to touch
- `Hex/Models/BasinModels.swift` — add `requiredScopeKey` to `ChannelDefinition`
- `Hex/App/HexAppDelegate.swift` — seed `requiredScopeKey` on channel defaults
- `Hex/Features/Settings/ChannelsSectionView.swift` — update availability check

---

## Open questions (both plans)
- Does reconnecting always reset all scope/action settings, or preserve them and just re-auth?
- Should disabled actions be hidden from the list or shown as greyed out?
- Account label fetch: do this eagerly post-connect or lazily on row expand?
- For multi-tool channels: should the user bind channels to specific tool instances, or should Basin pick automatically?

## Files to touch (tool row expansion)
- `Hex/Features/Settings/ToolsSectionView.swift` — expand/collapse state, new expanded layout
- `Hex/Models/BasinModels.swift` — add `enabledActionKeys: [String]?`, `connectedAccountLabel: String?`
- `Hex/Clients/ToolActions/GenericToolExecutor.swift` — action gating
- `Hex/Clients/ToolActions/ToolDefinitionLoader.swift` — filter `claudeSchemas` to enabled actions
- `Hex/Resources/Data/tool-definitions/*.json` — group actions by scope (new optional `scope_group` field on actions)
