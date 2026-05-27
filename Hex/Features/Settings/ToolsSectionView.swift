//
//  ToolsSectionView.swift
//  Basin
//
//  Settings section for connecting external tools (Jira, Slack, Toggl, etc.).
//  Two-tab auth: OAuth (preferred) or API Key (fallback).
//

import ComposableArchitecture
import HexCore
import SwiftData
import SwiftUI

struct ToolsSectionView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Query(sort: \Tool.name) private var tools: [Tool]
    @State private var connectingTool: Tool?

    var body: some View {
        Section {
            ForEach(tools) { tool in
                toolRow(tool)
            }
        } header: {
            Text("Tools")
        }
        .sheet(item: $connectingTool) { tool in
            ToolConnectSheet(tool: tool, onDismiss: { connectingTool = nil })
        }
    }

    private func disconnectTool(_ tool: Tool) {
        tool.isConnected = false
        tool.oauthAccessToken = nil
        tool.oauthRefreshToken = nil
        tool.oauthExpiresAt = nil
        tool.oauthScopes = nil
        tool.apiKey = nil
        tool.activeAuthMethod = tool.effectiveSupportsOAuth ? "oauth" : "api_key"
    }

    @ViewBuilder
    private func toolRow(_ tool: Tool) -> some View {
        Label {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                    if tool.isConnected {
                        HStack(spacing: 6) {
                            Text(tool.effectiveAuthMethod == "oauth" ? "Connected via OAuth" : "Connected via API key")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Button("Disconnect") {
                                disconnectTool(tool)
                            }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red.opacity(0.7))
                        }
                    }
                }
                Spacer()

                if tool.isConnected {
                    Toggle("Auto", isOn: Binding(
                        get: { tool.autoExecute },
                        set: { tool.autoExecute = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Auto-execute actions without confirmation")

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Connected")
                } else {
                    Button("Connect") {
                        connectingTool = tool
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                }
            }
        } icon: {
            Image(systemName: tool.iconSystemName)
        }
    }
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
            // Header
            HStack(spacing: 10) {
                Image(systemName: tool.iconSystemName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Connect \(tool.name)")
                    .font(.headline)
            }

            // Tab picker (only if both methods available)
            if availableTabs.count > 1 {
                Picker("Auth Method", selection: $selectedTab) {
                    ForEach(availableTabs, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Content
            switch selectedTab {
            case .oauth:
                oauthTab
            case .apiKey:
                apiKeyTab
            }

            Divider()

            // Actions
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
            apiKeyInput = tool.apiKey ?? ""
            baseURLInput = tool.baseURL ?? ""

            // Initialize scope toggles from saved selection, or default to all "default: true" scopes
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
            if tool.isOAuthConnected {
                // Connected state
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
                    if let expires = tool.oauthExpiresAt {
                        Text("Token expires: \(expires.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                // Not connected — scope picker + sign in button
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)

                    Text("Sign in with your \(tool.name) account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Scope toggles (shown when the tool has selectable scopes)
                    if !availableScopes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Access")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(availableScopes, id: \.key) { key, spec in
                                Toggle(spec.label, isOn: Binding(
                                    get: { enabledScopeKeys.contains(key) },
                                    set: { enabled in
                                        if enabled { enabledScopeKeys.insert(key) }
                                        else { enabledScopeKeys.remove(key) }
                                    }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
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

        // Build the scopes to request from the enabled keys
        let selectedScopeURLs: [String]? = availableScopes.isEmpty ? nil :
            availableScopes.compactMap { key, spec in enabledScopeKeys.contains(key) ? spec.scope : nil }

        Task {
            do {
                let tokens = try await OAuthClient.shared.startFlow(
                    provider: provider,
                    toolID: tool.id,
                    scopes: selectedScopeURLs
                )
                await MainActor.run {
                    tool.oauthAccessToken = tokens.accessToken
                    tool.oauthRefreshToken = tokens.refreshToken
                    tool.oauthScopes = tokens.scope
                    if let expiresIn = tokens.expiresIn {
                        tool.oauthExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
                    }
                    tool.activeAuthMethod = "oauth"
                    tool.isConnected = true
                    tool.selectedScopeKeys = Array(enabledScopeKeys)
                    isAuthenticating = false
                }

                // Post-connect: fetch service metadata (projects, channels, etc.)
                if tool.id == "jira" {
                    await JiraActionClient.fetchAndCacheProjects(tool: tool)
                }

                // Auto-dismiss after a brief success display
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
        tool.apiKey = apiKeyInput.isEmpty ? nil : apiKeyInput
        tool.baseURL = baseURLInput.isEmpty ? nil : baseURLInput
        tool.activeAuthMethod = "api_key"
        tool.isConnected = !apiKeyInput.isEmpty
        onDismiss()
    }

    private func disconnect() {
        tool.isConnected = false
        tool.oauthAccessToken = nil
        tool.oauthRefreshToken = nil
        tool.oauthExpiresAt = nil
        tool.oauthScopes = nil
        tool.apiKey = nil
        tool.activeAuthMethod = tool.effectiveSupportsOAuth ? "oauth" : "api_key"
        onDismiss()
    }
}
