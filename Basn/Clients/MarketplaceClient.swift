import ComposableArchitecture
import Foundation
import os
#if canImport(BasnCore)
import BasnCore
private let log = BasnLog.app
#else
private let log = Logger(subsystem: "com.lyra.basn", category: "marketplace")
#endif

// MARK: - Manifest types

struct MarketplaceManifest: Codable, Equatable {
    let version: String
    let updatedAt: String
    let defaultInstall: [String]
    let tools: [MarketplaceToolEntry]
    let categories: [MarketplaceCategory]

    enum CodingKeys: String, CodingKey {
        case version, tools, categories
        case updatedAt = "updated_at"
        case defaultInstall = "default_install"
    }
}

struct MarketplaceToolEntry: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let category: String
    let tags: [String]
    let author: String
    let verified: Bool
    let version: String
    let minimumBasnVersion: String
    let definitionUrl: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon, category, tags, author, verified, version
        case minimumBasnVersion = "minimum_basn_version"
        case definitionUrl = "definition_url"
        case updatedAt = "updated_at"
    }
}

struct MarketplaceCategory: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
}

// MARK: - Client interface

struct MarketplaceClient {
    /// Fetches the manifest; uses ETag/Last-Modified to avoid re-downloading unchanged data.
    var fetchManifest: @Sendable () async throws -> MarketplaceManifest
    /// Downloads a tool's definition JSON and writes it to InstalledTools/.
    var installTool: @Sendable (_ entry: MarketplaceToolEntry) async throws -> ToolDefinitionSpec
    /// Removes a marketplace-installed tool from InstalledTools/.
    var uninstallTool: @Sendable (_ toolID: String) async throws -> Void
    /// Returns IDs of installed marketplace tools that have newer versions available.
    var checkForUpdates: @Sendable () async throws -> [String]
}

// MARK: - Live implementation

extension MarketplaceClient: DependencyKey {
    static let liveValue = MarketplaceClient(
        fetchManifest: {
            let manifestURL = URL(string: "https://raw.githubusercontent.com/LyraDesigns/basn-marketplace/main/manifest.json")!
            let cacheDir = Self.cacheDirectory()
            let etagFile = cacheDir.appendingPathComponent("manifest.etag")
            let cachedFile = cacheDir.appendingPathComponent("manifest.json")

            var request = URLRequest(url: manifestURL)
            if let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse

            if http?.statusCode == 304, let cached = try? Data(contentsOf: cachedFile) {
                return try JSONDecoder().decode(MarketplaceManifest.self, from: cached)
            }

            if let etag = http?.value(forHTTPHeaderField: "ETag") {
                try? etag.write(to: etagFile, atomically: true, encoding: .utf8)
            }
            try? data.write(to: cachedFile, options: .atomic)
            return try JSONDecoder().decode(MarketplaceManifest.self, from: data)
        },

        installTool: { entry in
            let defURL = URL(string: entry.definitionUrl)!
            let (data, _) = try await URLSession.shared.data(from: defURL)
            let spec = try JSONDecoder().decode(ToolDefinitionSpec.self, from: data)

            let installDir = Self.installedToolsDirectory()
            try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
            let dest = installDir.appendingPathComponent("\(entry.id).json")
            try data.write(to: dest, options: .atomic)

            log.info("Installed marketplace tool: \(entry.id) v\(entry.version)")
            return spec
        },

        uninstallTool: { toolID in
            let dest = Self.installedToolsDirectory().appendingPathComponent("\(toolID).json")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
                log.info("Uninstalled marketplace tool: \(toolID)")
            }
        },

        checkForUpdates: {
            let installDir = Self.installedToolsDirectory()
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: installDir, includingPropertiesForKeys: nil
            ).filter({ $0.pathExtension == "json" }) else {
                return []
            }

            // Load manifest to compare versions
            let manifestURL = URL(string: "https://raw.githubusercontent.com/LyraDesigns/basn-marketplace/main/manifest.json")!
            let (data, _) = try await URLSession.shared.data(from: manifestURL)
            let manifest = try JSONDecoder().decode(MarketplaceManifest.self, from: data)
            let latestByID = Dictionary(uniqueKeysWithValues: manifest.tools.map { ($0.id, $0.version) })

            return files.compactMap { file -> String? in
                let toolID = file.deletingPathExtension().lastPathComponent
                guard let specData = try? Data(contentsOf: file),
                      let spec = try? JSONDecoder().decode(ToolDefinitionSpec.self, from: specData),
                      let installedVersion = spec.registry?.version,
                      let latestVersion = latestByID[toolID],
                      latestVersion > installedVersion
                else { return nil }
                return toolID
            }
        }
    )

    // MARK: - Paths

    static func installedToolsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.lyra.basn/InstalledTools", isDirectory: true)
    }

    static func cacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("com.lyra.basn/Marketplace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Test / preview value

extension MarketplaceClient: TestDependencyKey {
    static let testValue = MarketplaceClient(
        fetchManifest: { MarketplaceManifest(version: "1", updatedAt: "", defaultInstall: [], tools: [], categories: []) },
        installTool: { _ in fatalError("unimplemented") },
        uninstallTool: { _ in },
        checkForUpdates: { [] }
    )
}

extension DependencyValues {
    var marketplaceClient: MarketplaceClient {
        get { self[MarketplaceClient.self] }
        set { self[MarketplaceClient.self] = newValue }
    }
}
