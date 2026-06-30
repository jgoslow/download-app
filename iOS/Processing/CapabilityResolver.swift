//
//  CapabilityResolver.swift
//  Basn iOS
//
//  Maps the generic capability vocabulary <-> concrete tools, using the
//  declarative `capability` tags in the tool-definition JSON. Lets routing reason
//  over a small fixed vocabulary while resolving to whatever tool provides it.
//  Resolution is deliberately simple for v1 (any connected provider); a per-flow
//  tool preference can slot in here later without changing callers.
//

import Foundation

enum CapabilityResolver {

    /// All tool IDs whose definition declares an action providing this capability.
    static func providers(for capabilityID: String) -> [String] {
        ToolDefinitionLoader.loadAll()
            .filter { spec in spec.actions.values.contains { $0.capability == capabilityID } }
            .map(\.id)
            .sorted()
    }

    /// Capabilities covered by the given connected tools (so the router can skip
    /// the generic function for these and use the tool's real schema instead).
    static func coveredCapabilities(connectedToolIDs: Set<String>) -> Set<String> {
        var covered = Set<String>()
        for spec in ToolDefinitionLoader.loadAll() where connectedToolIDs.contains(spec.id) {
            for action in spec.actions.values {
                if let c = action.capability { covered.insert(c) }
            }
        }
        return covered
    }

    /// Connected tools that provide a capability (resolution candidates).
    static func connectedProviders(for capabilityID: String, connectedToolIDs: Set<String>) -> [String] {
        providers(for: capabilityID).filter { connectedToolIDs.contains($0) }
    }

    /// The capability a specific tool action provides (for deduping suggestions
    /// against already-planned tool-scoped actions).
    static func capability(forToolID toolID: String, actionType: String) -> String? {
        ToolDefinitionLoader.load(toolID)?.actions[actionType]?.capability
    }
}
