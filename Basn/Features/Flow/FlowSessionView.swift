import AppKit
import SwiftUI

// MARK: - FlowSessionView (macOS)
//
// macOS-first shell for the flow session experience. Functional for onboarding.
// A richer desktop layout is deferred to a follow-up; this delivers the prompt
// sequence and transcript area at adequate fidelity for the setup flow.

struct FlowSessionView: View {
    let prompts: [FlowPrompt]
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var model: FlowSessionMacViewModel

    init(prompts: [FlowPrompt], onComplete: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.prompts = prompts
        self.onComplete = onComplete
        self.onSkip = onSkip
        _model = State(initialValue: FlowSessionMacViewModel(prompts: prompts))
    }

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            VStack(spacing: 0) {
                // Transcript strip
                transcriptStrip

                Spacer(minLength: 0)

                // Prompt or completion
                if !model.isComplete {
                    promptArea
                } else {
                    completionArea
                }

                Spacer(minLength: 0)

                // Dot nav + bottom bar
                VStack(spacing: 16) {
                    dotNav
                    bottomBar
                }
                .padding(.bottom, 28)
            }
        }
        .frame(width: 520, height: 560)
        .task { await model.startTimers() }
    }

    // MARK: - Transcript Strip

    private var transcriptStrip: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                let visible = Array(model.transcriptSentences.suffix(4))
                ForEach(Array(visible.enumerated()), id: \.offset) { _, sentence in
                    Text(sentence)
                        .font(.callout)
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .frame(height: 72)
        .background(.quaternary.opacity(0.5))
    }

    // MARK: - Prompt Area

    private var promptArea: some View {
        VStack(spacing: 20) {
            if model.showPrompt, let prompt = model.activePrompt {
                VStack(spacing: 10) {
                    Text(prompt.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    if !prompt.detail.isEmpty {
                        Text(prompt.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: model.activeIndex)

                // Choice chips
                if let choices = prompt.choices, !choices.isEmpty {
                    FlowChipsView(
                        choices: choices,
                        selectedIDs: model.selectedChoices[prompt.id, default: []],
                        onToggle: { model.toggleChoice(promptID: prompt.id, choiceID: $0) }
                    )
                }

                // Text input
                if model.useTextInput {
                    textInputRow
                }
            }
        }
        .padding(.horizontal, 40)
    }

    private var textInputRow: some View {
        HStack(spacing: 8) {
            TextField("Type your response…", text: $model.textInputDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.submitTextInput() }

            Button("Send") { model.submitTextInput() }
                .buttonStyle(.borderedProminent)
                .disabled(model.textInputDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Completion Area

    private var completionArea: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All set.")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text("We've captured your setup. Give us a moment to prepare your flows and workflows.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button("Finish Setup") { onComplete() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    // MARK: - Dot Nav

    private var dotNav: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(model.prompts.enumerated()), id: \.offset) { index, prompt in
                    macDot(for: prompt, index: index)
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private func macDot(for prompt: FlowPrompt, index: Int) -> some View {
        let isActive = index == model.activeIndex
        let isAnswered = model.answeredPromptIDs.contains(prompt.id)

        ZStack {
            if isActive && prompt.timerSeconds != nil {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
                    .frame(width: 18, height: 18)
                Circle()
                    .trim(from: 0, to: model.timerProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
                    .animation(.linear(duration: 0.05), value: model.timerProgress)
            } else if isActive {
                Circle()
                    .stroke(prompt.isRequired ? Color.primary : Color.secondary, lineWidth: 2)
                    .frame(width: 18, height: 18)
            } else {
                Circle()
                    .fill(isAnswered ? Color.secondary.opacity(0.6) : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: isActive ? 18 : 8, height: isActive ? 18 : 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
        .onTapGesture {
            if index < model.activeIndex { model.goBack() }
            else if index > model.activeIndex { model.advance() }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button("skip setup") { onSkip() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

            Spacer()

            Toggle(isOn: $model.useTextInput.animation()) {
                Label("Type", systemImage: "keyboard")
                    .font(.callout)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)

            Button("Next  →") { model.advance() }
                .buttonStyle(.borderedProminent)
                .disabled(shouldBlockAdvance)
        }
        .padding(.horizontal, 24)
    }

    private var shouldBlockAdvance: Bool {
        guard let prompt = model.activePrompt else { return false }
        return prompt.isRequired && !model.answeredPromptIDs.contains(prompt.id)
    }
}

// MARK: - FlowSessionMacViewModel

@Observable
@MainActor
final class FlowSessionMacViewModel {
    let prompts: [FlowPrompt]
    var activeIndex: Int = 0
    var transcriptSentences: [String] = []
    var selectedChoices: [Int: Set<String>] = [:]
    var answeredPromptIDs: Set<Int> = []
    var timerRemaining: Double = 0
    var isComplete: Bool = false
    var showPrompt: Bool = true
    var useTextInput: Bool = false
    var textInputDraft: String = ""

    private var timerTask: Task<Void, Never>?

    init(prompts: [FlowPrompt]) {
        self.prompts = prompts
        startCurrentTimer()
    }

    var activePrompt: FlowPrompt? {
        guard activeIndex < prompts.count else { return nil }
        return prompts[activeIndex]
    }

    var timerProgress: Double {
        guard let p = activePrompt, let s = p.timerSeconds, s > 0 else { return 0 }
        return timerRemaining / s
    }

    func advance() {
        guard !isComplete else { return }
        let next = activeIndex + 1
        if next >= prompts.count { withAnimation { isComplete = true }; return }
        transition(to: next)
    }

    func goBack() {
        guard activeIndex > 0 else { return }
        transition(to: activeIndex - 1)
    }

    private func transition(to index: Int) {
        timerTask?.cancel()
        withAnimation { showPrompt = false }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            activeIndex = index
            timerRemaining = prompts[index].timerSeconds ?? 0
            withAnimation { showPrompt = true }
            startCurrentTimer()
        }
    }

    func toggleChoice(promptID: Int, choiceID: String) {
        var current = selectedChoices[promptID, default: []]
        if current.contains(choiceID) { current.remove(choiceID) } else { current.insert(choiceID) }
        selectedChoices[promptID] = current
        if !current.isEmpty { markAnswered(promptID: promptID) }
    }

    func markAnswered(promptID: Int) {
        guard !answeredPromptIDs.contains(promptID) else { return }
        answeredPromptIDs.insert(promptID)
        if activePrompt?.id == promptID && activePrompt?.isRequired == true {
            Task {
                try? await Task.sleep(for: .milliseconds(1000))
                advance()
            }
        }
    }

    func submitTextInput() {
        let text = textInputDraft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        transcriptSentences.append(text)
        if transcriptSentences.count > 20 { transcriptSentences.removeFirst() }
        if let id = activePrompt?.id { markAnswered(promptID: id) }
        textInputDraft = ""
    }

    func startTimers() async {}

    private func startCurrentTimer() {
        timerTask?.cancel()
        guard let s = activePrompt?.timerSeconds, s > 0 else { return }
        timerRemaining = s
        timerTask = Task { @MainActor in
            let step = 0.05
            while timerRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(step))
                timerRemaining = max(0, timerRemaining - step)
            }
            if !Task.isCancelled { advance() }
        }
    }
}

// MARK: - FlowChipsView (macOS)

private struct FlowChipsView: View {
    let choices: [FlowPrompt.PromptChoice]
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        // Use a simple wrapping layout
        let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(choices) { choice in
                let isSelected = selectedIDs.contains(choice.id)
                Button(action: { onToggle(choice.id) }) {
                    Text(choice.label)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
            }
        }
        .frame(maxWidth: 380)
    }
}
