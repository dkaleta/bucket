import Foundation
import Testing
@testable import GermanPractice

@MainActor private final class SpeechKeys: CredentialStoring {
    var key = "test-key"
    func read(_ provider: APIProvider) throws -> String { key }
    func save(_ key: String, for provider: APIProvider) throws {}
}
@MainActor private final class SpeechGenerator: SpeechGenerating {
    var texts: [String] = []
    var suspended = false
    var failure = false
    var waiter: CheckedContinuation<Data, Error>?
    func audio(text: String, apiKey: String) async throws -> Data {
        texts.append(text)
        if failure { throw PracticeError(message: "Service unavailable") }
        if suspended { return try await withCheckedThrowingContinuation { waiter = $0 } }
        return Data([1,2,3])
    }
}
@MainActor private final class SpeechPlayer: SpeechPlaying {
    var plays = 0
    var stops = 0
    var failure = false
    var suspended = false
    var waiter: CheckedContinuation<Void, Error>?
    func play(_ data: Data) async throws {
        plays += 1
        if failure { throw PracticeError(message: "Playback failed") }
        if suspended { try await withCheckedThrowingContinuation { waiter = $0 } }
    }
    func stop() {
        stops += 1
        waiter?.resume(throwing: CancellationError())
        waiter = nil
    }
}
@Suite @MainActor struct AnswerSpeechTests {
    private func settle(_ predicate: () -> Bool) async {
        for _ in 0..<1000 { if predicate() { return }; await Task.yield() }
        Issue.record("Speech state did not settle")
    }
    @Test func flashRequestContainsOnlyGermanAnswer() throws {
        let request = try ElevenLabsSpeech.request(text: "Das Sofa ist bequem.", apiKey: "example")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "api.elevenlabs.io")
        #expect(request.url?.query == "output_format=mp3_44100_128")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "example")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String:String])
        #expect(body == ["text":"Das Sofa ist bequem.", "model_id":"eleven_flash_v2_5", "language_code":"de"])
    }
    @Test func onDemandPlaybackReplayAndNavigation() async {
        let generator = SpeechGenerator(), player = SpeechPlayer()
        let speech = AnswerSpeech(credentials: SpeechKeys(), generator: generator, player: player)
        #expect(generator.texts.isEmpty)
        speech.toggle(text: "Das Sofa ist bequem.")
        await settle { speech.state == .idle }
        #expect(player.plays == 1)
        speech.toggle(text: "Das Sofa ist bequem.")
        await settle { speech.state == .idle }
        #expect(player.plays == 2)
        #expect(generator.texts.count == 1)
        speech.reset()
        speech.toggle(text: "Das Sofa ist bequem.")
        await settle { speech.state == .idle }
        #expect(generator.texts.count == 2)
        speech.toggle(text: "Ich bin hier.")
        await settle { speech.state == .idle }
        #expect(generator.texts.last == "Ich bin hier.")
    }
    @Test func cancellationRejectsLateAudio() async {
        let generator = SpeechGenerator(), player = SpeechPlayer()
        generator.suspended = true
        let speech = AnswerSpeech(credentials: SpeechKeys(), generator: generator, player: player)
        speech.toggle(text: "Hallo.")
        await settle { generator.waiter != nil }
        speech.toggle(text: "Hallo.")
        #expect(speech.state == .idle)
        generator.waiter?.resume(returning: Data([1]))
        for _ in 0..<20 { await Task.yield() }
        #expect(player.plays == 0)
        #expect(speech.errorMessage == nil)
    }
    @Test func stopPlaybackAndRecoverFromFailures() async {
        let generator = SpeechGenerator(), player = SpeechPlayer(), keys = SpeechKeys()
        let speech = AnswerSpeech(credentials: keys, generator: generator, player: player)
        keys.key = ""
        speech.toggle(text: "Hallo.")
        await settle { speech.state == .idle }
        #expect(speech.errorMessage?.contains("Settings") == true)
        #expect(generator.texts.isEmpty)
        keys.key = "key"
        generator.failure = true
        speech.toggle(text: "Hallo.")
        await settle { speech.state == .idle }
        #expect(speech.errorMessage == "Service unavailable")
        generator.failure = false
        player.failure = true
        speech.toggle(text: "Hallo.")
        await settle { speech.state == .idle }
        #expect(speech.errorMessage == "Playback failed")
        player.failure = false
        player.suspended = true
        speech.toggle(text: "Hallo.")
        await settle { player.waiter != nil }
        #expect(speech.state == .playing)
        speech.reset()
        #expect(speech.state == .idle)
        #expect(speech.errorMessage == nil)
        #expect(player.stops > 0)
    }
    @Test func malformedAudioIsRejected() async {
        let player = AnswerAudioPlayer()
        do { try await player.play(Data("invalid mp3".utf8)); Issue.record("Invalid audio played") }
        catch { #expect(error.localizedDescription.contains("audio")) }
    }
}
