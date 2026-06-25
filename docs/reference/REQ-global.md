---
type: requirement
subtype: global
status: active
created: 2026-03-19
updated: 2026-06-25
req_id: REQ-global
tags: [requirement]
---

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

### Tool Rows: Expandable (Shipped)
Tool rows in Settings use `DisclosureGroup`. Collapsed state shows **only**: icon, name, connection status icon. No other controls in collapsed state — the previous design crammed disconnect/auto-execute into the row subtitle and was rejected as too noisy.

Expanded state has four sections. Each section must be hidden if it has no content — never render a section header with nothing beneath it, and never render a `Divider()` before a section that may not appear.

**Connection** (always shown when connected):
- Auth method badge (OAuth / API Key)
- "Connected [date]" — from `tool.connectedAt`, set at connect time for both OAuth and API key paths
- Token health — sourced from `KeychainClient.loadExpiry(toolID:)`, color-coded: >30 days `.secondary`, 8–30 `.orange`, <8 `.red`, expired `.red`
- "Last used [relative]" or "Not yet used by Basin" — from `tool.lastUsedAt`, written by `GenericToolExecutor` on successful execution
- "Verify" button — fires `health_check` endpoint, shows result 4s then resets. Only shows when `spec.healthCheck != nil`. Every tool JSON must define `health_check`.

**Token expiry status in collapsed row:** expired tokens show orange `exclamationmark.circle.fill`. Green `checkmark.circle.fill` only for valid tokens. A green checkmark on an expired token is misleading — do not do this.

**Authorized permissions** (OAuth only, hide when empty):
Read-only list of scope labels from `tool.selectedScopeKeys` mapped via `availableScopes` in the tool JSON. Never make these inline-toggleable — changing OAuth scopes requires a full reconnect. "Reconnect to change" button opens the connect sheet.

**Basin can use** (hide when `spec` has no actions):
Service-area-level toggles for multi-scope tools (currently Google only). One toggle controls a named area (Calendar, Gmail, Docs) and maps to a set of action keys via a static mapping in `ToolsSectionView.ToolServiceArea.scopeActionMapping`. `tool.enabledActionKeys` stores **disabled** action keys — `nil` means all enabled. The naming is a known inconsistency; do not rename without updating all call sites.

For single-action tools, shows a text description instead of toggles. Service-area granularity (not individual action toggles) was an explicit design decision: individual toggles were too confusing for users who don't know what `create_document` vs `append_text` means.

**Controls** (always shown):
- "Requires approval" toggle — inverted `autoExecute`. Caption must read: *"Basin will ask before running actions. Overridden by individual workflow settings."* The override note is load-bearing — tool-level `autoExecute` is not the final word.
- "Disconnect" button.

### "Connected As" Label
After OAuth, fetch the user's identity from the service (e.g., Google userinfo, Jira `/me`) and store it on `Tool.connectedAccountLabel` to show in the settings UI. **Not yet implemented** — deferred because it requires a post-connect API fetch with error handling.

### Execution Plan: Action Display
Each action row in `ExecutionPlanView` must:
- Show the **tool service name** (e.g., "Google", "Jira") as a caption below the action label — not just an icon
- Be **tappable to expand** and reveal parameter key/value pairs (so users can verify what will be sent)
- Use **per-action icons** for multi-action tools: Google's `create_event` → calendar icon, `send_email` → envelope, `create_document` → doc icon
- Show a generic label ("Create document") in the collapsed state; detail in the expanded state

Reason: the same tool can perform very different actions, and the icon alone doesn't communicate enough for the user to make an informed approve/reject decision.

---

## Hotkey System

### tapDisabledByTimeout: Self-Healing Required
macOS can disable a CGEvent tap via `tapDisabledByTimeout`. The previous code left `isMonitoring = true`, so `activateTapIfNeeded` would silently skip restart — the hotkey stopped working permanently until relaunch. The fix: `handleTapDisabledEvent` in `KeyEventMonitorClient` clears `isMonitoring = false` on the main actor before scheduling the restart Task. **Do not remove or simplify this reset — without it the tap cannot be recreated.** (commit 4523ec1)

