import Foundation
import Logging

private let logger = Logger(label: "com.download.session-store")

/// Reads and writes Session JSON files to the local sessions directory.
///
/// Each session is a separate `<id>.json` file. The store does not hold an in-memory list —
/// the UI reads the list from disk on demand. This keeps the store simple and crash-safe.
public struct SessionStore: Sendable {
    public var save: @Sendable (Session) async throws -> Void
    public var loadAll: @Sendable () async throws -> [Session]
    public var delete: @Sendable (String) async throws -> Void  // by session id

    public init(
        save: @escaping @Sendable (Session) async throws -> Void,
        loadAll: @escaping @Sendable () async throws -> [Session],
        delete: @escaping @Sendable (String) async throws -> Void
    ) {
        self.save = save
        self.loadAll = loadAll
        self.delete = delete
    }
}

extension SessionStore {
    public static let live: SessionStore = .init(
        save: { session in
            let dir = try sessionsDirectory()
            let fileURL = dir.appendingPathComponent("\(session.id).json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
            logger.debug("Saved session \(session.id)")
        },
        loadAll: {
            let dir = try sessionsDirectory()
            let files = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ).filter { $0.pathExtension == "json" }
                .sorted { a, b in
                    let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return aDate > bDate  // newest first
                }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return files.compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let session = try? decoder.decode(Session.self, from: data) else {
                    logger.warning("Failed to decode session at \(url.lastPathComponent)")
                    return nil
                }
                return session
            }
        },
        delete: { id in
            let dir = try sessionsDirectory()
            let fileURL = dir.appendingPathComponent("\(id).json")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                logger.debug("Deleted session \(id)")
            }
        }
    )

    private static func sessionsDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Download/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
