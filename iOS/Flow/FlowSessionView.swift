import AVFoundation
import BasinShared
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

    @State private var model: FlowSessionViewModel

    init(prompts: [FlowPrompt], onComplete: @escaping () -> Void, onSkip: @escaping () -> Void, autoStart: Bool = false) {
        self.prompts = prompts
        self.onComplete = onComplete
        self.onSkip = onSkip
        self.autoStart = autoStart
        _model = State(initialValue: FlowSessionViewModel(prompts: prompts))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Live transcript strip
                LiveTranscriptView(
                    sentences: model.transcriptSentences,
                    isExpanded: $model.isTranscriptExpanded
                )

                Spacer(minLength: 0)

                // Active prompt
                if !model.isComplete {
                    PromptCarouselView(model: model)
                        .padding(.horizontal, 32)
                } else {
                    completionView
                        .padding(.horizontal, 32)
                }

                Spacer(minLength: 0)

                // Dot nav + controls
                VStack(spacing: 20) {
                    PromptDotNavView(model: model)

                    bottomControls
                }
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await model.startTimers()
            if autoStart { model.startFlow() }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    // Swipe left → next prompt, swipe right → previous prompt
                    guard !model.isTranscriptExpanded else { return }
                    if value.translation.width < -40 { model.advance() }
                    else if value.translation.width > 40 { model.goBack() }
                }
        )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        RecordToggleButton(model: model, onEnd: onComplete)
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
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.top, 8)
        }
    }
}

// MARK: - FlowSessionViewModel

@Observable
@MainActor
final class FlowSessionViewModel {
    let prompts: [FlowPrompt]
    var activeIndex: Int = 0
    var transcriptSentences: [String] = []
    var isTranscriptExpanded: Bool = false
    var selectedChoices: [Int: Set<String>] = [:]
    var answeredPromptIDs: Set<Int> = []
    var timerRemaining: Double = 0
    var isComplete: Bool = false
    var showPrompt: Bool = true
    var useTextInput: Bool = false
    var textInputDraft: String = ""

    private var timerTask: Task<Void, Never>?

    var isStarted: Bool = false

    init(prompts: [FlowPrompt]) {
        self.prompts = prompts
        // Pre-fill timerRemaining so the active dot shows a full ring in the "ready" state
        timerRemaining = prompts.first?.timerSeconds ?? 0
    }

    func startFlow() {
        guard !isStarted else { return }
        isStarted = true
        startCurrentTimer()
    }

    var activePrompt: FlowPrompt? {
        guard activeIndex < prompts.count else { return nil }
        return prompts[activeIndex]
    }

    var timerProgress: Double {
        guard let prompt = activePrompt, let seconds = prompt.timerSeconds, seconds > 0 else { return 0 }
        return timerRemaining / seconds
    }

    // MARK: - Navigation

    func advance() {
        guard !isComplete, isStarted else { return }
        let nextIndex = activeIndex + 1
        if nextIndex >= prompts.count {
            withAnimation(.easeInOut(duration: 0.4)) { isComplete = true }
            return
        }
        transitionToPrompt(nextIndex)
    }

    func goBack() {
        guard activeIndex > 0, isStarted else { return }
        transitionToPrompt(activeIndex - 1)
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

        // Update dot styling only — don't auto-advance so the user can select multiple chips
        if current.isEmpty { answeredPromptIDs.remove(promptID) }
        else { answeredPromptIDs.insert(promptID) }
    }

    func markAnswered(promptID: Int) {
        guard !answeredPromptIDs.contains(promptID) else { return }
        answeredPromptIDs.insert(promptID)
        // Short delay then auto-advance for required prompts that have been answered
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
        transcriptSentences.append(sentence)
        if transcriptSentences.count > 20 { transcriptSentences.removeFirst() }
    }

    // MARK: - Timers

