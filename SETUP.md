# Download App — Xcode Setup Guide

This file documents the Xcode project configuration steps that can't be done from the command line.
The source code is written and ready; these steps wire it into the Xcode build system.

---

## Prerequisites

- Xcode 16.2+ (macOS 15 SDK required for TCA)
- The fork is cloned at `~/localhost/download-app/`
- The existing `Hex` target builds and runs — confirm this before making changes

---

## Step 1: Rename the app (optional but recommended)

The fork is currently called "Hex". Rename it to "Download":

1. In the Project Navigator, click the top-level project (blue icon) → select the **Hex** target
2. Double-click the target name → rename to `Download`
3. Under **General → Display Name**: change to `Download`
4. Under **General → Bundle Identifier**: change to `com.jonasgoslow.download` (or your preferred ID)
5. Rename `Hex.xcodeproj` file on disk → `Download.xcodeproj` via Finder (then reopen in Xcode)

---

## Step 2: Add the Shared Swift package

The `Shared/` directory is a local Swift package (`Shared/Package.swift`). Add it to the Xcode project:

1. In Xcode: **File → Add Package Dependencies...**
2. Click **Add Local...** in the bottom left
3. Navigate to `~/localhost/download-app/Shared/` and click **Add Package**
4. When prompted for the target, select **Download** (macOS app)
5. Confirm `DownloadShared` is added to the macOS target's **Frameworks, Libraries, and Embedded Content**

---

## Step 3: Add iOS target

1. In Xcode: **File → New → Target...**
2. Choose **iOS → App**
3. Product name: `DownloadiOS`
4. Interface: SwiftUI, Language: Swift
5. Uncheck "Include Tests"
6. Add the `DownloadShared` package to this target (same as Step 2)
7. Add `HexCore` local package to this target
8. Move all source files from `iOS/` into the new target's group

**iOS Deployment Target:** iOS 17.0

---

## Step 4: Add watchOS target

1. In Xcode: **File → New → Target...**
2. Choose **watchOS → Watch App**
3. Product name: `DownloadWatch`
4. Companion app: select `DownloadiOS` (the iOS target)
5. Interface: SwiftUI
6. Add `DownloadShared` package to this target
7. Move all source files from `watchOS/` into the new target's group

**watchOS Deployment Target:** watchOS 10.0

**Required capabilities for watchOS target:**
- Add `NSUserNotificationsUsageDescription` to the watchOS Info.plist

---

## Step 5: Configure WatchConnectivity

The watchOS and iOS targets both need WatchConnectivity linked:

1. Select each target → **General → Frameworks, Libraries, and Embedded Content**
2. Click `+` → search for `WatchConnectivity.framework` → Add

---

## Step 6: Add UserNotifications entitlement

For local notification scheduling on macOS and iOS:

1. Select macOS target → **Signing & Capabilities → + Capability → Push Notifications**
   (Local notifications don't need Push Notifications but the entitlement is needed for notification categories)
2. Or for local-only: add `UserNotifications.framework` to Frameworks

---

## Step 7: Bundle download-types.json

The app loads DownloadType definitions from a JSON file. To bundle it:

1. Run the export script (once it exists): generates `download-types.json` from `context/download-types/*.md`
   in the `jonas-pathways` repo
2. Copy `download-types.json` into `Hex/Resources/Data/`
3. In Xcode: add the file to the **Download** target's **Build Phases → Copy Bundle Resources**

Until the export script exists, the app falls back to the built-in "Open" type only.

---

## Step 8: Build and test

```bash
# Build from command line (after Xcode setup):
xcodebuild -scheme Download -destination "platform=macOS" build

# Or just open in Xcode:
open ~/localhost/download-app/Download.xcodeproj
```

**Smoke test checklist:**
- [ ] App launches, menu bar icon appears
- [ ] Settings screen shows "Download" section with Server URL + Auth Token fields
- [ ] Press hotkey → speak → release → transcript appears in History tab
- [ ] `~/Library/Application Support/Download/sessions/` contains a `<uuid>.json` file
- [ ] Set a server URL → speak again → verify POST arrives at the server (use `npx json-server` for quick testing)
- [ ] Toggle "Paste transcript to cursor" → verify paste behavior toggles correctly

---

## Quick local server for testing

```bash
# Install: npm install -g json-server
# Create a simple endpoint that logs received sessions:
cat > /tmp/server.js << 'EOF'
const http = require('http')
const server = http.createServer((req, res) => {
  let body = ''
  req.on('data', chunk => body += chunk)
  req.on('end', () => {
    console.log('\n--- New session ---')
    console.log(JSON.stringify(JSON.parse(body), null, 2))
    res.writeHead(200)
    res.end()
  })
})
server.listen(3000, () => console.log('Listening on http://localhost:3000'))
EOF
node /tmp/server.js
```

Then in Download Settings: Server URL = `http://localhost:3000`

---

## Architecture notes

| Directory | Purpose |
|-----------|---------|
| `HexCore/` | macOS-only shared logic (TCA, settings, models) — existing Hex package |
| `Shared/` | Platform-agnostic Swift package (iOS + macOS + watchOS) — new |
| `Hex/` | macOS app source — being renamed to `Download` |
| `iOS/` | iOS app source files — stub, add to Xcode iOS target |
| `watchOS/` | watchOS app source files — stub, add to Xcode watchOS target |

The `DownloadShared` package is the long-term home for all models and services.
The `HexCore` equivalents (`DownloadSession`, `DownloadSettings`) will be removed
once all targets are linked to `DownloadShared`.
