# Basin OAuth App Registration

Basin uses OAuth 2.0 to connect to external services. You register once as the app developer; each user then authenticates with their own account.

**Callback URL for all providers:** `basin://oauth/callback`

---

## 1. GitHub

**Console:** https://github.com/settings/applications/new

1. Go to GitHub Settings > Developer settings > OAuth Apps > New OAuth App
2. Fill in:
   - **Application name:** Basin
   - **Homepage URL:** https://getbasin.ai
   - **Authorization callback URL:** `basin://oauth/callback`
3. Click "Register application"
4. Copy the **Client ID**
5. Generate a **Client Secret** (needed for token exchange from native apps)

**Scopes used:** `repo`, `read:user`

**Notes:**
- GitHub OAuth Apps don't support PKCE. The client secret is needed for the code-to-token exchange.
- For better security, consider using a GitHub App instead (supports PKCE, fine-grained permissions).

---

## 2. Google (Calendar + Gmail)

**Console:** https://console.cloud.google.com/apis/credentials

1. Create a new project (or use an existing one)
2. Go to APIs & Services > Credentials > Create Credentials > OAuth client ID
3. If prompted, configure the OAuth consent screen first:
   - User type: **External**
   - App name: **Basin**
   - Scopes: Add `calendar`, `gmail.send`
   - Test users: Add your own email while in testing
4. Create OAuth client ID:
   - Application type: **iOS** (yes, even for macOS — this gives you a client ID without a secret, which is correct for native apps with PKCE)
   - Bundle ID: `com.kitlangton.Hex (Basin's current bundle ID)`
5. Copy the **Client ID**

**Scopes used:**
- `https://www.googleapis.com/auth/calendar`
- `https://www.googleapis.com/auth/gmail.send`

**Notes:**
- Google supports PKCE — no client secret needed for native apps.
- The app will be in "testing" mode initially (limited to 100 test users). For production, submit for Google's verification review.

---

## 3. Atlassian (Jira)

**Console:** https://developer.atlassian.com/console/myapps/

1. Click "Create" > "OAuth 2.0 integration"
2. Name: **Basin**
3. Under Authorization:
   - Callback URL: `basin://oauth/callback`
4. Under Permissions:
   - Add **Jira API** > Configure:
     - `read:jira-work`
     - `write:jira-work`
     - `read:jira-user`
   - Add `offline_access` scope (for refresh tokens)
5. Under Settings:
   - Copy the **Client ID**

**Scopes used:** `read:jira-work`, `write:jira-work`, `read:jira-user`, `offline_access`

**Notes:**
- Atlassian supports PKCE (required for public clients).
- No client secret needed.
- The `audience` parameter must be `api.atlassian.com` (Basin handles this automatically).
- After auth, Basin needs to call `https://api.atlassian.com/oauth/token/accessible-resources` to get the cloud ID for API calls.

---

## 4. Slack

**Console:** https://api.slack.com/apps

1. Click "Create New App" > "From scratch"
2. App name: **Basin**, pick your workspace
3. Under OAuth & Permissions:
   - Redirect URLs: Add `basin://oauth/callback`
   - Bot Token Scopes: Add `chat:write`, `channels:read`, `users:read`
4. Under Basic Information:
   - Copy the **Client ID** and **Client Secret**
5. Install to Workspace (for testing)

**Scopes used:** `chat:write`, `channels:read`, `users:read`

**Notes:**
- Slack doesn't support PKCE — client secret is required.
- The token you get back is a bot token (`xoxb-...`).

---

## Where to put the Client IDs

Once registered, the client IDs need to be set in `OAuthProviderConfig` in `Hex/Clients/OAuthClient.swift`. In production, these will ship bundled in the app. Client secrets that are required (GitHub, Slack) should be stored securely — either in the Keychain at build time or fetched from a lightweight token-exchange proxy.

For development/testing, you can hardcode them temporarily in the config structs.
