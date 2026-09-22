import Foundation
import Testing
@testable import GermanPractice

@MainActor private final class FakeCredentials: CredentialStoring {
    var keys: [APIProvider: String] = [.elevenLabs: "test-eleven", .openAI: "test-openai"]
    func read(_ provider: APIProvider) throws -> String { keys[provider] ?? "" }
    func save(_ key: String, for provider: APIProvider) throws { keys[provider] = key }
}

@MainActor private final class FakeTranscriber: Transcribing {
    var onEvent: ((TranscriptionEvent) -> Void)?
    var onFailure: ((Error) -> Void)?
    var cancelled = false
    var stops = 0
    var stopWaiter: CheckedContinuation<Void, Error>?
    func start(apiKey: String) async throws {}
    func stop() async throws {
        stops += 1
        try await withCheckedThrowingContinuation { stopWaiter = $0 }
    }
    func cancel() {
        cancelled = true
        stopWaiter?.resume(throwing: CancellationError())
        stopWaiter = nil
    }
    func finish(_ text: String) {
        onEvent?(.committed(text))
        stopWaiter?.resume()
        stopWaiter = nil
    }
}

@MainActor private final class FakeGrader: Grading {
    var receivedAnswer: String?
    var receivedSentence: PracticeSentence?
    var shouldFail = false
    var suspend = false
    var waiter: CheckedContinuation<Grade, Error>?
    func grade(sentence: PracticeSentence, answer: String, apiKey: String) async throws -> Grade {
        receivedSentence = sentence
        receivedAnswer = answer
        if shouldFail { throw PracticeError(message: "Try again.") }
        if suspend { return try await withCheckedThrowingContinuation { waiter = $0 } }
        return Grade(score: 5, germanAnswer: "Ich bin hier.", tip: nil)
    }
}

@MainActor private final class Fixture {
    let credentials = FakeCredentials()
    let grader = FakeGrader()
    let defaults: UserDefaults
    var services: [FakeTranscriber] = []
    lazy var model = PracticeViewModel(credentials: credentials, grader: grader, defaults: defaults) { [unowned self] in
        let service = FakeTranscriber()
        services.append(service)
        return service
    }
    init() { defaults = UserDefaults(suiteName: "GermanPracticeTests.\(UUID())")! }
    func recording() async {
        model.record()
        await eventually { self.model.phase == .recording }
    }
    func ready(_ text: String = "Ich bin hier.") async {
        await recording()
        model.stop()
        await eventually { self.services.last?.stopWaiter != nil }
        services.last?.finish(text)
        await eventually { self.model.phase == .ready }
    }
}

@MainActor private func eventually(_ predicate: () -> Bool) async {
    for _ in 0..<1000 {
        if predicate() { return }
        await Task.yield()
    }
    Issue.record("Expected asynchronous state was not reached")
}

@Suite @MainActor struct PracticeTests {
    @Test func sentenceSet() {
        #expect(Sentences.all.count == 100)
        #expect(Set(Sentences.all.map(\.id)).count == 100)
        #expect(Set(Sentences.all.map(\.english)).count == 100)
        #expect(Sentences.all.allSatisfy { !$0.english.isEmpty && !$0.german.isEmpty })
    }

    @Test func transcriptReplacesInterimAndAppendsSegments() {
        var transcript = TranscriptAccumulator()
        transcript.apply(.partial("Ich"))
        transcript.apply(.partial("Ich bin"))
        #expect(transcript.text == "Ich bin")
        transcript.apply(.committed("Ich bin hier."))
        transcript.apply(.partial("Du bist"))
        transcript.apply(.committed("Du bist dort."))
        transcript.apply(.committed(""))
        #expect(transcript.text == "Ich bin hier. Du bist dort.")
    }

    @Test func stopWaitsForFinalWords() async {
        let fixture = Fixture()
        await fixture.recording()
        fixture.services[0].onEvent?(.partial("Ich bin"))
        fixture.model.stop()
        #expect(fixture.model.phase == .finalizing)
        #expect(!fixture.model.canCheck)
        await eventually { fixture.services[0].stopWaiter != nil }
        fixture.services[0].finish("Ich bin hier.")
        await eventually { fixture.model.phase == .ready }
        #expect(fixture.model.answer == "Ich bin hier.")
        #expect(fixture.model.canCheck)
        #expect(fixture.services[0].cancelled)
    }