### Modifier-Only Hotkeys: 0.3s Minimum Threshold
Modifier-only hotkeys (e.g., Option alone) enforce a 0.3s minimum hold before a recording is committed, even if `minimumKeyTime` is shorter. This prevents intercepting Option+Click (Finder duplicate), Option+A (special characters), and similar macOS shortcuts. Effective threshold: `max(minimumKeyTime, 0.3s)`. Regular hotkeys (Cmd+A, etc.) use only `minimumKeyTime`. See `docs/hotkey-semantics.md` for the full decision matrix.

### One Hotkey Capture Target Only
There is only one hotkey capture target: recording start/stop. A second target ("Paste Last Transcript") existed in Hex and was removed for Basin. Do not add new capture targets to `SettingsFeature` without a conscious product decision — each target requires significant state machinery and the complexity multiplies.

---

## Navigation & Settings Structure

### Sidebar Order
Basin, History | (divider) | Settings, Flows, Workflows, Tools, About. The top group is "use the app"; the bottom group is "configure the app." Flows, Workflows, and Tools are top-level items because they represent the three-layer system model — not sub-pages of Settings.

### Settings Page Contents
Settings shows only: Sound, General, Basin, History. Tools and Workflows have been promoted to top-level sidebar items and must not be re-added to the Settings page.

### Word Remappings: Hidden, Not Deleted
The Transforms (word remappings) UI was hidden from the sidebar but the underlying code (`WordRemappingsView`, all reducer logic) must be preserved. Speech-to-text correction for domain-specific terms may have a role in Basin. The decision to remove it permanently requires an audit. Do not delete `WordRemappingsView` or its associated reducer actions until that audit is complete.

---

## Recording Pipeline

### Standard AVAudioRecorder Only — No Pre-Arm Buffer
Basin uses explicit, hotkey-triggered recording. Super Fast Mode (pre-armed mic via AVAudioEngine ring buffer in `SuperFastCaptureController`) was removed because an always-on mic is contrary to Basin's explicit capture model. `RecordingClient` always uses standard `AVAudioRecorder`. `SuperFastCaptureController.swift` has been deleted. (commit 4523ec1)

### Empty Transcription: Do Not Save
If WhisperKit (or any STT engine) returns an empty string after a recording, the session must not be saved to history on either platform. iOS: guarded in `AppState.stopRecording()`. macOS: guarded in `TranscriptionFeature` before `finalizeRecordingAndStoreTranscript`. Do not remove these guards — blank captures pollute history and mislead stats.

### `warmUpRecorder` Must Not Be Called
Warming up the recorder was part of Super Fast Mode. The method has been removed from the `RecordingClient` protocol and live implementation. If a future feature requires mic pre-warming, it must be explicitly re-introduced with a documented rationale.

### Basin Never Auto-Pastes Transcript
`shouldPaste` is hardcoded to `false` in `TranscriptionFeature`. Basin's output is routed through Castellum and Workflows — not pasted blindly into the active app. The `pasteAfterSession` setting was removed from `BasinSettings`. Do not re-introduce auto-paste behavior without an explicit product decision. (commit 4523ec1)

---

## Removed Settings — Must Not Be Re-Introduced Without Explicit Decision

The following were deliberately removed from `HexSettings` (commit 4523ec1):

| Setting | Why removed |
|---------|-------------|
| `useClipboardPaste` | Basin always uses the clipboard-paste path — no user toggle needed. |
| `copyToClipboard` | Basin never auto-copies transcript to clipboard; output is routed via Castellum. |
| `superFastModeEnabled` | Super Fast Mode (always-armed mic) contradicts Basin's explicit capture model. |
| `pasteLastTranscriptHotkey` | "Paste Last Transcript" was removed; transcripts are in History. |

Removed from `BasinSettings`:

| Setting | Why removed |
|---------|-------------|
| `pasteAfterSession` | Basin never auto-pastes. See "Basin Never Auto-Pastes Transcript" above. |

---

## Menu Bar

### No "Paste Last Transcript" Button
Basin does not surface raw transcript paste in the menu bar. `MenuBarCopyLastTranscriptButton.swift` was deleted. Transcripts are accessible via the History view. (commit 4523ec1)

