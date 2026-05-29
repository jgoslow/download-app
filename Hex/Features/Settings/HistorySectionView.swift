import ComposableArchitecture
import Inject
import SwiftUI
import BasnCore

struct HistorySectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Section {
			Label {
				Toggle("Save Transcription History", isOn: Binding(
					get: { store.basnSettings.saveTranscriptionHistory },
					set: { store.send(.toggleSaveTranscriptionHistory($0)) }
				))
				Text("Save transcriptions and audio recordings for later access")
					.settingsCaption()
			} icon: {
				Image(systemName: "clock.arrow.circlepath")
			}

			if store.basnSettings.saveTranscriptionHistory {
				Label {
					HStack {
						Text("Maximum History Entries")
						Spacer()
						Picker("", selection: Binding(
							get: { store.basnSettings.maxHistoryEntries ?? 0 },
							set: { newValue in
								store.$basnSettings.withLock { $0.maxHistoryEntries = newValue == 0 ? nil : newValue }
							}
						)) {
							Text("Unlimited").tag(0)
							Text("50").tag(50)
							Text("100").tag(100)
							Text("200").tag(200)
							Text("500").tag(500)
							Text("1000").tag(1000)
						}
						.pickerStyle(.menu)
						.frame(width: 120)
					}
				} icon: {
					Image(systemName: "number.square")
				}

				if store.basnSettings.maxHistoryEntries != nil {
					Text("Oldest entries will be automatically deleted when limit is reached")
						.settingsCaption()
						.padding(.leading, 28)
				}
			}
		} header: {
			Text("History")
		} footer: {
			if !store.basnSettings.saveTranscriptionHistory {
				Text("When disabled, transcriptions will not be saved and audio files will be deleted immediately after transcription.")
					.font(.footnote)
					.foregroundColor(.secondary)
			}
		}
		.enableInjection()
	}
}
