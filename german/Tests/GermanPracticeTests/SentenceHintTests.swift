import Testing
@testable import GermanPractice

@Suite struct SentenceHintTests {
    @Test func everyWordHasAContextualHint() {
        #expect(Set(SentenceHints.translations.keys) == Set(Sentences.all.map(\.id)))
        for sentence in Sentences.all {
            let words = SentenceHints.words(for: sentence)
            let rawHints = SentenceHints.translations[sentence.id]?.components(separatedBy: "|") ?? []
            #expect(rawHints.count == words.count, "Hint count for: \(sentence.english)")
            #expect(words.map(\.english).joined(separator: " ") == sentence.english)
            #expect(Set(words.map(\.id)).count == words.count)
            #expect(words.allSatisfy { !$0.german.isEmpty && $0.german != "Hint unavailable" })
        }
    }

    @Test func foodSentenceProvidesVocabularyInsteadOfTheAnswer() {
        let words = SentenceHints.words(for: Sentences.all[29])
        #expect(words.map(\.english) == ["The", "food", "tastes", "good."])
        #expect(words.map(\.german) == ["der / die / das · here: das", "das Essen", "schmecken", "gut"])
    }

    @Test func expressionsAndContextAvoidLiteralMistranslations() {
        let getUp = SentenceHints.words(for: Sentences.all[40])
        #expect(getUp[1].german == "get up → aufstehen")
        #expect(getUp[2].german == getUp[1].german)
        let lookingFor = SentenceHints.words(for: Sentences.all[39])
        #expect(lookingFor[3].german == "looking for → suchen")
        #expect(SentenceHints.words(for: Sentences.all[32])[3].german == "offen")
        #expect(SentenceHints.words(for: Sentences.all[85])[1].german == "öffnen · command: öffne")
    }
}