### Flow History in Menu Bar (planned)
The menu bar extra should eventually show the last 10 flows run, with entries that deep-link to History filtered by flow. A TODO comment marks the placeholder in `HexApp.swift`. Blocked on History view supporting per-flow filtering.

---

## Audio Behavior

### Picker: Pause Media, Mute, Do Nothing
Current options in `GeneralSectionView`. "Lower Audio Volume" is intentionally absent — it requires a `.lowerVolume` case in `RecordingAudioBehavior` + handling in `RecordingClient` + a Picker entry. The infrastructure already exists (`getSystemVolume`/`setSystemVolume` in `RecordingClient`), same pattern as `.mute`, targeting ~30% volume reduction during recording. Implement when prioritized.

---

## Platform Scope

Basin targets **iOS, macOS, and Apple Watch**. Any infrastructure decision that would prevent a future iOS or watchOS port (e.g., AppKit-only APIs without an abstraction layer, macOS-only entitlements baked into shared logic) must be flagged.

- macOS: Apple Silicon, macOS 14+
- iOS: implemented, iOS 17+, iPhone and iPad
- watchOS: future work

### BasnCore Must Not Link to iOS
`BasnCore` (the HexCore SPM package) depends on Sauce (keyboard monitoring) and IOKit — both macOS-only frameworks. It must never be added to the iOS target. iOS-specific code that needs settings or logging must use `IOSAppSettings` (Foundation-only struct) and a local `os.Logger` instead. Use `#if canImport(BasnCore)` guards at any shared callsite that needs to compile on both platforms.

---

## Transcription

### On-Device Only — No Cloud STT
Transcription must never be sent to an external speech-to-text service. All STT runs locally using WhisperKit (CoreML) or FluidAudio/Parakeet. This is a privacy invariant. Do not add cloud transcription paths.

### Curated Model List
Settings → Transcription Model shows a compact, opinionated list with radio selection — not a dropdown or full model browser. The curated set is: Parakeet TDT v3 (default), Whisper Small (Tiny), Whisper Medium (Base), Whisper Large v3. Distil-Whisper is English-only and must not appear in the default list.

### Default Model
Parakeet TDT v3 (multilingual) via FluidAudio. This is the out-of-box experience for all new users.

### Model Storage Paths

**macOS:**
- WhisperKit: `~/Library/Application Support/com.lyra.basn/models/argmaxinc/whisperkit-coreml/<model>`
- Parakeet (FluidAudio): `~/Library/Containers/com.lyra.basn/Data/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml`
- `XDG_CACHE_HOME` is set at app launch so Parakeet caches under the app container — NOT `~/.cache/fluidaudio`, which is outside the sandbox and invisible at runtime.
- Availability detection must scan both `Application Support/FluidAudio/Models` and the app cache path.

**iOS:**
- WhisperKit: `<Documents>/huggingface/models/argmaxinc/whisperkit-coreml/<variant>`
- Parakeet/FluidAudio: not supported on iOS (macOS only in v1).
- `isModelDownloaded(variant:)` is a live filesystem check — there is no persisted bool. Do not introduce a cached `Bool` state for this.
- Model files must be excluded from iCloud backup (`URLResourceValues.isExcludedFromBackup = true`) immediately after download. Models are large and can be re-downloaded; backing them up wastes the user's iCloud quota.

### Default Model by Platform
- macOS: Parakeet TDT v3 (multilingual) via FluidAudio — `selectedModel = "parakeet-tdt-0.6b-v3"`
- iOS: Whisper Base — `selectedModel = "openai_whisper-base"` (Parakeet/FluidAudio is macOS-only)

---

## iOS

### State Management: Observable AppState, Not TCA
The iOS app uses `@Observable @MainActor class AppState` — not The Composable Architecture. TCA is macOS-only. Do not add TCA dependencies to the iOS target. All iOS state flows through `AppState` published to views via SwiftUI's `@Environment`.

### Navigation: 3-Tab Structure
iOS has exactly three tabs: **Home**, **Record**, **Settings**. History is accessible from the Home tab (toolbar link + inline "See all" on the last capture card). Do not add a standalone History tab — it was deliberately removed to keep the tab bar uncluttered.

