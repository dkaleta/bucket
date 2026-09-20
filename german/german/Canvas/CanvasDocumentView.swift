import SwiftUI

struct CanvasDocumentView: View {
    let document: CanvasDocument

    var body: some View {
        GeometryReader { geometry in
            let placements = CanvasDocumentLayout.placements(for: document, in: geometry.size)

            Canvas { context, _ in
                for placement in placements {
                    guard let symbol = context.resolveSymbol(id: placement.element.id) else { continue }
                    context.draw(symbol, at: placement.center, anchor: .center)
                }
            } symbols: {
                ForEach(placements, id: \.element.id) { placement in
                    textSymbol(for: placement)
                        .tag(placement.element.id)
                }
            }
            .accessibilityRepresentation {
                VStack {
                    ForEach(document.elements) { element in
                        Text(element.text)
                    }
                }
            }
        }
    }

    private func textSymbol(for placement: CanvasDocumentLayout.TextPlacement) -> some View {
        Text(placement.element.text)
            .font(.system(size: placement.element.style.fontSize))
            .foregroundStyle(placement.element.style.foreground == .primary ? Color.primary : Color.secondary)
            .multilineTextAlignment(.center)
            .frame(width: placement.width)
            .fixedSize(horizontal: false, vertical: true)
    }
}
