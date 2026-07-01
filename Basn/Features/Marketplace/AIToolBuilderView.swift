import ComposableArchitecture
import SwiftUI

// MARK: - Root

struct AIToolBuilderView: View {
    @Bindable var store: StoreOf<AIToolBuilderFeature>

    var body: some View {
        NavigationStack {
            Group {
                switch store.step {
                case .describe:   describeView
                case .generating: generatingView
                case .review:     reviewView
                case .done:       doneView
                }
            }
            .navigationTitle("Build Integration")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.dismissTapped) }
                }
            }
        }
    }

    // MARK: - Step 1: Describe

    private var describeView: some View {
        Form {
            Section {
                TextEditor(text: Binding(
                    get: { store.description },
                    set: { store.send(.descriptionChanged($0)) }
                ))
                .frame(minHeight: 100)
            } header: {
                Text("What do you want to connect?")
            } footer: {
                Text("Describe the service and what you want to do with your voice. For example: \"Notion — create a page in my inbox when I say create a note\" or \"Linear — create an issue with a title and priority\".")
                    .font(.footnote)
            }

            if let error = store.errorMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    store.send(.generateTapped)
                } label: {
                    HStack {
                        Spacer()
                        Label("Generate with AI", systemImage: "wand.and.stars")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(store.description.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Step 2: Generating

    private var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                Text("Building your integration…")
                    .font(.headline)
                Text("Claude is generating the API definition.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Step 3: Review

    @ViewBuilder
    private var reviewView: some View {
        if let spec = store.generatedSpec {
            List {
                // Tool header card
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: spec.icon)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(spec.name)
                                .font(.headline)
                            Text(authBadgeText(spec))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue.opacity(0.6))
                    }
                    .padding(.vertical, 4)
                }

                // Actions with validate buttons
                Section {
                    ForEach(spec.actions.sorted(by: { $0.key < $1.key }), id: \.key) { id, action in
                        ActionValidateRow(
                            actionID: id,
                            action: action,
                            isTesting: store.testingIDs.contains(id),
                            result: store.testResults[id],
                            message: store.testMessages[id],
                            onTest: { store.send(.testActionTapped(id)) }
                        )
                    }
                } header: {
                    Text("Actions (\(spec.actions.count))")
                }

                // Error banner
                if let error = store.errorMessage {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }

                // Submit / Install
                Section {
                    Button {
                        store.send(.submitTapped)
                    } label: {
                        HStack {
                            Spacer()
                            if store.isSubmitting {
                                ProgressView()
                            } else {
                                Label("Submit to Marketplace", systemImage: "arrow.up.circle")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!store.canSubmit || store.isSubmitting)
                } footer: {
                    Text("This creates a pull request in the Basn marketplace registry. Your integration will be visible to other users after review.")
                        .font(.footnote)
                }

                Section {
                    Button(role: .destructive) {
                        store.send(.retryDescription)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Describe again")
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 4: Done

    private var doneView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("Submitted!")
                    .font(.title2).fontWeight(.bold)
                Text("Your integration is under review.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let url = store.submissionURL, let link = URL(string: url) {
                    Link("View pull request", destination: link)
                        .font(.subheadline)
                }
            }
            Spacer()
            Button("Done") { store.send(.dismissTapped) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 32)
        }
        .padding()
    }

    // MARK: - Helpers

    private func authBadgeText(_ spec: ToolDefinitionSpec) -> String {
        let methods = spec.auth.methods.map { $0 == "api_key" ? "API Key" : $0 == "oauth" ? "OAuth" : $0 }
        return methods.joined(separator: " · ")
    }
}

// MARK: - Action validate row

private struct ActionValidateRow: View {
    let actionID: String
    let action: ToolDefinitionSpec.ActionSpec
    let isTesting: Bool
    let result: Bool?
    let message: String?
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.displayName)
                        .fontWeight(.medium)
                    Text(action.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                validateControl
            }

            if let msg = message {
                HStack(spacing: 4) {
                    Image(systemName: result == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(result == true ? Color.green : Color.red)
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(result == true ? Color.green : Color.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var validateControl: some View {
        if isTesting {
            ProgressView().controlSize(.small)
        } else if let passed = result {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? Color.green : Color.red)
                .onTapGesture { onTest() }
        } else {
            Button("Validate") { onTest() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
