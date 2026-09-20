import Foundation
import Observation

@MainActor @Observable
final class SentenceCanvasViewModel {
    private(set) var document: CanvasDocument

    private let sentences = MockSentencePair.examples
    private let englishElementID: UUID
    private let germanElementID: UUID
    private var sentenceIndex = 0

    init() {
        let englishID = UUID()
        let germanID = UUID()
        englishElementID = englishID
        germanElementID = germanID

        let first = MockSentencePair.examples[0]
        document = CanvasDocument(elements: [
            CanvasTextElement(
                id: englishID,
                text: first.english,
                center: CanvasPosition(x: 0.5, y: 1.0 / 3),
                width: CanvasTextWidth(),
                style: CanvasTextStyle()
            ),
            CanvasTextElement(
                id: germanID,
                text: first.german,
                center: CanvasPosition(x: 0.5, y: 2.0 / 3),
                width: CanvasTextWidth(),
                style: CanvasTextStyle(foreground: .secondary)
            )
        ])
    }

    func changeSentences() {
        sentenceIndex = (sentenceIndex + 1) % sentences.count
        let pair = sentences[sentenceIndex]
        document = document.replacingText([
            englishElementID: pair.english,
            germanElementID: pair.german
        ])
    }
}
