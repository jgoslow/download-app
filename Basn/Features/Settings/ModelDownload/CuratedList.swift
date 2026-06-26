import ComposableArchitecture
import Inject
import SwiftUI

struct CuratedList: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<ModelDownloadFeature>
	var directDownload: Bool = false

	private var sortedModels: [CuratedModelInfo] {
		// In directDownload mode (e.g. "See all models" sheet), always show everything.
		let all = (directDownload || store.showAllModels)
			? Array(store.curatedModels)
			: store.curatedModels.filter { $0.isParakeet }

		// Downloaded models always appear first, preserving relative order within each group.
		let downloaded = all.filter { $0.isDownloaded }
		let notDownloaded = all.filter { !$0.isDownloaded }
		return downloaded + notDownloaded
	}

	private var hiddenModels: [CuratedModelInfo] {
		store.curatedModels.filter { !$0.isParakeet }
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			ForEach(sortedModels) { model in
				CuratedRow(store: store, model: model, directDownload: directDownload)
			}

			// "Show more/less" is hidden in directDownload mode — all models are always visible there.
			if !directDownload && !hiddenModels.isEmpty {
				Button(action: { store.send(.toggleModelDisplay) }) {
					HStack {
						Spacer()
						Text(store.showAllModels ? "Show less" : "Show more")
							.font(.subheadline)
						Spacer()
					}
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
			}
		}
		.enableInjection()
	}
}
