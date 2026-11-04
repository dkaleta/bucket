import SwiftUI
import AVFoundation

@main
struct germanApp: App {
    private var windowTitle: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--gpt-live-check") { return "German Practice — GPT-Live check" }
        if ProcessInfo.processInfo.arguments.contains("--lesson-preview") { return "German Practice — Preview (microphone disabled)" }
        if ProcessInfo.processInfo.arguments.contains("--tutor-audio-check") { return "German Practice — Local audio check" }
        #endif
        return "German Practice"
    }
    var body: some Scene {
        Window(windowTitle, id: "practice") {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--gpt-live-check") {
                LiveTutorCheckView()
            } else if ProcessInfo.processInfo.arguments.contains("--tutor-audio-check") {
                TutorAudioCheckView()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
        .defaultSize(width: 780, height: 720)

        Settings { SettingsView() }
    }
}

#if DEBUG
/// Opt-in provider check. WebKit initializes local input permission; only synthetic audio is sent.
private struct LiveTutorCheckView: View {
    @State private var service: OpenAILiveTutor?
    @State private var result = "Testing GPT-Live with synthetic speech…"
    var body: some View {
        VStack {
            Text(result).textSelection(.enabled).padding()
            if let view = service?.webView { TutorWebRTCView(webView: view).frame(width: 2, height: 2) }
        }
        .frame(width: 550, height: 180)
        .task {
            let media = LiveWebRTCTransport()
            let connection = OpenAILiveTutor(media: media)
            service = connection
            var heardInput = false, heardOutput = false, receivedSound = false
            let interruption = ProcessInfo.processInfo.environment["GERMAN_LIVE_INTERRUPT_BASE64"]
                .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
            var interruptionSent = false, interruptedInput = "", interruptedOutput = ""
            var finished = false
            @MainActor func finish(_ message: String) {
                guard !finished else { return }; finished = true
                result = message; print(message); fflush(stdout)
                connection.disconnect()
            }
            connection.onEvent = { event in
                switch event {
                case let .transcript(_, role, text, _):
                    if role == .learner { heardInput = true } else { heardOutput = true }
                    if interruptionSent {
                        if role == .learner { interruptedInput += text } else { interruptedOutput += text }
                    }
                    print("GPT-Live \(role.rawValue): \(text)")
                case .status(.speaking):
                    receivedSound = true
                    if let interruption, !interruptionSent {
                        interruptionSent = true
                        Task { @MainActor in
                            do { try await media.speakFixture(interruption) }
                            catch { finish("FAIL: Synthetic interruption could not be sent.") }
                        }
                    }
                default: break
                }
                if interruption != nil {
                    if interruptedInput.lowercased().contains("stop") && interruptedOutput.lowercased().contains("morgen") {
                        finish("PASS: GPT-Live received a spoken interruption during reply audio and followed the new request (Guten Morgen).")
                    }
                } else if heardInput && heardOutput && receivedSound {
                    finish("PASS: GPT-Live heard synthetic speech, returned a transcript, and delivered non-silent WebRTC audio.")
                }
            }
            connection.onFailure = { finish("FAIL: \($0.localizedDescription)") }
            do {
                guard let encoded = ProcessInfo.processInfo.environment["GERMAN_LIVE_FIXTURE_BASE64"],
                      let fixture = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else {
                    throw PracticeError(message: "Set GERMAN_LIVE_FIXTURE_BASE64 to base64-encoded synthesized audio.")
                }
                media.useFixture(fixture)
                let sentence = PracticeSentence(id: 0, english: "Please close the window.", german: "Bitte schließ das Fenster.")
                let context = TutorContext(lesson: "Synthetic voice check", sentence: sentence, answer: "Bitte Fenster", grade: nil)
                try await connection.connect(context: context, apiKey: KeychainStore().read(.openAI))
                try await Task.sleep(for: .seconds(40))
                if !finished { finish("FAIL: No complete voice exchange. Input: \(heardInput), transcript: \(heardOutput), sound: \(receivedSound)") }
            } catch { finish("FAIL: \(error.localizedDescription)") }
        }
        .onDisappear { service?.disconnect() }
    }
}

/// Opt-in hardware regression check: no credentials, providers, saved audio, or user state.
private struct TutorAudioCheckView: View {
    @State private var result = "Checking microphone and silent playback…"

    var body: some View {
        Text(result).padding(32).frame(width: 500, height: 160)
            .task {
                guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                    result = "Audio check needs existing microphone permission. Run the app normally to grant it."
                    print(result)
                    return
                }
                let audio = RealtimeAudio()
                defer { audio.stop() }
                do {
                    let stream = try await audio.start()
                    // Exercise the reply path without playing audible sound or mic loopback.
                    try audio.enqueue(Data(count: 24_000))
                    let deadline = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        audio.stop()
                    }
                    defer { deadline.cancel() }
                    var bytes = 0
                    var peakLevel = 0.0
                    var playbackCompleted = false
                    audio.onDrained = { playbackCompleted = true }
                    for try await chunk in stream {
                        bytes += chunk.count
                        peakLevel = max(peakLevel, TutorPCM.level(chunk))
                    }
                    result = bytes > 0 && playbackCompleted
                        ? "Audio buffers arrived (\(bytes / 2) samples); silent playback completed; audio stopped. \(peakLevel > 0 ? "Microphone signal detected." : "No measurable microphone sound detected.")"
                        : "FAIL: capture samples = \(bytes / 2), playback completed = \(playbackCompleted)."
                    result += " Peak mic level: \(Int(peakLevel * 100))%."
                } catch { result = "FAIL: \(error.localizedDescription)" }
                print(result)
            }
    }
}
#endif
