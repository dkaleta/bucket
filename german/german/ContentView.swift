import SwiftUI

struct ContentView: View {
    @State private var model = PracticeViewModel(
        credentials: KeychainStore(), grader: OpenAIGrader(),
        makeTranscriber: { ElevenLabsTranscriber() }
    )
    @State private var promptID = UUID()

    private var prompt: CanvasDocument {
        CanvasDocument(elements: [CanvasTextElement(
            id: promptID, text: model.sentence.english,
            center: CanvasPosition(x: 0.5, y: 0.5),
            width: CanvasTextWidth(maximumPoints: 620, canvasFraction: 0.95),
            style: CanvasTextStyle(fontSize: 32)
        )])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Label("German practice", systemImage: "text.bubble")
                        .font(.headline)
                    Spacer()
                    Text(model.progress).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)

                VStack(spacing: 0) {
                    Text("SAY IT IN GERMAN")
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    CanvasDocumentView(document: prompt)
                        .frame(height: 150)
                }

                if model.phase != .idle && model.phase != .connecting {
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
                        if model.phase == .ready {
                            TextField("Your German translation", text: $model.answer, axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(2...5)
                                .font(.title3)
                                .accessibilityLabel("Your German answer")
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
                        Text(grade.germanAnswer).font(.title3).textSelection(.enabled)
                        if let tip = grade.tip, !tip.isEmpty {
                            Text(tip).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                }

                if let message = model.errorMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).textSelection(.enabled)
                }

                controls.controlSize(.large)
                if model.phase == .idle && model.errorMessage == nil {
                    Text("Read the sentence, then record your translation.")
                        .font(.callout).foregroundStyle(.secondary)
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
        .onDisappear { model.leave() }
    }

    @ViewBuilder private var controls: some View {
        switch model.phase {
        case .idle:
            Button(action: model.record) { Label("Record", systemImage: "mic.fill") }
                .buttonStyle(.borderedProminent)
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
                Button("Try again", action: model.record).buttonStyle(.bordered)
                Button(model.isLast ? "Start again" : "Next", action: model.next)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview { ContentView() }
