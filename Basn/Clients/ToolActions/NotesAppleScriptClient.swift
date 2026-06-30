import Foundation
import BasinShared
import os
#if os(iOS)
import UIKit
#endif

private let log = Logger(subsystem: "com.lyra.basn", category: "notes")

/// Creates notes in Apple Notes.
///
/// - macOS: NSAppleScript — silently creates the note in the background, no interaction needed.
/// - iOS: UIActivityViewController share sheet — presents a share sheet so the user can tap
///   "Notes" to save. This IS interactive; the user sees a modal and picks the app.
///   It's the only way to get content into Notes on iOS without a 3rd-party API.
enum NotesAppleScriptClient {

    static func execute(action: PlannedAction, handler: String) async -> ActionResult {
        switch handler {
        case "applescript_notes_create":
            return await createNote(action: action)
        default:
            return ActionResult(actionID: action.id, success: false, error: "Unknown Notes handler: \(handler)")
        }
    }

    private static func createNote(action: PlannedAction) async -> ActionResult {
        let params = action.parameters
        guard let title = params["title"] as? String, !title.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "Note title is required")
        }
        guard let body = params["body"] as? String, !body.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "Note body is required")
        }
        let folder = params["folder"] as? String

        #if os(macOS)
        return await createNoteAppleScript(title: title, body: body, folder: folder, actionID: action.id)
        #else
        return await createNoteShareSheet(title: title, body: body, actionID: action.id)
        #endif
    }

    // MARK: - macOS: AppleScript (silent, no interaction)

    #if os(macOS)
    private static func createNoteAppleScript(
        title: String, body: String, folder: String?, actionID: String
    ) async -> ActionResult {
        let escapedTitle  = escaped(title)
        let escapedBody   = escaped(body)

        let script: String
        if let folder {
            let escapedFolder = escaped(folder)
            script = """
            tell application "Notes"
                if not (exists folder "\(escapedFolder)") then
                    make new folder with properties {name:"\(escapedFolder)"}
                end if
                tell folder "\(escapedFolder)"
                    make new note with properties {name:"\(escapedTitle)", body:"<div><h1>\(escapedTitle)</h1><p>\(escapedBody)</p></div>"}
                end tell
            end tell
            """
        } else {
            script = """
            tell application "Notes"
                make new note with properties {name:"\(escapedTitle)", body:"<div><h1>\(escapedTitle)</h1><p>\(escapedBody)</p></div>"}
            end tell
            """
        }

        return await Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            appleScript?.executeAndReturnError(&error)

            if let error {
                let message = (error[NSAppleScript.errorMessage] as? String) ?? "AppleScript failed"
                log.error("Notes AppleScript error: \(message)")
                return ActionResult(actionID: actionID, success: false, error: message)
            }

            log.info("Notes AppleScript: created '\(title)'")
            return ActionResult(actionID: actionID, success: true, message: "Note '\(title)' created in Apple Notes")
        }.value
    }

    private static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
    #endif

    // MARK: - iOS: Share Sheet (interactive)

    #if os(iOS)
    @MainActor
    private static func createNoteShareSheet(
        title: String, body: String, actionID: String
    ) async -> ActionResult {
        // Compose a single string that Notes will use as the note body.
        // The first line becomes the note title in Notes.
        let shareText = "\(title)\n\n\(body)"

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return ActionResult(
                actionID: actionID,
                success: false,
                error: "Could not present share sheet — bring Basn to the foreground and try again."
            )
        }

        // Find the topmost presented controller so we don't try to present over a modal
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        return await withCheckedContinuation { continuation in
            let activity = UIActivityViewController(
                activityItems: [shareText],
                applicationActivities: nil
            )
            // Hide activities that aren't useful for note-taking
            activity.excludedActivityTypes = [
                .airDrop, .postToFacebook, .postToTwitter, .postToWeibo,
                .message, .mail, .print, .copyToPasteboard, .assignToContact,
                .saveToCameraRoll, .addToReadingList, .postToFlickr,
                .postToVimeo, .postToTencentWeibo, .openInIBooks,
                .markupAsPDF
            ]
            activity.completionWithItemsHandler = { activityType, completed, _, error in
                if let error {
                    log.error("Share sheet error: \(error.localizedDescription)")
                    continuation.resume(returning: ActionResult(
                        actionID: actionID, success: false, error: error.localizedDescription
                    ))
                } else if completed {
                    log.info("Note shared via \(activityType?.rawValue ?? "unknown")")
                    continuation.resume(returning: ActionResult(
                        actionID: actionID, success: true,
                        message: "Note '\(title)' saved via share sheet"
                    ))
                } else {
                    // User dismissed without completing
                    continuation.resume(returning: ActionResult(
                        actionID: actionID, success: false,
                        error: "Share cancelled — note not saved"
                    ))
                }
            }
            presenter.present(activity, animated: true)
        }
    }
    #endif
}
