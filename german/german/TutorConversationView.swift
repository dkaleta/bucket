import SwiftUI
import WebKit

struct TutorConversationView: View {
    let context: TutorContext
    @Environment(\.dismiss) private var dismiss
    @State private var tutor: VoiceTutor = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--lesson-preview") { return LessonPreview.tutor() }
        #endif
        return VoiceTutor(credentials: KeychainStore())
    }()

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Talk to your tutor", systemImage: "mic.bubble.fill").font(.title2.bold())
                Spacer()
                Button("Close") { tutor.stop(); dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(context.question).font(.headline)
                if !context.learnerAnswer.isEmpty {
                    Text("Your answer: \(context.learnerAnswer)").foregroundStyle(.secondary)
                }
                if let grade = context.grade {
                    Text("\(grade.score) / 5 · \(grade.germanAnswer)")
                    if let tip = grade.tip, !tip.isEmpty {
                        Text(tip).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(tutor.phase == .active ? "Connected to GPT-Live" : tutor.phase == .connecting ? "Connecting to GPT-Live…" : "Microphone stopped",
                          systemImage: tutor.phase == .active ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(tutor.phase == .active ? Color.green : .secondary)
                    Spacer()
                    Text(tutor.isMuted ? "Mic muted" : "Mic active: \(Int(tutor.secondsSent)) s")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Text("Microphone level").font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    Image(systemName: tutor.isMuted ? "mic.slash.fill" : "mic.fill")
                    ProgressView(value: tutor.inputLevel)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Microphone level")
                        .accessibilityValue("\(Int(tutor.inputLevel * 100)) percent")
                }
                Text("Input: \(tutor.inputDevice)").foregroundStyle(.secondary)
                HStack {
                    Text("Output: \(tutor.outputDevice)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Test speaker", systemImage: "speaker.wave.2", action: tutor.testSpeaker)
                        .disabled(!tutor.canTestSpeaker)
                        .help("Play a short sound through the same output as tutor replies")
                }
                Text(tutor.playbackStatus).foregroundStyle(.secondary)
                if tutor.isFullDuplex {
                    Text("You can interrupt by speaking, even while your tutor is talking.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(12)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            if let notice = tutor.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }

            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if tutor.messages.isEmpty {
                            Text("Ask about this sentence or how to say something similar, in English or German. You can speak naturally and interrupt at any time.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(tutor.messages) { message in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(message.role.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(message.text).textSelection(.enabled)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(message.role == .tutor ? Color.accentColor.opacity(0.08) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: tutor.messages.last?.text) { _, _ in reader.scrollTo("bottom", anchor: .bottom) }
            }
            .frame(minHeight: 110, idealHeight: 220)


            if let message = tutor.errorMessage {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }

            HStack(spacing: 12) {
                if tutor.phase == .connecting {
                    ProgressView().controlSize(.small)
                    Text("Connecting…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: tutor.stop)
                } else if tutor.phase == .active {
                    Label(tutor.isMuted ? "Microphone muted" : tutor.status.rawValue,
                          systemImage: tutor.isMuted ? "mic.slash.fill" : "waveform")
                        .foregroundStyle(tutor.isMuted ? Color.secondary : .accentColor)
                        .accessibilityAddTraits(.updatesFrequently)
                    Spacer()
                    if tutor.canInterrupt {
                        Button("Interrupt", action: tutor.interrupt)
                    }
                    Button(action: tutor.toggleMute) {
                        Label(tutor.isMuted ? "Unmute" : "Mute", systemImage: tutor.isMuted ? "mic.slash.fill" : "mic.fill")
                    }
                    Button("End conversation", action: tutor.stop)
                } else {
                    Text(tutor.phase == .failed ? "Connection stopped" : "Conversation ended")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("New conversation") { tutor.start(context: context) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            Text("OpenAI receives your microphone audio and this exercise’s context. Voice conversations aren’t saved on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 560, height: 720)
        .background {
            if let webView = tutor.webView {
                TutorWebRTCView(webView: webView).frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .task { tutor.start(context: context) }
        .onDisappear { tutor.stop() }
        .onReceive(NotificationCenter.default.publisher(for: MicrophoneTest.willStart)) { _ in tutor.stop() }
    }
}

struct TutorWebRTCView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
