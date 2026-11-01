#if DEBUG
import Foundation

/// Isolated UI fixture: never reads credentials, saves user state, or contacts providers.
@MainActor enum LessonPreview {
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
    private struct Generator: LessonGenerating {
        func generate(tag: LessonTag, source: PracticeSentence, count: Int, excluding: [String], apiKey: String) async throws -> [PracticeSentence] {
            try await Task.sleep(for: .milliseconds(300))
            return (1...count).map { index in
                PracticeSentence(id: index, english: "Does train \(index) leave today?",
                    german: "Fährt Zug \(index) heute ab?", tagIDs: [tag.id, tag.id == "when" ? "separable" : "when"],
                    wordHints: ["question helper", "der Zug", "\(index)", "abfahren", "heute"])
            }
        }
    }
}
#endif
