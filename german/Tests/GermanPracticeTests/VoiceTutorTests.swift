import AVFoundation
import Foundation
import Testing
@testable import GermanPractice

@MainActor private final class TutorKeys: CredentialStoring {
    var key = "test-key"
    func read(_ provider: APIProvider) throws -> String { key }
    func save(_ key: String, for provider: APIProvider) throws {}
}
@MainActor private final class TutorConnection: TutorConnecting {
    var onEvent: ((TutorEvent) -> Void)?
    var onFailure: ((Error) -> Void)?
    var contexts: [TutorContext] = []
    var muted = false
    var stops = 0
    var suspend = false
    var waiter: CheckedContinuation<Void, Never>?
    func connect(context: TutorContext, apiKey: String) async throws {
        contexts.append(context)
        if suspend { await withCheckedContinuation { waiter = $0 } }
    }
    func setMuted(_ muted: Bool) { self.muted = muted }
    func testSpeaker() throws {}
    func interrupt() async throws {}
    func disconnect() { stops += 1 }
}
@MainActor private final class FakeTutorSocket: TutorSocket {
    var request: URLRequest?
    var sent: [[String: Any]] = []
    var closed = false
    var queued: [[String: Any]] = [["type": "session.created"], ["type": "session.updated"]]
    var waiter: CheckedContinuation<[String: Any], Error>?
    func open(_ request: URLRequest) { self.request = request }
    func send(_ event: [String: Any]) async throws {
        if closed { throw CancellationError() }
        sent.append(event)
    }
    func receive() async throws -> [String: Any] {
        if closed { throw CancellationError() }
        if !queued.isEmpty { return queued.removeFirst() }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
    func push(_ event: [String: Any]) {
        if let waiter { self.waiter = nil; waiter.resume(returning: event) }
        else { queued.append(event) }
    }
    func close() {
        closed = true
        waiter?.resume(throwing: CancellationError()); waiter = nil
    }
}
@MainActor private final class FakeTutorAudio: RealtimeAudioIO {
    var onDrained: (() -> Void)?
    var playedMilliseconds = 375
    var hasQueuedAudio = false
    var permissionDenied = false
    var starts = 0
    var suspendStart = false
    var startWaiter: CheckedContinuation<Void, Never>?
    var stopped = false
    var outputStops = 0
    var played: [Data] = []
    var input: AsyncThrowingStream<Data, Error>.Continuation?
    func requestPermission() async throws {
        if permissionDenied { throw PracticeError(message: "Microphone access denied") }
    }
    func start() async throws -> AsyncThrowingStream<Data, Error> {
        starts += 1
        if suspendStart { await withCheckedContinuation { startWaiter = $0 } }
        return AsyncThrowingStream { input = $0 }
    }
    func enqueue(_ pcm: Data) throws { played.append(pcm); hasQueuedAudio = true }
    func stopOutput() { outputStops += 1; hasQueuedAudio = false }
    func stop() { stopped = true; stopOutput(); input?.finish(); input = nil }
}

@MainActor private final class TutorCaptureFixture: LocalMicrophoneCapturing {
    var deviceID: String?
    var sink: AsyncThrowingStream<Data, Error>.Continuation?
    var suspended = false
    var waiter: CheckedContinuation<Void, Never>?
    var stops = 0
    func start(deviceID: String) async throws -> AsyncThrowingStream<Data, Error> {
        self.deviceID = deviceID
        if suspended { await withCheckedContinuation { waiter = $0 } }
        return AsyncThrowingStream { sink = $0 }
    }
    func stop() { stops += 1; sink?.finish(); sink = nil }
}
@MainActor private final class ReplyFixture: RealtimeReplyPlaying {
    var onDrained: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var playedMilliseconds = 100
    var hasQueuedAudio = false
    var deviceName = "Test speakers"
    var starts = 0
    var stopped = false
    var played: [Data] = []
    func start() throws { starts += 1 }
    func enqueue(_ pcm: Data) throws { played.append(pcm); hasQueuedAudio = true }
    func stopOutput() { hasQueuedAudio = false }
    func stop() { stopped = true; stopOutput() }
}

@Suite @MainActor struct VoiceTutorTests {
    private var context: TutorContext {
        TutorContext(lesson: "Requests", sentence: PracticeSentence(id: 1,
            english: "Please close the window.", german: "Bitte schließ das Fenster.", tagIDs: ["home"]),
            answer: "Bitte Fenster", grade: Grade(score: 2, germanAnswer: "Bitte schließ das Fenster.", tip: "Add the verb and article."))
    }
    private func settle(_ predicate: () -> Bool) async {
        for _ in 0..<2000 { if predicate() { return }; await Task.yield() }
        Issue.record("Tutor state did not settle")
    }
    @Test func contextIncludesQuestionAnswerAndDistinctFeedback() throws {
        let event = try OpenAIRealtimeTutor.contextEvent(context)
        let item = try #require(event["item"] as? [String: Any])
        let content = try #require(item["content"] as? [[String: String]])
        let text = try #require(content.first?["text"])
        let json = try #require(text.split(separator: "\n", maxSplits: 1).last)
        let decoded = try JSONDecoder().decode(TutorContext.self, from: Data(json.utf8))
        #expect(decoded.question == "Please close the window.")
        #expect(decoded.learnerAnswer == "Bitte Fenster")
        #expect(decoded.referenceGerman == "Bitte schließ das Fenster.")
        #expect(decoded.grade?.score == 2)
        #expect(decoded.grade?.tip == "Add the verb and article.")
        #expect(decoded.tags == ["Home"])
        let ungraded = TutorContext(lesson: "Mixed", sentence: PracticeSentence(id: 2, english: "Hello.", german: "Hallo."), answer: "", grade: nil)
        #expect(ungraded.grade == nil)
        #expect(ungraded.learnerAnswer.isEmpty)
    }
    @Test func controllerMergesTranscriptMutesAndDisconnects() async {
        let connection = TutorConnection()
        let tutor = VoiceTutor(credentials: TutorKeys(), makeConnection: { connection })
        #expect(connection.contexts.isEmpty)
        tutor.start(context: context)
        await settle { tutor.phase == .active }
        #expect(connection.contexts.first?.learnerAnswer == "Bitte Fenster")
        connection.onEvent?(.transcript(id: "u", role: .learner, text: "How do I say I am closing the window?", append: false))
        connection.onEvent?(.transcript(id: "a", role: .tutor, text: "Ich ", append: true))
        connection.onEvent?(.transcript(id: "a", role: .tutor, text: "schließe das Fenster.", append: true))
        #expect(tutor.messages.count == 2)
        #expect(tutor.messages.last?.text == "Ich schließe das Fenster.")
        connection.onEvent?(.input(level: 0.7, secondsSent: 2.5))
        connection.onEvent?(.devices(input: "USB microphone", output: "Headphones"))
        #expect(tutor.inputLevel == 0.7 && tutor.secondsSent == 2.5)
        #expect(tutor.inputDevice == "USB microphone" && tutor.outputDevice == "Headphones")
        tutor.toggleMute(); #expect(connection.muted && tutor.isMuted)
        #expect(tutor.inputLevel == 0)
        tutor.toggleMute(); #expect(!connection.muted && !tutor.isMuted)
        let callback = connection.onEvent
        tutor.stop()
        callback?(.transcript(id: "late", role: .tutor, text: "Too late", append: false))
        #expect(tutor.messages.count == 2)
        #expect(connection.stops == 1)
        #expect(tutor.phase == .ended)
    }
    @Test func missingKeyAndRuntimeFailureRecover() async {
        let keys = TutorKeys(), connection = TutorConnection()
        let tutor = VoiceTutor(credentials: keys, makeConnection: { connection })
        keys.key = ""
        tutor.start(context: context)
        await settle { tutor.phase == .failed }
        #expect(tutor.errorMessage?.contains("Settings") == true)
        #expect(connection.contexts.isEmpty)
        keys.key = "test"
        tutor.start(context: context)
        await settle { tutor.phase == .active }
        connection.onFailure?(PracticeError(message: "Connection lost"))
        #expect(tutor.phase == .failed)
        #expect(tutor.errorMessage == "Connection lost")
        #expect(connection.stops == 1)
        tutor.start(context: context)
        await settle { tutor.phase == .active }
        #expect(tutor.errorMessage == nil)
        tutor.stop()
    }
    @Test func closeDuringConnectionRejectsLateSuccess() async {
        let connection = TutorConnection()
        connection.suspend = true
        let tutor = VoiceTutor(credentials: TutorKeys(), makeConnection: { connection })
        tutor.start(context: context)
        await settle { connection.waiter != nil }
        tutor.stop()
        connection.waiter?.resume(); connection.waiter = nil
        for _ in 0..<30 { await Task.yield() }
        #expect(tutor.phase == .ended)
        #expect(connection.onEvent == nil)
        #expect(connection.stops >= 1)
    }
    @Test func immediateCloseNeverStartsConnection() async {
        let connection = TutorConnection()
        let tutor = VoiceTutor(credentials: TutorKeys(), makeConnection: { connection })
        tutor.start(context: context); tutor.stop()
        for _ in 0..<30 { await Task.yield() }
        #expect(connection.contexts.isEmpty)
    }
    @Test func handshakeContextAndMutedAudio() async throws {
        let socket = FakeTutorSocket(), audio = FakeTutorAudio()
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        try await service.connect(context: context, apiKey: "example")
        defer { service.disconnect() }
        #expect(socket.request?.url?.host == "api.openai.com")
        #expect(socket.request?.value(forHTTPHeaderField: "Authorization") == "Bearer example")
        #expect(socket.sent.compactMap { $0["type"] as? String } == ["session.update", "conversation.item.create"])
        #expect(audio.starts == 1)
        let bytes = Data([1,2,3,4])
        audio.input?.yield(bytes)
        await settle { socket.sent.count == 3 }
        #expect(socket.sent.last?["audio"] as? String == bytes.base64EncodedString())
        service.setMuted(true)
        audio.input?.yield(bytes)
        await settle { socket.sent.count == 4 }
        #expect(socket.sent.last?["audio"] as? String == Data(count: 4).base64EncodedString())
        service.setMuted(false)
        audio.input?.yield(bytes)
        await settle { socket.sent.count == 5 }
        #expect(socket.sent.last?["audio"] as? String == bytes.base64EncodedString())
        service.disconnect()
        #expect(audio.stopped && socket.closed)
    }
    @Test func interruptionTruncatesHeardAudioAndRejectsLateChunks() async throws {
        let socket = FakeTutorSocket(), audio = FakeTutorAudio()
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        try await service.connect(context: context, apiKey: "example")
        defer { service.disconnect() }
        try await service.handle(["type": "response.created", "response": ["id": "r1"]])
        let delta: [String: Any] = ["type": "response.output_audio.delta", "response_id": "r1", "item_id": "a1", "content_index": 0, "delta": Data([0,1]).base64EncodedString()]
        try await service.handle(delta)
        #expect(audio.played.count == 1)
        try await service.handle(["type": "input_audio_buffer.speech_started", "item_id": "u2"])
        #expect(!audio.hasQueuedAudio)
        #expect(socket.sent.last?["type"] as? String == "conversation.item.truncate")
        #expect(socket.sent.last?["audio_end_ms"] as? Int == 375)
        try await service.handle(delta)
        #expect(audio.played.count == 1)
        try await service.handle(["type": "response.created", "response": ["id": "r2"]])
        try await service.handle(["type": "response.done", "response": ["id": "r1", "status": "cancelled"]])
        var newDelta = delta; newDelta["response_id"] = "r2"; newDelta["item_id"] = "a2"
        try await service.handle(newDelta)
        #expect(audio.played.count == 2)
    }
    @Test func interruptionBeforeFirstAudioRejectsCancelledReply() async throws {
        let socket = FakeTutorSocket(), audio = FakeTutorAudio()
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        try await service.connect(context: context, apiKey: "example")
        defer { service.disconnect() }
        try await service.handle(["type": "response.created", "response": ["id": "r1"]])
        try await service.handle(["type": "input_audio_buffer.speech_started", "item_id": "u2"])
        try await service.handle(["type": "response.output_audio.delta", "response_id": "r1", "item_id": "a1", "delta": Data([0,1]).base64EncodedString()])
        #expect(audio.played.isEmpty)
        #expect(socket.sent.count == 2)
    }
    @Test func permissionAndServerFailuresStopAllResources() async throws {
        let deniedSocket = FakeTutorSocket(), deniedAudio = FakeTutorAudio()
        deniedAudio.permissionDenied = true
        let denied = OpenAIRealtimeTutor(socket: deniedSocket, audio: deniedAudio)
        do { try await denied.connect(context: context, apiKey: "example"); Issue.record("Permission denial ignored") }
        catch { #expect(error.localizedDescription.contains("Microphone")) }
        #expect(deniedSocket.request == nil)
        #expect(deniedAudio.starts == 0)
        let socket = FakeTutorSocket(), audio = FakeTutorAudio()
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        var failure: Error?
        service.onFailure = { failure = $0 }
        try await service.connect(context: context, apiKey: "example")
        socket.push(["type": "error", "error": ["code": "insufficient_quota"]])
        await settle { failure != nil }
        #expect(failure?.localizedDescription.contains("usage limit") == true)
        #expect(socket.closed && audio.stopped)
    }
    @Test func captureFailureStopsSession() async throws {
        let socket = FakeTutorSocket(), audio = FakeTutorAudio()
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        var failure: Error?
        service.onFailure = { failure = $0 }
        try await service.connect(context: context, apiKey: "example")
        audio.input?.finish(throwing: PracticeError(message: "Audio input failed"))
        await settle { failure != nil }
        #expect(failure?.localizedDescription == "Audio input failed")
        #expect(socket.closed && audio.stopped)
    }
    @Test func closingWhileAudioStartsCannotActivateOrSendAudio() async {
        let socket = FakeTutorSocket(), audio = FakeTutorAudio()
        audio.suspendStart = true
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        var events = 0
        service.onEvent = { _ in events += 1 }
        let connection = Task { try await service.connect(context: context, apiKey: "example") }
        await settle { audio.startWaiter != nil }
        service.disconnect()
        audio.startWaiter?.resume(); audio.startWaiter = nil
        do { try await connection.value; Issue.record("Closed connection became active") }
        catch { #expect(error is CancellationError) }
        #expect(events == 0)
        #expect(socket.sent.count == 2)
        #expect(audio.input == nil)
        #expect(socket.closed && audio.stopped)
    }
    @Test func settingsCaptureBytesReachTutorUnchangedWithIndependentPlayback() async throws {
        let capture = TutorCaptureFixture(), playback = ReplyFixture(), socket = FakeTutorSocket()
        let audio = RealtimeAudio(capture: capture, playback: playback,
            input: MicrophoneDevice(id: "working-settings-input", name: "Working microphone"), permission: {})
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        try await service.connect(context: context, apiKey: "test")
        #expect(capture.deviceID == "working-settings-input")
        #expect(audio.deviceNames.input == "Working microphone")
        #expect(playback.starts == 1)
        let samples = TutorPCM.testTone()
        capture.sink?.yield(samples)
        await settle { socket.sent.count == 3 }
        #expect(socket.sent.last?["audio"] as? String == samples.base64EncodedString())
        try await service.handle(["type": "response.created", "response": ["id": "r"]])
        try await service.handle(["type": "response.output_audio.delta", "item_id": "a", "response_id": "r", "delta": samples.base64EncodedString()])
        #expect(playback.played == [samples])
        service.disconnect()
        #expect(capture.sink == nil && playback.stopped)
    }
    @Test func sharedCaptureErrorClosesMicrophonePlaybackAndSocket() async throws {
        let capture = TutorCaptureFixture(), playback = ReplyFixture(), socket = FakeTutorSocket()
        let audio = RealtimeAudio(capture: capture, playback: playback,
            input: MicrophoneDevice(id: "mic", name: "Microphone"), permission: {})
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        var failure: Error?
        service.onFailure = { failure = $0 }
        try await service.connect(context: context, apiKey: "test")
        capture.sink?.finish(throwing: PracticeError(message: "Input disconnected"))
        await settle { failure != nil }
        #expect(failure?.localizedDescription == "Input disconnected")
        #expect(capture.sink == nil && playback.stopped && socket.closed)
    }
    @Test func sharedCaptureCancellationCannotStartPlaybackLate() async throws {
        let capture = TutorCaptureFixture(), playback = ReplyFixture()
        capture.suspended = true
        let audio = RealtimeAudio(capture: capture, playback: playback,
            input: MicrophoneDevice(id: "mic", name: "Microphone"), permission: {})
        let pending = Task { try await audio.start() }
        await settle { capture.waiter != nil }
        audio.stop()
        capture.waiter?.resume(); capture.waiter = nil
        do { _ = try await pending.value; Issue.record("Closed capture restarted") }
        catch { #expect(error is CancellationError) }
        #expect(playback.starts == 0 && capture.sink == nil)
    }
    @Test func repliesDoNotFeedBackIntoMicrophoneAndInterruptResumesInput() async throws {
        let socket = FakeTutorSocket(), audio = FakeTutorAudio()
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        try await service.connect(context: context, apiKey: "test")
        defer { service.disconnect() }
        try await service.handle(["type": "response.created", "response": ["id": "r"]])
        let samples = TutorPCM.testTone()
        try await service.handle(["type": "response.output_audio.delta", "item_id": "a", "response_id": "r", "delta": samples.base64EncodedString()])
        audio.input?.yield(samples)
        await settle { socket.sent.count == 3 }
        #expect(socket.sent.last?["audio"] as? String == Data(count: samples.count).base64EncodedString())
        try await service.interrupt()
        #expect(!audio.hasQueuedAudio)
        let cancel = try #require(socket.sent.first { $0["type"] as? String == "response.cancel" })
        #expect(cancel["response_id"] as? String == "r")
        #expect(socket.sent.last?["type"] as? String == "conversation.item.truncate")
        #expect(socket.sent.last?["audio_end_ms"] as? Int == 375)
        try await service.handle(["type": "error", "error": ["code": "response_cancel_not_active", "event_id": cancel["event_id"]!]])
        // Late audio from the cancelled response must never resume playback.
        try await service.handle(["type": "response.output_audio.delta", "item_id": "a", "response_id": "r", "delta": samples.base64EncodedString()])
        #expect(audio.played.count == 1)
        try await Task.sleep(for: .milliseconds(400))
        audio.input?.yield(samples)
        await settle { socket.sent.count == 6 }
        #expect(socket.sent.last?["audio"] as? String == samples.base64EncodedString())
    }

    @Test func pcmConversionSupportsTutorAndExistingTranscriptionRates() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
        buffer.frameLength = 4800
        for index in 0..<4800 { buffer.floatChannelData?[0][index] = 0.25 }
        let tutorEncoder = try PCMEncoder(inputFormat: format, sampleRate: 24_000)
        let transcriptionEncoder = try PCMEncoder(inputFormat: format)
        // AVAudioConverter buffers frames across calls. Verify a second of input with
        // a small allowance for unflushed resampler frames, rather than per-chunk lengths.
        var tutorPCM = Data(), transcriptionPCM = Data()
        for _ in 0..<10 {
            tutorPCM.append(try tutorEncoder.encode(buffer))
            transcriptionPCM.append(try transcriptionEncoder.encode(buffer))
        }
        #expect((46_000...48_000).contains(tutorPCM.count))
        #expect((30_000...32_000).contains(transcriptionPCM.count))
        #expect(tutorPCM.contains { $0 != 0 })
    }
    @Test func micMeterDistinguishesSilenceFromSound() {
        #expect(TutorPCM.level(Data()) == 0)
        #expect(TutorPCM.level(Data(count: 2400)) == 0)
        let tone = TutorPCM.testTone()
        #expect(tone.count == 14_400)
        #expect(TutorPCM.level(tone) > 0.5)
        #expect(TutorPCM.level(tone) < 1)
        #expect(tone.prefix(2) == Data([0, 0]))
        #expect(tone.suffix(2) == Data([0, 0]))
    }
    @Test func speakerTestUsesReplyOutputAndDoesNotSendToneToTutor() async throws {
        let socket = FakeTutorSocket(), audio = FakeTutorAudio()
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        var playback = ""
        var level = 1.0
        service.onEvent = {
            if case .playback(let text) = $0 { playback = text }
            if case .input(let value, _) = $0 { level = value }
        }
        try await service.connect(context: context, apiKey: "example")
        defer { service.disconnect() }
        try service.testSpeaker()
        #expect(audio.played == [TutorPCM.testTone()])
        #expect(socket.sent.count == 2)
        audio.input?.yield(Data([100, 100, 100, 100]))
        await settle { socket.sent.count == 3 }
        #expect(socket.sent.last?["audio"] as? String == Data(count: 4).base64EncodedString())
        #expect(level == 0)
        audio.hasQueuedAudio = false
        audio.onDrained?()
        #expect(playback == "Test sound played")
    }
    @Test func serverEventsDistinguishHearingFromReceivingAndPlayingReply() async throws {
        let socket = FakeTutorSocket(), audio = FakeTutorAudio()
        let service = OpenAIRealtimeTutor(socket: socket, audio: audio)
        var status: TutorStatus?
        var playback = ""
        service.onEvent = {
            if case .status(let value) = $0 { status = value }
            if case .playback(let text) = $0 { playback = text }
        }
        try await service.connect(context: context, apiKey: "example")
        defer { service.disconnect() }
        #expect(status == .listening)
        try await service.handle(["type": "input_audio_buffer.speech_started", "item_id": "u"])
        #expect(status == .hearing)
        try await service.handle(["type": "input_audio_buffer.speech_stopped", "item_id": "u"])
        #expect(status == .thinking)
        try await service.handle(["type": "response.created", "response": ["id": "r"]])
        try await service.handle(["type": "response.output_audio.delta", "response_id": "r", "item_id": "a", "delta": Data([0,1]).base64EncodedString()])
        #expect(status == .speaking)
        #expect(playback.contains("received"))
        try await service.handle(["type": "response.done", "response": ["id": "r", "status": "completed"]])
        #expect(status == .speaking)
        audio.hasQueuedAudio = false
        audio.onDrained?()
        #expect(status == .listening)
        #expect(playback == "Reply playback finished")
    }
}

/// Opt-in: sends a locally synthesized fixture, never live microphone audio.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GERMAN_VOICE_LIVE_TESTS"] == "1"))
@MainActor struct VoiceTutorLiveTests {
    @Test func syntheticSpeechReceivesTranscriptAndSpokenReply() async throws {
        let key = try KeychainStore().read(.openAI)
        try #require(!key.isEmpty)
        let path = try #require(ProcessInfo.processInfo.environment["GERMAN_VOICE_FIXTURE"])
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let pcm = try PCMEncoder(inputFormat: file.processingFormat, sampleRate: 24_000).encode(buffer)
        let capture = TutorCaptureFixture()
        let playback = RealtimeReplyPlayer()
        let audio = RealtimeAudio(capture: capture, playback: playback,
            input: MicrophoneDevice(id: "synthetic-fixture", name: "Synthetic speech fixture"), permission: {})
        let service = OpenAIRealtimeTutor(audio: audio)
        var heardSpeech = false
        var learnerText = ""
        var tutorText = ""
        var failure: Error?
        var secondsSent = 0.0
        var receivedReply = false
        var finishedPlayback = false
        service.onFailure = { failure = $0 }
        service.onEvent = { event in
            switch event {
            case .status(.hearing): heardSpeech = true
            case .status(.speaking): receivedReply = true
            case .status(.listening): if receivedReply && !audio.hasQueuedAudio { finishedPlayback = true }
            case let .input(_, seconds): secondsSent = seconds
            case let .transcript(_, role, text, append):
                if role == .learner { learnerText = text }
                else if append { tutorText += text }
                else { tutorText = text }
            default: break
            }
        }
        let context = TutorContext(lesson: "Requests", sentence: PracticeSentence(id: 0,
            english: "Please close the window.", german: "Bitte schließ das Fenster."),
            answer: "Bitte Fenster", grade: Grade(score: 2, germanAnswer: "Bitte schließ das Fenster.", tip: "Add the verb."))
        try await service.connect(context: context, apiKey: key)
        defer { service.disconnect() }
        let feed = Task { @MainActor in
            for start in stride(from: 0, to: pcm.count, by: 2400) {
                capture.sink?.yield(pcm.subdata(in: start..<min(start + 2400, pcm.count)))
                try await Task.sleep(for: .milliseconds(50))
            }
            for _ in 0..<600 {
                capture.sink?.yield(Data(count: 2400))
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        defer { feed.cancel() }
        for _ in 0..<300 {
            if failure != nil || (finishedPlayback && tutorText.contains("Fenster") && learnerText != "…") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("Synthetic voice check: sent \(secondsSent)s, speech detected \(heardSpeech), reply played \(finishedPlayback), played milliseconds \(audio.playedMilliseconds)")
        #expect(failure == nil, "\(failure?.localizedDescription ?? "")")
        #expect(heardSpeech)
        #expect(learnerText.lowercased().contains("window"))
        #expect(tutorText.contains("Fenster"))
        #expect(receivedReply && finishedPlayback)
        #expect(audio.playedMilliseconds > 0)
    }
}
