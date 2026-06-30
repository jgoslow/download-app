#if os(macOS)
import Foundation
import BasinShared
import os

private let log = Logger(subsystem: "com.lyra.basn", category: "notes-applescript")

/// Creates notes in Apple Notes via AppleScript.
/// macOS only — AppleScript is not available on iOS.
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

        let escapedTitle  = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody   = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let script: String
        if let folder {
            let escapedFolder = folder.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
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

        return await runAppleScript(script, actionID: action.id, success: "Note '\(title)' created in Apple Notes")
    }

    // MARK: - AppleScript runner

    private static func runAppleScript(_ source: String, actionID: String, success: String) async -> ActionResult {
        return await Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: source)
            let result = appleScript?.executeAndReturnError(&error)

            if let error {
                let message = (error[NSAppleScript.errorMessage] as? String) ?? "AppleScript failed"
                log.error("AppleScript error: \(message)")
                return ActionResult(actionID: actionID, success: false, error: message)
            }

            log.info("AppleScript succeeded: \(result?.stringValue ?? "(no result)")")
            return ActionResult(actionID: actionID, success: true, message: success)
        }.value
    }
}
#endif
