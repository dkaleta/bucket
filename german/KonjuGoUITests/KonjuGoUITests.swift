import XCTest

final class KonjuGoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--konjugo-ui-testing"]
        app.launch()
        return app
    }

    @MainActor func testLookupShowsDetailsRowsAndExpandableRule() {
        let app = launch()
        let field = app.textFields["verbInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.clickOrTap()
        field.typeText("fahren")
        app.buttons["conjugateButton"].clickOrTap()
        XCTAssertTrue(app.staticTexts["verbTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["to travel / go by vehicle"].exists)
        let du = app.descendants(matching: .any)["row_du"].firstMatch
        reveal(du, in: app)
        XCTAssertTrue(du.label.contains("fährst"))
        XCTAssertTrue(du.label.contains("a changes to ä"))
        let info = app.buttons["ruleInfo"]
        reveal(info, in: app)
        info.clickOrTap()
        XCTAssertTrue(app.staticTexts["ruleExplanation"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "KonjuGo conjugation and rule"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        info.clickOrTap()
        XCTAssertFalse(app.staticTexts["ruleExplanation"].exists)
    }

    @MainActor func testSwitchTenseAndSettings() {
        let app = launch()
        app.textFields["verbInput"].clickOrTap()
        app.textFields["verbInput"].typeText("fahren")
        app.buttons["conjugateButton"].clickOrTap()
        XCTAssertTrue(app.staticTexts["verbTitle"].waitForExistence(timeout: 5))
        let segmented = app.segmentedControls["tensePicker"]
        if segmented.exists {
            reveal(segmented, in: app)
            segmented.buttons["Perfekt"].clickOrTap()
        } else {
            #if os(macOS)
            let picker = app.popUpButtons["tensePicker"]
            #else
            let picker = app.buttons["tensePicker"]
            #endif
            reveal(picker, in: app)
            picker.clickOrTap()
            #if os(macOS)
            app.menuItems["Perfekt"].click()
            #else
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Perfekt")).firstMatch.tap()
            #endif
        }
        let ich = app.descendants(matching: .any)["row_ich"].firstMatch
        reveal(ich, in: app)
        XCTAssertTrue(ich.label.contains("bin gefahren"))
        XCTAssertTrue(ich.label.contains("-en"))
        app.buttons["settingsButton"].clickOrTap()
        XCTAssertTrue(app.secureTextFields["openAIKey"].waitForExistence(timeout: 5))
        app.buttons["Done"].clickOrTap()
    }

    @MainActor func testGroupedMoodMenuAndImperativePersons() {
        let app = launch()
        app.textFields["verbInput"].clickOrTap()
        app.textFields["verbInput"].typeText("fahren")
        app.buttons["conjugateButton"].clickOrTap()
        XCTAssertTrue(app.staticTexts["verbTitle"].waitForExistence(timeout: 5))
        #if os(macOS)
        let picker = app.popUpButtons["tensePicker"]
        #else
        let picker = app.buttons["tensePicker"]
        #endif
        reveal(picker, in: app)
        picker.clickOrTap()
        #if os(macOS)
        XCTAssertTrue(app.menuItems["Konjunktiv I · Präsens"].exists)
        XCTAssertTrue(app.menuItems["Konjunktiv II · würde-Form · Futur I"].exists)
        let menuScreenshot = XCTAttachment(screenshot: app.screenshot())
        menuScreenshot.name = "Grouped mood menu"
        menuScreenshot.lifetime = .keepAlways
        add(menuScreenshot)
        let imperativeItems = app.menuItems.matching(identifier: "Imperativ").allElementsBoundByIndex
        XCTAssertFalse(imperativeItems.isEmpty)
        imperativeItems.last?.click()
        #else
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Imperativ")).firstMatch.tap()
        #endif
        let formal = app.descendants(matching: .any)["row_formalSie"].firstMatch
        reveal(formal, in: app)
        XCTAssertTrue(formal.label.contains("fahren Sie"))
        XCTAssertTrue(app.descendants(matching: .any)["row_du"].firstMatch.label.contains("fahr"))
        XCTAssertFalse(app.descendants(matching: .any)["row_ich"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["row_erSieEs"].firstMatch.exists)
    }

    @MainActor func testLoadingPreferenceInSettings() {
        let app = launch()
        app.buttons["settingsButton"].clickOrTap()
        #if os(macOS)
        let picker = app.popUpButtons["loadingModePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "On demand")
        picker.click()
        app.menuItems["Load everything"].click()
        XCTAssertEqual(picker.value as? String, "Load everything")
        #else
        let picker = app.buttons["loadingModePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Load everything"].tap()
        #endif
        app.buttons["Done"].clickOrTap()
        app.buttons["settingsButton"].clickOrTap()
        #if os(macOS)
        XCTAssertEqual(app.popUpButtons["loadingModePicker"].value as? String, "Load everything")
        #endif
        app.buttons["Done"].clickOrTap()
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        #if os(macOS)
        for _ in 0..<8 where !element.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200) }
        #else
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        #endif
    }
}

private extension XCUIElement {
    @MainActor func clickOrTap() {
        #if os(macOS)
        click()
        #else
        tap()
        #endif
    }
}
