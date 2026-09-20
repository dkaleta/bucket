import CoreGraphics

/// Resolves document coordinates into points without drawing or modifying the document.
enum CanvasDocumentLayout {
    struct TextPlacement {
        let element: CanvasTextElement
        let center: CGPoint
        let width: CGFloat
    }

    static func placements(for document: CanvasDocument, in size: CGSize) -> [TextPlacement] {
        document.elements.map { element in
            TextPlacement(
                element: element,
                center: CGPoint(x: size.width * element.center.x, y: size.height * element.center.y),
                width: min(element.width.maximumPoints, size.width * element.width.canvasFraction)
            )
        }
    }
}
