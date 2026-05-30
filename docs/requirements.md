# Basin — Product & Technical Requirements

A living document. Every entry here exists because there is a reason that isn't obvious from reading the code. Add the WHY, not just the what. Update rather than delete — removed requirements should be marked `[REMOVED]` with the reason.

---

## System Architecture

### Three-Layer Model
Flows → Castellum → Workflows → Tools. This hierarchy is intentional and must not collapse.

- **Flows** are the only user-configured trigger concept. Users create, name, schedule, and customize them.
- **Workflows** (previously Channels) are *emergent outcomes* — aqueducts to specific destinations, through specific tools, creating specific results. They are NOT predefined by the user, not toggled on/off in a list, and not a 1:1 mapping to a single tool action. They arise from what the capture says and what tools are connected. The `Workflow` SwiftData model stores the plain-English LLM instruction that makes each workflow unique.
- **Tools** are the only other user-configured layer. Users connect services and choose which scopes to grant.
- **Castellum** decides what workflows are possible for a given capture. It must not be bypassed in ways that skip user-facing confirmation.

**Do not build a pre-configured workflow list that users must maintain.** If you find yourself seeding `Workflow` records by default, stop and re-read this section.

---

## Tool System

### Declarative JSON Definitions
Tool integrations must be defined in `Hex/Resources/Data/tool-definitions/*.json`. Do NOT add per-tool Swift files for standard HTTP integrations. The reason: tool definitions are data, not code — they can be added, updated, and eventually user-contributed without a new release.

### Tool Seeding: Upsert by ID
Tool records in SwiftData must be seeded using upsert-by-ID, not "insert only if table is empty." Reason: users who installed before a new tool was added would never see it otherwise. Any tool in `Tool.allDefaults` that isn't in the database must be inserted on each launch.

### Workflow Mapping in Tool JSON
Every tool JSON must have a `"workflows"` key mapping workflow IDs to action names. This is how Castellum knows what a tool can do. The key was historically called `"channels"` — do not revert it.

---

## Authentication & OAuth

### Google: Refresh Tokens Require `access_type=offline`
Google does not return a `refresh_token` unless the authorization URL includes `access_type=offline` AND `prompt=consent`. Without this, tokens expire after ~1 hour with no way to refresh. Both params must be appended for every Google OAuth flow. This is handled in `OAuthClient.swift` `startFlow()`.

### Google: Scope Selection at Connect Time
When a user connects Google, they must be shown toggles for each available scope (Calendar, Gmail, Docs, Drive). The selected scope keys are stored in `Tool.selectedScopeKeys`. This is important because Google's token grants permissions at the OAuth scope level — if Gmail isn't selected at connect time, the token cannot send email, and reconnecting is the only fix.

### OAuth Callback: Raise Settings Window
After the OAuth redirect returns to the app, the settings window must be raised — not the transcription overlay. The `HexAppDelegate` URL handler must call `settingsWindow.makeKeyAndOrderFront(nil)`. Reason: a blank/invisible window was previously appearing because `NSApp.activate()` raised the wrong window.

### Google Client Secret in Build Config
`GOOGLE_CLIENT_SECRET` must flow through `Secrets.xcconfig` → `Info.plist` → runtime. It must never be hardcoded in Swift source. See `Hex/Config/Secrets.xcconfig.template` for the template.

---

## Gmail Send: Special Handler Required
Gmail's API requires the message body to be a base64url-encoded RFC 2822 MIME string in a `{"raw": "..."}` JSON envelope. Simple template interpolation cannot produce this. The `send_email` action in `google.json` must use `"special_handler": "gmail_send"`, and `GenericToolExecutor` must construct the MIME message from `to`, `subject`, `body` parameters before calling the API.

---

## Google Docs: Separate API Base URL
The Google Docs API lives at `https://docs.googleapis.com`, not `https://www.googleapis.com`. Actions using the Docs API must hardcode the full URL in their `endpoint` field rather than using `{base_url}` substitution.

---

## Error Messages: User-Friendly Only
`GenericToolExecutor` must never surface raw API error bodies to the user. All HTTP errors must pass through `friendlyErrorMessage()`. Specific rules:

- **401** → "Authentication expired. Reconnect in Settings → Tools."
- **403 + insufficientPermissions or PERMISSION_DENIED** → "Missing permission for this action. Disconnect and reconnect in Settings → Tools, making sure the required access is enabled."  
  Reason: a 403 on a Google action almost always means the user didn't grant that scope at connect time — the fix is to disconnect and reconnect with the correct scope checked.
- **404** → "Resource not found. Check your configuration."
- **429** → "Rate limit reached. Try again in a moment."
- **5xx** → "Server error. Try again later."

---

## Pre-flight Scope Checks (planned)
Before executing a planned action, Castellum must check whether the matched tool has the required scope enabled. If not, the action should be marked blocked in the plan view with a "→ Settings" link before any API call is attempted. This prevents the bad UX of showing a success spinner that later fails with a confusing error. Currently, failures are only surfaced post-execution.

---

## AI / Castellum

### System Prompt: Must Not Hardcode User Identity
The session analysis system prompt in `AnthropicClient.swift` currently hardcodes `"Jonas, a developer and founder of Lyra Designs"`. This must be generalized before Basin ships to other users. The prompt must inject user name and context from `BasnSettings` (user profile fields). Reference: `docs/plans/2026-05-30-claude-touchpoint-analysis.md`.

### Two Claude Calls Should Become One
Currently, session analysis (Touchpoint 1, `AnthropicClient.swift`) and action planning (Touchpoint 2, `CastellumPlannerClient+Live.swift`) are two sequential HTTP round trips. The Claude API supports mixed `text` + `tool_use` blocks in a single response. These must be merged into a unified `CastellumClient.swift` before the first multi-user release. Reason: eliminates one full round-trip of latency on every capture. Reference: `docs/plans/2026-05-30-claude-touchpoint-analysis.md`.

