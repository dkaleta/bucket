import CoreGraphics
import Testing
@testable import LangMap

@Suite @MainActor struct LangMapTests {
    private func makeMap() -> MapState {
        let map = MapState()
        map.resize(CGSize(width: 1120, height: 650))
        return map
    }

    @Test func hierarchyHasTwoLevelsAndUniqueIDs() {
        let branches = GrammarTopic.branches
        #expect(branches.count == 6)
        let all = branches + branches.flatMap(\.children)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(branches.allSatisfy { !$0.children.isEmpty })
        #expect(branches.flatMap(\.children).allSatisfy { $0.children.isEmpty })
        #expect(all.allSatisfy { !$0.title.isEmpty && MapLayout.palette.indices.contains($0.colorIndex) })
    }

    @Test func cameraRoundTripAndPointerAnchoring() {
        var camera = MapCamera(scale: 1.7, offset: CGPoint(x: -125, y: 67))
        let world = CGPoint(x: 312, y: -82)
        let screen = camera.screen(world)
        #expect(abs(camera.world(screen).x - world.x) < 0.00001)
        #expect(abs(camera.world(screen).y - world.y) < 0.00001)
        camera.zoom(to: 3.4, around: screen)
        #expect(abs(camera.screen(world).x - screen.x) < 0.00001)
        #expect(abs(camera.screen(world).y - screen.y) < 0.00001)
        camera.pan(by: CGSize(width: 20, height: -40))
        #expect(abs(camera.screen(world).x - screen.x - 20) < 0.00001)
    }

    @Test func boundsFitAndNodesDoNotOverlap() {
        for branch in [nil] + GrammarTopic.branches.map(Optional.some) {
            let nodes = MapLayout.nodes(branch: branch)
            for (i, first) in nodes.enumerated() {
                for second in nodes.dropFirst(i + 1) {
                    #expect(!first.bounds.intersects(second.bounds), "\(first.title) overlaps \(second.title)")
                }
            }
            let viewport = CGSize(width: 1000, height: 650)
            let scale = MapLayout.fitScale(nodes: nodes, viewport: viewport)
            let bounds = MapLayout.bounds(of: nodes)
            #expect(bounds.width * scale <= viewport.width - 99)
            #expect(bounds.height * scale <= viewport.height - 99)
        }
    }

    @Test func hitTestingUsesTransformedMeasuredBounds() throws {
        let map = makeMap()
        let node = try #require(map.overviewNodes.first { $0.id == "structure" })
        map.pan(by: CGSize(width: 45, height: -27))
        map.camera.zoom(to: map.camera.scale * 1.4, around: .zero)
        #expect(MapLayout.hit(at: map.camera.screen(node.center), camera: map.camera, nodes: map.overviewNodes)?.id == node.id)
        let outside = CGPoint(x: node.bounds.maxX + 1, y: node.center.y)
        #expect(MapLayout.hit(at: map.camera.screen(outside), camera: map.camera, nodes: map.overviewNodes) == nil)
    }

    @Test func crossFadeFollowsZoomAndReverses() throws {
        let map = makeMap()
        let node = try #require(map.overviewNodes.first { $0.id == "verbs" })
        let anchor = map.camera.screen(node.center)
        map.zoom(factor: 1.8, at: anchor)
        #expect(map.focus?.branch.id == "verbs")
        #expect(abs(map.progress - 0.5) < 0.00001)
        #expect(abs(map.camera.screen(node.center).x - anchor.x) < 0.00001)
        map.zoom(factor: 2.4 / 1.8, at: anchor)
        #expect(abs(map.progress - 1) < 0.00001)
        map.zoom(factor: 1.8 / 2.4, at: anchor)
        #expect(abs(map.progress - 0.5) < 0.00001)
        map.zoom(factor: 1.1 / 1.8, at: anchor)
        #expect(map.focus == nil)
        #expect(map.progress == 0)
    }

    @Test func focusSurvivesPanningAndZoomingOverOtherBranches() throws {
        let map = makeMap()
        map.enter(branchID: "verbs")
        #expect(map.showingDetail)
        map.pan(by: CGSize(width: 200, height: -75))
        let other = try #require(map.overviewNodes.first { $0.id == "nouns" })
        map.zoom(factor: 1.1, at: map.camera.screen(other.center))
        #expect(map.focus?.branch.id == "verbs")
        map.enter(branchID: "nouns")
        #expect(map.focus?.branch.id == "verbs")
        #expect(map.activeNodes.dropFirst().allSatisfy { $0.id.hasPrefix("verbs.") })
    }

    @Test func emptySpaceZoomClampsWithoutEntering() {
        let map = makeMap()
        let empty = CGPoint(x: -10000, y: -10000)
        map.zoom(factor: 100, at: empty)
        #expect(map.focus == nil)
        #expect(map.camera.scale == map.fittedScale * 8)
        map.zoom(factor: 0.0001, at: empty)
        #expect(map.camera.scale == map.fittedScale * 0.5)
        let before = map.camera
        map.zoom(factor: .nan, at: empty)
        #expect(map.camera == before)
    }

    @Test func branchCanFinishOpeningAtMaximumCameraZoom() throws {
        let map = makeMap()
        map.zoom(factor: 100, at: CGPoint(x: -10000, y: -10000))
        let node = try #require(map.overviewNodes.first { $0.id == "verbs" })
        map.zoom(factor: 2.4, at: map.camera.screen(node.center))
        #expect(map.progress == 1)
        #expect(map.camera.scale == map.fittedScale * 8)
        map.zoom(factor: 0.4, at: map.viewportCenter)
        #expect(map.focus == nil)
    }

    @Test func backRestoresOverviewAndResetFitsEverything() {
        let map = makeMap()
        map.pan(by: CGSize(width: 60, height: 30))
        let original = map.camera
        map.enter(branchID: "nouns")
        map.pan(by: CGSize(width: -400, height: 90))
        map.back()
        #expect(map.camera == original)
        #expect(map.focus == nil)
        map.reset()
        #expect(map.camera.offset == map.viewportCenter)
        #expect(map.camera.scale == map.fittedScale)
        #expect(map.zoomPercent == 100)
    }

    @Test func resizePreservesWorldCenterAndSavedOverview() {
        let map = makeMap()
        let overviewCenter = map.camera.world(map.viewportCenter)
        map.enter(branchID: "cases")
        let detailCenter = map.camera.world(map.viewportCenter)
        map.resize(CGSize(width: 1400, height: 900))
        #expect(map.camera.world(map.viewportCenter) == detailCenter)
        map.back()
        #expect(map.camera.world(map.viewportCenter) == overviewCenter)
    }

    @Test func noThirdLevelAndInvalidBranchesAreIgnored() {
        let map = makeMap()
        map.enter(branchID: "missing")
        #expect(map.focus == nil)
        map.enter(branchID: "tenses")
        map.enter(branchID: "tenses.0")
        #expect(map.focus?.branch.id == "tenses")
        map.zoom(factor: 2, at: map.viewportCenter)
        #expect(map.progress == 1)
        #expect(map.focus?.branch.id == "tenses")
    }
}
