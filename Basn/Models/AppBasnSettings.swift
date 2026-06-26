import ComposableArchitecture
import Dependencies
import Foundation
import BasnCore

// Re-export types so the app target can use them without BasnCore prefixes.
typealias RecordingAudioBehavior = BasnCore.RecordingAudioBehavior
typealias BasnSettings = BasnCore.BasnSettings

extension SharedReaderKey
	where Self == FileStorageKey<BasnSettings>.Default
{
	static var basnSettings: Self {
		Self[
			.fileStorage(.basnSettingsURL),
			default: .init()
		]
	}
}

// MARK: - Storage Migration

extension URL {
	static var basnSettingsURL: URL {
		get {
			URL.basnMigratedFileURL(named: "hex_settings.json")
		}
	}
}
