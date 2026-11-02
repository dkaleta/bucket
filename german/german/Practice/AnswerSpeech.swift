import Foundation
import Observation

@MainActor @Observable final class AnswerSpeech {
    enum State { case idle, loading, playing }
    private(set) var state: State = .idle
    private(set) var errorMessage: String?
    private let credentials: any CredentialStoring
    private let generator: any SpeechGenerating
    private let player: any SpeechPlaying
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var cached: (text: String, data: Data)?

    init(credentials: any CredentialStoring, generator: (any SpeechGenerating)? = nil,
         player: (any SpeechPlaying)? = nil) {
        self.credentials = credentials
        self.generator = generator ?? ElevenLabsSpeech()
        self.player = player ?? AnswerAudioPlayer()
    }

    var buttonLabel: String {
        switch state {
        case .idle: return "Listen to the German answer"
        case .loading: return "Cancel speech generation"
        case .playing: return "Stop playback"
        }
    }

    func toggle(text: String) {
        guard state == .idle else { stop(); return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = nil
        state = .loading
        let id = UUID()
        requestID = id
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let data: Data
                if let cached, cached.text == text { data = cached.data }
                else {
                    let key = try credentials.read(.elevenLabs)
                    guard !key.isEmpty else { throw PracticeError(message: "Add your ElevenLabs API key in Settings to hear the answer.") }
                    data = try await generator.audio(text: text, apiKey: key)
                }
                guard requestID == id, !Task.isCancelled else { return }
                cached = (text, data)
                state = .playing
                try await player.play(data)
                guard requestID == id, !Task.isCancelled else { return }
                state = .idle
                task = nil
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                cached = nil
                state = .idle
                errorMessage = error.localizedDescription
                task = nil
            }
        }
    }

    func stop() {
        requestID = UUID()
        task?.cancel()
        task = nil
        player.stop()
        state = .idle
        errorMessage = nil
    }

    func reset() { stop(); cached = nil }
}
