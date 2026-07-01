import AuthenticationServices
import AVFoundation
import Speech
import SwiftData
import SwiftUI

// MARK: - OnboardingView

/// Full-screen dark onboarding with looping water video background.
/// Step 0: Welcome. Step 1: Mic permission (gated on model download).
/// Place "onboarding_water_mill.mp4" in the iOS target bundle to enable the video background.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var page = 0

    var body: some View {
        ZStack {
            // Video background — falls back to dark gradient if file not bundled
            videoBackground

            // Vignette scrim — darker at top/bottom where text lives, lets video breathe in the middle
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.72), location: 0.0),
                    .init(color: .black.opacity(0.35), location: 0.4),
                    .init(color: .black.opacity(0.35), location: 0.6),
                    .init(color: .black.opacity(0.78), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ZStack(alignment: .bottom) {
                TabView(selection: $page) {
                    WelcomePage(onContinue: { withAnimation { page = 1 } })
                        .tag(0)
                    MicPermissionPage(
                        modelReady: appState.isModelDownloaded(variant: appState.settings.selectedModel),
                        onComplete: { withAnimation { page = 2 } }
                    )
                    .tag(1)
                    SetupFlowBridgePage(
                        onFlowComplete: {
                            appState.completeOnboarding()
                            appState.completeSetupFlow()
                        },
                        modelReady: appState.isModelDownloaded(variant: appState.settings.selectedModel)
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                if appState.downloadingModelVariant != nil || !appState.isModelDownloaded(variant: appState.settings.selectedModel) {
                    downloadBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: appState.downloadingModelVariant != nil)
        }
        .preferredColorScheme(.dark)
        .task {
            await appState.downloadDefaultModelIfNeeded()
        }
    }

    // MARK: - Video Background

    private var videoBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LoopingVideoView(filename: "onboarding_water_mill")
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: - Download Banner

    private var downloadBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if appState.downloadingModelVariant != nil {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.7))
                }
                Text(
                    appState.downloadingModelVariant != nil
                        ? "Downloading transcription model…"
                        : "Preparing transcription model…"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

                Spacer()

                if appState.downloadingModelVariant != nil && appState.modelDownloadProgress > 0 {
                    Text("\(Int(appState.modelDownloadProgress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ProgressView(value: appState.downloadingModelVariant != nil ? appState.modelDownloadProgress : 0)
                .tint(.white)
        }
        .background(.ultraThinMaterial.opacity(0.6))
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white.gradient)
                    .symbolEffect(.pulse)

                VStack(spacing: 14) {
                    Text("Welcome to Basn")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Capture your stream of consciousness and channel it..")
                            .font(.body)
                            .foregroundStyle(.white)

                        Text("Basn gives you a place to capture your free-form thoughts aloud and put them to work — mix work and life, simple notes or even complicated workstreams. Connect to the tools you already use.")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.75))

                        Text("Basn — let your thoughts flow.")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.6))
                            .italic()
                    }
                    .padding(.horizontal, 36)
                }
            }

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
            .foregroundStyle(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 32)
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Mic Permission Page

