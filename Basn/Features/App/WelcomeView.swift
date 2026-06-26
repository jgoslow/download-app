import AVFoundation
import AppKit
import BasnCore
import ComposableArchitecture
import SwiftUI

// MARK: - WelcomeView

/// First-launch onboarding panel for macOS.
/// Step 0: Welcome + microphone permission.
/// Step 1: Language selection (auto-downloads the matching Parakeet model).
struct WelcomeView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var requesting = false
    @State private var modelStore = Store(initialState: ModelDownloadFeature.State()) {
        ModelDownloadFeature()
    }
    @State private var selectedLanguage: Language? = .english
    @State private var showAllModels = false

    enum Language: CaseIterable {
        case english
        case multilingual

        var modelName: String {
            switch self {
            case .english: return ParakeetModel.englishV2.identifier
            case .multilingual: return ParakeetModel.multilingualV3.identifier
            }
        }

        var title: String {
            switch self {
            case .english: return "English"
            case .multilingual: return "Multi-lingual"
            }
        }

        var description: String {
            switch self {
            case .english: return "Optimized for English — faster and more accurate for English speakers."
            case .multilingual: return "Transcribe in any language. Works best for non-English recordings."
            }
        }
    }

    @State private var showFlowSession = false

    var body: some View {
        Group {
            if step == 0 {
                welcomeStep
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            } else if step == 1 {
                languageStep
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            } else {
                setupFlowStep
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .sheet(isPresented: $showFlowSession) {
            FlowSessionView(
                prompts: FlowDefinition.setupPrompts,
                onComplete: {
                    showFlowSession = false
                    markDoneAndContinue()
                },
                onSkip: {
                    showFlowSession = false
                    markDoneAndContinue()
                }
            )
        }
        .frame(width: 480)
        .sheet(isPresented: $showAllModels) {
            allModelsSheet
        }
        .task {
            // Fetch available models then immediately start downloading Parakeet v2 (English)
            // so the download is in progress by the time the user reaches the language step.
            modelStore.send(.fetchModels)
            // Brief yield so modelsLoaded can process before we queue the download
            try? await Task.sleep(for: .milliseconds(200))
            modelStore.send(.selectModel(Language.english.modelName))
            modelStore.send(.downloadSelectedModel)
        }
    }

    // MARK: - Step 0: Welcome + Mic

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image("BasnIcon")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .cornerRadius(18)

                VStack(spacing: 12) {
                    Text("Welcome to Basn")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Capture your stream of consciousness and channel it..")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("Basn gives you a place to capture your free-form thoughts aloud and put them to work — mix work and life, simple notes or even complicated workstreams. Connect to the tools you already use.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text("Basn — let your thoughts flow.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 360)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                micPermissionCard

                if micStatus == .authorized || micStatus == .denied || micStatus == .restricted {
                    Button("Next: Choose your language  →") {
                        withAnimation { step = 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 48)
        .frame(minHeight: 480)
    }

    private var micPermissionCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(micStatusColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "mic.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(micStatusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Microphone")
                    .font(.headline)
                Text(micStatusDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            micActionButton
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var micActionButton: some View {
        switch micStatus {
        case .notDetermined:
            Button("Allow") {
                Task { await requestMic() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(requesting)

        case .authorized:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)

        case .denied, .restricted:
            Button("Open Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                )
            }
            .buttonStyle(.bordered)

        @unknown default:
            EmptyView()
        }
    }

    private var micStatusColor: Color {
        switch micStatus {
        case .authorized: .green
        case .denied, .restricted: .red
        default: .blue
        }
    }

    private var micStatusDescription: String {
        switch micStatus {
        case .notDetermined: "Required to capture your voice"
        case .authorized: "Access granted"
        case .denied: "Denied — open System Settings to allow"
        case .restricted: "Restricted by device policy"
        @unknown default: "Unknown"
        }
    }

    private func requestMic() async {
        requesting = true
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        micStatus = granted ? .authorized : .denied
        requesting = false
    }

    // MARK: - Step 1: Language Selection

    private var languageStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Choose your language")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Basn will download the best transcription model for your needs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            VStack(spacing: 12) {
                ForEach(Language.allCases, id: \.self) { language in
                    languageCard(language)
                }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 24)

            Divider()

            HStack {
                Button("Back") {
                    withAnimation { step = 0 }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()

                Button("See all models") {
                    showAllModels = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()

                nextButton
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
        }
        .frame(minHeight: 480)
    }

    @ViewBuilder
    private var nextButton: some View {
        let selected = selectedLanguage
        let isDownloading = modelStore.isDownloading &&
            modelStore.downloadingModelName == selected?.modelName
        let isDownloaded = selected.map { isLanguageDownloaded($0) } ?? false

        if selected == nil {
            Button("Next") { }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        } else if isDownloading {
            Button("Downloading…") { }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        } else {
            Button(isDownloaded ? "Next  →" : "Skip for now") {
                proceedToLanguage()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func languageCard(_ language: Language) -> some View {
        let isSelected = selectedLanguage == language
        let isDownloadingThis = modelStore.downloadingModels.contains(language.modelName)
        let isActivelyDownloading = modelStore.downloadingModelName == language.modelName
        let downloaded = isLanguageDownloaded(language)
        let progress = isActivelyDownloading ? modelStore.downloadProgress : 0

        return Button(action: { selectLanguage(language) }) {
            ZStack(alignment: .leading) {
                // progress fill that sweeps across the card background
                if isSelected && !downloaded {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: geo.size.width * CGFloat(progress))
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                }

                HStack(spacing: 14) {
                    // Selection indicator
                    ZStack {
                        if isSelected && isActivelyDownloading {
                            Circle()
                                .stroke(Color.blue.opacity(0.2), lineWidth: 2.5)
                                .frame(width: 22, height: 22)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .frame(width: 22, height: 22)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.3), value: progress)
                        } else if isSelected && downloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 22))
                        } else {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                                .font(.system(size: 22))
                        }
                    }
                    .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(language.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    // Status label on right
                    VStack(alignment: .trailing, spacing: 2) {
                        if isSelected {
                            if downloaded {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                    Text("Downloaded")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            } else if isActivelyDownloading {
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.blue)
                            } else if isDownloadingThis {
                                Text("Downloading…")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .frame(width: 84, alignment: .trailing)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? (downloaded ? Color.green.opacity(0.06) : Color.blue.opacity(0.04))
                    : Color(NSColor.controlBackgroundColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.4) : Color.gray.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - All Models Sheet

    private var allModelsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("All models")
                        .font(.headline)
                    Text("Select a model to download it automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { showAllModels = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                CuratedList(store: modelStore, directDownload: true)
                    .padding(24)
            }
        }
        .frame(width: 480, height: 440)
    }

    // MARK: - Step 2: Setup Flow Bridge

    private var setupFlowStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                VStack(spacing: 12) {
                    Text("Let your thoughts flow.")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))

                    Text("Basn works by capturing your thoughts as you speak (or type) and surfacing prompts for you during a flow session. Prompts can come from the flow, things you've said before, or other sources.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 360)

                    Text("Let's try it out with a **setup flow**.")
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 360)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button("▶  Start Flow") {
                    showFlowSession = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 260)

                Button("skip setup") {
                    markDoneAndContinue()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 48)
        .frame(minHeight: 480)
    }

    // MARK: - Actions

    private func isLanguageDownloaded(_ language: Language) -> Bool {
        modelStore.curatedModels.first { $0.internalName == language.modelName }?.isDownloaded ?? false
    }

    private func selectLanguage(_ language: Language) {
        selectedLanguage = language
        modelStore.send(.selectModel(language.modelName))
        let alreadyDownloadingThis = modelStore.isDownloading && modelStore.downloadingModelName == language.modelName
        if !isLanguageDownloaded(language) && !alreadyDownloadingThis {
            // Start the new download. Any previous download keeps running in the background;
            // ModelDownloadFeature will mark it downloaded when it finishes without
            // disrupting the UI state for the newly active download.
            modelStore.send(.downloadSelectedModel)
        }
    }

    private func proceedToLanguage() {
        let selectedModel = selectedLanguage?.modelName
        // Delete any models that finished downloading but weren't chosen.
        for model in modelStore.curatedModels where model.isDownloaded && model.internalName != selectedModel {
            modelStore.send(.deleteModel(model.internalName))
        }
        withAnimation { step = 2 }
    }

    private func markDoneAndContinue() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }
}
