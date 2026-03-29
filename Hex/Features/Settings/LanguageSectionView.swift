import SwiftUI
import Inject
#if canImport(ComposableArchitecture)
	import ComposableArchitecture
#endif

struct LanguageSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Label {
			Picker("Output Language", selection: Binding(
				get: { store.hexSettings.outputLanguage },
				set: { newValue in store.$hexSettings.withLock { $0.outputLanguage = newValue } }
			)) {
				ForEach(store.languages, id: \.id) { language in
					Text(language.name).tag(language.code)
				}
			}
			.pickerStyle(.menu)
		} icon: {
			Image(systemName: "globe")
		}
		.enableInjection()
	}
}