### Model Tiering
- Session analysis and action planning should default to Haiku 4.5, escalating to Sonnet for complex sessions (>500 words, 3+ person names, 4+ matched tools).
- Live prompt coverage (periodic, during recording) already uses Haiku — do not change this.
- A local `SessionComplexityClassifier` (no API call) should gate model selection before every Castellum call.
- A `HeuristicRouter` (local regex/pattern matching) should bypass Claude entirely for ~30% of simple sessions (reminders, quick notes, "text mom"). Reference: `docs/plans/2026-05-30-claude-touchpoint-analysis.md`.

### Integration Pipeline Consistency
Three places must always agree on the complete set of integrations. Adding a new one requires updating all three — missing any one silently drops the integration:
1. `SessionAnalysis.Integration` enum — `HexCore/Sources/BasnCore/Models/SessionAnalysis.swift`
2. `integrationToToolID` map — `Hex/Clients/CastellumPlannerClient+Live.swift`
3. Analysis system prompt integrations list and description — `Hex/Clients/AnthropicClient.swift`

Additionally, the relevant tool's `"workflows"` key in its JSON definition must include the new action type. Example: adding `"docs"` required all four changes — and `"docs"` → `"google"` in the map, `create_document` in google.json's `workflows` key.

### Direct Action vs. Workflow Disambiguation
Castellum must distinguish between two planning modes:
- **Direct tool action** — one unambiguous API call against one connected tool. Use when the transcript maps cleanly with no meaningful alternative (e.g., "log 2 hours in Toggl").
- **Workflow** — multi-step or multi-tool sequence that emerges from content and connected tools.

When intent is ambiguous and could route to multiple tools (e.g., "write me a note" could go to Apple Notes, Day One, Google Docs, or Reminders), Castellum must surface alternatives or prompt for clarification rather than pick silently or drop the action. Verbs like "note", "remind me", "write", "save" have no canonical single-tool mapping and should trigger disambiguation.

### Auto-Execute
If every tool involved in a planned action set has `autoExecute = true` (the user has turned off "Requires Approval" for that tool), Castellum skips the approval step and executes immediately after planning. Implemented in `CastellumFeature.planReceived`. Do not add a confirmation step for auto-execute tools — the setting is explicit user intent.

### Contact Context Injection (planned)
Before the unified Castellum call, load top-50 contacts and inject into the user message for name resolution (e.g., "Diego" → Jira assignee email). This is NOT a separate API call — it's extra context added to the existing call. Only include when the session contains person mentions or delegation content.

---

## Data & Persistence

### Audio Files: Disk-Only
Audio files stay on disk. SwiftData stores the path only, not the audio data. Do not change this — storing audio blobs in SwiftData would bloat the CloudKit sync payload.

### SwiftData + CloudKit
Cross-device sync uses SwiftData with CloudKit private database. On-device first; no server-side processing currently. Any new `@Model` types must be added to the schema registration in `HexApp.swift`.

---

## UI / UX

### Workflow Section: No Hardcoded List
`WorkflowsSectionView` must show an empty state when no workflows exist. It must not show a hardcoded list of workflow types. Workflows appear in this view only after Castellum has produced them as outcomes of actual captures.

### Tool Rows: Planned Expansion
Tool rows in Settings should expand to show: connected-as account label, token health, action-level toggles (which actions are enabled), auto-execute toggle, disconnect button, test connection. Currently only the top-level connect/disconnect state is shown. See `docs/plans/tool-row-expansion.md`.

### "Connected As" Label
After OAuth, fetch the user's identity from the service (e.g., Google userinfo, Jira `/me`) and store it on `Tool.connectedAccountLabel` to show in the settings UI. Currently not implemented.

### Execution Plan: Action Display
Each action row in `ExecutionPlanView` must:
- Show the **tool service name** (e.g., "Google", "Jira") as a caption below the action label — not just an icon
- Be **tappable to expand** and reveal parameter key/value pairs (so users can verify what will be sent)
- Use **per-action icons** for multi-action tools: Google's `create_event` → calendar icon, `send_email` → envelope, `create_document` → doc icon
- Show a generic label ("Create document") in the collapsed state; detail in the expanded state

Reason: the same tool can perform very different actions, and the icon alone doesn't communicate enough for the user to make an informed approve/reject decision.

---

## Platform Scope

Basin targets **iOS, macOS, and Apple Watch**. Any infrastructure decision that would prevent a future iOS or watchOS port (e.g., AppKit-only APIs without an abstraction layer, macOS-only entitlements baked into shared logic) must be flagged.

Current note: `Info.plist` requires **Apple Silicon Mac, macOS 14+** for the existing build. The iOS/watchOS targets are future work.

---

## Naming & Brand

- App display name: **Basin** (product). Short name: **Basn** (used in some brand contexts).
- Internal Xcode scheme/bundle: `com.kitlangton.Hex` (legacy, not yet migrated).
- "Channel" is the historic name for Workflow. Treat it as an alias when reading old code or git history — do not reintroduce it as a user-facing concept.
- See `brand.md` for bundle IDs, icon guidelines, and naming conventions.

---

## Security & Credentials

- All API tokens are managed via environment variables / secrets manager. Never hardcode, echo, or log token values.
- `Tool.oauthAccessToken`, `Tool.apiKey` are sensitive fields — do not log them (use `privacy: .private` annotation or omit from logs entirely).
- Do not read or write `.env` files from within the app or agent tooling.
- Before calling any endpoint known to return a credential in its response body, pause and confirm with the user. Known endpoint: Toggl `GET /api/v9/me` returns `api_token`.
