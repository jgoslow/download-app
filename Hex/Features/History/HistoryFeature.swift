import AVFoundation
import AppKit
import ComposableArchitecture
import Dependencies
import HexCore
import Inject
import SwiftData
import SwiftUI

private let historyLogger = HexLog.history

// MARK: - Date Extensions

extension Date {
	func relativeFormatted() -> String {
		let calendar = Calendar.current
		let now = Date()

		if calendar.isDateInToday(self) {
			return "Today"
		} else if calendar.isDateInYesterday(self) {
			return "Yesterday"
		} else if let daysAgo = calendar.dateComponents([.day], from: self, to: now).day, daysAgo < 7 {
			let formatter = DateFormatter()
			formatter.dateFormat = "EEEE" // Day of week
			return formatter.string(from: self)
		} else {
			let formatter = DateFormatter()
			formatter.dateStyle = .medium
			formatter.timeStyle = .none
			return formatter.string(from: self)
		}
	}
}

// MARK: - Legacy Storage (kept for migration reads)

extension SharedReaderKey
	where Self == FileStorageKey<TranscriptionHistory>.Default
{
	static var transcriptionHistory: Self {
		Self[
			.fileStorage(.transcriptionHistoryURL),
			default: .init()
		]
	}
}

extension URL {
	static var transcriptionHistoryURL: URL {
		get {
			URL.hexMigratedFileURL(named: "transcription_history.json")
		}
	}
}

// MARK: - Audio Player

class AudioPlayerController: NSObject, AVAudioPlayerDelegate {
	private var player: AVAudioPlayer?
	var onPlaybackFinished: (() -> Void)?

	func play(url: URL) throws -> AVAudioPlayer {
		let player = try AVAudioPlayer(contentsOf: url)
		player.delegate = self
		player.play()
		self.player = player
		return player
	}

	func stop() {
		player?.stop()
		player = nil
	}

	func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
		self.player = nil
		Task { @MainActor in
			onPlaybackFinished?()
		}
	}
}

// MARK: - History Feature

@Reducer
struct HistoryFeature {
	@ObservableState
	struct State: Equatable {
		// Legacy — kept for backward compat during transition
		@Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
		var playingCaptureID: String?
		var audioPlayer: AVAudioPlayer?
		var audioPlayerController: AudioPlayerController?

		mutating func stopAudioPlayback() {
			audioPlayerController?.stop()
			audioPlayer = nil
			audioPlayerController = nil
			playingCaptureID = nil
		}
	}

	enum Action {
		case playCapture(String, audioPath: String?)
		case stopPlayback
		case copyToClipboard(String)
		case deleteCapture(String)
		case deleteAllCaptures
		case confirmDeleteAll
		case playbackFinished
		case navigateToSettings
	}

	@Dependency(\.pasteboard) var pasteboard
	@Dependency(\.modelContext) var basinDB

	var body: some ReducerOf<Self> {
		Reduce { state, action in
			switch action {
			case let .playCapture(id, audioPath):
				if state.playingCaptureID == id {
					state.stopAudioPlayback()
					return .none
				}

				state.stopAudioPlayback()

				guard let audioPath else { return .none }
				let url = URL(fileURLWithPath: audioPath)

				do {
					let controller = AudioPlayerController()
					let player = try controller.play(url: url)

					state.audioPlayer = player
					state.audioPlayerController = controller
					state.playingCaptureID = id

					return .run { send in
						await withCheckedContinuation { continuation in
							controller.onPlaybackFinished = {
								continuation.resume()
								Task { @MainActor in
									send(.playbackFinished)
								}
							}
						}
					}
				} catch {
					historyLogger.error("Failed to play audio: \(error.localizedDescription)")
					return .none
				}

			case .stopPlayback, .playbackFinished:
				state.stopAudioPlayback()
				return .none

			case let .copyToClipboard(text):
				return .run { [pasteboard] _ in
					await pasteboard.copy(text)
				}

			case let .deleteCapture(id):
				if state.playingCaptureID == id {
					state.stopAudioPlayback()
				}

				return .run { _ in
					try await basinDB.deleteCapture(id)
					historyLogger.info("Deleted capture \(id)")
				}

			case .deleteAllCaptures:
				return .send(.confirmDeleteAll)

			case .confirmDeleteAll:
				state.stopAudioPlayback()

				return .run { _ in
					let captures = try await basinDB.fetchCaptures(nil)
					for capture in captures {
						try await basinDB.deleteCapture(capture.id)
					}
					historyLogger.info("Deleted all captures")
				}

			case .navigateToSettings:
				return .none
			}
		}
	}
}

// MARK: - Capture Row View

