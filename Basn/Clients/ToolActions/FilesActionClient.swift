import Foundation
import BasinShared
import os

private let log = Logger(subsystem: "com.lyra.basn", category: "files")

/// Saves text files to iCloud Drive (or local Documents folder if iCloud isn't available).
enum FilesActionClient {

    static func execute(action: PlannedAction, handler: String) async -> ActionResult {
        switch handler {
        case "files_save_text":
            return await saveText(action: action)
        default:
            return ActionResult(actionID: action.id, success: false, error: "Unknown Files handler: \(handler)")
        }
    }

    private static func saveText(action: PlannedAction) async -> ActionResult {
        let params = action.parameters
        guard let filename = params["filename"] as? String, !filename.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "filename is required")
        }
        guard let content = params["content"] as? String else {
            return ActionResult(actionID: action.id, success: false, error: "content is required")
        }

        let subfolder = params["folder"] as? String ?? "Basn"
        let baseURL = iCloudDriveURL() ?? localDocumentsURL()

        let folderURL = baseURL.appendingPathComponent(subfolder, isDirectory: true)
        let fileURL   = folderURL.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            log.info("Saved file: \(fileURL.path)")
            return ActionResult(
                actionID: action.id,
                success: true,
                message: "'\(filename)' saved to \(subfolder)/"
            )
        } catch {
            log.error("Failed to save file: \(error.localizedDescription)")
            return ActionResult(actionID: action.id, success: false, error: error.localizedDescription)
        }
    }

    // MARK: - Path resolution

    private static func iCloudDriveURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    private static func localDocumentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