    @Test func resetRestartsAndIgnoresOldCallbacks() async {
        let fixture = Fixture()
        await fixture.recording()
        let old = fixture.services[0]
        let lateEvent = old.onEvent
        let lateFailure = old.onFailure
        old.onEvent?(.partial("Old words"))
        fixture.model.record()
        await eventually { fixture.services.count == 2 && fixture.model.phase == .recording }
        lateEvent?(.committed("Obsolete text"))
        lateFailure?(PracticeError(message: "Obsolete error"))
        #expect(fixture.model.answer.isEmpty)
        #expect(fixture.model.errorMessage == nil)
        #expect(fixture.model.index == 0)
        #expect(old.cancelled)
        fixture.model.leave()
    }

    @Test func emptyAnswersCannotBeChecked() async {
        let fixture = Fixture()
        await fixture.ready("")
        #expect(!fixture.model.canCheck)
        fixture.model.answer = " \n "
        fixture.model.check()
        #expect(fixture.grader.receivedAnswer == nil)
        #expect(fixture.model.phase == .ready)
    }

    @Test func typedAnswerIsGradedWithoutTranscription() async {
        let fixture = Fixture()
        fixture.credentials.keys[.elevenLabs] = ""
        fixture.model.answer = "  Ich bin hier.\n"
        #expect(fixture.model.canCheck)
        fixture.model.check()
        #expect(!fixture.model.canCheck)
        await eventually { fixture.model.phase == .graded }
        #expect(fixture.grader.receivedAnswer == "Ich bin hier.")
        #expect(fixture.grader.receivedSentence?.id == fixture.model.sentence.id)
        #expect(fixture.model.grade?.score == 5)
        #expect(fixture.services.isEmpty)

        fixture.model.retry()
        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.answer.isEmpty)
        #expect(fixture.model.grade == nil)
        #expect(fixture.model.index == 0)
        #expect(!fixture.model.canCheck)
        fixture.model.answer = "Ich bin hier."
        fixture.model.check()
        await eventually { fixture.model.phase == .graded }
        fixture.model.next()
        #expect(fixture.model.index == 1)
        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.answer.isEmpty)
        #expect(fixture.services.isEmpty)
    }

    @Test func blankTypedAnswerCannotBeSubmitted() {
        let fixture = Fixture()
        for answer in ["", " \n\t "] {
            fixture.model.answer = answer
            #expect(!fixture.model.canCheck)
            fixture.model.check()
            #expect(fixture.model.phase == .idle)
            #expect(fixture.grader.receivedAnswer == nil)
        }
    }

    @Test func typedAnswerSurvivesGradingFailureAndCanBeEdited() async {
        let fixture = Fixture()
        fixture.grader.shouldFail = true
        fixture.model.answer = "Ich bin her."
        fixture.model.check()
        await eventually { fixture.model.phase == .ready }
        #expect(fixture.model.answer == "Ich bin her.")
        #expect(fixture.model.errorMessage == "Try again.")
        fixture.model.answer = "Ich bin hier."
        fixture.grader.shouldFail = false
        fixture.model.check()
        await eventually { fixture.model.phase == .graded }
        #expect(fixture.grader.receivedAnswer == "Ich bin hier.")
        #expect(fixture.model.errorMessage == nil)
        #expect(fixture.services.isEmpty)
    }

    @Test func checksEditedAnswerAndRemembersProgress() async {
        let fixture = Fixture()
        await fixture.ready("Ich bin her.")
        fixture.model.answer = " Ich bin hier. "
        fixture.model.check()
        await eventually { fixture.model.phase == .graded }
        #expect(fixture.grader.receivedAnswer == "Ich bin hier.")
        #expect(fixture.model.grade?.score == 5)
        fixture.model.next()
        #expect(fixture.model.index == 1)
        #expect(fixture.model.answer.isEmpty)
        #expect(fixture.model.grade == nil)
        #expect(fixture.model.phase == .idle)
        let restored = PracticeViewModel(credentials: fixture.credentials, grader: fixture.grader,
                                         defaults: fixture.defaults, makeTranscriber: { FakeTranscriber() })
        #expect(restored.index == 1)
    }

    @Test func lastSentenceStartsAgain() async {
        let fixture = Fixture()
        fixture.defaults.set(99, forKey: "practice.sentenceIndex")
        #expect(fixture.model.isLast)
        await fixture.ready()
        fixture.model.check()
        await eventually { fixture.model.phase == .graded }
        fixture.model.next()
        #expect(fixture.model.index == 0)
        #expect(fixture.defaults.integer(forKey: "practice.sentenceIndex") == 0)
    }

    @Test func missingKeysAndGradingErrorsAreRecoverable() async {
        let fixture = Fixture()
        fixture.credentials.keys[.elevenLabs] = ""
        fixture.model.record()
        await eventually { fixture.model.phase == .idle }
        #expect(fixture.services.isEmpty)
        #expect(fixture.model.errorMessage?.contains("Settings") == true)
        fixture.credentials.keys[.elevenLabs] = "test"
        await fixture.ready()
        fixture.credentials.keys[.openAI] = ""
        fixture.model.check()
        await eventually { fixture.model.phase == .ready }
        #expect(fixture.model.answer == "Ich bin hier.")
        fixture.credentials.keys[.openAI] = "test"
        fixture.grader.shouldFail = true
        fixture.model.check()
        await eventually { fixture.model.phase == .ready }
        #expect(fixture.model.errorMessage == "Try again.")
        fixture.grader.shouldFail = false
        fixture.model.check()
        await eventually { fixture.model.phase == .graded }
    }

    @Test func disconnectPreservesAvailableTranscript() async {
        let fixture = Fixture()
        await fixture.recording()
        fixture.services[0].onEvent?(.partial("Ich bin"))
        fixture.services[0].onFailure?(PracticeError(message: "Connection lost"))
        #expect(fixture.model.phase == .ready)
        #expect(fixture.model.answer == "Ich bin")
        #expect(fixture.services[0].cancelled)
    }

    @Test func finalizationFailureKeepsEditableText() async {
        let fixture = Fixture()
        await fixture.recording()
        fixture.services[0].onEvent?(.partial("Ich bin hier"))
        fixture.model.stop()
        await eventually { fixture.services[0].stopWaiter != nil }
        fixture.services[0].stopWaiter?.resume(throwing: PracticeError(message: "Transcription took too long."))
        fixture.services[0].stopWaiter = nil
        await eventually { fixture.model.phase == .ready }
        #expect(fixture.model.answer == "Ich bin hier")
        #expect(fixture.model.canCheck)
        #expect(fixture.services[0].cancelled)
    }

    @Test func leavingDuringFinalizationCancelsAndIgnoresLateWords() async {
        let fixture = Fixture()
        await fixture.recording()
        fixture.model.stop()
        await eventually { fixture.services[0].stopWaiter != nil }
        let lateEvent = fixture.services[0].onEvent
        fixture.model.leave()
        lateEvent?(.committed("Discarded"))
        #expect(fixture.model.phase == .idle)
        #expect(fixture.model.answer.isEmpty)
        #expect(fixture.services[0].cancelled)
    }

    @Test func savedPositionIsClamped() {
        let fixture = Fixture()
        fixture.defaults.set(999, forKey: "practice.sentenceIndex")
        #expect(fixture.model.index == 99)
    }

    @Test func staleGradeCannotReplaceNewAttempt() async {
        let fixture = Fixture()
        await fixture.ready()
        fixture.grader.suspend = true
        fixture.model.check()
        await eventually { fixture.grader.waiter != nil }
        fixture.model.record()
        await eventually { fixture.model.phase == .recording }
        fixture.grader.waiter?.resume(returning: Grade(score: 1, germanAnswer: "Obsolete", tip: nil))
        fixture.grader.waiter = nil
        for _ in 0..<10 { await Task.yield() }
        #expect(fixture.model.grade == nil)
        #expect(fixture.model.phase == .recording)
        fixture.model.leave()
    }

    @Test func requestUsesStructuredOutputAndNoStorage() throws {
        let data = try OpenAIGrader.body(sentence: Sentences.all[0], answer: "Ich bin hier.")
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect(body["model"] as? String == "gpt-4.1-mini")
        let text = try #require(body["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["strict"] as? Bool == true)
        #expect(format["type"] as? String == "json_schema")
    }

    @Test func responseDecoding() throws {
        func response(_ grade: String, status: String = "completed") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["status": status, "output": [
                ["type": "message", "content": [["type": "output_text", "text": grade]]]
            ]])
        }
        let valid = #"{"score":5,"germanAnswer":"Ich bin hier.","tip":null}"#
        #expect(try OpenAIGrader.decode(response(valid)).score == 5)
        #expect(throws: PracticeError.self) { try OpenAIGrader.decode(response(valid, status: "incomplete")) }
        #expect(throws: PracticeError.self) { try OpenAIGrader.decode(response(#"{"score":6,"germanAnswer":"X","tip":null}"#)) }
        #expect(throws: PracticeError.self) { try OpenAIGrader.decode(response(#"{"score":3,"germanAnswer":"","tip":null}"#)) }
        #expect(throws: PracticeError.self) { try OpenAIGrader.decode(Data("invalid".utf8)) }
        let refusal = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}"#.utf8)
        #expect(throws: PracticeError.self) { try OpenAIGrader.decode(refusal) }
    }
}
