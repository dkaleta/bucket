import Foundation
import Testing
@testable import GermanPractice

@Suite(.enabled(if: ProcessInfo.processInfo.environment["GERMAN_LIVE_TESTS"] == "1"))
@MainActor struct GradingLiveTests {
    @Test func distinguishesMinorSpellingFromMeaningErrors() async throws {
        let key = try KeychainStore().read(.openAI)
        try #require(!key.isEmpty, "Save an OpenAI key in German Practice Settings before running live tests.")
        let grader = OpenAIGrader()
        let cases: [(english: String, reference: String, answer: String, scores: ClosedRange<Int>)] = [
            ("My name is Anna.", "Ich heiße Anna.", "ich haiße anna", 4...4),
            ("My name is Anna.", "Ich heiße Anna.", "ich heiße anna", 5...5),
            ("My name is Anna.", "Ich heiße Anna.", "mein name ist anna", 5...5),
            ("I am learning German.", "Ich lerne Deutsch.", "ich lerne deutsh", 4...4),
            ("I am hungry.", "Ich habe Hunger.", "Ich habe keinen Hunger.", 1...2)
        ]
        for item in cases {
            let sentence = PracticeSentence(id: 0, english: item.english, german: item.reference)
            let grade = try await grader.grade(sentence: sentence, answer: item.answer, apiKey: key)
            #expect(item.scores.contains(grade.score), "Answer: \(item.answer); grade: \(grade)")
            #expect(grade.tip?.lowercased().contains("capital") != true)
            if grade.score == 5 { #expect(grade.tip == nil) }
        }
    }
}