private struct MicPermissionPage: View {
    let modelReady: Bool
    let onComplete: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var micStatus = AVAudioApplication.shared.recordPermission
    @State private var speechStatus = SFSpeechRecognizer.authorizationStatus()
    @State private var requestingMic = false
    @State private var requestingSpeech = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Text("Two quick permissions")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Both make Basn work better. Neither leaves your device.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Mic permission card
                permissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Records your voice. Audio is transcribed on-device using Whisper — never uploaded. Deleted after transcription completed.",
                    status: micStatusLabel,
                    isGranted: micStatus == .granted,
                    isDenied: micStatus == .denied,
                    isRequesting: requestingMic,
                    buttonLabel: micButtonLabel,
                    onTap: {
                        switch micStatus {
                        case .undetermined: Task { await requestMic() }
                        case .denied: openURL(URL(string: "app-settings:")!)
                        default: break
                        }
                    }
                )

                // Speech recognition card
                permissionCard(
                    icon: "waveform",
                    title: "Live Transcript",
                    description: "Shows what you're saying in real time during a flow, and lets you say \"next\" to advance hands-free. Processed on-device by Apple.",
                    status: speechStatusLabel,
                    isGranted: speechStatus == .authorized,
                    isDenied: speechStatus == .denied,
                    isRequesting: requestingSpeech,
                    buttonLabel: speechButtonLabel,
                    onTap: {
                        switch speechStatus {
                        case .notDetermined: Task { await requestSpeech() }
                        case .denied: openURL(URL(string: "app-settings:")!)
                        default: break
                        }
                    }
                )
            }

            Spacer()

            VStack(spacing: 14) {
                // Continue — enabled once mic is granted
                Button(action: { if modelReady { onComplete() } }) {
                    HStack(spacing: 8) {
                        if !modelReady {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(modelReady ? "Continue" : "Waiting for model…")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(micStatus == .granted && modelReady ? .blue : .white.opacity(0.15))
                .foregroundStyle(.white)
                .disabled(micStatus != .granted || !modelReady)

                if micStatus != .granted {
                    Button("skip for now") { if modelReady { onComplete() } }
                        .foregroundStyle(modelReady ? .white.opacity(0.4) : .white.opacity(0.2))
                        .font(.subheadline)
                        .disabled(!modelReady)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 100)
        }
        .onAppear {
            micStatus = AVAudioApplication.shared.recordPermission
            speechStatus = SFSpeechRecognizer.authorizationStatus()
        }
    }

    // MARK: - Permission Card

    @ViewBuilder
    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        status: String?,
        isGranted: Bool,
        isDenied: Bool,
        isRequesting: Bool,
        buttonLabel: String,
        onTap: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isGranted ? .green : .white.opacity(0.9))
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(isGranted ? .green : isDenied ? .red.opacity(0.8) : .white.opacity(0.4))
                }
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            if !isGranted {
                Button(action: onTap) {
                    Group {
                        if isRequesting {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Text(buttonLabel).font(.subheadline.weight(.medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
                .foregroundStyle(.white)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.25), lineWidth: 1))
                .disabled(isRequesting)
            }
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isGranted ? Color.green.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 28)
        .animation(.easeInOut(duration: 0.25), value: isGranted)
    }

    // MARK: - Labels

    private var micStatusLabel: String? {
        switch micStatus {
        case .granted: return "Granted ✓"
        case .denied: return "Denied"
        default: return nil
        }
    }

    private var micButtonLabel: String {
        micStatus == .denied ? "Open Settings" : "Allow Microphone"
    }

    private var speechStatusLabel: String? {
        switch speechStatus {
        case .authorized: return "Enabled ✓"
        case .denied, .restricted: return "Denied"
        default: return nil
        }
    }

    private var speechButtonLabel: String {
        speechStatus == .denied ? "Open Settings" : "Enable Voice Transcript"
    }

    // MARK: - Permission requests

    private func requestMic() async {
        requestingMic = true
        await AVAudioApplication.requestRecordPermission()
        micStatus = AVAudioApplication.shared.recordPermission
        requestingMic = false
    }

    private func requestSpeech() async {
        requestingSpeech = true
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { s in continuation.resume(returning: s) }
        }
        speechStatus = status
        requestingSpeech = false
    }
}

// MARK: - Setup Flow Bridge Page

private struct SetupFlowBridgePage: View {
    let onFlowComplete: () -> Void
    let modelReady: Bool

    @Environment(\.modelContext) private var modelContext

