import ComposableArchitecture
import SwiftUI

struct WorkflowsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Form {
            WorkflowsSectionView(store: store)
        }
        .formStyle(.grouped)
    }
}
