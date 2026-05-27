import SwiftData
import SwiftUI

struct FlowsView: View {
    @Query(sort: \FlowDefinition.sortOrder) private var flows: [FlowDefinition]

    var body: some View {
        Form {
            Section {
                if flows.isEmpty {
                    Text("No flows yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    ForEach(flows) { flow in
                        flowRow(flow)
                    }
                }
            } header: {
                Text("Flows")
            } footer: {
                Text("Flows set the context for each capture — what Castellum pays attention to and how it routes your words.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func flowRow(_ flow: FlowDefinition) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(flow.name)
                if !flow.intro.isEmpty {
                    Text(flow.intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: flow.id == "open" ? "arrow.trianglehead.2.clockwise.rotate.90" : "circle.dotted")
        }
    }
}