    // Wizard state — one fullScreenCover drives all post-flow screens
    @State private var activeCover: SetupCover?
    @State private var toolsToConnect: [Tool] = []
    @State private var connectedToolIDs: Set<String> = []
    @State private var connectIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 36) {
                VStack(spacing: 16) {
                    Text("Let your thoughts flow.")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Basn listens while you speak and guides you with prompts. Click the button below to start a ”setup flow”.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }

                Button {
                    activeCover = .flow
                } label: {
                    ZStack {
                        Circle()
                            .fill(modelReady ? Color.blue : Color.white.opacity(0.15))
                            .frame(width: 72, height: 72)
                        if !modelReady {
                            ProgressView().tint(.white.opacity(0.6))
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!modelReady)
            }

            Spacer()

            Button("skip for now", action: onFlowComplete)
                .foregroundStyle(.white.opacity(0.4))
                .font(.subheadline)
                .padding(.bottom, 100)
        }
        .fullScreenCover(item: $activeCover) { cover in
            coverView(for: cover)
        }
    }

    // MARK: - Cover routing

    @ViewBuilder
    private func coverView(for cover: SetupCover) -> some View {
        switch cover {
        case .nativeApps:
            SetupNativeAppsView(onContinue: {
                activeCover = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    if toolsToConnect.isEmpty {
                        let toolOrder = ["jira", "github", "slack", "toggl", "google", "wave"]
                        let stored = (try? modelContext.fetch(FetchDescriptor<Tool>())) ?? []
                        toolsToConnect = toolOrder.compactMap { id in stored.first(where: { $0.id == id }) }
                    }
                    activeCover = .connectTool(index: 0)
                }
            })

        case .flow:
            FlowSessionView(
                prompts: FlowPrompt.setupFlowPrompts,
                onComplete: { handleFlowEnd() },
                onSkip: { activeCover = nil; onFlowComplete() },
                autoStart: true,
                onResult: { choices, _ in
                    let toolOrder = ["jira", "github", "slack", "toggl", "google", "wave"]
                    let selected = choices[5, default: []]
                    // Fetch from context at result time — avoids stale closure capture
                    let stored = (try? modelContext.fetch(FetchDescriptor<Tool>())) ?? []
                    let matched = toolOrder.filter { selected.contains($0) }
                    let rest = toolOrder.filter { !selected.contains($0) }
                    toolsToConnect = (matched + rest).compactMap { id in
                        stored.first(where: { $0.id == id })
                    }
                    connectIndex = 0
                    connectedToolIDs = []
                }
            )

        case .connectTool(let index):
            if index < toolsToConnect.count {
                let tool = toolsToConnect[index]
                SetupToolConnectView(
                    tool: tool,
                    stepNumber: index + 1,
                    totalSteps: toolsToConnect.count,
                    onConnect: {
                        connectedToolIDs.insert(tool.id)
                        advanceTool()
                    },
                    onSkip: { advanceTool() }
                )
            } else {
                SetupDoneView(connectedTools: [], onFinish: { activeCover = nil; onFlowComplete() })
            }

        case .workflows:
            SetupWorkflowsView(
                connectedTools: toolsToConnect.filter { connectedToolIDs.contains($0.id) },
                onContinue: {
                    activeCover = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        activeCover = .suggestedFlow
                    }
                }
            )

        case .suggestedFlow:
            SetupSuggestedFlowView(
                onContinue: {
                    activeCover = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        activeCover = .done
                    }
                }
            )

        case .done:
            SetupDoneView(
                connectedTools: toolsToConnect.filter { connectedToolIDs.contains($0.id) },
                onFinish: { activeCover = nil; onFlowComplete() }
            )
        }
    }

    // MARK: - Navigation

    private func handleFlowEnd() {
        activeCover = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            // Show native apps screen first, then proceed to third-party tool connect
            activeCover = .nativeApps
        }
    }

    private func advanceTool() {
        activeCover = nil
        let next = connectIndex + 1
        connectIndex = next
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if next < toolsToConnect.count {
                activeCover = .connectTool(index: next)
            } else {
                // After all tools: show workflow suggestions
                activeCover = .workflows
            }
        }
    }
}

// Drives which fullScreenCover is active in the setup wizard
private enum SetupCover: Identifiable {
    case flow
    case nativeApps
    case connectTool(index: Int)
    case workflows
    case suggestedFlow
    case done

    var id: String {
        switch self {
        case .flow: return "flow"
        case .nativeApps: return "native-apps"
        case .connectTool(let i): return "connect-\(i)"
        case .workflows: return "workflows"
        case .suggestedFlow: return "suggested-flow"
        case .done: return "done"
        }
    }
}

