import Foundation
import Testing
@testable import GermanPractice

@MainActor private final class LessonKeys: CredentialStoring {
    func read(_ provider: APIProvider) throws -> String { "fake" }
    func save(_ key: String, for provider: APIProvider) throws {}
}
@MainActor private struct LessonGrader: Grading {
    func grade(sentence: PracticeSentence, answer: String, apiKey: String) async throws -> Grade {
        Grade(score: 4, germanAnswer: sentence.german, tip: "Try this.")
    }
}
@MainActor private final class LessonGenerator: LessonGenerating {
    var counts: [Int] = []
    var failure = false
    var suspended = false
    var waiter: CheckedContinuation<[PracticeSentence], Error>?
    func generate(tag: LessonTag, source: PracticeSentence, count: Int, excluding: [String], apiKey: String) async throws -> [PracticeSentence] {
        counts.append(count)
        if failure { throw PracticeError(message: "Offline") }
        if suspended { return try await withCheckedThrowingContinuation { waiter = $0 } }
        return questions(count, tag: tag.id)
    }
}
private func questions(_ count: Int = 5, tag: String = "when") -> [PracticeSentence] {
    (1...count).map { PracticeSentence(id: $0, english: "When is train \($0)?", german: "Wann fährt Zug \($0)?", tagIDs: [tag, "travel"], wordHints: ["wann", "sein", "der Zug", "\($0)"]) }
}
@MainActor private func settle(_ check: () -> Bool) async {
    for _ in 0..<1000 { if check() { return }; await Task.yield() }
    Issue.record("Operation did not finish")
}
@Suite @MainActor struct LessonTests {
    private func model(_ generator: LessonGenerator, defaults: UserDefaults, store: PracticeSessionStore? = nil) -> PracticeViewModel {
        PracticeViewModel(credentials: LessonKeys(), grader: LessonGrader(), defaults: defaults,
                          generator: generator, sessionStore: store, makeTranscriber: { fatalError("No recording in lesson tests") })
    }
    @Test func catalogueAndCoverage() {
        #expect(Set(LessonTag.all.map(\.id)).count == LessonTag.all.count)
        for sentence in Sentences.all {
            #expect((2...4).contains(sentence.tagIDs.count))
            #expect(sentence.tagIDs.allSatisfy { LessonTag.find($0) != nil })
        }
        #expect(Sentences.all[78].tagIDs == ["when","travel","separable"])
    }
    @Test func nestedReturnAndRestart() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(78, forKey: "practice.sentenceIndex")
        defaults.set(5, forKey: "practice.lessonSize")
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "/session.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PracticeSessionStore(url: url)
        let generator = LessonGenerator()
        let vm = model(generator, defaults: defaults, store: store)
        vm.answer = "wann zug"
        vm.check()
        await settle { vm.phase == .graded }
        vm.startLesson(LessonTag.find("when")!)
        await settle { vm.sessions.count == 2 }
        vm.answer = "first lesson draft"
        vm.startLesson(LessonTag.find("present")!)
        await settle { vm.sessions.count == 3 }
        vm.answer = "nested draft"
        vm.saveProgress()
        let restored = model(generator, defaults: defaults, store: store)
        #expect(restored.sessions.count == 3)
        #expect(restored.answer == "nested draft")
        #expect(restored.phase == .ready)
        restored.returnToParent()
        #expect(restored.answer == "first lesson draft")
        #expect(restored.progress == "1 / 5")
        restored.returnToParent()
        #expect(restored.answer == "wann zug")
        #expect(restored.grade?.score == 4)
        #expect(restored.phase == .graded)
        #expect(restored.progress == "79 / 100")
        #expect(defaults.integer(forKey: "practice.sentenceIndex") == 78)
        #expect(generator.counts == [5,5])
    }
    @Test func completionAndSizes() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let generator = LessonGenerator()
        let vm = model(generator, defaults: defaults)
        vm.startLesson(LessonTag.find("when")!)
        await settle { !vm.isPreparing }
        #expect(vm.progress == "1 / 10")
        for _ in 0..<10 {
            vm.answer = "answer"
            vm.check()
            await settle { vm.phase == .graded }
            vm.next()
        }
        #expect(vm.sessions.count == 1)
        #expect(vm.index == 0)
        defaults.set(20, forKey: "practice.lessonSize")
        vm.startLesson(LessonTag.find("when")!)
        await settle { !vm.isPreparing }
        #expect(vm.progress == "1 / 20")
    }
    @Test func failureCancellationAndLateResponse() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let generator = LessonGenerator()
        let vm = model(generator, defaults: defaults)
        vm.answer = "keep this"
        generator.failure = true
        vm.startLesson(LessonTag.find("when")!)
        await settle { vm.lessonError != nil }
        #expect(vm.answer == "keep this")
        #expect(vm.sessions.count == 1)
        generator.failure = false
        generator.suspended = true
        vm.startLesson(LessonTag.find("when")!)
        await settle { generator.waiter != nil }
        vm.cancelLesson()
        generator.waiter?.resume(returning: questions(10))
        for _ in 0..<20 { await Task.yield() }
        #expect(vm.sessions.count == 1)
        #expect(vm.preparingTag == nil)
    }
    @Test func corruptSnapshotAndLegacyMigration() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(78, forKey: "practice.sentenceIndex")
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "/session.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: url)
        let store = PracticeSessionStore(url: url)
        let vm = model(LessonGenerator(), defaults: defaults, store: store)
        #expect(vm.index == 78)
        #expect(vm.errorMessage != nil)
        vm.answer = "recovered answer"
        vm.saveProgress()
        #expect(try store.load()?.last?.answer == "recovered answer")
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(files.contains { $0.contains("unreadable-") })
        let restored = model(LessonGenerator(), defaults: defaults, store: store)
        #expect(restored.answer == "recovered answer")
    }

    @Test func generationContractAndValidation() throws {
        let tag = LessonTag.find("when")!
        let body = try #require(JSONSerialization.jsonObject(with: OpenAILessonGenerator.body(tag: tag, source: Sentences.all[78], count: 5, excluding: [])) as? [String: Any])
        #expect(body["service_tier"] as? String == "ultrafast")
        #expect(body["store"] as? Bool == false)
        func response(_ qs: [PracticeSentence], status: String = "completed") throws -> Data {
            let encoded = try JSONEncoder().encode(qs)
            let array = try JSONSerialization.jsonObject(with: encoded)
            let text = String(decoding: try JSONSerialization.data(withJSONObject: ["questions":array]), as: UTF8.self)
            return try JSONSerialization.data(withJSONObject: ["status":status,"output":[["type":"message","content":[["type":"output_text","text":text]]]]])
        }
        #expect(try OpenAILessonGenerator.decode(response(questions()), count: 5, tag: "when", excluding: []).count == 5)
        #expect(throws: (any Error).self) { try OpenAILessonGenerator.decode(response(questions(), status: "incomplete"), count: 5, tag: "when", excluding: []) }
        #expect(throws: (any Error).self) { try OpenAILessonGenerator.decode(response(questions()), count: 5, tag: "when", excluding: [questions()[0].english]) }
        var invalid = questions(); invalid[0].wordHints = []
        #expect(throws: (any Error).self) { try OpenAILessonGenerator.validate(invalid, count: 5) }
        invalid = questions(); invalid[0].tagIDs = ["unknown","when"]
        #expect(throws: (any Error).self) { try OpenAILessonGenerator.validate(invalid, count: 5) }
        invalid = questions(); invalid[1] = invalid[0]
        #expect(throws: (any Error).self) { try OpenAILessonGenerator.validate(invalid, count: 5) }
        #expect(throws: (any Error).self) { try OpenAILessonGenerator.validate(questions(), count: 10) }
        #expect(SentenceHints.words(for: questions()[0]).first?.german == "wann")
    }
}
