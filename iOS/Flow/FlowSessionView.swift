import AVFoundation
import BasinShared
import Speech
import SwiftUI

// MARK: - FlowSessionView

/// Full-screen flow session experience. Drives a list of FlowPrompts with a live transcript
/// area at the top, a centered prompt carousel, and dot navigation at the bottom.
///
/// Used for the onboarding setup flow and for all user-defined flows going forward.
struct FlowSessionView: View {
    let prompts: [FlowPrompt]
    let onComplete: () -> Void
    let onSkip: () -> Void
    let autoStart: Bool
    /// Optional: fires with chip selections + transcript just before `onComplete`.
    let onResult: (([Int: Set<String>], [String]) -> Void)?

    @State private var model: FlowSessionViewModel

    init(
        prompts: [FlowPrompt],
        onComplete: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        autoStart: Bool = false,
        onResult: (([Int: Set<String>], [String]) -> Void)? = nil
    ) {
        self.prompts = prompts
        self.onComplete = onComplete
        self.onSkip = onSkip
        self.autoStart = autoStart
        self.onResult = onResult
        _model = State(initialValue: FlowSessionViewModel(prompts: prompts))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Pre-start: centered waveform button only
            if !model.isStarted {
                preStartView
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .offset(y: -60))
                    ))
            }

            // Main flow layout — appears after start
            if model.isStarted {
                startedLayout
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 28)),
                        removal: .opacity
                    ))
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await model.startTimers()

            // Request speech recognition permission; fall back to keyboard if denied
            let speechStatus = await FlowTranscriptionEngine.requestAuthorization()
            if speechStatus != .authorized || AVAudioApplication.shared.recordPermission != .granted {
                model.useTextInput = true
            }

            if autoStart {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    model.startFlow()
                }
            }
        }
        .onDisappear {
            model.stopTranscription()
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard model.isStarted, !model.isTranscriptExpanded else { return }
                    if value.translation.width < -40 { model.advance() }
                    else if value.translation.width > 40 { model.goBack() }
                }
        )
    }

    // MARK: - Pre-start View

    private var preStartView: some View {
        Button {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                model.startFlow()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: "waveform")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Started Layout

    private var startedLayout: some View {
        VStack(spacing: 0) {
            LiveTranscriptView(
                entries: model.transcriptEntries,
                partialText: model.currentPartialText,
                speechDenied: model.isSpeechRecognitionDenied,
                isExpanded: $model.isTranscriptExpanded
            )

            Spacer(minLength: 0)

            if !model.isComplete {
                PromptCarouselView(model: model)
                    .padding(.horizontal, 32)
            } else {
                completionView
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 0)

            flowBottomBar
        }
    }

    // MARK: - Flow Bottom Bar

    private var flowBottomBar: some View {
        VStack(spacing: 14) {
            PromptDotNavView(model: model)

            HStack(alignment: .center) {
                // Input mode toggles (left)
                HStack(spacing: 18) {
                    Button {
                        withAnimation { model.useTextInput = false }
                        model.startTranscriptionIfNeeded()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(!model.useTextInput ? .white : .white.opacity(0.28))
                    }

                    Button {
                        withAnimation { model.useTextInput = true }
                        model.stopTranscription()
                    } label: {
                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(model.useTextInput ? .white : .white.opacity(0.28))
                    }
                }

                Spacer()

                // Flow name (right, tappable for future flow switching)
                Button(action: {}) {
                    Text("Setup Flow")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 52)
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("All set.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("We've captured your setup. Give us a moment to prepare your flows and workflows.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button("Finish Setup") {
                onResult?(model.selectedChoices, model.transcriptEntries.map(\.sentence))
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.top, 8)
        }
    }
}

// MARK: - TranscriptEntry

struct TranscriptEntry: Identifiable {
    let id = UUID()
    let sentence: String
    let promptIndex: Int
    let promptTitle: String
}

// MARK: - FlowSessionViewModel

@Observable
@MainActor
final class FlowSessionViewModel {
    let prompts: [FlowPrompt]
    var activeIndex: Int = 0
    var transcriptEntries: [TranscriptEntry] = []
    var currentPartialText: String = ""
    var isTranscriptExpanded: Bool = false
    var selectedChoices: [Int: Set<String>] = [:]
    var answeredPromptIDs: Set<Int> = []
    var timerRemaining: Double = 0
    var isComplete: Bool = false
    var showPrompt: Bool = true
    var useTextInput: Bool = false
    var textInputDraft: String = ""
    var showCheckmark: Bool = false
    var isStarted: Bool = false
    var isSpeechRecognitionDenied: Bool = false

    private var timerTask: Task<Void, Never>?
    private var transcriptionEngine: FlowTranscriptionEngine?

    init(prompts: [FlowPrompt]) {
        self.prompts = prompts
        timerRemaining = prompts.first?.timerSeconds ?? 0
    }

    func startFlow() {
        guard !isStarted else { return }
        isStarted = true
        // Default to keyboard if mic permission hasn't been granted
        if AVAudioApplication.shared.recordPermission != .granted {
            useTextInput = true
        }
        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        isSpeechRecognitionDenied = speechAuth == .denied || speechAuth == .restricted
        startCurrentTimer()
        if !useTextInput {
            startTranscriptionIfNeeded()
        }
    }

    // MARK: - Transcription

    func startTranscriptionIfNeeded() {
        guard transcriptionEngine == nil,
              !useTextInput,
              AVAudioApplication.shared.recordPermission == .granted,
              SFSpeechRecognizer.authorizationStatus() == .authorized
        else { return }

        let engine = FlowTranscriptionEngine()
        engine.onPartialUpdate = { [weak self] text in
            self?.currentPartialText = text
        }
        engine.onSentenceComplete = { [weak self] sentence in
            self?.appendTranscriptSentence(sentence)
            self?.currentPartialText = ""
        }
        engine.onNextCommand = { [weak self] in
            self?.advance()
        }
        do {
            try engine.start()
            transcriptionEngine = engine
        } catch {
            // Transcription unavailable — fall back to keyboard silently
            useTextInput = true
        }
    }

    func stopTranscription() {
        transcriptionEngine?.stop()
        transcriptionEngine = nil
        currentPartialText = ""
    }

    // MARK: - Properties

    var activePrompt: FlowPrompt? {
        guard activeIndex < prompts.count else { return nil }
        return prompts[activeIndex]
    }

    var timerProgress: Double {
        guard let prompt = activePrompt, let seconds = prompt.timerSeconds, seconds > 0 else { return 0 }
        return timerRemaining / seconds
    }

    // MARK: - Navigation

    func advanceWithCheckmark() {
        guard !isComplete, isStarted, !showCheckmark else { return }
        timerTask?.cancel()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { showCheckmark = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation { showCheckmark = false }
            try? await Task.sleep(for: .milliseconds(100))
            advance()
        }
    }

    func advance() {
        guard !isComplete, isStarted else { return }
        let nextIndex = activeIndex + 1
        if nextIndex >= prompts.count {
            stopTranscription()
            withAnimation(.easeInOut(duration: 0.4)) { isComplete = true }
            return
        }
        transitionToPrompt(nextIndex)
    }

    func goBack() {
        guard activeIndex > 0, isStarted else { return }
        transitionToPrompt(activeIndex - 1)
    }

    func jumpToPrompt(_ index: Int) {
        guard index >= 0, index < prompts.count, isStarted else { return }
        transitionToPrompt(index)
    }

    private func transitionToPrompt(_ index: Int) {
        timerTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { showPrompt = false }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            activeIndex = index
            timerRemaining = prompts[index].timerSeconds ?? 0
            withAnimation(.easeIn(duration: 0.25)) { showPrompt = true }
            startCurrentTimer()
        }
    }

    // MARK: - Choice Selection

    func toggleChoice(promptID: Int, choiceID: String) {
        var current = selectedChoices[promptID, default: []]
        if current.contains(choiceID) { current.remove(choiceID) }
        else { current.insert(choiceID) }
        selectedChoices[promptID] = current

        if current.isEmpty { answeredPromptIDs.remove(promptID) }
        else { answeredPromptIDs.insert(promptID) }
    }

    func markAnswered(promptID: Int) {
        guard !answeredPromptIDs.contains(promptID) else { return }
        answeredPromptIDs.insert(promptID)
        if activePrompt?.id == promptID && activePrompt?.isRequired == true {
            Task {
                try? await Task.sleep(for: .milliseconds(1200))
                advance()
            }
        }
    }

    // MARK: - Text Input

    func submitTextInput() {
        guard !textInputDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        appendTranscriptSentence(textInputDraft)
        if let id = activePrompt?.id { markAnswered(promptID: id) }
        textInputDraft = ""
    }

    func appendTranscriptSentence(_ sentence: String) {
        let entry = TranscriptEntry(
            sentence: sentence,
            promptIndex: activeIndex,
            promptTitle: activePrompt?.title ?? ""
        )
        transcriptEntries.append(entry)
        if transcriptEntries.count > 20 { transcriptEntries.removeFirst() }
    }

    // MARK: - Timers

    func startTimers() async {}

    private func startCurrentTimer() {
        timerTask?.cancel()
        guard let seconds = activePrompt?.timerSeconds, seconds > 0 else { return }
        timerRemaining = seconds
        timerTask = Task { @MainActor in
            let interval: Double = 0.05
            while timerRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                timerRemaining = max(0, timerRemaining - interval)
            }
            if !Task.isCancelled { advance() }
        }
    }
}

