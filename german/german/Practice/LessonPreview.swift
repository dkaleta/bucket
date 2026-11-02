#if DEBUG
import Foundation

/// Isolated UI fixture: never reads credentials, saves user state, or contacts providers.
@MainActor enum LessonPreview {
    static func speech() -> AnswerSpeech {
        AnswerSpeech(credentials: Keys(), generator: PreviewSpeech(), player: PreviewPlayer())
    }
    private struct PreviewSpeech: SpeechGenerating {
        func audio(text: String, apiKey: String) async throws -> Data {
            try await Task.sleep(for: .seconds(1))
            return Data([0])
        }
    }
    private struct PreviewPlayer: SpeechPlaying {
        func play(_ data: Data) async throws { try await Task.sleep(for: .seconds(3)) }
        func stop() {}
    }
    static func model() -> PracticeViewModel {
        let defaults = UserDefaults(suiteName: "GermanPractice.LessonPreview")!
        defaults.set(78, forKey: "practice.sentenceIndex")
        defaults.set(5, forKey: "practice.lessonSize")
        return PracticeViewModel(credentials: Keys(), grader: Grader(), defaults: defaults,
                                 generator: Generator(), makeTranscriber: { ElevenLabsTranscriber() })
    }
    private struct Keys: CredentialStoring {
        func read(_ provider: APIProvider) throws -> String { provider == .openAI ? "preview" : "" }
        func save(_ key: String, for provider: APIProvider) throws {}
    }
    private struct Grader: Grading {
        func grade(sentence: PracticeSentence, answer: String, apiKey: String) async throws -> Grade {
            Grade(score: 5, germanAnswer: sentence.german, tip: nil)
        }
    }
    private final class Generator: LessonGenerating {
        private var batch = 0
        func generate(request: PracticeGenerationRequest, count: Int, excluding: [String], apiKey: String) async throws -> [PracticeSentence] {
        let tag: LessonTag
        switch request {
        case .mixedBeginner: tag = LessonTag.find("when")!
        case .focused(let focus, _): tag = focus
        }
            batch += 1
            let offset = batch * 20
            try await Task.sleep(for: .milliseconds(300))
            return (1...count).map { index in
                PracticeSentence(id: index, english: "Does train \(index + offset) leave today?",
                    german: "Fährt Zug \(index + offset) heute ab?", tagIDs: [tag.id, tag.id == "when" ? "separable" : "when"],
                    wordHints: ["question helper", "der Zug", "\(index + offset)", "abfahren", "heute"])
            }
        }
    }
}
#endif
