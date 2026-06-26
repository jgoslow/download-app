import BasnCore
import ComposableArchitecture
import Darwin
import Inject
import SwiftUI

struct CuratedRow: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<ModelDownloadFeature>
	let model: CuratedModelInfo
	/// When true (used in "See all models" during onboarding): clicking always selects + starts download;
	/// radio shows circular arc progress; no separate download button.
	var directDownload: Bool = false

	var isSelected: Bool {
		if directDownload {
			return store.basnSettings.selectedModel == model.internalName
		}
		guard model.isDownloaded else { return false }
		let selected = store.basnSettings.selectedModel
		if model.internalName.contains("*") || model.internalName.contains("?") {
			return fnmatch(model.internalName, selected, 0) == 0
		}
		if selected.contains("*") || selected.contains("?") {
			return fnmatch(selected, model.internalName, 0) == 0
		}
		return model.internalName == selected
	}

	// True if this model is downloading (active foreground or background)
	private var isDownloadingThis: Bool {
		store.downloadingModels.contains(model.internalName)
	}

	// True only for the model currently reporting progress
	private var isActivelyDownloading: Bool {
		store.downloadingModelName == model.internalName
	}

	var body: some View {
		Button(action: rowAction) {
			HStack(alignment: .center, spacing: 12) {
				radioIndicator

				VStack(alignment: .leading, spacing: 6) {
					HStack(spacing: 6) {
						Text(model.displayName)
							.font(.headline)
							.foregroundStyle(rowForegroundStyle)
						if let badge = model.badge {
							Text(badge)
								.font(.caption2)
								.fontWeight(.semibold)
								.foregroundStyle(.white)
								.padding(.horizontal, 6)
								.padding(.vertical, 2)
								.background(badgeColor)
								.clipShape(RoundedRectangle(cornerRadius: 4))
						}
					}
					HStack(spacing: 16) {
						HStack(spacing: 6) {
							StarRatingView(model.accuracyStars)
							Text("Accuracy").font(.caption2).foregroundStyle(.secondary)
						}
						HStack(spacing: 6) {
							StarRatingView(model.speedStars)
							Text("Speed").font(.caption2).foregroundStyle(.secondary)
						}
					}
				}

				Spacer(minLength: 12)

				HStack(spacing: 12) {
					Text(model.storageSize)
						.foregroundStyle(.secondary)
						.font(.subheadline)
						.frame(width: 56, alignment: .trailing)

					trailingControl
				}
			}
			.padding(12)
			.background(rowBackground)
			.overlay(
				RoundedRectangle(cornerRadius: 10)
					.stroke(isSelected ? Color.blue.opacity(0.35) : Color.gray.opacity(0.18))
			)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.disabled(!directDownload && !model.isDownloaded && !isDownloadingThis)
		.contextMenu {
			if isDownloadingThis {
				Button("Cancel Download", role: .destructive) { store.send(.cancelDownload) }
			}
			if model.isDownloaded || isDownloadingThis {
				Button("Show in Finder") { store.send(.openModelLocation) }
			}
			if model.isDownloaded {
				Divider()
				Button("Delete", role: .destructive) {
					store.send(.selectModel(model.internalName))
					store.send(.deleteSelectedModel)
				}
			}
		}
		.enableInjection()
	}

	// MARK: - Sub-views

	@ViewBuilder
	private var radioIndicator: some View {
		ZStack {
			if directDownload && isActivelyDownloading {
				// Circular arc progress fill — only for the model actively reporting progress
				Circle()
					.stroke(Color.blue.opacity(0.2), lineWidth: 2.5)
					.frame(width: 22, height: 22)
				Circle()
					.trim(from: 0, to: store.downloadProgress)
					.stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
					.frame(width: 22, height: 22)
					.rotationEffect(.degrees(-90))
					.animation(.linear(duration: 0.3), value: store.downloadProgress)
			} else if directDownload && isDownloadingThis {
				// Background download in progress — indeterminate spinner in the radio circle
				ProgressView()
					.controlSize(.small)
					.frame(width: 22, height: 22)
			} else {
				Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
					.foregroundStyle(radioColor)
			}
		}
		.frame(width: 22, height: 22)
	}

	@ViewBuilder
	private var trailingControl: some View {
		if isDownloadingThis {
			if directDownload {
				if isActivelyDownloading {
					Text("\(Int(store.downloadProgress * 100))%")
						.font(.system(size: 11, weight: .medium, design: .monospaced))
						.foregroundStyle(.blue)
						.frame(width: 48, alignment: .trailing)
				} else {
					// Background download: show a neutral "queued" indicator
					Image(systemName: "arrow.down.circle")
						.foregroundStyle(.blue)
						.font(.title3)
						.frame(width: 48)
				}
			} else {
				VStack(spacing: 3) {
					ProgressView(value: isActivelyDownloading ? store.downloadProgress : nil)
						.progressViewStyle(.circular)
						.controlSize(.small)
						.tint(.blue)
						.frame(width: 24, height: 24)
					if isActivelyDownloading {
						Text("\(Int(store.downloadProgress * 100))%")
							.font(.system(size: 9, weight: .medium, design: .monospaced))
							.foregroundStyle(.secondary)
					}
				}
				.frame(width: 48)
			}
		} else if model.isDownloaded {
			Image(systemName: "checkmark.circle.fill")
				.foregroundStyle(.green)
				.font(.title2)
				.frame(width: 48)
		} else {
			if directDownload {
				Image(systemName: "arrow.down.circle")
					.foregroundStyle(.secondary)
					.font(.title3)
					.frame(width: 48)
			} else {
				Button {
					store.send(.selectModel(model.internalName))
					store.send(.downloadSelectedModel)
				} label: {
					Label("Download", systemImage: "arrow.down.circle.fill")
						.font(.subheadline.weight(.medium))
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
				.frame(width: 104, alignment: .trailing)
			}
		}
	}

	@ViewBuilder
	private var rowBackground: some View {
		if isSelected {
			RoundedRectangle(cornerRadius: 10)
				.fill(Color.blue.opacity(0.08))
		} else if !directDownload && !model.isDownloaded {
			RoundedRectangle(cornerRadius: 10)
				.fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
		} else {
			RoundedRectangle(cornerRadius: 10)
				.fill(Color(NSColor.controlBackgroundColor))
		}
	}

	private var radioColor: Color {
		if directDownload {
			return isSelected ? .blue : .secondary
		}
		return model.isDownloaded ? (isSelected ? .blue : .secondary) : Color.secondary.opacity(0.35)
	}

	private var rowForegroundStyle: Color {
		if directDownload { return .primary }
		return model.isDownloaded ? .primary : .secondary
	}

	private var badgeColor: Color {
		if directDownload { return Color.accentColor }
		return model.isDownloaded ? Color.accentColor : Color.secondary
	}

	// MARK: - Actions

	private func rowAction() {
		store.send(.selectModel(model.internalName))
		if directDownload && !model.isDownloaded && !isDownloadingThis {
			store.send(.downloadSelectedModel)
		}
	}
}
