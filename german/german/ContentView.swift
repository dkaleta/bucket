import SwiftUI

struct ContentView: View {
    @State private var speech: AnswerSpeech = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--lesson-preview") { return LessonPreview.speech() }
        #endif
        return AnswerSpeech(credentials: KeychainStore())
    }()
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PracticeViewModel = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--lesson-preview") { return LessonPreview.model() }
        #endif
        return PracticeViewModel(credentials: KeychainStore(), grader: OpenAIGrader(), sessionStore: .standard,
                                 makeTranscriber: { ElevenLabsTranscriber() })
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if model.needsMainBatch {
                    Label("German practice", systemImage: "text.bubble").font(.headline)
                    Text("Fresh practice, 10 questions at a time.").font(.title2)
                    Text(model.errorMessage ?? "Mixed everyday topics at beginner level.")
                        .foregroundStyle(.secondary)
                    Button(model.mainBatchActionTitle, action: model.startMainBatch)
                        .buttonStyle(.borderedProminent).disabled(model.isPreparing)
                } else {
                    HStack {
                        Label(model.title, systemImage: "text.bubble")
                            .font(.headline)
                        Spacer()
                        Text(model.progress).monospacedDigit().foregroundStyle(.secondary)
                        Button(action: model.reloadQuestions) {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canReloadQuestions)
                        .help("Replace this set with fresh questions")
                        .accessibilityLabel("Reload questions")
                    }
                    .padding(.bottom, 16)

                    if let parent = model.parentTitle {
                        VStack(spacing: 8) {
                            Text(model.breadcrumbs).font(.caption).foregroundStyle(.secondary)
                            Button("Return to \(parent)", action: model.returnToParent)
                                .disabled(!model.canStartLesson)
                        }
                    }

                    VStack(spacing: 0) {
                        Text("TRANSLATE INTO GERMAN")
                            .font(.caption.weight(.semibold))
                            .tracking(2)
                            .foregroundStyle(.secondary)
                        SentencePromptView(sentence: model.sentence)
                            .id("\(model.sessionID)-\(model.sentence.id)")
                    }

                    CenteredWordLayout {
                        ForEach(model.tags) { tag in
                            Button(tag.title) { model.startLesson(tag) }
                                .buttonStyle(.bordered)
                                .clipShape(Capsule())
                                .help("Practice \(tag.title.lowercased()) in a new lesson")
                                .accessibilityLabel("Start lesson: \(tag.title)")
                                .disabled(!model.canStartLesson)
                        }
                    }

                    if model.phase != .connecting {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Your answer").font(.subheadline.weight(.medium))
                                Spacer()
                                if model.phase == .recording {
                                    Label("Listening", systemImage: "record.circle.fill")
                                        .font(.caption).foregroundStyle(.red)
                                } else if model.phase == .ready {
                                    Text("Edit if needed").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if model.phase == .idle || model.phase == .ready {
                                TextField("Your German translation", text: $model.answer, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .lineLimit(2...5)
                                    .font(.title3)
                                    .accessibilityLabel("Your German answer")
                                    .onSubmit(model.check)
                                    .onKeyPress(.return, phases: .down) { press in
                                        guard !press.modifiers.contains(.shift) else { return .ignored }
                                        model.check()
                                        return .handled
                                    }
                            } else {
                                Text(model.answer.isEmpty ? "Your words will appear here…" : model.answer)
                                    .font(.title3)
                                    .foregroundStyle(model.answer.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(20)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
                    }

                    if let grade = model.grade, model.phase == .graded {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(grade.score)").font(.system(size: 36, weight: .semibold, design: .rounded))
                                Text("/ 5").font(.title3).foregroundStyle(.secondary)
                                Spacer()
                                Text(grade.score == 5 ? "Well done" : grade.score >= 3 ? "Keep going" : "Try once more")
                                    .foregroundStyle(.secondary)
                            }
                            HStack(alignment: .top, spacing: 12) {
                                Text(grade.germanAnswer).font(.title3).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button { speech.toggle(text: grade.germanAnswer) } label: {
                                    ZStack {
                                        Image(systemName: speech.state == .idle ? "speaker.wave.2.fill" : "stop.fill")
                                            .opacity(speech.state == .loading ? 0 : 1)
                                        if speech.state == .loading { ProgressView().controlSize(.small) }
                                    }.frame(width: 20, height: 20)
                                }
                                .buttonStyle(.bordered)
                                .help(speech.buttonLabel)
                                .accessibilityLabel(speech.buttonLabel)
                            }
                            if let message = speech.errorMessage {
                                Text(message).font(.callout).foregroundStyle(.secondary)
                            }
                            if let tip = grade.tip, !tip.isEmpty {
                                Text(tip).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .contain)
                    }

                    if let message = model.errorMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).textSelection(.enabled)
                    }

                    controls.controlSize(.large)
                    if model.phase == .idle && model.errorMessage == nil {
                        Text("Type your translation or record it aloud.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 620)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 480, minHeight: 520)
        .toolbar {
            ToolbarItem { SettingsLink { Label("Settings", systemImage: "gearshape") } }
        }
        .sheet(isPresented: Binding(get: { model.showsGeneration }, set: { if !$0 { model.cancelLesson() } })) {
            VStack(spacing: 20) {
                if model.isPreparing {
                    ProgressView()
                    Text(model.preparingMain ? "Preparing 10 fresh practice questions…" : "Preparing \(model.preparingCount) questions about \(model.preparingTag?.title.lowercased() ?? "this topic")…")
                } else {
                    Text(model.lessonError ?? "Could not prepare the lesson.")
                    Button("Retry", action: model.retryGeneration)
                }
                Button("Cancel", action: model.cancelLesson).keyboardShortcut(.cancelAction)
            }
            .padding(32).frame(width: 380)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveProgress() }
        }
        .task { model.prepareInitialBatchIfNeeded() }
        .onChange(of: model.sessions.last?.id) { _, _ in speech.reset() }
        .onChange(of: model.index) { _, _ in speech.reset() }
        .onChange(of: model.phase) { _, phase in if phase != .graded { speech.reset() } }
        .onChange(of: model.showsGeneration) { _, active in if active { speech.stop() } }
        .onDisappear { speech.reset(); model.leave() }
    }

    @ViewBuilder private var controls: some View {
        switch model.phase {
        case .idle:
            HStack(spacing: 12) {
                Button(action: model.record) { Label("Record", systemImage: "mic.fill") }
                    .buttonStyle(.bordered)
                Button("Check answer", action: model.check)
                    .buttonStyle(.borderedProminent).disabled(!model.canCheck)
            }
        case .connecting:
            HStack {
                ProgressView().controlSize(.small)
                Text("Connecting…").foregroundStyle(.secondary)
                Button("Cancel", action: model.leave).buttonStyle(.bordered)
            }
        case .recording:
            HStack(spacing: 12) {
                Button("Reset", systemImage: "arrow.counterclockwise", action: model.record)
                    .buttonStyle(.bordered)
                Button("Stop", systemImage: "stop.fill", action: model.stop)
                    .buttonStyle(.borderedProminent)
            }
        case .finalizing:
            HStack {
                ProgressView().controlSize(.small)
                Text("Finishing transcription…").foregroundStyle(.secondary)
            }
        case .ready:
            HStack(spacing: 12) {
                Button("Record again", action: model.record).buttonStyle(.bordered)
                Button("Check answer", action: model.check)
                    .buttonStyle(.borderedProminent).disabled(!model.canCheck)
            }
        case .grading:
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking your answer…").foregroundStyle(.secondary)
            }
        case .graded:
            HStack(spacing: 12) {
                Button("Try again", action: model.retry).buttonStyle(.bordered)
                Button(model.isLast ? model.parentTitle.map { "Return to \($0)" } ?? "Next 10 questions" : "Next", action: model.next)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct SentencePromptView: View {
    let sentence: PracticeSentence
    @State private var hoveredWord: Int?

    private var words: [SentenceWordHint] { SentenceHints.words(for: sentence) }
    private var hint: String? { words.first { $0.id == hoveredWord }?.german }

    var body: some View {
        VStack(spacing: 0) {
            CenteredWordLayout {
                ForEach(words) { word in
                    Text(word.english)
                        .font(.system(size: 32))
                        .fixedSize()
                        .foregroundStyle(hoveredWord == word.id ? Color.accentColor : .primary)
                        .underline(hoveredWord == word.id)
                        .accessibilityHint(word.german)
                        .onHover { hovering in
                            if hovering { hoveredWord = word.id }
                            else if hoveredWord == word.id { hoveredWord = nil }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)

            // Keep the hint outside the hover targets so displaying it cannot move
            // the words or intercept the pointer and immediately dismiss itself.
            Text(hint ?? "Hover over a word for a hint.")
                .font(hint == nil ? .caption : .callout.weight(.medium))
                .foregroundStyle(hint == nil ? Color.secondary : .primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(hint == nil ? 0 : 0.1),
                            in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, minHeight: 56)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Wraps individual hover targets into centered lines without changing word order.
private struct CenteredWordLayout: Layout {
    private let spacing: CGFloat = 8
    private let lineSpacing: CGFloat = 5

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0,
                      height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}

#Preview { ContentView() }