// MARK: - Setup Native Apps View

private struct SetupNativeAppsView: View {
    let onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tool.name) private var allTools: [Tool]

    @State private var appeared = false

    private var systemTools: [Tool] {
        allTools.filter { $0.effectiveAuthMethod == "system" }
    }

    private static let descriptions: [String: String] = [
        "apple-reminders": "Set reminders from your captures.",
        "apple-calendar":  "Create calendar events hands-free.",
        "apple-notes":     "Jot notes directly into Apple Notes.",
        "apple-files":     "Save files to your iCloud Drive.",
        "apple-mail":      "Draft and send emails by voice.",
        "apple-messages":  "Send iMessages from a capture.",
        "apple-maps":      "Navigate to places you mention.",
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.1))
                                .frame(width: 72, height: 72)
                            Image(systemName: "iphone.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .scaleEffect(appeared ? 1 : 0.5)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.65), value: appeared)

                        VStack(spacing: 10) {
                            Text("Built-in apps")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Basn can work with apps already on your iPhone — no account needed. Turn on the ones you'd like to use.")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.65))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
                    }

                    VStack(spacing: 0) {
                        ForEach(systemTools) { tool in
                            @Bindable var tool = tool
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.white.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: tool.iconSystemName)
                                        .font(.system(size: 18))
                                        .foregroundStyle(tool.isEnabled ? .white : .white.opacity(0.4))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(tool.isEnabled ? .white : .white.opacity(0.5))
                                    Text(Self.descriptions[tool.id] ?? "Use from your captures.")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.4))
                                }

                                Spacer()

                                Toggle("", isOn: $tool.isEnabled)
                                    .toggleStyle(.switch)
                                    .tint(.blue)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)

                            if tool.id != systemTools.last?.id {
                                Divider()
                                    .background(.white.opacity(0.08))
                                    .padding(.leading, 82)
                            }
                        }
                    }
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.easeOut(duration: 0.45).delay(0.2), value: appeared)
                }

                Spacer()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.bottom, 80)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.35), value: appeared)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                appeared = true
            }
        }
    }
}

// MARK: - Setup Tool Connect View

private struct SetupToolConnectView: View {
    @Bindable var tool: Tool
    let stepNumber: Int
    let totalSteps: Int
    let onConnect: () -> Void
    let onSkip: () -> Void

    @State private var apiKeyInput = ""
    @State private var isAuthenticating = false
    @State private var authError: String?

    private var toolSpec: ToolDefinitionSpec? { ToolDefinitionLoader.load(tool.id) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: step counter + skip
                HStack {
                    Text("\(stepNumber) of \(totalSteps)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Button("skip", action: onSkip)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 32)
                .padding(.top, 64)

                Spacer()

                // Tool identity
                VStack(spacing: 28) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 96, height: 96)
                        Image(systemName: toolSpec?.icon ?? tool.iconSystemName)
                            .font(.system(size: 42))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 10) {
                        Text("Connect \(tool.name)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(toolDescription(tool.id))
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 48)
                    }
                }

                Spacer()

                // Auth controls
                VStack(spacing: 14) {
                    if let error = authError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    if tool.effectiveSupportsOAuth {
                        Button {
                            Task { await connectOAuth() }
                        } label: {
                            HStack(spacing: 10) {
                                if isAuthenticating { ProgressView().controlSize(.small).tint(.white) }
                                Text(isAuthenticating ? "Connecting…" : "Connect with OAuth")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .disabled(isAuthenticating)
                    }

                    if tool.effectiveSupportsAPIKey {
                        VStack(spacing: 10) {
                            if tool.effectiveSupportsOAuth {
                                Text("or enter an API key")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.35))
                            }

                            SecureField(tool.apiKeyLabel ?? "API Key", text: $apiKeyInput)
                                .padding(14)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                                .tint(.blue)
                                .padding(.horizontal, 32)

                            if !apiKeyInput.isEmpty {
                                Button("Save key", action: connectAPIKey)
                                    .font(.headline)
                                    .padding(.horizontal, 32)
                            }
                        }
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            apiKeyInput = KeychainClient.load(toolID: tool.id, key: .apiKey) ?? ""
        }
    }

