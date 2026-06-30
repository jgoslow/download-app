import Foundation
import SwiftData
import os
#if canImport(BasnCore)
import BasnCore
private let log = BasnLog.app
#else
private let log = Logger(subsystem: "com.lyra.basn", category: "marketplace-seeder")
#endif

/// Runs once after first launch to install the marketplace's `default_install` tools.
///
/// Bundled tool definitions are shipped with the app for the 5 core integrations.
/// The seeder's job is to register those tools in SwiftData (so they appear in Settings → Tools)
/// and, on subsequent launches, silently update any installed marketplace tool that has a
/// newer version available in the registry.
enum MarketplaceSeeder {
    private static let seededKey = "BasnMarketplaceSeeded"

    /// Call this once during app startup (after the model container is ready).
    @MainActor
    static func seedIfNeeded(modelContext: ModelContext) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }

        log.info("Running marketplace first-launch seed")

        do {
            // Fetch the manifest — this tells us which tools to install by default
            let manifestURL = URL(string: "https://raw.githubusercontent.com/LyraDesigns/basn-marketplace/main/manifest.json")!
            let (data, _) = try await URLSession.shared.data(from: manifestURL)
            let manifest = try JSONDecoder().decode(MarketplaceManifest.self, from: data)

            // Existing tools in SwiftData — skip IDs already present
            let existingDescriptor = FetchDescriptor<Tool>()
            let existingTools = (try? modelContext.fetch(existingDescriptor)) ?? []
            let existingIDs = Set(existingTools.map(\.id))

            // Install bundled defaults for any default_install tool not already in the store
            for toolID in manifest.defaultInstall where !existingIDs.contains(toolID) {
                let entry = manifest.tools.first(where: { $0.id == toolID })
                if let spec = ToolDefinitionLoader.load(toolID) {
                    let tool = Tool(
                        id: spec.id,
                        name: spec.name,
                        iconSystemName: spec.icon,
                        activeAuthMethod: spec.auth.methods.first,
                        supportsOAuth: spec.auth.methods.contains("oauth"),
                        supportsAPIKey: spec.auth.methods.contains("api_key"),
                        apiKeyLabel: spec.auth.apiKeyLabel,
                        installedFromMarketplace: false,
                        marketplaceVersion: entry?.version,
                        marketplaceSource: entry.map { $0.verified ? "verified" : "community" }
                    )
                    modelContext.insert(tool)
                    log.info("Seeded tool: \(toolID)")
                }
            }

            try? modelContext.save()
            defaults.set(true, forKey: seededKey)
            log.info("Marketplace seed complete")
        } catch {
            // Non-fatal: bundled defaults already work, seeder runs again next launch
            log.error("Marketplace seed failed: \(error.localizedDescription)")
        }
    }

    /// Re-seed — wipes the seeded flag so the next launch seeds again. Debug only.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: seededKey)
    }
}