    func startTimers() async {
        // No-op for now — timer management is handled inline via startCurrentTimer()
    }

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
    let sentences: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(isExpanded ? .vertical : []) {
                        VStack(alignment: .leading, spacing: 6) {
                            let visible = isExpanded ? sentences : Array(sentences.suffix(3))
                            ForEach(Array(visible.enumerated()), id: \.offset) { _, sentence in
                                Text(sentence)
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.3))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(sentence)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, isExpanded ? 56 : 16)
                        .padding(.bottom, 8)
                        .frame(minWidth: geo.size.width)
                    }
                    .onChange(of: sentences.count) { _, _ in
                        if let last = sentences.last {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
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

                // Text input field (when useTextInput mode)
                if model.useTextInput {
                    textInputField
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Pre-start hint
                if !model.isStarted {
                    Text("tap the mic to begin")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            } else {
                // Beat gap between prompts — intentionally blank
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

private struct PromptDotNavView: View {
    @Bindable var model: FlowSessionViewModel

    private let activeDotSize: CGFloat = 20
    private let inactiveDotSize: CGFloat = 8
    private let dotSpacing: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: dotSpacing) {
                ForEach(Array(model.prompts.enumerated()), id: \.offset) { index, prompt in
                    dotView(for: prompt, index: index)
                        .onTapGesture {
                            if index < model.activeIndex { model.goBack() }
                            else if index > model.activeIndex { model.advance() }
                        }
                }
            }
            .offset(x: centeringOffset(screenWidth: geo.size.width))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.activeIndex)
        }
        .frame(height: activeDotSize + 8)
    }

    // Keeps the active dot centered: dot[a] center = a*(inactiveSize+spacing) + activeSize/2
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
                activeDot(for: prompt)
            } else {
                inactiveDot(for: prompt, isAnswered: isAnswered)
            }
        }
        .frame(width: isActive ? activeDotSize : inactiveDotSize,
               height: isActive ? activeDotSize : inactiveDotSize)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }

    @ViewBuilder
    private func activeDot(for prompt: FlowPrompt) -> some View {
        let hasTimer = prompt.timerSeconds != nil
        let isRequired = prompt.isRequired

        ZStack {
            if hasTimer {
                // Liquid drain ring
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2.5)

                Circle()
                    .trim(from: 0, to: model.timerProgress)
                    .stroke(
                        prompt.isCastellumGenerated ? Color.purple : Color.white,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.05), value: model.timerProgress)

            } else if isRequired {
                // Solid bright with scale pulse
                Circle()
                    .stroke(Color.white, lineWidth: 2.5)
                    .scaleEffect(requiredPulse)
                    .animation(
                        .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: requiredPulse
                    )

            } else {
                // Optional — dim
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
            }

            // Castellum shimmer overlay
            if prompt.isCastellumGenerated {
                Circle()
                    .fill(Color.purple.opacity(0.2))
            }
        }
        .onAppear { startPulse() }
    }

    @State private var requiredPulse: Double = 1.0

    private func startPulse() {
        requiredPulse = 1.05
    }

    @ViewBuilder
    private func inactiveDot(for prompt: FlowPrompt, isAnswered: Bool) -> some View {
        Circle()
            .fill(dotColor(for: prompt, isAnswered: isAnswered))
    }

    private func dotColor(for prompt: FlowPrompt, isAnswered: Bool) -> Color {
        if isAnswered { return .white.opacity(0.6) }
        if prompt.isRequired { return .white.opacity(0.4) }
        return .white.opacity(0.2)
    }
}

// MARK: - RecordToggleButton

private struct RecordToggleButton: View {
    @Bindable var model: FlowSessionViewModel
    let onEnd: () -> Void

    @State private var recordingPulse = false

    var body: some View {
        HStack(spacing: 20) {
            Button {
                withAnimation { model.useTextInput = false }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(model.useTextInput ? .white.opacity(0.4) : .white)
                    .frame(width: 36, height: 36)
            }

            // Main record/stop button
            ZStack {
                // Pulsing ring while recording
                if model.isStarted {
                    Circle()
                        .stroke(Color.red.opacity(recordingPulse ? 0.45 : 0.12), lineWidth: 2.5)
                        .frame(width: 88, height: 88)
                        .scaleEffect(recordingPulse ? 1.0 : 0.9)
                        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: recordingPulse)
                        .onAppear { recordingPulse = true }
                }

                Button {
                    if model.isStarted {
                        onEnd()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            model.startFlow()
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.isStarted ? Color.red : Color.blue)
                            .frame(width: 68, height: 68)
                            .animation(.easeInOut(duration: 0.25), value: model.isStarted)

                        if model.useTextInput {
                            Image(systemName: "keyboard.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: model.isStarted ? "stop.fill" : "mic.fill")
                                .font(.system(size: model.isStarted ? 22 : 26))
                                .foregroundStyle(.white)
                                .animation(.easeInOut(duration: 0.2), value: model.isStarted)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation { model.useTextInput = true }
            } label: {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(model.useTextInput ? .white : .white.opacity(0.4))
                    .frame(width: 36, height: 36)
            }
        }
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
