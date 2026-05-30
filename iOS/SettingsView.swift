import AuthenticationServices
import BasinShared
import SwiftData
import SwiftUI

// MARK: - Root

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            Form {
                captureSection
                integrationsSection
                preferencesSection
                basnSection
                aboutSection
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 140)
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        Section("Capture") {
            NavigationLink {
                FlowsSettingsView()
            } label: {
                Label("Flows", systemImage: "wind")
            }

            NavigationLink {
                ModelSettingsView()
            } label: {
                HStack {
                    Label("Transcription Model", systemImage: "waveform")
                    Spacer()
                    modelStatusBadge
                }
            }

            NavigationLink {
                LanguageSettingsView()
            } label: {
                HStack {
                    Label("Output Language", systemImage: "globe")
                    Spacer()
                    Text(appState.settings.outputLanguage ?? "Auto")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var modelStatusBadge: some View {
        if appState.downloadingModelVariant != nil {
            Text("\(Int(appState.modelDownloadProgress * 100))%")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        } else if appState.isModelDownloaded(variant: appState.settings.selectedModel) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Integrations

    private var integrationsSection: some View {
        Section("Integrations") {
            NavigationLink {
                ToolsSettingsView()
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
            }

            NavigationLink {
                WorkflowsSettingsView()
            } label: {
                Label("Workflows", systemImage: "arrow.triangle.branch")
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        @Bindable var appState = appState
        return Section("Preferences") {
            NavigationLink {
                SoundSettingsView()
            } label: {
                Label("Sound", systemImage: "speaker.wave.2.fill")
            }

            NavigationLink {
                HistorySettingsView()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    // MARK: - Basn

    private var basnSection: some View {
        Section("Basn") {
            NavigationLink {
                AISettingsView()
            } label: {
                Label("AI & Server", systemImage: "sparkles")
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://getbasn.ai")!) {
                Label("getbasn.ai", systemImage: "globe")
            }
        }
    }
}

// MARK: - Flows Settings

private struct FlowsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            ForEach(appState.flows) { flow in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(flow.name)
                            .fontWeight(appState.activeFlow.id == flow.id ? .semibold : .regular)
                        if !flow.domains.isEmpty {
                            Text(flow.domains.prefix(3).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if appState.activeFlow.id == flow.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { appState.selectFlow(flow) }
            }
        }
        .navigationTitle("Flows")
    }
}

// MARK: - Model Settings

private struct CuratedModel {
    let displayName: String
    let internalName: String
    let tagline: String
    let storageSize: String
    let accuracyStars: Int
    let speedStars: Int
}

private let iosModels: [CuratedModel] = [
    CuratedModel(displayName: "Whisper Tiny",   internalName: "openai_whisper-tiny",              tagline: "Fastest, basic accuracy",    storageSize: "73 MB",  accuracyStars: 2, speedStars: 5),
    CuratedModel(displayName: "Whisper Base",   internalName: "openai_whisper-base",              tagline: "Balanced speed and accuracy", storageSize: "140 MB", accuracyStars: 3, speedStars: 4),
    CuratedModel(displayName: "Whisper Large",  internalName: "openai_whisper-large-v3-v20240930", tagline: "Highest accuracy, slower",    storageSize: "1.5 GB", accuracyStars: 5, speedStars: 2),
]

private struct ModelSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                ForEach(iosModels, id: \.internalName) { model in
                    ModelRow(model: model)
                }
            } header: {
                Text("Transcription Model")
            } footer: {
                Text("All models run entirely on your device — your voice never leaves your iPhone.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Transcription Model")
    }
}

private struct ModelRow: View {
    @Environment(AppState.self) private var appState
    let model: CuratedModel

    private var isDownloaded: Bool { appState.isModelDownloaded(variant: model.internalName) }
    private var isActive: Bool { appState.settings.selectedModel == model.internalName && isDownloaded }
    private var isDownloading: Bool { appState.downloadingModelVariant == model.internalName }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(model.displayName).fontWeight(.medium)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    }
                }
                Text(model.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    starRow(label: "Accuracy", count: model.accuracyStars)
                    starRow(label: "Speed", count: model.speedStars)
                    Text(model.storageSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            modelControl
        }
        .padding(.vertical, 2)
    }

    private func starRow(label: String, count: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Circle()
                    .fill(i < count ? Color.blue : Color(.systemGray4))
                    .frame(width: 5, height: 5)
            }
        }
    }

    @ViewBuilder
    private var modelControl: some View {
        if isDownloading {
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: appState.modelDownloadProgress)
                    .frame(width: 64)
                Text("\(Int(appState.modelDownloadProgress * 100))%")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else if isActive {
            Text("Active")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.blue.opacity(0.12))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        } else if isDownloaded {
            Button("Select") {
                appState.settings.selectedModel = model.internalName
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button("Download") {
                Task { await appState.downloadModel(variant: model.internalName) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.downloadingModelVariant != nil)
        }
    }
}

// MARK: - Language Settings

private struct LanguageSettingsView: View {
    @Environment(AppState.self) private var appState

    private let languages: [(code: String?, name: String)] = [
        (nil, "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ru", "Russian"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("pl", "Polish"),
        ("sv", "Swedish"),
        ("tr", "Turkish"),
    ]

    var body: some View {
        List {
            ForEach(languages, id: \.name) { lang in
                Button {
                    appState.settings.outputLanguage = lang.code
                } label: {
                    HStack {
                        Text(lang.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if appState.settings.outputLanguage == lang.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .navigationTitle("Output Language")
    }
}

// MARK: - Tools Settings

private struct ToolsSettingsView: View {
    @Query(sort: \Tool.name) private var tools: [Tool]
    @State private var connectingTool: Tool?

    var body: some View {
        List {
            ForEach(tools) { tool in
                ToolRowView(tool: tool, onConnect: { connectingTool = tool })
            }
        }
        .navigationTitle("Tools")
        .sheet(item: $connectingTool) { tool in
            ToolConnectSheet(tool: tool, onDismiss: { connectingTool = nil })
        }
    }
}

// MARK: - Tool Row

private struct ToolRowView: View {
    @Bindable var tool: Tool
    let onConnect: () -> Void

    @State private var isExpanded = false

    private var spec: ToolDefinitionSpec? { ToolDefinitionLoader.load(tool.id) }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            toolExpandedContent
        } label: {
            HStack {
                Label(tool.name, systemImage: spec?.icon ?? tool.iconSystemName)
                Spacer()
                if tool.isConnected {
                    let tokenExpired = KeychainClient.loadExpiry(toolID: tool.id).map { $0 < Date() } ?? false
                    if tokenExpired {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                } else {
                    Button("Connect") { onConnect() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private var toolExpandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tool.isConnected {
                // Connection info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(tool.effectiveAuthMethod == "oauth" ? "OAuth" : "API Key")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)
                        if let connectedAt = tool.connectedAt {
                            Text("Connected \(connectedAt, format: .dateTime.month(.wide).day().year())")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    if let expires = KeychainClient.loadExpiry(toolID: tool.id) {
                        tokenHealthText(expires)
                    }
                }

                // Controls
                HStack {
                    Toggle("Requires approval", isOn: Binding(
                        get: { !tool.autoExecute },
                        set: { tool.autoExecute = !$0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                Button("Disconnect") { disconnectTool() }
                    .foregroundStyle(.red)
            } else {
                Button("Connect \(tool.name)") { onConnect() }
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private func tokenHealthText(_ expiresAt: Date) -> some View {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        let label: String = days <= 0 ? "Token expired" : days < 8 ? "Expiring in \(days) days" : "Auth valid"
        let color: Color = days > 30 ? .secondary : days > 8 ? .orange : .red
        return Text(label).font(.caption2).foregroundStyle(color)
    }

    private func disconnectTool() {
        tool.isConnected = false
        tool.oauthScopes = nil
        KeychainClient.deleteAll(toolID: tool.id)
        tool.activeAuthMethod = tool.effectiveSupportsOAuth ? "oauth" : "api_key"
        isExpanded = false
    }
}

// MARK: - Tool Connect Sheet

private struct ToolConnectSheet: View {
    @Bindable var tool: Tool
    let onDismiss: () -> Void

    @State private var apiKeyInput = ""
    @State private var baseURLInput = ""
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var enabledScopeKeys: Set<String> = []
    @State private var selectedTab: AuthTab = .oauth

    private var toolSpec: ToolDefinitionSpec? { ToolDefinitionLoader.load(tool.id) }
    private var availableScopes: [(key: String, spec: ToolDefinitionSpec.AuthSpec.ScopeSpec)] {
        (toolSpec?.auth.availableScopes ?? [:]).sorted { $0.key < $1.key }.map { (key: $0.key, spec: $0.value) }
    }

    enum AuthTab: String, CaseIterable { case oauth = "OAuth"; case apiKey = "API Key" }

    private var availableTabs: [AuthTab] {
        var t: [AuthTab] = []
        if tool.effectiveSupportsOAuth { t.append(.oauth) }
        if tool.effectiveSupportsAPIKey { t.append(.apiKey) }
        return t
    }

    var body: some View {
        NavigationStack {
            Form {
                if availableTabs.count > 1 {
                    Section {
                        Picker("Auth Method", selection: $selectedTab) {
                            ForEach(availableTabs, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                switch selectedTab {
                case .oauth: oauthSection
                case .apiKey: apiKeySection
                }

                if tool.isConnected {
                    Section {
                        Button("Disconnect", role: .destructive) { disconnect(); onDismiss() }
                    }
                }
            }
            .navigationTitle("Connect \(tool.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                if selectedTab == .apiKey {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveAPIKey(); onDismiss() }
                            .disabled(apiKeyInput.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            selectedTab = tool.effectiveSupportsOAuth ? .oauth : .apiKey
            if tool.activeAuthMethod == "api_key" { selectedTab = .apiKey }
            apiKeyInput = KeychainClient.load(toolID: tool.id, key: .apiKey) ?? ""
            baseURLInput = tool.baseURL ?? ""
            if let saved = tool.selectedScopeKeys {
                enabledScopeKeys = Set(saved)
            } else if let scopes = toolSpec?.auth.availableScopes {
                enabledScopeKeys = Set(scopes.compactMap { k, v in v.default == true ? k : nil })
            }
        }
    }

    @ViewBuilder
    private var oauthSection: some View {
        if tool.isConnected && tool.effectiveAuthMethod == "oauth" {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.green).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected via OAuth").fontWeight(.medium)
                        if let expires = KeychainClient.loadExpiry(toolID: tool.id) {
                            Text("Expires \(expires.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            if !availableScopes.isEmpty {
                Section("Access") {
                    ForEach(availableScopes, id: \.key) { item in
                        Toggle(item.spec.label, isOn: Binding(
                            get: { enabledScopeKeys.contains(item.key) },
                            set: { if $0 { enabledScopeKeys.insert(item.key) } else { enabledScopeKeys.remove(item.key) } }
                        ))
                    }
                }
            }

            Section {
                if isAuthenticating {
                    HStack { ProgressView(); Text("Waiting for authorization…").foregroundStyle(.secondary) }
                } else {
                    Button {
                        startOAuth()
                    } label: {
                        Label("Sign in with \(tool.name)", systemImage: "arrow.up.forward.app")
                    }
                    .disabled(availableScopes.isEmpty ? false : enabledScopeKeys.isEmpty)
                }
                if let err = authError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("Basn opens an in-app browser to authenticate. Only a revocable token is stored — never your password.")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        Section {
            if tool.id == "jira" {
                TextField("https://your-org.atlassian.net", text: $baseURLInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            SecureField(tool.apiKeyLabel ?? "API Key", text: $apiKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text(tool.id == "jira" ? "Instance URL + API Key" : "API Key")
        } footer: {
            apiKeyFooter
        }
    }

    @ViewBuilder
    private var apiKeyFooter: some View {
        switch tool.id {
        case "jira":    Text("Create a token at id.atlassian.com › Security › API tokens. Enter as email:token.")
        case "github":  Text("Create a Personal Access Token at github.com/settings/tokens with repo scope.")
        case "toggl":   Text("Find your token at track.toggl.com/profile (bottom of the page).")
        case "slack":   Text("Create a Slack app at api.slack.com/apps, add chat:write, install to workspace.")
        default:        EmptyView()
        }
    }

    private func startOAuth() {
        guard let provider = tool.oauthProvider else { return }
        isAuthenticating = true
        authError = nil
        let selectedScopeURLs: [String]? = availableScopes.isEmpty ? nil :
            availableScopes.compactMap { enabledScopeKeys.contains($0.key) ? $0.spec.scope : nil }
        Task {
            do {
                let tokens = try await OAuthClient.shared.startFlow(provider: provider, toolID: tool.id, scopes: selectedScopeURLs)
                await MainActor.run {
                    try? KeychainClient.save(tokens.accessToken, toolID: tool.id, key: .accessToken)
                    if let r = tokens.refreshToken { try? KeychainClient.save(r, toolID: tool.id, key: .refreshToken) }
                    tool.oauthScopes = tokens.scope
                    if let exp = tokens.expiresIn {
                        try? KeychainClient.saveExpiry(Date().addingTimeInterval(TimeInterval(exp)), toolID: tool.id)
                    }
                    tool.activeAuthMethod = "oauth"
                    tool.isConnected = true
                    tool.selectedScopeKeys = Array(enabledScopeKeys)
                    tool.connectedAt = Date()
                    isAuthenticating = false
                }
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { onDismiss() }
            } catch {
                await MainActor.run { authError = error.localizedDescription; isAuthenticating = false }
            }
        }
    }

    private func saveAPIKey() {
        if apiKeyInput.isEmpty {
            KeychainClient.delete(toolID: tool.id, key: .apiKey)
            tool.isConnected = false
        } else {
            try? KeychainClient.save(apiKeyInput, toolID: tool.id, key: .apiKey)
            tool.isConnected = true
            tool.connectedAt = Date()
        }
        tool.baseURL = baseURLInput.isEmpty ? nil : baseURLInput
        tool.activeAuthMethod = "api_key"
    }

    private func disconnect() {
        tool.isConnected = false
        tool.oauthScopes = nil
        KeychainClient.deleteAll(toolID: tool.id)
        tool.activeAuthMethod = tool.effectiveSupportsOAuth ? "oauth" : "api_key"
    }
}

// MARK: - Workflows Settings

private struct WorkflowsSettingsView: View {
    @Query(sort: \Workflow.sortOrder) private var workflows: [Workflow]

    var body: some View {
        List {
            if workflows.isEmpty {
                ContentUnavailableView(
                    "No workflows yet",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Workflows emerge from your captures. Basn creates them when it spots a repeating pattern.")
                )
            } else {
                ForEach(workflows) { workflow in
                    HStack {
                        Image(systemName: workflow.iconSystemName)
                            .foregroundStyle(workflow.isEnabled ? .blue : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workflow.name).fontWeight(.medium)
                            Text(workflow.instruction)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { workflow.isEnabled },
                            set: { workflow.isEnabled = $0 }
                        ))
                        .labelsHidden()
                    }
                }
            }
        }
        .navigationTitle("Workflows")
    }
}

// MARK: - Sound Settings

private struct SoundSettingsView: View {
    @Environment(AppState.self) private var appState

    private var volumePercent: Double {
        appState.settings.soundEffectsVolume.clamped(to: 0...1)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Sound Effects", isOn: Binding(
                    get: { appState.settings.soundEffectsEnabled },
                    set: { appState.settings.soundEffectsEnabled = $0 }
                ))

                if appState.settings.soundEffectsEnabled {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int(volumePercent * 100))%")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { volumePercent },
                        set: { appState.settings.soundEffectsVolume = $0 }
                    ))
                }
            }
        }
        .navigationTitle("Sound")
    }
}

// MARK: - History Settings

private struct HistorySettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                Toggle("Save Capture History", isOn: Binding(
                    get: { appState.settings.saveTranscriptionHistory },
                    set: { appState.settings.saveTranscriptionHistory = $0 }
                ))
            } footer: {
                if !appState.settings.saveTranscriptionHistory {
                    Text("Captures won't be saved and audio files will be deleted immediately after transcription.")
                }
            }

            if appState.settings.saveTranscriptionHistory {
                Section("Limit") {
                    Picker("Maximum entries", selection: Binding(
                        get: { appState.settings.maxHistoryEntries ?? 0 },
                        set: { appState.settings.maxHistoryEntries = $0 == 0 ? nil : $0 }
                    )) {
                        Text("Unlimited").tag(0)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("200").tag(200)
                        Text("500").tag(500)
                        Text("1000").tag(1000)
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

// MARK: - AI & Server Settings

private struct AISettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anthropic API Key")
                        .font(.subheadline).fontWeight(.medium)
                    SecureField("sk-ant-…", text: Binding(
                        get: { appState.settings.anthropicAPIKey },
                        set: { appState.settings.anthropicAPIKey = $0 }
                    ))
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Text("Enables AI analysis after each capture — summaries, tasks, and routing to your tools.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("AI")
            }

            Section {
                Toggle("Advanced", isOn: $showAdvanced.animation())
            }

            if showAdvanced {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server URL")
                            .font(.subheadline).fontWeight(.medium)
                        TextField("http://localhost:3000", text: Binding(
                            get: { appState.settings.serverURL },
                            set: { appState.settings.serverURL = $0 }
                        ))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Text("POST /transcript endpoint. Leave blank to save locally only.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Auth Token")
                            .font(.subheadline).fontWeight(.medium)
                        SecureField("Bearer token", text: Binding(
                            get: { appState.settings.authToken },
                            set: { appState.settings.authToken = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Text("Sent as Authorization: Bearer <token>.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Server")
                }
            }
        }
        .navigationTitle("AI & Server")
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
