import Foundation

/// Describes what the canvas displays, independently of SwiftUI and the sentence source.
struct CanvasDocument: Equatable {
    let elements: [CanvasTextElement]

    /// Publishes a new snapshot while preserving each element's identity and layout.
    func replacingText(_ replacements: [CanvasTextElement.ID: String]) -> CanvasDocument {
        CanvasDocument(elements: elements.map { element in
            var updated = element
            if let text = replacements[element.id] {
                updated.text = text
            }
            return updated
        })
    }
}

struct CanvasTextElement: Identifiable, Equatable {
    let id: UUID
    var text: String
    let center: CanvasPosition
    let width: CanvasTextWidth
    let style: CanvasTextStyle
}

/// Coordinates relative to the available canvas: (0, 0) is its top-left corner.
struct CanvasPosition: Equatable {
    let x: Double
    let y: Double
}

struct CanvasTextWidth: Equatable {
    var maximumPoints: Double = 720
    var canvasFraction: Double = 0.8
}

struct CanvasTextStyle: Equatable {
    enum Foreground: Equatable {
        case primary
        case secondary
    }

    var fontSize: Double = 28
    var foreground: Foreground = .primary
}
