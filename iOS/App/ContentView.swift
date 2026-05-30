import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .home
    @State private var useTypeMode = false
    @State private var showTextInput = false
    @State private var typedText = ""

    enum Tab { case home, record, settings }

    // Layout constants — all distances are from the safe-area top edge
    // (overlay(alignment:.bottom) aligns to content bottom = safe-area top edge)
    private let fabSize: CGFloat = 124
    private let tabHeight: CGFloat = 56
    private let toggleSize: CGFloat = 44

    // FAB center sits 28pt above the tab bar top line.
    // FAB bottom = center - radius = 28 - 62 = -34 … negative means it dips 34pt into the tab bar.
    // fabBottomPad puts the FAB's *bottom* edge at that position from overlay bottom:
    //   fabBottomPad = tabHeight - 28 - fabSize/2 = 56 - 28 - 62 = -34  → use 0 (pin bottom to overlay bottom)
    // Simpler: pad(.bottom, 0) puts FAB bottom at overlay bottom; center is 62pt above that.
    // Adjust by raising: fabBottomPad = 20 → FAB bottom 20pt above overlay, center 82pt, tab top 56pt → center 26pt above tab top.
    // 40 % of the FAB above the menu bar top → FAB top = tabHeight + 0.4×fabSize = 105.6 pt
    // FAB center = 105.6 − 62 = 43.6 pt; FAB bottom = −18.4 pt (dips into safe-area zone).
    private let fabBottomPad: CGFloat = -18

    // Toggle: bottom edge sits 12pt above the tab bar top line.
    private let toggleBottomPad: CGFloat = 68

    // Horizontal offset so the toggle is equidistant from the FAB's circular edge
    // and the menu bar top line.
    //
    // At the toggle's y level the FAB only extends horizontally to fabXAtToggleY
    // (chord of a circle), not the full radius. The vertical gap to the menu bar
    // is (toggleBottomPad - tabHeight). Setting horizontal gap equal gives:
    //   offset = -(fabXAtToggleY + verticalGap + toggleRadius)
    private var fabColor: Color {
        if useTypeMode { return .black }
        if appState.isTranscribing { return Color(.systemGray3) }
        return appState.isRecording ? .red : .blue
    }

    private var fabIcon: String {
        useTypeMode ? "keyboard" : (appState.isRecording ? "waveform" : "mic.fill")
    }

    private var toggleXOffset: CGFloat {
        let fabCenterY   = fabBottomPad  + fabSize   / 2   // 44 pt above safe-area top
        let toggleCenterY = toggleBottomPad + toggleSize / 2  // 90 pt above safe-area top
        let dy            = toggleCenterY - fabCenterY        // 46 pt
        let fabR          = fabSize / 2                       // 62 pt
        let fabXAtY       = sqrt(max(0, fabR * fabR - dy * dy)) // chord ≈ 41.6 pt
        let gap           = toggleBottomPad - tabHeight       // 12 pt (= vertical gap)
        return -(fabXAtY + gap + toggleSize / 2)             // ≈ −75.6 pt
    }

    var body: some View {
        tabContent
            // Reserve exactly tabHeight at the bottom; safe area is handled automatically.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: tabHeight)
            }
            // The visible bar (background + FAB + toggle) floats over the reserved space.
            .overlay(alignment: .bottom) {
                bottomBarOverlay
            }
            .sheet(isPresented: $showTextInput) {
                TextInputSheet(text: $typedText) {
                    showTextInput = false
                    typedText = ""
                }
            }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:     HomeView()
        case .record:   RecordView()
        case .settings: SettingsView()
        }
    }

    // MARK: - Bottom Bar Overlay

    private var bottomBarOverlay: some View {
        ZStack(alignment: .bottom) {

            // ── Tab bar strip ──────────────────────────────────────────────────
            // Items centered within tabHeight; background extends into safe area below.
            HStack(spacing: 0) {
                barItem(tab: .home, icon: "house.fill", label: "Home")
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: fabSize + 32)   // gap for FAB
                barItem(tab: .settings, icon: "gearshape.fill", label: "Settings")
                    .frame(maxWidth: .infinity)
            }
            .frame(height: tabHeight)
            // Background extends past the strip down into the device safe area.
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.4))
                            .frame(height: 0.5)
                    }
                    .ignoresSafeArea(edges: .bottom)
            }

            // ── Mode toggle ────────────────────────────────────────────────────
            // Completely above the tab bar top line.
            Button { handleToggle() } label: {
                ZStack {
                    Circle()
                        .fill(useTypeMode ? Color.blue : Color.black)
                        .shadow(color: (useTypeMode ? Color.blue : Color.black).opacity(0.35), radius: 4, y: 2)
                    Image(systemName: useTypeMode ? "mic.fill" : "keyboard")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .frame(width: toggleSize, height: toggleSize)
            // Horizontal: equidistant from FAB circular edge and menu bar top.
            .offset(x: toggleXOffset)
            // Vertical: bottom edge 60pt above safe-area top → clears tab bar top (56pt) by 4pt.
            .padding(.bottom, toggleBottomPad)

            // ── FAB ────────────────────────────────────────────────────────────
            // Large circle, overlapping the top of the tab bar. Red while recording.
            Button { handleFabTap() } label: {
                ZStack {
                    Circle()
                        .fill(fabColor)
                        .shadow(color: fabColor.opacity(0.4), radius: 16, y: 4)
                    if appState.isTranscribing {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.large)
                    } else {
                        Image(systemName: fabIcon)
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: fabSize, height: fabSize)
            .disabled(appState.isTranscribing)
            // Bottom edge sits fabBottomPad above safe-area top.
            .padding(.bottom, fabBottomPad)
        }
    }

    // MARK: - Actions

    private func handleFabTap() {
        selectedTab = .record
        if useTypeMode {
            showTextInput = true
        } else {
            Task {
                if appState.isRecording {
                    await appState.stopRecording()
                } else {
                    await appState.startRecording()
                }
            }
        }
    }

    private func handleToggle() {
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            useTypeMode.toggle()
        }
        if appState.isRecording { Task { await appState.stopRecording() } }
    }

    // MARK: - Bar Item

    private func barItem(tab: Tab, icon: String, label: String) -> some View {
        let isActive = selectedTab == tab
        return Button { selectedTab = tab } label: {
            // Icon + label centered inside the fixed tabHeight frame — no safe area padding here.
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                    .foregroundStyle(isActive ? .blue : .secondary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? .blue : .secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(height: tabHeight)
    }
}

// MARK: - Text Input Sheet

private struct TextInputSheet: View {
    @Binding var text: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Type your thoughts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onDismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            // TODO: wire to session creation (Phase 7)
                            onDismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
