import SwiftUI

/// Explicitly animatable camera values keep Canvas drawing in sync with SwiftUI animations.
struct MapDrawing: View, Animatable {
    var scale: CGFloat
    var offset: CGPoint
    var progress: CGFloat
    let overview: [MapNode]
    let detail: [MapNode]
    let hoveredID: String?
    @Environment(\.colorScheme) private var colorScheme

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(scale, offset.x), .init(offset.y, progress)) }
        set {
            scale = newValue.first.first
            offset.x = newValue.first.second
            offset.y = newValue.second.first
            progress = newValue.second.second
        }
    }

    var body: some View {
        Canvas { context, size in
            // The understated grid gives panning a spatial reference.
            let step = max(18, min(80, 40 * scale))
            let xStart = offset.x.truncatingRemainder(dividingBy: step)
            let yStart = offset.y.truncatingRemainder(dividingBy: step)
            var dots = Path()
            for x in stride(from: xStart, through: size.width, by: step) {
                for y in stride(from: yStart, through: size.height, by: step) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                }
            }
            context.fill(dots, with: .color(.primary.opacity(0.075)))
            context.transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.x, ty: offset.y)
            draw(overview, opacity: 1 - progress, context: context)
            draw(detail, opacity: progress, context: context)
        }
    }

    private func draw(_ nodes: [MapNode], opacity: CGFloat, context: GraphicsContext) {
        guard opacity > 0, let root = nodes.first else { return }
        context.drawLayer { layer in
            layer.opacity = opacity
            for node in nodes.dropFirst() {
                let left = node.center.x < root.center.x
                let start = CGPoint(x: left ? root.bounds.minX : root.bounds.maxX, y: root.center.y)
                let end = CGPoint(x: left ? node.bounds.maxX : node.bounds.minX, y: node.center.y)
                let midX = (start.x + end.x) / 2
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end, control1: CGPoint(x: midX, y: start.y),
                              control2: CGPoint(x: midX, y: end.y))
                layer.stroke(path, with: .color(MapLayout.palette[node.colorIndex].opacity(0.32)),
                             style: StrokeStyle(lineWidth: 1.6 * node.unitScale, lineCap: .round))
            }
            for node in nodes { drawNode(node, context: layer) }
        }
    }

    private func drawNode(_ node: MapNode, context: GraphicsContext) {
        var layer = context
        layer.translateBy(x: node.center.x, y: node.center.y)
        layer.scaleBy(x: node.unitScale, y: node.unitScale)
        let rect = CGRect(x: -node.size.width / 2, y: -node.size.height / 2,
                          width: node.size.width, height: node.size.height)
        let path = Path(roundedRect: rect, cornerRadius: node.isRoot ? 24 : 18)
        let color: Color = node.colorIndex < 0 ? .primary : MapLayout.palette[node.colorIndex]
        let hovered = hoveredID == node.id && !node.isRoot
        let surface: Color = colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.99)
        layer.fill(path, with: .color(surface))
        layer.fill(path, with: .color(color.opacity(hovered ? 0.16 : node.isRoot ? 0.07 : 0.045)))
        layer.stroke(path, with: .color(color.opacity(hovered ? 0.8 : 0.25)), lineWidth: hovered ? 2 : 1)
        let title = Text(node.title)
            .font(.system(size: node.isRoot ? 23 : 17, weight: node.isRoot ? .semibold : .medium))
            .foregroundStyle(node.isRoot ? Color.primary : color)
        layer.draw(layer.resolve(title), at: CGPoint(x: 0, y: node.subtitle.isEmpty ? 0 : -9))
        if !node.subtitle.isEmpty {
            let subtitle = Text(node.subtitle)
                .font(.system(size: node.isRoot ? 10 : 11, weight: .medium))
                .tracking(node.isRoot ? 1.7 : 0)
                .foregroundStyle(.secondary)
            layer.draw(layer.resolve(subtitle), at: CGPoint(x: 0, y: node.isRoot ? 20 : 16))
        }
    }
}
