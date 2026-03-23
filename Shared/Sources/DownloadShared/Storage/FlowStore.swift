import Foundation
import Logging

private let logger = Logger(label: "com.download.type-store")

/// Loads Flow definitions from the bundled `download-types.json` file.
///
/// The JSON file is generated from `context/download-types/*.md` in the jonas-pathways repo
/// via an export script. No app update needed to change or add session types — re-export
/// and the app picks up changes on next launch.
///
/// Fallback: if the file is missing or unreadable, returns `[.openDefault]` so the app
/// always has at least one usable type.
public struct FlowStore: Sendable {
    public var loadAll: @Sendable () async -> [Flow]

    public init(loadAll: @escaping @Sendable () async -> [Flow]) {
        self.loadAll = loadAll
    }
}

extension FlowStore {
    public static func live(bundle: Bundle = .main) -> FlowStore {
        .init(loadAll: {
            // Look for the JSON file in Application Support first (user-updated copy),
            // then fall back to the bundled copy.
            if let userFile = userFlowsURL(),
               let types = try? loadFromURL(userFile), !types.isEmpty {
                logger.debug("Loaded \(types.count) download types from Application Support")
                return ensureOpenPresent(types)
            }
            if let bundledURL = bundle.url(forResource: "download-types", withExtension: "json"),
               let types = try? loadFromURL(bundledURL), !types.isEmpty {
                logger.debug("Loaded \(types.count) download types from bundle")
                return ensureOpenPresent(types)
            }
            logger.warning("No download-types.json found — falling back to Open only")
            return [.openDefault]
        })
    }

    private static func loadFromURL(_ url: URL) throws -> [Flow] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([Flow].self, from: data)
    }

    private static func userFlowsURL() -> URL? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }
        return appSupport.appendingPathComponent("Download/download-types.json")
    }

    /// Guarantee "open" is always the first entry, even if the JSON omits it.
    private static func ensureOpenPresent(_ types: [Flow]) -> [Flow] {
        if types.contains(where: { $0.id == Flow.openID }) { return types }
        return [.openDefault] + types
    }
}
