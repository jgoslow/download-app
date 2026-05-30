# Basin iOS + Rebrand Plan

## Context

Basin/Hex was forked from an open-source macOS speech-to-text app called Hex. The app's identity, bundle ID, code symbols, and infrastructure all still carry Hex branding. Before building the iOS version, it makes sense to complete the rebrand to Basin (under the Lyra Designs identity) so the iOS target starts clean and both apps share a coherent identity. This plan covers (1) the rebrand, then (2) the iOS port.

---

## Phase 0: Hex → Basin Rebrand (do first)

### Scope Assessment

**~60 Swift files** contain `HexLog`, `HexSettings`, `HexApp`, `HexCore` symbols. The changes are mostly mechanical find-and-replace, but several have real-world consequences.

### What changes in code

| Area | Old | New |
|---|---|---|
| Bundle ID (macOS) | `com.kitlangton.Hex` | `com.lyradesigns.basin` |
| Bundle ID (debug) | `com.kitlangton.Hex.debug` | `com.lyradesigns.basin.debug` |
| Test target | `com.kitlangton.HexTests` | `com.lyradesigns.basin.tests` |
| Package: HexCore | `import HexCore` / `HexLog.*` | Rename package to `BasinCore`; `BasinLog.*` |
| Settings type | `HexSettings`, `.hexSettings` shared key | `BasinSettings`, `.basinSettings` |
| App entry | `HexApp.swift`, `HexAppDelegate.swift` | `BasinApp.swift`, `BasinAppDelegate.swift` |
| Model file | `AppHexSettings.swift` | `AppBasinSettings.swift` |
| Logging subsystem | `"com.kitlangton.Hex"` in `Logging.swift` | `"com.lyradesigns.basin"` |
| Storage paths | `HexCore/Sources/HexCore/StoragePaths.swift` | Updated subsystem string |
| Sparkle feed | `hex-updates.s3.amazonaws.com/appcast.xml` | New S3 bucket/path |
| Project name | `Hex.xcodeproj`, scheme `Hex` | `Basin.xcodeproj`, scheme `Basin` |
| URL scheme | Already `basin://` in OAuthClient ✓ | No change needed |

**Files to touch**: `Hex.xcodeproj/project.pbxproj`, `HexCore/Package.swift`, all ~60 Swift files with Hex symbols, `Info.plist`, `Hex.entitlements`, `tools/src/cli.ts` (release tooling S3 paths), `CLAUDE.md`.

### Consequences that require action beyond code

| Consequence | Action required |
|---|---|
| **Apple Developer Portal** | Register new App ID `com.lyradesigns.basin`; create new provisioning profile |
| **Code signing** | New profile for new bundle ID; re-notarize |
| **SwiftData container path** | Changes from `Application Support/com.kitlangton.Hex/` to `Application Support/com.lyradesigns.basin/` → **existing data not auto-migrated** (history, tool connections reset for current users) |
| **UserDefaults domain** | Settings stored under old bundle ID won't be found → settings reset |
| **Model cache** | WhisperKit models at old path won't be found → users re-download models |
| **OAuth re-auth** | Redirect URI is already `basin://oauth/callback` so OAuth app registrations in Google/Slack/Atlassian are fine. BUT SwiftData `Tool` records (which store tokens) live in the old container → **users must reconnect tools after first launch** |
| **Sparkle** | New appcast URL needs to be set up; existing Sparkle feed stays for the "last Hex build" that updates to "first Basin build" |
| **S3 release artifacts** | Update `tools/src/cli.ts` upload paths; set up redirect or alias from `hex-latest.dmg` |

**Recommended approach**: Accept the data loss for current users (Jonas + any early testers). It's a pre-release app and the clean break is worth it. Add a first-launch migration notice: "Basin has been renamed — please reconnect your tools."

### Order of operations
1. Register `com.lyradesigns.basin` in Apple Developer Portal
2. Rename `Hex.xcodeproj` → `Basin.xcodeproj` and update all project references
3. Rename `HexCore/` → `BasinCore/`, update Package.swift and all `import HexCore` → `import BasinCore`
4. Global symbol rename: `HexLog` → `BasinLog`, `HexSettings` → `BasinSettings`, `HexApp` → `BasinApp`, etc.
5. Update `Info.plist`, entitlements, build settings
6. Update release tooling S3 paths
7. Update `CLAUDE.md`
8. Build + test; cut a "Basin 1.0" release

---

## What to Remove from Both Apps: PasteboardClient

`Hex/Clients/PasteboardClient.swift` implements macOS auto-paste via AppleScript and accessibility — this is being removed entirely from both macOS and iOS.

**Removal scope**:
- Delete `PasteboardClient.swift`
- Remove `@Dependency(\.pasteboard)` from `TranscriptionFeature.swift`
- Remove all `pasteboard.*` call sites in `TranscriptionFeature`
- Remove any `autoPaste` setting from `HexSettings` / `BasinSettings`
- Remove the paste-related settings UI from `GeneralSectionView`
- Remove `com.apple.security.automation.apple-events` from entitlements (used only for paste AppleScript)