struct CaptureRowView: View {
	let capture: CaptureRecord
	let isPlaying: Bool
	let onPlay: () -> Void
	let onCopy: () -> Void
	let onDelete: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(capture.rawText)
				.font(.body)
				.lineLimit(nil)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.trailing, 40)
				.padding(12)

			Divider()

			HStack {
				HStack(spacing: 6) {
					if let bundleID = capture.sourceAppBundleID,
					   let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
						Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
							.resizable()
							.frame(width: 14, height: 14)
						if let appName = capture.sourceAppName {
							Text(appName)
						}
						Text("•")
					}

					Image(systemName: "clock")
					Text(capture.timestamp.relativeFormatted())
					Text("•")
					Text(capture.timestamp.formatted(date: .omitted, time: .shortened))
					Text("•")
					Text(String(format: "%.1fs", capture.durationSeconds))
				}
				.font(.subheadline)
				.foregroundStyle(.secondary)

				Spacer()

				HStack(spacing: 10) {
					Button {
						onCopy()
						showCopyAnimation()
					} label: {
						HStack(spacing: 4) {
							Image(systemName: showCopied ? "checkmark" : "doc.on.doc.fill")
							if showCopied {
								Text("Copied").font(.caption)
							}
						}
					}
					.buttonStyle(.plain)
					.foregroundStyle(showCopied ? .green : .secondary)
					.help("Copy to clipboard")

					if capture.audioPath != nil {
						Button(action: onPlay) {
							Image(systemName: isPlaying ? "stop.fill" : "play.fill")
						}
						.buttonStyle(.plain)
						.foregroundStyle(isPlaying ? .blue : .secondary)
						.help(isPlaying ? "Stop playback" : "Play audio")
					}

					Button(action: onDelete) {
						Image(systemName: "trash.fill")
					}
					.buttonStyle(.plain)
					.foregroundStyle(.secondary)
					.help("Delete capture")
				}
				.font(.subheadline)
			}
			.frame(height: 20)
			.padding(.horizontal, 12)
			.padding(.vertical, 6)

			// Analysis summary if available
			if let analysis = capture.analysis {
				Divider()
				HStack(spacing: 6) {
					Image(systemName: "sparkles")
						.foregroundStyle(.blue)
					Text(analysis.summary)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 6)
			}
		}
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(Color(.windowBackgroundColor).opacity(0.5))
				.overlay(
					RoundedRectangle(cornerRadius: 8)
						.strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
				)
		)
		.onDisappear {
			copyTask?.cancel()
		}
	}

	@State private var showCopied = false
	@State private var copyTask: Task<Void, Error>?

	private func showCopyAnimation() {
		copyTask?.cancel()

		copyTask = Task {
			withAnimation {
				showCopied = true
			}

			try await Task.sleep(for: .seconds(1.5))

			withAnimation {
				showCopied = false
			}
		}
	}
}

// MARK: - History View

struct HistoryView: View {
	@ObserveInjection var inject
	let store: StoreOf<HistoryFeature>
	@Query(sort: \CaptureRecord.timestamp, order: .reverse)
	private var captures: [CaptureRecord]
	@State private var showingDeleteConfirmation = false
	@Shared(.hexSettings) var hexSettings: HexSettings

	var body: some View {
		Group {
			if !hexSettings.saveTranscriptionHistory {
				ContentUnavailableView {
					Label("History Disabled", systemImage: "clock.arrow.circlepath")
				} description: {
					Text("Transcription history is currently disabled.")
				} actions: {
					Button("Enable in Settings") {
						store.send(.navigateToSettings)
					}
				}
			} else if captures.isEmpty {
				ContentUnavailableView {
					Label("No Captures", systemImage: "waveform")
				} description: {
					Text("Your capture history will appear here.")
				}
			} else {
				ScrollView {
					LazyVStack(spacing: 12) {
						ForEach(captures) { capture in
							CaptureRowView(
								capture: capture,
								isPlaying: store.playingCaptureID == capture.id,
								onPlay: { store.send(.playCapture(capture.id, audioPath: capture.audioPath)) },
								onCopy: { store.send(.copyToClipboard(capture.rawText)) },
								onDelete: { store.send(.deleteCapture(capture.id)) }
							)
						}
					}
					.padding()
				}
				.toolbar {
					Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
						Label("Delete All", systemImage: "trash")
					}
				}
				.alert("Delete All Captures", isPresented: $showingDeleteConfirmation) {
					Button("Delete All", role: .destructive) {
						store.send(.confirmDeleteAll)
					}
					Button("Cancel", role: .cancel) {}
				} message: {
					Text("Are you sure you want to delete all captures? This action cannot be undone.")
				}
			}
		}.enableInjection()
	}
}
