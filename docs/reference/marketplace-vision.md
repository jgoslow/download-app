---
name: Tool marketplace and extensibility vision
description: Custom tools via endpoint/MCP config, user-built channels, potential marketplace with IAP pricing
type: project
---

Basin's tool/channel system should be extensible and modular:

**Custom tools:** Users can define their own tools by providing an endpoint URL, required tokens (with setup instructions), object structure, and prompt actions. Could also be an MCP server with auth. This makes Basin a platform, not just an app.

**Why:** The core value users pay for is the flow/capture/ritual experience. Tools and channels are modular — people should be able to build bespoke workflows on top of Basin. Jonas values building things others can be creative with.

**Marketplace vision:**
- Registry where people publish tools they've built
- In-app purchases for premium/third-party tools
- Basin's revenue comes from the capture experience + marketplace cut
- Similar to how Shortcuts or Zapier let users compose automations, but voice-first

**How to apply:** When designing the Tool and Channel models, keep extensibility in mind. The current `Tool` model already has `authType`, `authToken`, `authMetadata`, `baseURL` — this is the foundation for custom tool definitions. Future additions: prompt action descriptions, object schema (JSON), MCP server URL, marketplace ID, pricing tier.