// MARK: - LiveTranscriptView

private struct LiveTranscriptView: View {
    let entries: [TranscriptEntry]
    let partialText: String
    let speechDenied: Bool
    @Binding var isExpanded: Bool

    @Environment(\.openURL) private var openURL

    private var isEmpty: Bool { entries.isEmpty && partialText.isEmpty }

    /// Collapse consecutive entries from the same prompt into groups.
    private func grouped(_ items: [TranscriptEntry]) -> [(title: String, sentences: [String])] {
        var result: [(title: String, sentences: [String])] = []
        for entry in items {
            if let last = result.indices.last, result[last].title == entry.promptTitle {
                result[last].sentences.append(entry.sentence)
            } else {
                result.append((title: entry.promptTitle, sentences: [entry.sentence]))
            }
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(isExpanded ? .vertical : []) {
                        VStack(alignment: .leading, spacing: 6) {
                            if isEmpty && speechDenied {
                                // Option B nudge: contextual, non-blocking
                                Button {
                                    openURL(URL(string: "app-settings:")!)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "waveform.slash")
                                            .font(.caption2)
                                        Text("Voice transcript off · Enable in Settings →")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.white.opacity(0.28))
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                let visible = isExpanded ? entries : Array(entries.suffix(3))
                                let groups = grouped(visible)
                                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                                    if !group.title.isEmpty {
                                        Text(group.title)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.22))
                                            .padding(.top, 4)
                                    }
                                    ForEach(Array(group.sentences.enumerated()), id: \.offset) { _, sentence in
                                        Text(sentence)
                                            .font(.callout)
                                            .foregroundStyle(.white.opacity(0.3))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                // Live in-progress speech — slightly brighter to show it's active
                                if !partialText.isEmpty {
                                    Text(partialText)
                                        .font(.callout)
                                        .foregroundStyle(.white.opacity(0.5))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id("partial")
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, isExpanded ? 56 : 16)
                        .padding(.bottom, 8)
                        .frame(minWidth: geo.size.width)
                    }
                    .onChange(of: entries.count) { _, _ in
                        withAnimation { proxy.scrollTo("partial", anchor: .bottom) }
                    }
                    .onChange(of: partialText) { _, _ in
                        withAnimation { proxy.scrollTo("partial", anchor: .bottom) }
                    }
                }
            }
            .frame(height: isExpanded ? UIScreen.main.bounds.height * 0.85 : UIScreen.main.bounds.height * 0.18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if !isExpanded && value.translation.height > 30 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isExpanded = true
                            }
                        } else if isExpanded && value.translation.height < -30 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isExpanded = false
                            }
                        }
                    }
            )

            if isExpanded {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
    }
}

