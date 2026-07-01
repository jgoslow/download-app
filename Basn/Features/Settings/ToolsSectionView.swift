//
//  ToolsSectionView.swift
//  Basin
//
//  Settings section for connecting external tools (Jira, Slack, Toggl, etc.).
//  Each tool row is collapsible. The expanded state shows:
//    1. Connection info — auth method, date connected, token expiry health
//    2. Authorized permissions — scopes granted at OAuth time (non-interactive)
//    3. Basin can use — service-area toggles controlling what Basin actually does
//    4. Controls — Requires Approval toggle + Disconnect
//
//  TODO: Alert the user via system notification N days before token expiry (KeychainClient.loadExpiry).
//  TODO: When an action fails due to an expired token, surface a "Reconnect [Tool] →"
//        inline link in the workflow summary card (add at the failure path in CastellumExecutor).
//

import ComposableArchitecture
import BasnCore
import SwiftData
import SwiftUI

struct ToolsSectionView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Query(sort: \Tool.name) private var tools: [Tool]
    @State private var connectingTool: Tool?
    @State private var showingMarketplace = false
    @State private var showingToolBuilder = false
    @Shared(.basnSettings) private var basnSettings: BasnSettings

    var body: some View {
        Section {
            ForEach(tools) { tool in
                ToolRowView(tool: tool, onConnect: { connectingTool = tool })
            }
        } header: {
            Text("Tools")
        } footer: {
            HStack(spacing: 16) {
                Button {
                    showingMarketplace = true
                } label: {
                    Label("Browse Marketplace", systemImage: "storefront")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Button {
                    showingToolBuilder = true
                } label: {
                    Label("Build with AI", systemImage: "wand.and.stars")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 4)
        }
        .sheet(item: $connectingTool) { tool in
            ToolConnectSheet(tool: tool, onDismiss: { connectingTool = nil })
        }
        .sheet(isPresented: $showingMarketplace) {
            MarketplaceView(store: Store(initialState: MarketplaceFeature.State()) {
                MarketplaceFeature()
            })
        }
        .sheet(isPresented: $showingToolBuilder) {
            AIToolBuilderView(store: Store(
                initialState: AIToolBuilderFeature.State(apiKey: basnSettings.basinSettings.anthropicAPIKey)
            ) {
                AIToolBuilderFeature()
            })
        }
    }
}

// MARK: - Tool Row

private struct ToolRowView: View {
    @Bindable var tool: Tool
    let onConnect: () -> Void

    @State private var isExpanded = false
    @State private var verifyState: VerifyState = .idle

    private enum VerifyState { case idle, checking, success, failed }

    private var spec: ToolDefinitionSpec? { ToolDefinitionLoader.load(tool.id) }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                if tool.effectiveAuthMethod == "system" {
                    Text("Uses system permissions. No setup needed — Basn will request access the first time you use this tool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if tool.isConnected {
                    connectionSection
                    if let grantedScopes = grantedScopeLabels, !grantedScopes.isEmpty {
                        Divider()
                        authorizedPermissionsSection(grantedScopes)
                    }
                    if hasBasinCanUseContent {
                        Divider()
                        basinCanUseSection
                    }
                    Divider()
                }
                controlsSection
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
            .task(id: tool.id) {
                await silentlyRefreshIfExpired()
            }
        } label: {
            HStack {
                // TODO: Replace SF Symbol with branded asset (e.g. Image("tool-\(tool.id)"))
                //       once SVG brand icons are added to the asset catalog.
                Label(tool.name, systemImage: spec?.icon ?? tool.iconSystemName)
                Spacer()
                if tool.effectiveAuthMethod == "system" {
                    Toggle("", isOn: $tool.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                } else if tool.isConnected {
                    let tokenExpired = KeychainClient.loadExpiry(toolID: tool.id).map { $0 < Date() } ?? false
                    if tokenExpired {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .help("Token expired — reconnect to continue using this tool")
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button("Connect") { onConnect() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - Connection section

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(tool.effectiveAuthMethod == "oauth" ? "OAuth" : "API Key")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.secondary)

                if let connectedAt = tool.connectedAt {
                    Text("Connected \(connectedAt, format: .dateTime.month(.wide).day().year())")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let expiresAt = KeychainClient.loadExpiry(toolID: tool.id) {
                let expired = expiresAt < Date()
                HStack(spacing: 8) {
                    tokenHealthView(expiresAt: expiresAt)
                    if expired {
                        Spacer()
                        Button("Reconnect") { onConnect() }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            HStack(spacing: 8) {
                if let lastUsedAt = tool.lastUsedAt {
                    Text("Last used \(lastUsedAt, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Not yet used by Basin")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if spec?.healthCheck != nil {
                    verifyButton
                }
            }
        }
    }

    private var verifyButton: some View {
        Group {
            switch verifyState {
            case .idle:
                Button("Verify") { runVerify() }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
            case .checking:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Checking…").font(.caption2).foregroundStyle(.secondary)
                }
            case .success:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            case .failed:
                Label("Auth failed", systemImage: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func silentlyRefreshIfExpired() async {
        guard tool.isConnected, tool.effectiveAuthMethod == "oauth" else { return }
        guard let expiresAt = KeychainClient.loadExpiry(toolID: tool.id), expiresAt < Date() else { return }
        guard let refreshToken = KeychainClient.load(toolID: tool.id, key: .refreshToken) else { return }
        guard let provider = tool.oauthProvider else { return }
        let clientID = OAuthProviderConfig.config(for: provider)?.clientID ?? ""

        do {
            let response = try await OAuthClient.shared.refreshToken(
                provider: provider,
                refreshToken: refreshToken,
                clientID: clientID
            )
            try? KeychainClient.save(response.accessToken, toolID: tool.id, key: .accessToken)
            if let newRefresh = response.refreshToken {
                try? KeychainClient.save(newRefresh, toolID: tool.id, key: .refreshToken)
            }
            if let expiresIn = response.expiresIn {
                try? KeychainClient.saveExpiry(Date().addingTimeInterval(TimeInterval(expiresIn)), toolID: tool.id)
            }
            // Updating tokenLastRefreshedAt triggers a SwiftUI re-render, which re-reads the
            // keychain expiry and clears the "Token expired" warning in the UI.
            tool.tokenLastRefreshedAt = Date()
        } catch {
            // Silent — if refresh fails, the "Token expired / Reconnect" UI stays visible.
        }
    }

    private func runVerify() {
        guard let spec else { return }
        verifyState = .checking
        Task {
            let ok = await GenericToolExecutor.verify(tool: tool, spec: spec)
            await MainActor.run { verifyState = ok ? .success : .failed }
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { verifyState = .idle }
        }
    }

    private func tokenHealthView(expiresAt: Date) -> some View {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        return HStack(spacing: 4) {
            Image(systemName: days > 8 ? "key.fill" : "exclamationmark.triangle.fill")
                .font(.caption2)
            Group {
                if days <= 0 {
                    Text("Token expired — reconnect now")
                } else if days < 8 {
                    Text("Expiring in \(days) days — reconnect soon")
                } else if days <= 30 {
                    Text("Expires in \(days) days")
                } else {
                    Text("Auth valid")
                }
            }
            .font(.caption2)
        }
        .foregroundStyle(days > 30 ? Color.secondary : days > 8 ? Color.orange : Color.red)
    }

    // MARK: - Authorized permissions section

    /// Human-readable labels for the scopes actually granted at OAuth connect time.
    private var grantedScopeLabels: [String]? {
        guard tool.effectiveAuthMethod == "oauth",
              let selectedKeys = tool.selectedScopeKeys,
              let availableScopes = spec?.auth.availableScopes else { return nil }
        return selectedKeys.compactMap { availableScopes[$0]?.label }
    }

    private func authorizedPermissionsSection(_ labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Authorized permissions")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(labels, id: \.self) { label in
                    Label(label, systemImage: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Reconnect to change") { onConnect() }
                .font(.caption2)
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
        }
    }

    // MARK: - Basin can use section

    private var hasBasinCanUseContent: Bool {
        if let areas = serviceAreas, !areas.isEmpty { return true }
        return spec?.actions.values.first != nil
    }

    @ViewBuilder
    private var basinCanUseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Basin can use")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let areas = serviceAreas, !areas.isEmpty {
                ForEach(areas) { area in
                    serviceAreaToggle(area)
                }
            } else if let firstAction = spec?.actions.values.first {
                // Single-action tool — just describe what it does
                Text(firstAction.description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func serviceAreaToggle(_ area: ToolServiceArea) -> some View {
        let allDisabled = area.actionKeys.allSatisfy { Set(tool.enabledActionKeys ?? []).contains($0) }

        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(area.label)
                    .font(.callout)
                Text(area.description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !allDisabled },
                set: { enabled in
                    var current = Set(tool.enabledActionKeys ?? [])
                    if enabled {
                        area.actionKeys.forEach { current.remove($0) }
                    } else {
                        area.actionKeys.forEach { current.insert($0) }
                    }
                    tool.enabledActionKeys = current.isEmpty ? nil : Array(current)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
    }

    // MARK: - Controls section

    private var controlsSection: some View {
        HStack(spacing: 12) {
            if tool.isConnected {
                VStack(alignment: .leading, spacing: 1) {
                    Toggle("Requires approval", isOn: Binding(
                        get: { !tool.autoExecute },
                        set: { tool.autoExecute = !$0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Text("Basin will ask before running actions. Overridden by individual workflow settings.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if tool.effectiveAuthMethod != "system" {
                    Button("Disconnect") { disconnectTool() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red.opacity(0.8))
                        .font(.callout)
                }
            } else {
                Button("Connect \(tool.name)") { onConnect() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Helpers

    private func disconnectTool() {
        tool.isConnected = false
        tool.oauthScopes = nil
        KeychainClient.deleteAll(toolID: tool.id)
        tool.activeAuthMethod = tool.effectiveSupportsOAuth ? "oauth" : "api_key"
        isExpanded = false
    }

    // Service areas for this tool, derived from available OAuth scopes + static action mapping.
    // Nil means no sub-areas (single-action tools show a description caption instead).
    private var serviceAreas: [ToolServiceArea]? {
        guard let availableScopes = spec?.auth.availableScopes,
              !availableScopes.isEmpty,
              let spec else { return nil }
        return ToolServiceArea.areas(for: tool.id, scopes: availableScopes, actions: spec.actions)
    }
}

// MARK: - Service Area model

/// A Basin-defined capability grouping that maps to a set of action keys.
/// One toggle controls whether Basin uses any action within the area.
private struct ToolServiceArea: Identifiable {
    let id: String
    let label: String
    let description: String
    let actionKeys: [String]

    /// Derives service areas for a given tool by matching known scope→action mappings.
    static func areas(
        for toolID: String,
        scopes: [String: ToolDefinitionSpec.AuthSpec.ScopeSpec],
        actions: [String: ToolDefinitionSpec.ActionSpec]
    ) -> [ToolServiceArea]? {
        let mapping = scopeActionMapping[toolID] ?? [:]
        guard !mapping.isEmpty else { return nil }

        var result: [ToolServiceArea] = []
        var covered: Set<String> = []

        for (scopeKey, actionKeys) in mapping.sorted(by: { $0.key < $1.key }) {
            let validKeys = actionKeys.filter { actions[$0] != nil }
            guard !validKeys.isEmpty, let scopeSpec = scopes[scopeKey] else { continue }
            covered.formUnion(validKeys)

            let desc = validKeys.compactMap { actions[$0]?.displayName }.joined(separator: ", ")
            result.append(ToolServiceArea(id: scopeKey, label: scopeSpec.label, description: desc, actionKeys: validKeys))
        }

        // Ungrouped actions (not covered by any scope mapping)
        let ungrouped = actions.keys.filter { !covered.contains($0) }.sorted()
        if !ungrouped.isEmpty {
            let desc = ungrouped.compactMap { actions[$0]?.displayName }.joined(separator: ", ")
            result.append(ToolServiceArea(id: "__other", label: "Other", description: desc, actionKeys: ungrouped))
        }

        return result.isEmpty ? nil : result
    }

    /// Maps tool ID → scope key → action keys covered by that scope.
    /// Extend this as new tools with multi-scope support are added.
    private static let scopeActionMapping: [String: [String: [String]]] = [
        "google": [
            "calendar": ["create_event"],
            "gmail": ["send_email"],
            "docs": ["create_document", "append_text", "read_document"],
            "drive_file": []
        ]
    ]
}

// MARK: - Connect Sheet

private struct ToolConnectSheet: View {
    @Bindable var tool: Tool
    let onDismiss: () -> Void

    @State private var selectedTab: AuthTab = .oauth
    @State private var apiKeyInput = ""
    @State private var baseURLInput = ""
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var enabledScopeKeys: Set<String> = []

    private var toolSpec: ToolDefinitionSpec? { ToolDefinitionLoader.load(tool.id) }
    private var availableScopes: [(key: String, spec: ToolDefinitionSpec.AuthSpec.ScopeSpec)] {
        guard let scopes = toolSpec?.auth.availableScopes else { return [] }
        return scopes.sorted { $0.key < $1.key }.map { (key: $0.key, spec: $0.value) }
    }

    enum AuthTab: String, CaseIterable {
        case oauth = "OAuth"
        case apiKey = "API Key"
    }

    private var availableTabs: [AuthTab] {
        var tabs: [AuthTab] = []
        if tool.effectiveSupportsOAuth { tabs.append(.oauth) }
        if tool.effectiveSupportsAPIKey { tabs.append(.apiKey) }
        return tabs
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: tool.iconSystemName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Connect \(tool.name)")
                    .font(.headline)
            }

            if availableTabs.count > 1 {
                Picker("Auth Method", selection: $selectedTab) {
                    ForEach(availableTabs, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch selectedTab {
            case .oauth: oauthTab
            case .apiKey: apiKeyTab
            }

            Divider()

            HStack {
                if tool.isConnected {
                    Button("Disconnect") { disconnect() }
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                if selectedTab == .apiKey {
                    Button("Save") { saveAPIKey() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(apiKeyInput.isEmpty)
                }
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            selectedTab = tool.effectiveSupportsOAuth ? .oauth : .apiKey
            if tool.activeAuthMethod == "api_key" && tool.effectiveSupportsAPIKey {
                selectedTab = .apiKey
            }
            apiKeyInput = KeychainClient.load(toolID: tool.id, key: .apiKey) ?? ""
            baseURLInput = tool.baseURL ?? ""

            if let saved = tool.selectedScopeKeys {
                enabledScopeKeys = Set(saved)
            } else if let scopes = toolSpec?.auth.availableScopes {
                enabledScopeKeys = Set(scopes.compactMap { key, spec in spec.default == true ? key : nil })
            }
        }
    }

    // MARK: - OAuth Tab

    private var oauthTab: some View {
        VStack(spacing: 12) {
            if tool.isConnected && tool.effectiveAuthMethod == "oauth" {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    Text("Connected via OAuth")
                        .font(.subheadline)
                    if let scopes = tool.oauthScopes {
                        Text("Scopes: \(scopes)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let expires = KeychainClient.loadExpiry(toolID: tool.id) {
                        Text("Token expires: \(expires.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)

                    Text("Sign in with your \(tool.name) account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !availableScopes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Access")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(availableScopes, id: \.key) { item in
                                HStack {
                                    Text(item.spec.label)
                                        .font(.callout)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { enabledScopeKeys.contains(item.key) },
                                        set: { enabled in
                                            if enabled { enabledScopeKeys.insert(item.key) }
                                            else { enabledScopeKeys.remove(item.key) }
                                        }
                                    ))
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Text("Basin will open your browser to authenticate. Your credentials are never stored in the app — only a revocable access token.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    if isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for authorization...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            startOAuth()
                        } label: {
                            Label("Sign in with \(tool.name)", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(availableScopes.isEmpty ? false : enabledScopeKeys.isEmpty)
                    }

                    if let authError {
                        Text(authError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - API Key Tab

    private var apiKeyTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tool.id == "jira" {
                Text("Instance URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://your-org.atlassian.net", text: $baseURLInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            Text(tool.apiKeyLabel ?? "API Key")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Paste your token", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            apiKeyHelpText
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var apiKeyHelpText: some View {
        switch tool.id {
        case "jira":
            Text("Create a token at id.atlassian.com > Security > API tokens. Enter as email:token.")
                .font(.caption).foregroundStyle(.tertiary)
        case "github":
            Text("Create a Personal Access Token at github.com/settings/tokens with repo scope.")
                .font(.caption).foregroundStyle(.tertiary)
        case "toggl":
            Text("Find your API token at track.toggl.com/profile (bottom of the page).")
                .font(.caption).foregroundStyle(.tertiary)
        case "slack":
            Text("Create a Slack app at api.slack.com/apps, add chat:write scope, install to workspace.")
                .font(.caption).foregroundStyle(.tertiary)
        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func startOAuth() {
        guard let provider = tool.oauthProvider else { return }

        isAuthenticating = true
        authError = nil

        let selectedScopeURLs: [String]? = availableScopes.isEmpty ? nil :
            availableScopes.compactMap { item in enabledScopeKeys.contains(item.key) ? item.spec.scope : nil }

        Task {
            do {
                let tokens = try await OAuthClient.shared.startFlow(
                    provider: provider,
                    toolID: tool.id,
                    scopes: selectedScopeURLs
                )
                await MainActor.run {
                    try? KeychainClient.save(tokens.accessToken, toolID: tool.id, key: .accessToken)
                    if let refresh = tokens.refreshToken {
                        try? KeychainClient.save(refresh, toolID: tool.id, key: .refreshToken)
                    }
                    tool.oauthScopes = tokens.scope
                    if let expiresIn = tokens.expiresIn {
                        try? KeychainClient.saveExpiry(Date().addingTimeInterval(TimeInterval(expiresIn)), toolID: tool.id)
                    }
                    tool.activeAuthMethod = "oauth"
                    tool.isConnected = true
                    tool.selectedScopeKeys = Array(enabledScopeKeys)
                    tool.connectedAt = Date()
                    isAuthenticating = false
                }

                if tool.id == "jira" {
                    await JiraActionClient.fetchAndCacheProjects(tool: tool)
                }

                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { onDismiss() }
            } catch {
                await MainActor.run {
                    authError = error.localizedDescription
                    isAuthenticating = false
                }
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
        onDismiss()
    }

    private func disconnect() {
        tool.isConnected = false
        tool.oauthScopes = nil
        KeychainClient.deleteAll(toolID: tool.id)
        tool.activeAuthMethod = tool.effectiveSupportsOAuth ? "oauth" : "api_key"
        onDismiss()
    }
}
