//
//  ToolDefinitionLoader.swift
//  Basin
//
//  Loads declarative tool definitions from bundled JSON files.
//  Each definition describes: auth, endpoints, discovery, actions, and Claude context.
//  This replaces per-integration Swift files with a data-driven approach.
//

import Foundation
import os
#if canImport(BasnCore)
import BasnCore
private let loaderLogger = BasnLog.app
#else
private let loaderLogger = Logger(subsystem: "com.lyra.basn", category: "tool-loader")
#endif

/// A parsed tool definition from JSON.
struct ToolDefinitionSpec: Codable {
    let id: String
    let name: String
    let icon: String
    let auth: AuthSpec
    let baseUrl: BaseURLSpec?
    let discovery: [String: DiscoverySpec]?
    let actions: [String: ActionSpec]
    /// Maps workflow IDs to the action this tool uses to execute them.
    /// e.g. {"create-event": "create_event", "write-email": "send_email"}
    let workflows: [String: String]?
    let claudeContext: ClaudeContextSpec?
    /// Lightweight endpoint used by "Verify connection" in Settings → Tools.
    let healthCheck: HealthCheckSpec?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, auth, discovery, actions, workflows
        case baseUrl = "base_url"
        case claudeContext = "claude_context"
        case healthCheck = "health_check"
    }

    struct HealthCheckSpec: Codable {
        let endpoint: String
        let method: String
    }

    struct AuthSpec: Codable {
        let methods: [String]
        let oauthProvider: String?
        let apiKeyLabel: String?
        let apiKeyFormat: String?
        let apiKeyHelp: String?
        let scopesSelectable: Bool?
        let availableScopes: [String: ScopeSpec]?

        enum CodingKeys: String, CodingKey {
            case methods
            case oauthProvider = "oauth_provider"
            case apiKeyLabel = "api_key_label"
            case apiKeyFormat = "api_key_format"
            case apiKeyHelp = "api_key_help"
            case scopesSelectable = "scopes_selectable"
            case availableScopes = "available_scopes"
        }

        struct ScopeSpec: Codable {
            let label: String
            let scope: String
            let `default`: Bool?
        }
    }

    struct BaseURLSpec: Codable {
        let oauth: String?
        let apiKey: String?
        let requiresDiscovery: Bool?

        enum CodingKeys: String, CodingKey {
            case oauth
            case apiKey = "api_key"
            case requiresDiscovery = "requires_discovery"
        }
    }

    struct DiscoverySpec: Codable {
        let endpoint: String
        let method: String
        let extract: String
        let description: String
        let refreshIntervalHours: Int?
        let dependsOn: String?

        enum CodingKeys: String, CodingKey {
            case endpoint, method, extract, description
            case refreshIntervalHours = "refresh_interval_hours"
            case dependsOn = "depends_on"
        }
    }

    struct ActionSpec: Codable {
        let displayName: String
        let description: String
        let endpoint: String
        let method: String
        let headers: [String: String]?
        let bodyTemplate: AnyCodable?
        let specialHandler: String?
        let parameters: [String: ParameterSpec]
        let successExtract: String?
        let successMessage: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case description, endpoint, method, headers, parameters
            case bodyTemplate = "body_template"
            case specialHandler = "special_handler"
            case successExtract = "success_extract"
            case successMessage = "success_message"
        }
    }

    struct ParameterSpec: Codable {
        let type: String
        let required: Bool?
        let description: String
        let source: String?
        let `default`: String?
        let `enum`: [String]?
    }

    struct ClaudeContextSpec: Codable {
        let projectMatching: String?
        let defaults: [String: String]?

        enum CodingKeys: String, CodingKey {
            case projectMatching = "project_matching"
            case defaults
        }
    }
}

/// Simple wrapper for encoding/decoding arbitrary JSON values.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map(\.value)
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let num = value as? Double { try container.encode(num) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else { try container.encodeNil() }
    }
}

// MARK: - Loader

enum ToolDefinitionLoader {
    private static var cache: [String: ToolDefinitionSpec] = [:]

    /// Load all bundled tool definitions.
    static func loadAll() -> [ToolDefinitionSpec] {
        if !cache.isEmpty { return Array(cache.values) }

        guard let defDir = Bundle.main.url(forResource: "tool-definitions", withExtension: nil) else {
            // Try finding individual files
            var defs: [ToolDefinitionSpec] = []
            for name in ["jira", "slack", "toggl", "github", "calendar", "email", "wave"] {
                if let def = load(name) { defs.append(def) }
            }
            return defs
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: defDir, includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "json" }) else {
            return []
        }

        return files.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            return load(name)
        }
    }

    /// Load a specific tool definition by ID.
    static func load(_ toolID: String) -> ToolDefinitionSpec? {
        if let cached = cache[toolID] { return cached }

        // Try tool-definitions subdirectory first, then root Data
        let url = Bundle.main.url(forResource: toolID, withExtension: "json", subdirectory: "Data/tool-definitions")
            ?? Bundle.main.url(forResource: toolID, withExtension: "json")

        guard let url else {
            loaderLogger.debug("No tool definition found for \(toolID)")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let spec = try JSONDecoder().decode(ToolDefinitionSpec.self, from: data)
            cache[toolID] = spec
            loaderLogger.info("Loaded tool definition: \(spec.id) (\(spec.actions.count) actions)")
            return spec
        } catch {
            loaderLogger.error("Failed to parse tool definition \(toolID): \(error.localizedDescription)")
            return nil
        }
    }

    /// Build Claude tool_use schemas from a tool definition.
    /// Pass `tool` to filter out actions the user has disabled in Settings → Tools.
    static func claudeSchemas(for spec: ToolDefinitionSpec, tool: Tool? = nil) -> [[String: Any]] {
        let disabledKeys = Set(tool?.enabledActionKeys ?? [])
        return spec.actions
            .filter { disabledKeys.isEmpty || !disabledKeys.contains($0.key) }
            .map { actionType, action in
                var properties: [String: Any] = [:]
                var required: [String] = []

                for (paramName, param) in action.parameters {
                    var prop: [String: Any] = [
                        "type": param.type == "array" ? "array" : "string",
                        "description": param.description
                    ]
                    if let enumValues = param.enum {
                        prop["enum"] = enumValues
                    }
                    properties[paramName] = prop

                    if param.required == true {
                        required.append(paramName)
                    }
                }

                return [
                    "name": "\(spec.id)_\(actionType)",
                    "description": action.description,
                    "input_schema": [
                        "type": "object",
                        "properties": properties,
                        "required": required
                    ]
                ] as [String: Any]
            }
    }
}
