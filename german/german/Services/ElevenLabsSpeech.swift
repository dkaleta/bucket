import AVFoundation
import Foundation

@MainActor protocol SpeechGenerating {
    func audio(text: String, apiKey: String) async throws -> Data
}

@MainActor protocol SpeechPlaying {
    func play(_ data: Data) async throws
    func stop()
}

@MainActor final class ElevenLabsSpeech: SpeechGenerating {
    private let session: URLSession
    // ElevenLabs' documented default voice; Flash supports German with language_code de.
    static let voiceID = "JBFqnCBsd6RMkjVDRZzb"
    init(session: URLSession = .shared) { self.session = session }

    static func request(text: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)?output_format=mp3_44100_128")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text, "model_id": "eleven_flash_v2_5", "language_code": "de"
        ])
        return request
    }

    func audio(text: String, apiKey: String) async throws -> Data {
        let (data, response) = try await session.data(for: Self.request(text: text, apiKey: apiKey))
        guard let response = response as? HTTPURLResponse else {
            throw PracticeError(message: "Could not reach ElevenLabs. Tap the speaker to try again.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let message: String
            switch response.statusCode {
            case 401, 403: message = "Check your ElevenLabs API key and text-to-speech access in Settings."
            case 429: message = "ElevenLabs usage limit reached. Check your balance or try again shortly."
            default: message = "ElevenLabs could not generate speech (\(response.statusCode)). Tap the speaker to try again."
            }
            throw PracticeError(message: message)
        }
        guard !data.isEmpty, response.mimeType?.hasPrefix("audio/") == true else {
            throw PracticeError(message: "ElevenLabs returned no playable audio. Tap the speaker to try again.")
        }
        return data
    }
}

@MainActor final class AnswerAudioPlayer: SpeechPlaying {
    private var player: AVAudioPlayer?
    func play(_ data: Data) async throws {
        stop()
        let audio: AVAudioPlayer
        do { audio = try AVAudioPlayer(data: data) }
        catch { throw PracticeError(message: "Could not play this audio. Tap the speaker to try again.") }
        player = audio
        guard audio.prepareToPlay(), audio.play() else {
            player = nil
            throw PracticeError(message: "Could not start audio playback. Check your sound output and try again.")
        }
        defer {
            audio.stop()
            if player === audio { player = nil }
        }
        while audio.isPlaying {
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
    }
    func stop() { player?.stop(); player = nil }
}