### FAB Recording Button
- Idle: blue circle, mic icon
- Recording: red circle, waveform icon — tap to stop
- Transcribing: grey circle, ProgressView spinner — disabled (cannot start new recording)
- Type-mode: FAB takes the keyboard icon and black fill; toggle takes the mic icon and blue fill — the icons and colors fully swap between the two buttons. Do not make the toggle always show one icon regardless of mode.
- The FAB overlaps the tab bar. All scrollable views must have a `safeAreaInset(edge: .bottom)` or equivalent padding of **140pt** to clear the FAB. This is derived from FAB geometry (center 44pt above safe-area top, top edge 106pt above) — 140pt gives comfortable clearance.

### iOS Settings Structure
Sections in order: Capture (Flows, Transcription Model, Output Language) → Integrations (Tools, Workflows) → Preferences (Sound, History) → Basn (AI & Server) → About.

Omitted vs. macOS: no HotKey section (no global hotkeys on iOS), no Sparkle update check (App Store handles this), no microphone device picker (iOS controls input routing).

### Per-Model Download State
`AppState` tracks downloads with `downloadingModelVariant: String?` (nil = not downloading) and `modelDownloadProgress: Double`. There is no single `isModelDownloaded: Bool` — use `isModelDownloaded(variant:)` for per-model checks. A model must be fully downloaded before `settings.selectedModel` is updated. Do not switch the active model mid-download.

### iOS WhisperKit Initialization
`AppState.ensureWhisperKitLoaded(variant:)` loads WhisperKit from the local `Documents/huggingface` path using `WhisperKitConfig(model:modelFolder:prewarm:load:)`. Do not pass `tokenizerFolder` — WhisperKit locates the tokenizer inside the model folder automatically. Pre-load is triggered: (a) at app launch if the model is already downloaded, (b) immediately after a download completes. This keeps first-recording latency low.

### iOS OAuth
Uses `ASWebAuthenticationSession` via `OAuthClient.shared.startFlow()` — same entry point as macOS, with platform dispatch inside. Do not call `NSWorkspace.shared.open()` on iOS.

### iOS Widget & Deep Link
- The `basin://` URL scheme is registered in `iOS/Info.plist` (a real plist file — the iOS target does not use `GENERATE_INFOPLIST_FILE`).
- The home screen widget (`BasnWidget` WidgetKit extension) uses `widgetURL(URL(string: "basin://capture")!)`.
- `ContentView` handles `.onOpenURL { url in ... }` for `basin://capture`: switches to the Record tab, exits type mode, and immediately calls `appState.startRecording()`.
- Do not remove or bypass the URL scheme — the widget has no other communication path to the app.

### History Timestamps
Show relative time ("5 minutes ago", "2 hours ago", "yesterday", "5 days ago") for captures within the last 7 days. Show abbreviated date ("May 23") for older captures. Do not use SwiftUI's `.relative` date style — it counts up like a timer and is visually indistinguishable from a recording duration.

### AVAudioSession Must Be Activated Before Accessing `inputNode`
In `FlowTranscriptionEngine.beginSession()`, `AVAudioSession.setCategory()` and `setActive(true)` must run **before** any access to `audioEngine.inputNode`. `inputNode.outputFormat(forBus:0)` returns 0 Hz if the session is not yet active, causing `installTap` to throw `IsFormatSampleRateAndChannelCountValid`. Additionally, `installTap` must pass `nil` for the `format:` parameter so AVAudioEngine picks up the hardware's native format — passing the explicit output format is redundant and fragile. Without both constraints, `FlowTranscriptionEngine.start()` crashes.