    private func toolDescription(_ id: String) -> String {
        switch id {
        case "jira":   return "Create and update issues from your captures."
        case "github": return "Turn captures into issues and pull requests."
        case "slack":  return "Send messages and updates to your channels."
        case "toggl":  return "Log time from what you capture."
        case "google": return "Schedule events and draft emails."
        case "wave":   return "Track expenses and income from your notes."
        default:       return "Connect to use it in your workflows."
        }
    }

    private func connectOAuth() async {
        guard let provider = tool.oauthProvider else { return }
        isAuthenticating = true
        authError = nil
        do {
            let tokens = try await OAuthClient.shared.startFlow(provider: provider, toolID: tool.id, scopes: nil)
            try? KeychainClient.save(tokens.accessToken, toolID: tool.id, key: .accessToken)
            if let r = tokens.refreshToken { try? KeychainClient.save(r, toolID: tool.id, key: .refreshToken) }
            if let exp = tokens.expiresIn {
                try? KeychainClient.saveExpiry(Date().addingTimeInterval(TimeInterval(exp)), toolID: tool.id)
            }
            tool.oauthScopes = tokens.scope
            tool.activeAuthMethod = "oauth"
            tool.isConnected = true
            tool.connectedAt = Date()
            try? await Task.sleep(for: .milliseconds(600))
            onConnect()
        } catch {
            authError = error.localizedDescription
        }
        isAuthenticating = false
    }

    private func connectAPIKey() {
        guard !apiKeyInput.isEmpty else { return }
        try? KeychainClient.save(apiKeyInput, toolID: tool.id, key: .apiKey)
        tool.isConnected = true
        tool.activeAuthMethod = "api_key"
        tool.connectedAt = Date()
        onConnect()
    }
}

// MARK: - Setup Done View

private struct SetupDoneView: View {
    let connectedTools: [Tool]
    let onFinish: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                        .scaleEffect(appeared ? 1.0 : 0.4)
                        .opacity(appeared ? 1.0 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: appeared)

                    VStack(spacing: 12) {
                        Text("You're all set.")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if connectedTools.isEmpty {
                            Text("You can connect tools any time in Settings.")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.55))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 48)
                        } else {
                            VStack(spacing: 8) {
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.4))

                                HStack(spacing: 16) {
                                    ForEach(connectedTools) { tool in
                                        VStack(spacing: 4) {
                                            Image(systemName: tool.iconSystemName)
                                                .font(.system(size: 20))
                                                .foregroundStyle(.white.opacity(0.85))
                                            Text(tool.name)
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()

                Button(action: onFinish) {
                    Text("Start using Basn")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.bottom, 80)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                appeared = true
            }
        }
    }
}

// MARK: - Setup Workflows View (placeholder)

private struct SetupWorkflowsView: View {
    let connectedTools: [Tool]
    let onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 96, height: 96)
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 42))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(appeared ? 1.0 : 0.5)
                    .opacity(appeared ? 1.0 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65), value: appeared)

                    VStack(spacing: 14) {
                        Text("Your workflows")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Based on what you told us, Basn will suggest workflows that route your captures to the right places.")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 48)

                        Text("Workflow suggestions coming soon.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.top, 8)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
                }

                Spacer()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.bottom, 80)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.3), value: appeared)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                appeared = true
            }
        }
    }
}

// MARK: - Setup Suggested Flow View (placeholder)

private struct SetupSuggestedFlowView: View {
    let onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 96, height: 96)
                        Image(systemName: "drop.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse)
                    }
                    .scaleEffect(appeared ? 1.0 : 0.5)
                    .opacity(appeared ? 1.0 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65), value: appeared)

                    VStack(spacing: 14) {
                        Text("Your first flow")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Basn will suggest a flow that fits how you work — a regular capture ritual that keeps you moving.")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 48)

                        Text("Flow suggestions coming soon.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.top, 8)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
                }

                Spacer()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.bottom, 80)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.3), value: appeared)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                appeared = true
            }
        }
    }
}
