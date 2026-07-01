import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.lyra.basn", category: "tool-builder")

// MARK: - Client interface

struct ToolBuilderClient {
    /// Ask Claude to generate a tool definition JSON from a natural-language description.
    /// Returns the raw JSON string on success.
    var generate: @Sendable (_ description: String, _ apiKey: String) async throws -> String
}

// MARK: - Live implementation

extension ToolBuilderClient: DependencyKey {

    static let liveValue = ToolBuilderClient(
        generate: { description, apiKey in
            guard !apiKey.isEmpty else { throw ToolBuilderError.noAPIKey }
            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                throw ToolBuilderError.invalidURL
            }

            let requestBody: [String: Any] = [
                "model": "claude-sonnet-4-6",
                "max_tokens": 2048,
                "system": systemPrompt,
                "messages": [
                    ["role": "user", "content": "Generate a tool definition for: \(description)"]
                ]
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            request.timeoutInterval = 45

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw ToolBuilderError.invalidResponse
            }
            guard http.statusCode == 200 else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                log.error("Anthropic error \(http.statusCode): \(preview)")
                if http.statusCode == 401 {
                    throw ToolBuilderError.unauthorized
                }
                throw ToolBuilderError.serverError(http.statusCode, preview)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String
            else {
                throw ToolBuilderError.malformedResponse
            }

            // Strip markdown fences if Claude wrapped the JSON
            let cleaned = stripMarkdownFences(text)
            log.info("Tool definition generated (\(cleaned.count) chars)")
            return cleaned
        }
    )

    // Remove ```json ... ``` fences that Claude sometimes adds
    private static func stripMarkdownFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum ToolBuilderError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int, String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key configured. Add one in Settings → AI & Server."
        case .invalidURL, .invalidResponse:
            return "Unexpected response from the AI service."
        case .unauthorized:
            return "Invalid Anthropic API key. Check Settings → AI & Server."
        case .serverError(let code, _):
            return "AI service returned error \(code). Try again."
        case .malformedResponse:
            return "Could not parse the AI response. Try rephrasing the description."
        }
    }
}

// MARK: - Test value

extension ToolBuilderClient: TestDependencyKey {
    static let testValue = ToolBuilderClient(
        generate: { _, _ in
            """
            {"id":"test-tool","name":"Test","icon":"wrench","auth":{"methods":["api_key"],
            "api_key_label":"API Key","api_key_format":"bearer"},
            "base_url":{"api_key":"https://api.example.com/v1"},
            "health_check":{"endpoint":"{base_url}/me","method":"GET"},
            "actions":{"create_item":{"display_name":"Create Item",
            "description":"Creates an item","endpoint":"{base_url}/items","method":"POST",
            "parameters":{"title":{"type":"string","required":true,"description":"Title"}},
            "success_message":"Created","capability":"create_task"}},
            "workflows":{"create-task":"create_item"},
            "claude_context":{"defaults":{}}}
            """
        }
    )
}

extension DependencyValues {
    var toolBuilderClient: ToolBuilderClient {
        get { self[ToolBuilderClient.self] }
        set { self[ToolBuilderClient.self] = newValue }
    }
}

// MARK: - System prompt

private let systemPrompt = """
You are a tool definition generator for Basn, a macOS/iOS voice capture app. Your job is to \
generate a valid JSON tool definition that connects Basn to an external service via its REST API.

The JSON must follow this exact schema (only include fields that apply):

{
  "id": "service_name",
  "name": "Service Display Name",
  "icon": "sf_symbol_name",
  "auth": {
    "methods": ["api_key"],
    "api_key_label": "API Key",
    "api_key_format": "bearer",
    "api_key_help": "Where to find the key, with URL"
  },
  "base_url": {
    "api_key": "https://api.example.com/v1"
  },
  "health_check": {
    "endpoint": "{base_url}/me",
    "method": "GET"
  },
  "actions": {
    "action_id": {
      "display_name": "Human Label",
      "description": "What this action does",
      "endpoint": "{base_url}/resources",
      "method": "POST",
      "headers": { "Content-Type": "application/json" },
      "body_template": {
        "title": "{title}",
        "body": "{body}"
      },
      "parameters": {
        "title": {
          "type": "string",
          "required": true,
          "description": "The item title"
        }
      },
      "success_message": "Created: {title}",
      "capability": "create_task"
    }
  },
  "workflows": {
    "create-task": "action_id"
  },
  "claude_context": {
    "defaults": {}
  }
}

RULES:
- id: lowercase snake_case, no spaces (e.g. "notion", "linear", "airtable")
- icon: must be a real SF Symbols name (e.g. "doc.text", "checkmark.circle", "calendar", "envelope", "clock", "person.circle", "link", "tag", "briefcase")
- auth.methods: ["api_key"], ["oauth"], or ["oauth", "api_key"]
- api_key_format: "bearer" (Authorization: Bearer KEY), "basic" (Authorization: Basic base64(KEY)), or "basic_token_only" (Authorization: Basic base64(KEY:api_token))
- Endpoint parameters use {param_name} placeholders; {base_url} is always available
- Body template values must have matching parameter entries
- capability options: log_time, create_task, schedule_event, send_message, capture_note, send_email, create_document
- workflows maps workflow IDs to action IDs
- Return ONLY valid JSON — no markdown code fences, no explanation, no comments
"""