### SwiftData `@Query` in Closures: Use `modelContext` Instead
`@Query` returns a value-type array. Closures in SwiftUI structs capture that array at closure-creation time, not execution time. If `@Query` had not yet populated (e.g., the `fullScreenCover` was presented before the seed ran, or the environment wasn't forwarded), the closure silently operates on an empty array.

Fix: use `@Environment(\.modelContext) private var modelContext` instead of `@Query` when records are needed inside a closure. Call `modelContext.fetch()` at execution time to always get live data. `ModelContext` is a reference type — capturing it in a closure and fetching later is safe and always reflects the current store.

Applied in `iOS/Onboarding/OnboardingView.swift` `SetupFlowBridgePage.onResult` and `handleFlowEnd()` — previously `allTools` from `@Query` was captured stale and always empty, causing the tool onboarding wizard to skip straight to "All Set".

### `fullScreenCover` Requires Explicit `.modelContainer()` Forwarding
SwiftUI does not reliably propagate `.modelContainer()` to `fullScreenCover` content. Any view presented in a `fullScreenCover` that contains `@Query` or `@Environment(\.modelContext)` must receive `.modelContainer(Self.modelContainer)` explicitly on the presented view. See `iOS/App/BasnAppIOS.swift` — `OnboardingView()` in the cover explicitly gets `.modelContainer(Self.modelContainer)`.

### `fullScreenCover` Must Be Anchored to a Persistent View
Do not attach `.fullScreenCover(isPresented:)` to a view that is conditionally removed from the hierarchy during or after the cover's dismissal animation. If the anchor view disappears (e.g., `if needsSetup { setupCard }` removes the card when setup completes), SwiftUI may abort the dismissal mid-animation. Attach covers to a parent that is always present — for home-screen flows, that is the `NavigationStack` in `HomeView.body`.

---

## Logging

All diagnostics use the unified `BasnLog` helper (`HexCore/Sources/BasnCore/Logging.swift`). Rules:
- **Never use `print`** anywhere in the app.
- Use an existing log category (`.transcription`, `.recording`, `.settings`) or add a new case to the `BasnLog.Category` enum so Console.app filter predicates stay consistent.
- Apply `, privacy: .private` for any potentially sensitive content: transcript text, file paths, API responses.
- `Tool.oauthAccessToken` and `Tool.apiKey` must never appear in any log statement, even with privacy annotations.

---

## Build Tooling

### Package Manager: SPM Only
No CocoaPods, no Carthage. All dependencies are declared in `Package.swift` files and resolved by SPM. Do not introduce CocoaPods (which would require a Ruby toolchain and `Podfile`) — the whole dependency graph is SPM.

### Changesets
Every user-facing change (feature, UX improvement, bug fix) needs a `.changeset/*.md` fragment before release. Use the non-interactive script: `bun run changeset:add-ai patch|minor|major "Summary"`. Agents must not run `changeset version` — that's the release tool's responsibility.

### Release Pipeline
Automated via `tools/src/cli.ts` (TypeScript/Bun). Handles versioning, notarization, DMG signing, S3 upload, and GitHub release. Run from repo root: `bun run tools/src/cli.ts release`. Requires a clean working tree.

### Ruby Scope
Ruby appears in exactly two places — intentionally limited:
1. `hex.rb` — Homebrew cask formula. This format is required by Homebrew; not a choice.
2. `tools/add_ios_target.rb` — One-time script using the `xcodeproj` gem to add the iOS build target. No TypeScript equivalent exists for editing `.xcodeproj` files.

Do not introduce Ruby elsewhere. All other scripting is TypeScript/Bun.

---

## Naming & Brand

- App name: **Basn**. Bundle ID: `com.lyra.basn`. See `brand.md` for full naming conventions.
- The source folder `Hex/`, `package.json` name `"hex-app"`, and `hex.rb` are **legacy rename debt** from the project's original "Hex" name. Treat them as migration targets, not correct naming. Do not preserve or deepen "Hex" naming in new code.
- "Channel" is the historic name for Workflow. Treat it as an alias when reading old code or git history — do not reintroduce it as a user-facing concept.

---

## Security & Credentials

- All API tokens are managed via environment variables / secrets manager. Never hardcode, echo, or log token values.
- `Tool.oauthAccessToken`, `Tool.apiKey` are sensitive fields — do not log them (use `privacy: .private` annotation or omit from logs entirely).
- Do not read or write `.env` files from within the app or agent tooling.
- Before calling any endpoint known to return a credential in its response body, pause and confirm with the user. Known endpoint: Toggl `GET /api/v9/me` returns `api_token`.
