# Plan: Expandable Tool Rows in Settings

## Context

Settings → Tools currently shows flat rows — just the tool name + "Connected via OAuth" + a Disconnect button crammed into the subtitle. Users can't see what Basin can actually *do* with a connected tool, and the auto-execute toggle is buried in the row with no context. The existing plan (`docs/plans/tool-row-expansion.md`) describes the full vision; this implements the core of it.

## Scope (this task)

- Expand/collapse rows via `DisclosureGroup`
- Collapsed header: icon + name + green checkmark (connected) or "Connect" button — nothing else
- Expanded body: four sections — Connection, Permissions (scope-level), Actions (action-level), Controls
- Scope toggles surfaced inline (already stored in `tool.selectedScopeKeys`); changing triggers a "Reconnect to apply" nudge
- Action-level toggles backed by a new `enabledActionKeys` field on `Tool`; grouped under their scope/service
- `ToolDefinitionLoader.claudeSchemas` filters to only enabled actions
- `GenericToolExecutor` refuses disabled actions at runtime

**Skipped for later:** `connectedAccountLabel` (requires post-connect fetch), `scope_group` JSON field on actions (grouping done heuristically via `selectedScopeKeys` mapping), Test connection button.

---

## Implementation

### 1. Model — `Hex/Models/BasinModels.swift`

Add one field to `Tool`:

```swift
/// Action keys the user has explicitly disabled. Nil means all actions enabled.
var enabledActionKeys: [String]?
```

No migration needed — SwiftData adds optional properties automatically.

### 2. View — `Hex/Features/Settings/ToolsSectionView.swift`

Replace the current `toolRow` with a `DisclosureGroup`-based layout.

**Collapsed header:**
```
[icon]  Tool Name                    ✅  (or "Connect" button)
```

**Expanded body — four sections:**

**Connection**
- Auth method chip: `"OAuth"` or `"API Key"` in a `.caption` badge
- Token health line: derive from `tool.oauthExpiresAt`:
  - Nil → nothing shown
  - > 30 days → `"Token valid"` in `.tertiary`
  - 8–30 days → `"Expires in X days"` in `.orange`
  - < 8 days → `"Expiring soon — reconnect"` in `.red`

**Permissions — scope level** (only shown when tool has `scopes_selectable: true` and is connected)
- Show scope toggles for each available scope (same spec as the connect sheet: `toolSpec.auth.availableScopes`)
- Bound to `tool.selectedScopeKeys`
- When any toggle changes from the persisted value, show an inline nudge: `"Reconnect to apply scope changes"` with a "Reconnect" button that opens `ToolConnectSheet`
- State: `@State private var pendingScopeChange: Bool` per row

**Actions — action level** (only shown when connected and tool spec has actions)
- Load `ToolDefinitionSpec` via `ToolDefinitionLoader.load(tool.id)`
- Group actions under their scope where possible: for tools with `available_scopes`, bucket each action under the scope key it belongs to (e.g. `create_event` → Calendar, `send_email` → Gmail, `create_document`/`append_text`/`read_document` → Docs). Use a static mapping in the view keyed off known scope keys; fall back to a flat list for tools without scopes.
- Each action shows `action.displayName` + a `Toggle` (on by default)
- Initial state: `tool.enabledActionKeys == nil` → all on; otherwise disabled keys are the stored set
- `onChange`: write `[String]` of *disabled* keys to `tool.enabledActionKeys` (nil if all enabled)

**Controls**
- Auto-execute toggle (moved from collapsed row) — labeled `"Auto-execute"` with `.help` explaining it
- Disconnect button (moved from collapsed row subtitle), styled `.destructive`

Add `@State private var expandedToolIDs: Set<String> = []` to `ToolsSectionView` (or use `DisclosureGroup`'s built-in binding — the latter is simpler).

### 3. Schema filtering — `Hex/Clients/ToolActions/ToolDefinitionLoader.swift`

`claudeSchemas(for:tool:)` — add a `tool: Tool?` parameter (default `nil` for call sites that don't have one):

```swift
static func claudeSchemas(for spec: ToolDefinitionSpec, tool: Tool? = nil) -> [[String: Any]] {
    let disabledKeys = Set(tool?.enabledActionKeys ?? [])
    return spec.actions
        .filter { disabledKeys.isEmpty || !disabledKeys.contains($0.key) }
        .map { actionType, action in … }
}
```

Update call sites in `CastellumPlannerClient+Live.swift` to pass the matched `Tool` instance.

### 4. Runtime gating — `Hex/Clients/ToolActions/GenericToolExecutor.swift`

At the top of the execute function, after resolving the action spec:

```swift
if let disabled = tool.enabledActionKeys, disabled.contains(actionType) {
    throw ToolExecutionError.actionDisabled(actionType)
}
```

Add `actionDisabled(String)` case to `ToolExecutionError` (or whatever error type is used).

---

## Files to touch

| File | Change |
|------|--------|
| `Hex/Models/BasinModels.swift` | Add `enabledActionKeys: [String]?` to `Tool` |
| `Hex/Features/Settings/ToolsSectionView.swift` | Rewrite `toolRow` with `DisclosureGroup`, 4-section expanded body |
| `Hex/Clients/ToolActions/ToolDefinitionLoader.swift` | Add `tool:` param to `claudeSchemas`, filter disabled actions |
| `Hex/Clients/ToolActions/GenericToolExecutor.swift` | Refuse disabled actions at runtime |
| `Hex/Clients/CastellumPlannerClient+Live.swift` | Pass `Tool` to `claudeSchemas` |

---

## Verification

1. Build and run the app
2. Open Settings → Tools
3. Confirm connected tool rows are clean (no disconnect/auto-execute clutter in collapsed state)
4. Click a connected tool — it should expand showing Connection info, action toggles, and Controls
5. Disable one action (e.g. `send_email` on Google), then trigger a voice capture that would use that action — Castellum should not plan it (schema filtered) and `GenericToolExecutor` should refuse it if called directly
6. Re-enable — action returns to available
7. Unconnected tools: expand/collapse still works; no Actions section shown
