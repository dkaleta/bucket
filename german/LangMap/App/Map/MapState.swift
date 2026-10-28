import Foundation
import CoreGraphics
import Observation

@MainActor @Observable
final class MapState {
    struct Focus {
        let branch: GrammarTopic
        var overviewCamera: MapCamera
        let entryScale: CGFloat
        let origin: CGPoint
        let unit: CGFloat
        // Tracks zoom intent even at a camera clamp, so a branch can always open.
        var relativeZoom: CGFloat = 1
    }

    var camera = MapCamera()
    private(set) var viewport = CGSize.zero
    private(set) var fittedScale: CGFloat = 1
    private(set) var focus: Focus?
    private(set) var hoveredID: String?
    private var pointer: CGPoint?

    var overviewNodes: [MapNode] { MapLayout.nodes() }
    var detailNodes: [MapNode] {
        guard let focus else { return [] }
        return MapLayout.nodes(branch: focus.branch, origin: focus.origin, unit: focus.unit)
    }
    var progress: CGFloat { Self.fadeProgress(relativeZoom: focus?.relativeZoom ?? 1) }
    var showingDetail: Bool { progress >= 0.5 }
    var activeNodes: [MapNode] { showingDetail ? detailNodes : overviewNodes }
    var viewportCenter: CGPoint { CGPoint(x: viewport.width / 2, y: viewport.height / 2) }
    var zoomPercent: Int { Int((camera.scale / fittedScale * 100).rounded()) }

    static func fadeProgress(relativeZoom: CGFloat) -> CGFloat {
        let t = min(max((relativeZoom - 1.2) / 1.2, 0), 1)
        return t * t * (3 - 2 * t)
    }

    func resize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != viewport else { return }
        let oldSize = viewport
        viewport = size
        if oldSize == .zero { reset(); return }
        let delta = CGSize(width: (size.width - oldSize.width) / 2, height: (size.height - oldSize.height) / 2)
        camera.pan(by: delta)
        focus?.overviewCamera.pan(by: delta)
        hover(at: pointer)
    }

    func reset() {
        focus = nil
        hoveredID = nil
        fittedScale = MapLayout.fitScale(nodes: overviewNodes, viewport: viewport)
        camera = MapCamera(scale: fittedScale, offset: viewportCenter)
    }

    func hover(at point: CGPoint?) {
        pointer = point
        hoveredID = point.flatMap { MapLayout.hit(at: $0, camera: camera, nodes: activeNodes)?.id }
    }

    func pan(by delta: CGSize) {
        camera.pan(by: delta)
        hover(at: pointer)
    }

    func zoom(factor: CGFloat, at anchor: CGPoint) {
        guard factor.isFinite, factor > 0, factor != 1 else { return }
        if focus == nil, factor > 1,
           let node = MapLayout.hit(at: anchor, camera: camera, nodes: overviewNodes), !node.isRoot {
            capture(branchID: node.id)
        }
        var desiredScale = camera.scale * factor
        if var current = focus {
            let maximumRelativeZoom = max(2.4, fittedScale * 8 / current.entryScale)
            current.relativeZoom = min(max(current.relativeZoom * factor, 0.5), maximumRelativeZoom)
            desiredScale = current.entryScale * current.relativeZoom
            focus = current
            if factor < 1 && current.relativeZoom <= 1.2 { focus = nil }
        }
        let newScale = min(max(desiredScale, fittedScale * 0.5), fittedScale * 8)
        camera.zoom(to: newScale, around: anchor)
        hover(at: pointer)
    }

    func enter(branchID: String) {
        guard focus == nil, capture(branchID: branchID), let focus else { return }
        let destinationScale = min(focus.entryScale * 2.4, fittedScale * 8)
        // Explicit navigation fits the chosen map; gesture navigation keeps its anchor.
        camera = MapCamera(scale: destinationScale,
                           offset: CGPoint(x: viewportCenter.x - focus.origin.x * destinationScale,
                                           y: viewportCenter.y - focus.origin.y * destinationScale))
        self.focus?.relativeZoom = 2.4
        hoveredID = nil
    }

    func back() {
        guard let focus else { return }
        camera = focus.overviewCamera
        self.focus = nil
        hoveredID = nil
    }

    @discardableResult private func capture(branchID: String) -> Bool {
        guard let branch = GrammarTopic.branches.first(where: { $0.id == branchID }),
              let node = overviewNodes.first(where: { $0.id == branchID }) else { return false }
        let destinationScale = min(camera.scale * 2.4, fittedScale * 8)
        let detailFit = MapLayout.fitScale(nodes: MapLayout.nodes(branch: branch), viewport: viewport)
        focus = Focus(branch: branch, overviewCamera: camera, entryScale: camera.scale,
                      origin: node.center, unit: detailFit / destinationScale)
        return true
    }
}
