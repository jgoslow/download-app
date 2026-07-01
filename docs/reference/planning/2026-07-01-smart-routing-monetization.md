# Smart Routing — Monetization & Multi-Provider Architecture

**Status:** Planning only — no implementation yet  
**Context:** Discussed 2026-07-01 after shipping the initial LightweightRouter (Claude Haiku, user's own Anthropic key)

## Business Model Options

Smart Routing (cloud-backed intent classification for devices without Apple Intelligence) will be offered via one of:

1. **Subscription upsell** — Basn manages the API key pool; the feature is gated behind a paid tier. User sees a paywall if they try to enable it without a subscription.
2. **BYO API key** — User provides their own key for a supported LLM provider. Already implemented for Anthropic (Claude Haiku). Needs to be extended to additional providers (see below).

These two paths may coexist: subscription for zero-setup, BYO key for power users.

## Multi-Provider Support (BYO Key)

The current `LightweightRouter` is hardcoded to the Anthropic Messages API + Claude Haiku. When extending to multiple providers, the settings UI should allow selecting a provider + entering the corresponding API key. Minimum provider set to consider:

| Provider | Suggested model | Notes |
|---|---|---|
| Anthropic | claude-haiku-4-5 | Already implemented |
| OpenAI | gpt-4o-mini | Widely held keys, very cheap |
| Google | gemini-flash-1.5 | Strong multilingual, free tier |
| Groq | llama-3-8b-instant | Very fast, generous free tier |

The LightweightRouter API call should be factored behind a thin provider-adapter interface so new providers can be added without touching the routing logic.

## Custom Server Endpoint (Hook URL)

An alternative path that doesn't require Basn to manage any provider integrations: the user configures a **hook URL** — an HTTP endpoint they control (their own server, a Cloudflare Worker, a Make/Zapier webhook, etc.).

Flow:
1. After transcription, Basn POSTs the transcript (text only) to the hook URL
2. The endpoint processes it (runs its own LLM call, applies its own logic) and returns a `PlannedAction[]` JSON response
3. Basn uses that response as the routing result, same as if it came from LightweightRouter

This makes Basn the client of any routing backend — users can run their own models, apply enterprise rules, or integrate with internal systems.

Response contract the hook URL must return:
```json
{
  "actions": [
    {
      "toolID": "apple-calendar",
      "actionType": "create_event",
      "label": "Review journals",
      "parameters": {
        "title": "Review journals",
        "start_time": "2026-07-02T15:00:00-05:00",
        "end_time": "2026-07-02T17:00:00-05:00"
      }
    }
  ],
  "modelUsed": "my-custom-model"
}
```

The existing `serverURL` + `authToken` settings fields in `IOSAppSettings` may serve as the hook URL mechanism, or a separate dedicated field should be added to avoid confusion with the existing transcript-save server.

## What to Build When Ready

- Factor `LightweightRouter` API call behind a `RoutingProviderAdapter` protocol
- Add provider selection UI to Settings → AI & Server
- Add hook URL field (distinct from transcript save server URL)
- Subscription gate: check entitlement before enabling if Basn-managed key is used
- Privacy disclosure sheet should update dynamically based on selected provider