After Castellum processes a capture on both platforms: results are shown in the app UI. Users can copy individual outputs via a copy icon.

---

## Phase 1: iOS Target Setup

- Add "Basin (iOS)" target to `Basin.xcodeproj` (after rebrand)
- New `iOS/App/BasinAppIOS.swift` entry point — standard `@main` with `WindowGroup`
- New `iOS/Basin-iOS.entitlements` — mic permission, network, keychain
- Link to iOS target: `WhisperKit`, `ComposableArchitecture`, `BasinCore`, `BasinShared`
- Do NOT link to iOS: `FluidAudio`, `Sauce`, `Sparkle`, `Inject`
- `#if canImport(FluidAudio)` guards in `TranscriptionClient.swift` already exist — iOS build skips Parakeet automatically

---

## Phase 2: OAuth Token → iCloud Keychain

**Current state**: `oauthAccessToken` and `oauthRefreshToken` are plain strings on the SwiftData `Tool` model (`Hex/Models/BasinModels.swift`). SwiftData doesn't sync between devices.

**Target**: Tokens in iCloud Keychain (`kSecAttrSynchronizable = kCFBooleanTrue`) — sync automatically across all Apple ID devices.

**Steps**:
1. New `iOS/Clients/KeychainClient.swift` (linked to both targets) — wraps `SecItem*` with sync attributes:
   - `kSecAttrService = "com.lyradesigns.basin.oauth"`
   - `kSecAttrAccount = "<providerID>_access_token"` / `"<providerID>_refresh_token"`
   - `kSecAttrSynchronizable = kCFBooleanTrue`
   - `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock`
2. `OAuthClient`: write tokens to Keychain after exchange/refresh
3. Tool action clients (`JiraActionClient`, `SlackActionClient`, `GenericToolExecutor`): read from Keychain instead of SwiftData `Tool` properties
4. Remove `oauthAccessToken` / `oauthRefreshToken` / `oauthExpiresAt` from `Tool` SwiftData model
5. Add `com.apple.security.keychain-access-groups` to both macOS and iOS entitlements with `$(AppIdentifierPrefix)com.lyradesigns.basin`

No App Group needed for iCloud Keychain sync — just `kSecAttrSynchronizable = true` plus matching team ID.

---

## Phase 3: iOS Client Implementations

| Client | macOS | iOS |
|---|---|---|
| `RecordingClient` | CoreAudio device enumeration, AppKit media keys | `AVAudioSession` routing; no device picker (iOS controls input) |
| `OAuthClient` | `NSWorkspace.shared.open()` + URL scheme callback | `ASWebAuthenticationSession` (handles round-trip internally) |
| `KeyEventMonitorClient` | Carbon/CGEventTap global hotkeys | No-op stub — recording is UI-driven |
| `PasteboardClient` | Deleted | N/A |
| `PermissionClient` | Mic + accessibility + input monitoring | Mic only |

Platform-specific `liveValue` registered with `#if os(iOS)` / `#if os(macOS)` in a shared DependencyKey extension file.

---

## Phase 4: iOS App Shell + Navigation

**Tab bar — 3 items only:**
```
[History]  [● Record]  [Settings]
```
All other screens (Flows, Workflows, Tools) live under Settings.

**Landing page (before tapping Record):**
- Full-screen "capture card" showing the active Flow name, its description/prompts, and a centered water-circle record button
- Flow selector is available (swipe or tap to switch flows)
- This is the first thing a user sees — designed for fast capture

**Transcription overlay (Live Activity — when not in foreground):**
- Uses ActivityKit `Live Activity` for Dynamic Island (iPhone 14 Pro+) and lock screen
- Visual: the water-circle drain animation (spinning vortex) while recording is active
- Compact presentation: animated water icon + elapsed recording time
- Falls back to a standard notification banner on non-Dynamic Island devices
- File: `iOS/LiveActivity/BasinRecordingActivity.swift`

---

## Phase 5: Onboarding (Both Platforms)

macOS and iOS onboarding should both include an explicit audio permission request step.

**macOS**: First launch → `AVCaptureDevice.requestAccess(for: .audio)` before any recording attempt. Currently this may happen implicitly; make it explicit in a welcome screen.

**iOS**: Standard `AVAudioApplication.requestRecordPermission` in onboarding flow. Show a custom explanation screen before triggering the system prompt ("Basin needs your microphone to capture your voice notes").

---

## Phase 6: iOS Settings (Adapted from macOS)

Reuse these macOS sections (no AppKit dependencies):
- Model section (`ModelSectionView`)
- Language section (`LanguageSectionView`)
- Sound section (`SoundSectionView`)
- Tools section (`ToolsSectionView`)
- Workflows section (`WorkflowsSectionView`)
- History section (`HistorySectionView`)
- Basin/About section

Drop for iOS:
- HotKey section (no global hotkeys)
- Permissions section (replace with inline mic permission prompt)
- Microphone device picker (no input selection on iOS)
- Sparkle "Check for Updates" (App Store handles this)

---

## Phase 7: Model Download on iOS

