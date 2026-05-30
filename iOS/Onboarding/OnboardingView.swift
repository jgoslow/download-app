import AVFoundation
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
                        onComplete: { appState.completeOnboarding() }
                    )
                    .tag(1)
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
                        Text("Catch your stream of consciousness and put it to work.")
                            .font(.body)
                            .foregroundStyle(.white)

                        Text("Basn gives you a place to capture your free-form thoughts aloud and channel them to the right destination — mix work and life, simple notes or even complicated workstreams. Connect to the tools you already use.")
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
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 12) {
                    Text("Microphone Access")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Basn needs your microphone to capture your voice notes. Your audio is processed on-device.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                statusCard
            }

            Spacer()

            VStack(spacing: 12) {
                primaryButton

                if micStatus == .denied {
                    Button("Skip for now") {
                        if modelReady { onComplete() }
                    }
                    .foregroundStyle(modelReady ? .white.opacity(0.6) : .white.opacity(0.3))
                    .font(.subheadline)
                    .disabled(!modelReady)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 100)
        }
        .onAppear {
            micStatus = AVAudioApplication.shared.recordPermission
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch micStatus {
        case .denied:
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone access denied")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text("Settings → Privacy → Microphone → allow Basn")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(16)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)

        case .granted:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text("Microphone access granted")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(16)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch micStatus {
        case .undetermined:
            Button(action: { Task { await requestPermission() } }) {
                Group {
                    if requesting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Allow Microphone").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
            .foregroundStyle(.white)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.3), lineWidth: 1))
            .disabled(requesting)

        case .denied:
            Button {
                if let url = URL(string: "app-settings:") { openURL(url) }
            } label: {
                Text("Open Settings")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
            .foregroundStyle(.white)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.3), lineWidth: 1))

        case .granted:
            Button(action: { if modelReady { onComplete() } }) {
                HStack(spacing: 8) {
                    if !modelReady {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(modelReady ? "Start using Basn" : "Waiting for model…")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(modelReady ? .blue : .white.opacity(0.15))
            .foregroundStyle(.white)
            .disabled(!modelReady)

        @unknown default:
            EmptyView()
        }
    }

    private func requestPermission() async {
        requesting = true
        await AVAudioApplication.requestRecordPermission()
        micStatus = AVAudioApplication.shared.recordPermission
        requesting = false
        if micStatus == .granted && modelReady {
            try? await Task.sleep(for: .milliseconds(500))
            onComplete()
        }
    }
}