// MARK: - PromptCarouselView

private struct PromptCarouselView: View {
    @Bindable var model: FlowSessionViewModel

    var body: some View {
        VStack(spacing: 24) {
            if model.showPrompt, let prompt = model.activePrompt {
                VStack(spacing: 12) {
                    Text(prompt.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    if !prompt.detail.isEmpty {
                        Text(prompt.detail)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: model.activeIndex)

                // Choice chips
                if let choices = prompt.choices, !choices.isEmpty {
                    ChoiceChipsView(
                        choices: choices,
                        selectedIDs: model.selectedChoices[prompt.id, default: []],
                        onToggle: { choiceID in
                            model.toggleChoice(promptID: prompt.id, choiceID: choiceID)
                        }
                    )
                    .transition(.opacity)
                }

                // Text input field (keyboard mode)
                if model.useTextInput {
                    textInputField
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else {
                // Beat gap between prompts
                Color.clear.frame(height: 60)
            }
        }
    }

    private var textInputField: some View {
        HStack(spacing: 8) {
            TextField("Type your response…", text: $model.textInputDraft, axis: .vertical)
                .lineLimit(1...4)
                .padding(12)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .tint(.blue)
                .submitLabel(.send)
                .onSubmit { model.submitTextInput() }

            Button {
                model.submitTextInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(model.textInputDraft.isEmpty ? .white.opacity(0.3) : .blue)
            }
            .disabled(model.textInputDraft.isEmpty)
        }
    }
}

// MARK: - ChoiceChipsView

private struct ChoiceChipsView: View {
    let choices: [FlowPrompt.PromptChoice]
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(choices) { choice in
                let isSelected = selectedIDs.contains(choice.id)
                Button(action: { onToggle(choice.id) }) {
                    Text(choice.label)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? .black : .white)
                        .background(
                            isSelected ? Color.white : Color.white.opacity(0.15),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
            }
        }
    }
}

// MARK: - PromptDotNavView

/// Dot navigation where the active dot is the main action button.
/// - Tap active dot: checkmark flash → advance to next prompt
/// - Tap inactive dot: jump to that prompt
/// - Long press + drag: enter preview mode — swipe to browse prompts, release to navigate
private struct PromptDotNavView: View {
    @Bindable var model: FlowSessionViewModel

    private let activeDotSize: CGFloat = 56
    private let inactiveDotSize: CGFloat = 8
    private let dotSpacing: CGFloat = 14

    @State private var requiredPulse: Double = 1.0
    @State private var isPreviewMode: Bool = false
    @State private var previewIndex: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            // Preview card — floats above the dot nav when in preview mode
            if isPreviewMode, previewIndex < model.prompts.count {
                let previewPrompt = model.prompts[previewIndex]
                VStack(spacing: 4) {
                    Text(previewPrompt.title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                    if previewIndex != model.activeIndex {
                        Text(previewIndex < model.activeIndex ? "← back" : "forward →")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)
                .offset(y: -(activeDotSize + 24))
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPreviewMode)
                .zIndex(1)
            }

            // Dot row
            GeometryReader { geo in
                HStack(spacing: dotSpacing) {
                    ForEach(Array(model.prompts.enumerated()), id: \.offset) { index, prompt in
                        dotView(for: prompt, index: index)
                    }
                }
                .offset(x: centeringOffset(screenWidth: geo.size.width))
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.activeIndex)
                // Long press → enter preview mode
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                isPreviewMode = true
                                previewIndex = model.activeIndex
                            }
                        }
                )
                // Drag while in preview mode → update preview index; release → navigate
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            guard isPreviewMode else { return }
                            let stride = inactiveDotSize + dotSpacing
                            let offset = Int((-value.translation.width / stride).rounded())
                            let raw = model.activeIndex + offset
                            previewIndex = max(0, min(model.prompts.count - 1, raw))
                        }
                        .onEnded { _ in
                            guard isPreviewMode else { return }
                            let target = previewIndex
                            withAnimation { isPreviewMode = false }
                            if target != model.activeIndex {
                                model.jumpToPrompt(target)
                            }
                        }
                )
            }
            .frame(height: activeDotSize + 8)
        }
        // Extra height to accommodate the floating preview card
        .frame(height: activeDotSize + 8 + (isPreviewMode ? activeDotSize + 24 : 0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPreviewMode)
    }

    private func centeringOffset(screenWidth: CGFloat) -> CGFloat {
        let activeDotCenter = CGFloat(model.activeIndex) * (inactiveDotSize + dotSpacing) + activeDotSize / 2
        return screenWidth / 2 - activeDotCenter
    }

    @ViewBuilder
    private func dotView(for prompt: FlowPrompt, index: Int) -> some View {
        let isActive = index == model.activeIndex
        let isAnswered = model.answeredPromptIDs.contains(prompt.id)

        ZStack {
            if isActive {
                activeDotButton(for: prompt)
            } else {
                inactiveDot(for: prompt, isAnswered: isAnswered)
                    .onTapGesture {
                        guard !isPreviewMode else { return }
                        if index < model.activeIndex { model.goBack() }
                        else if index > model.activeIndex { model.advance() }
                    }
            }
        }
        .frame(
            width: isActive ? activeDotSize : inactiveDotSize,
            height: isActive ? activeDotSize : inactiveDotSize
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }

    @ViewBuilder
    private func activeDotButton(for prompt: FlowPrompt) -> some View {
        let hasTimer = prompt.timerSeconds != nil
        let isRequired = prompt.isRequired

        Button(action: {
            guard !isPreviewMode else { return }
            model.advanceWithCheckmark()
        }) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))

                if hasTimer {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: model.timerProgress)
                        .stroke(
                            prompt.isCastellumGenerated ? Color.purple : Color.white,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: model.timerProgress)
                } else if isRequired {
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                        .scaleEffect(requiredPulse)
                        .animation(
                            .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                            value: requiredPulse
                        )
                } else {
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                }

                if prompt.isCastellumGenerated {
                    Circle().fill(Color.purple.opacity(0.15))
                }

                if model.showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isPreviewMode)
        .onAppear { requiredPulse = 1.05 }
    }

    @ViewBuilder
    private func inactiveDot(for prompt: FlowPrompt, isAnswered: Bool) -> some View {
        Circle().fill(dotColor(for: prompt, isAnswered: isAnswered))
    }

    private func dotColor(for prompt: FlowPrompt, isAnswered: Bool) -> Color {
        if isAnswered { return .white.opacity(0.6) }
        if prompt.isRequired { return .white.opacity(0.4) }
        return .white.opacity(0.2)
    }
}

// MARK: - FlowLayout (wrapping HStack for choice chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxY: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxY = y + rowHeight
        }
        return CGSize(width: width, height: maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
