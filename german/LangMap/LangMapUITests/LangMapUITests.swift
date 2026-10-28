import XCTest

final class LangMapUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testOverviewBranchAndReturn() throws {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["branch-verbs"].waitForExistence(timeout: 5))
        for id in ["structure", "verbs", "tenses", "nouns", "cases", "connections"] {
            XCTAssertTrue(app.buttons["branch-\(id)"].exists)
        }
        capture("Overview", app: app)
        app.buttons["branch-verbs"].doubleClick()
        XCTAssertTrue(app.staticTexts["topic-verbs.0"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["focused-branch"].value as? String, "Verbs")
        XCTAssertFalse(app.buttons["branch-nouns"].exists)
        XCTAssertTrue(app.staticTexts["topic-verbs.4"].exists)
        capture("Verbs", app: app)
        app.buttons["overview"].click()
        XCTAssertTrue(app.buttons["branch-verbs"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["topic-verbs.0"].exists)
    }

    @MainActor func testZoomResetAndEscape() throws {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["branch-tenses"].waitForExistence(timeout: 5))
        app.buttons["Zoom in"].click()
        XCTAssertEqual(app.staticTexts["zoom-percent"].value as? String, "120%")
        app.buttons["Reset view"].click()
        XCTAssertEqual(app.staticTexts["zoom-percent"].value as? String, "100%")
        app.buttons["branch-tenses"].doubleClick()
        XCTAssertTrue(app.staticTexts["topic-tenses.5"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["branch-tenses"].waitForExistence(timeout: 3))
        app.buttons["branch-nouns"].doubleClick()
        XCTAssertTrue(app.staticTexts["topic-nouns.0"].waitForExistence(timeout: 3))
        app.buttons["Reset view"].click()
        XCTAssertTrue(app.buttons["branch-nouns"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["zoom-percent"].value as? String, "100%")
    }

    @MainActor func testPointerZoomPanAndReversibleFade() throws {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        let branch = app.buttons["branch-verbs"]
        XCTAssertTrue(branch.waitForExistence(timeout: 5))
        let originalX = branch.frame.midX
        let start = branch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 220, dy: 0))
        start.click(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(branch.frame.midX, originalX + 220, accuracy: 3)
        let zoomAnchor = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: branch.frame.midX - app.windows.firstMatch.frame.minX,
                                 dy: branch.frame.midY - app.windows.firstMatch.frame.minY))
        zoomAnchor.hover()
        func percentage() -> Int {
            let value = app.staticTexts["zoom-percent"].value as? String ?? ""
            return Int(value.replacingOccurrences(of: "%", with: "")) ?? 0
        }
        for _ in 0..<15 {
            if percentage() >= 175 { break }
            XCUIElement.perform(withKeyModifiers: .command) {
                zoomAnchor.scroll(byDeltaX: 0, deltaY: 12)
            }
        }
        XCTAssertGreaterThanOrEqual(percentage(), 175)
        XCTAssertLessThan(percentage(), 240)
        capture("Mid-transition", app: app)
        for _ in 0..<15 {
            if percentage() >= 245 { break }
            XCUIElement.perform(withKeyModifiers: .command) {
                zoomAnchor.scroll(byDeltaX: 0, deltaY: 12)
            }
        }
        XCTAssertTrue(app.staticTexts["topic-verbs.0"].waitForExistence(timeout: 3))
        capture("Gesture detail", app: app)
        for _ in 0..<20 {
            if percentage() <= 115 { break }
            XCUIElement.perform(withKeyModifiers: .command) {
                zoomAnchor.scroll(byDeltaX: 0, deltaY: -12)
            }
        }
        XCTAssertTrue(app.buttons["branch-verbs"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["focused-branch"].exists)
        let oldFrame = app.buttons["branch-verbs"].frame
        zoomAnchor.scroll(byDeltaX: 40, deltaY: 0)
        XCTAssertNotEqual(app.buttons["branch-verbs"].frame.minX, oldFrame.minX)
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
