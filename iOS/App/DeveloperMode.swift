//
//  DeveloperMode.swift
//  Basn iOS
//
//  Hidden "Developer mode" unlock. Ships in every build but stays locked and
//  invisible until someone who knows the easter egg unlocks it:
//    Settings → About → tap the version row 7× → enter the passphrase.
//
//  Once unlocked, a Developer section appears in Settings exposing the capture
//  archive toggle (so debug captures work on a real device / TestFlight without
//  a #if DEBUG build). The unlock state persists in UserDefaults.
//

import Foundation

enum DeveloperMode {

    static let unlockedKey = "BasnDeveloperUnlocked"

    /// Number of taps on the version row that reveals the passphrase prompt.
    static let tapsToReveal = 7

    /// CHANGE THIS to your own secret before committing/shipping. Keep it
    /// non-obvious — anyone reading the binary's strings could find it, so this
    /// is obscurity, not security. Comparison is case-insensitive, trimmed.
    static let unlockPhrase = "open the basn"

    static var isUnlocked: Bool {
        get { UserDefaults.standard.bool(forKey: unlockedKey) }
        set { UserDefaults.standard.set(newValue, forKey: unlockedKey) }
    }

    /// Returns true (and unlocks) if `phrase` matches.
    @discardableResult
    static func tryUnlock(_ phrase: String) -> Bool {
        let normalized = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == unlockPhrase.lowercased() else { return false }
        isUnlocked = true
        return true
    }

    static func lock() {
        isUnlocked = false
    }
}
