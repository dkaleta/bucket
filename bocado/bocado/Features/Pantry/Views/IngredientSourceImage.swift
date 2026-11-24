import SwiftUI

struct IngredientSourceImage: View {
    let image: CGImage
    let point: CGPoint
    let name: String
    var move: ((CGPoint) -> Void)?

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    let x = point.x * size.width
                    let y = point.y * size.height
                    ZStack(alignment: .topLeading) {
                        Circle()
                            .fill(KitchenTheme.accent.opacity(0.45))
                            .strokeBorder(.white, lineWidth: 2)
                            .frame(width: 24, height: 24)
                            .overlay { Circle().fill(.white).frame(width: 5, height: 5) }
                            .shadow(radius: 2)
                            .position(x: x, y: y)
                        if !name.isEmpty {
                            Text(name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(KitchenTheme.text, in: Capsule())
                                .frame(width: min(size.width, 150))
                                .position(x: min(max(x, min(size.width, 150) / 2), size.width - min(size.width, 150) / 2),
                                          y: y > 42 ? y - 26 : min(y + 26, size.height - 12))
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard size.width > 0, size.height > 0 else { return }
                        move?(CGPoint(x: min(max(location.x / size.width, 0), 1),
                                      y: min(max(location.y / size.height, 0), 1)))
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("ingredient-source-photo")
            .accessibilityLabel("Source photo, marked item: \(name)")
    }
}
