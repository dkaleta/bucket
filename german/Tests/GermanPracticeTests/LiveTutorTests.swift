import Foundation
import Testing
@testable import GermanPractice

@MainActor private final class LiveMediaFake: LiveMediaTransport {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: ((Error) -> Void)?
    var closed = false
    var mutes: [Bool] = []
    var accepted = false
    var autoStart = true
    func prepare() async throws -> String { "test-offer" }
    func accept(_ sdp: String) async throws {
        #expect(sdp == "test-answer")
        accepted = true
        if autoStart { onEvent?(["type": "session.started"]) }
    }
    func setMuted(_ muted: Bool) { mutes.append(muted) }
    func testSpeaker() throws {}
    func close() { closed = true }
}

@Suite @MainActor struct LiveTutorTests {
    private var context: TutorContext {
        TutorContext(lesson: "Practice", sentence: PracticeSentence(id: 900, english: "Close the window.", german: "Schließ das Fenster.", tagIDs: []), answer: "Fenster", grade: nil)
    }
    private func success(_ request: URLRequest) async throws -> (Data, URLResponse) {
        (Data(#"{"session":{"id":"live_test"},"transport":{"type":"webrtc","sdp":"test-answer"}}"#.utf8),
         HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
    }
    @Test func liveRequestCarriesContextWithWebRTCAudioAndNoStorage() throws {
        let request = try OpenAILiveTutor.request(context: context, apiKey: "test-key", sdp: "offer")
        #expect(request.url?.path == "/v1/live/sessions")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let session = try #require(body["session"] as? [String: Any])
        #expect(session["model"] as? String == "gpt-live-1")
        #expect(session["store"] as? Bool == false)
        let audio = try #require(session["audio"] as? [String: Any])
        #expect(audio["format"] == nil)
        #expect(audio["input"] == nil) // No turn detection gate or PCM append protocol.
        #expect((body["transport"] as? [String: Any])?["type"] as? String == "webrtc")
        let bodyText = String(decoding: request.httpBody!, as: UTF8.self)
        #expect(bodyText.contains("Fenster"))
        #expect(!bodyText.contains("test-key"))
    }
    @Test func incomingReplyDoesNotMuteTheMicrophone() async throws {
        let media = LiveMediaFake()
        let service = OpenAILiveTutor(media: media, exchange: success)
        var received: [String] = []
        service.onEvent = { if case let .transcript(_, _, text, _) = $0 { received.append(text) } }
        try await service.connect(context: context, apiKey: "test")
        #expect(service.isFullDuplex)
        media.onEvent?(["type": "local.level", "input": 0.7, "seconds": 2.0, "speaking": true])
        media.onEvent?(["type": "session.output_transcript.delta", "delta": "The answer is", "start_ms": 1000, "end_ms": 2000])
        media.onEvent?(["type": "session.input_transcript.delta", "delta": "Wait", "start_ms": 1500, "end_ms": 2100])
        #expect(received == ["The answer is", "Wait"])
        #expect(media.mutes.isEmpty)
        service.setMuted(true); service.setMuted(false)
        #expect(media.mutes == [true, false])
        service.disconnect()
        #expect(media.closed)
    }
    @Test func overlappingTranscriptsKeepSeparateTimelinesAndExactText() throws {
        var transcript = LiveTranscript()
        let aValue = transcript.append(["type": "session.input_transcript.delta", "delta": "I would", "event_id": "1", "start_ms": 100, "end_ms": 300])
        let a = try #require(aValue)
        let bValue = transcript.append(["type": "session.output_transcript.delta", "delta": "Sure", "event_id": "2", "start_ms": 200, "end_ms": 400])
        let b = try #require(bValue)
        let cValue = transcript.append(["type": "session.input_transcript.delta", "delta": " like like that", "event_id": "3", "start_ms": 300, "end_ms": 600])
        let c = try #require(cValue)
        #expect(a.id == c.id)
        #expect(a.id != b.id)
        #expect(a.text + c.text == "I would like like that")
        let duplicate = transcript.append(["type": "session.input_transcript.delta", "delta": "duplicate", "event_id": "3", "start_ms": 300, "end_ms": 600])
        #expect(duplicate == nil)
        #expect(transcript.fragments.count == 3)
        #expect(transcript.fragments[2].start == 300)
    }
    @Test func closeDuringHandshakeRejectsLateStartAndClosesMedia() async {
        let media = LiveMediaFake(); media.autoStart = false
        let service = OpenAILiveTutor(media: media, exchange: success)
        let connecting = Task { try await service.connect(context: context, apiKey: "test") }
        for _ in 0..<30 { if media.accepted { break }; await Task.yield() }
        service.disconnect()
        media.onEvent?(["type": "session.started"])
        do { try await connecting.value; Issue.record("Cancelled session connected") } catch {}
        #expect(media.closed)
    }
    @Test func accessFailureDoesNotFallBackToOldRealtimeAPI() async {
        let media = LiveMediaFake()
        let service = OpenAILiveTutor(media: media) { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        }
        do { try await service.connect(context: context, apiKey: "test"); Issue.record("Expected access failure") }
        catch { #expect(error.localizedDescription.contains("GPT-Live access")) }
        #expect(media.closed)
        #expect(!media.accepted)
    }
}