- Audit `ModelDownloadFeature.swift` storage path construction — use platform-conditional paths
- WhisperKit model download uses `URLSession` — works on iOS as-is
- Verify CoreML inference runs on A-series chip (should — WhisperKit explicitly supports iOS)
- Exclude model files from iCloud backup (`URLResourceKey.isExcludedFromBackupKey = true`)

---

## Phase 8: iOS Widget

**Widget type**: WidgetKit `AppIntentConfiguration` with a "Start Open Flow" action.

**Interaction**: Tap the widget → deep link opens the app → immediately enters recording state for the Open flow (or user's default flow).

**Implementation**:
- New target: `BasinWidget` extension
- `BasinWidgetIntent`: `AppIntent` that opens the app with a flow ID parameter
- Widget UI: water-circle icon + "Tap to capture" label + current time/date
- Deep link: `basin://capture?flow=open` handled in `BasinAppIOS.swift`
- Small and medium widget sizes

**Flow selection via voice** (concurrent feature):
- During live transcription (periodic parsing), scan partial transcript for phrases like "let's do a morning flow", "switch to day's end", "start a weekly review"
- Match against loaded `Flow` names using fuzzy comparison
- When detected: `TranscriptionFeature` sends `.setFlow(id:)` action, updating active flow mid-session
- Add to `PeriodicParsingController.swift` as a parallel "intent detection" pass alongside the existing prompt-addressed parsing
- File: extend `PeriodicParsingController.swift` or add `FlowIntentDetector.swift`

---

## Critical Files

| File | Change |
|---|---|
| `Hex.xcodeproj` → `Basin.xcodeproj` | Bundle IDs, product names, target names |
| `HexCore/` → `BasinCore/` | Package rename |
| `Hex/Models/BasinModels.swift` | Remove `oauthAccessToken`/`oauthRefreshToken`/`oauthExpiresAt` from `Tool` |
| `Hex/Clients/PasteboardClient.swift` | Delete |
| `Hex/Clients/OAuthClient.swift` | Write tokens to Keychain; guard `NSWorkspace` behind `#if os(macOS)` |
| `Hex/Clients/ToolActions/JiraActionClient.swift` | Read tokens from Keychain |
| `Hex/Clients/ToolActions/GenericToolExecutor.swift` | Read tokens from Keychain |
| `Hex/Features/Transcription/TranscriptionFeature.swift` | Remove pasteboard dependency; add iOS conditional guards |
| `Hex/Features/App/AppFeature.swift` | Platform-conditional permission checks |
| `HexCore/Sources/HexCore/Logging.swift` | Rename `HexLog` → `BasinLog` |
| `HexCore/Sources/HexCore/Settings/HexSettings.swift` | Rename to `BasinSettings.swift` |

## New Files

| File | Purpose |
|---|---|
| `iOS/App/BasinAppIOS.swift` | iOS `@main` entry point |
| `iOS/Basin-iOS.entitlements` | iOS entitlements |
| `iOS/Clients/KeychainClient.swift` | iCloud Keychain wrapper (both targets) |
| `iOS/Clients/RecordingClientIOS.swift` | AVAudioSession recording |
| `iOS/Clients/OAuthClientASWAS.swift` | ASWebAuthenticationSession OAuth |
| `iOS/Features/Home/CaptureCardView.swift` | Landing flow capture UI |
| `iOS/Features/Transcription/RecordingViewIOS.swift` | In-progress recording UI |
| `iOS/Features/Settings/SettingsViewIOS.swift` | iOS settings root |
| `iOS/LiveActivity/BasinRecordingActivity.swift` | Dynamic Island / lock screen recording indicator |
| `iOS/Widget/BasinWidget.swift` | Home screen WidgetKit target |
| `iOS/Clients/PeriodicParsingController+FlowIntent.swift` | Flow-switching via voice detection |

---

## Recommended Order

1. **Phase 0 (Rebrand)** — do before any iOS work; both apps get clean identity
2. **Remove PasteboardClient** — clean cut, unblocks entitlement simplification
3. **Phase 1 (iOS target)** — scaffolding compiles
4. **Phase 2 (Keychain)** — auth works cross-device from the start
5. **Phase 3 (iOS clients)** — recording + OAuth work on iOS
6. **Phase 4 (Navigation + UI shell)** — usable app
7. **Phase 5 (Onboarding)** — both platforms get permission flow
8. **Phase 6 (Settings)** — full settings parity
9. **Phase 7 (Model download)** — transcription works on device
10. **Phase 8 (Widget + flow intent)** — power features

---

## Verification

1. **Rebrand**: macOS app builds and runs as "Basin"; all logging shows `com.lyradesigns.basin`
2. **Auth sync**: Connect Google on macOS → open iOS app → Google shows connected (Keychain synced via iCloud)
3. **Record on iOS**: Tap mic → speak → transcript appears → Castellum fires → Jira/Slack executes
4. **Widget**: Tap widget → app opens → immediately enters recording
5. **Flow intent**: Say "let's switch to morning flow" mid-recording → active flow updates
6. **Live Activity**: Put app in background while recording → Dynamic Island shows water animation
7. **Onboarding**: Fresh install of both apps requests mic permission explicitly
