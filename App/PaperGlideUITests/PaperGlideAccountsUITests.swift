import XCTest

final class PaperGlideAccountsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNameStepAndOfflineLeaderboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-paperGlideResetStore"]
        app.launch()

        let helper = app.staticTexts["nameHelper"]
        XCTAssertTrue(helper.waitForExistence(timeout: 15))
        XCTAssertEqual(helper.label, "pick a name. letters, numbers and _ only. you can't change it later.")
        XCTAssertTrue(app.buttons["playButton"].isHittable)
        XCTAssertTrue(app.textFields["nameField"].exists)
        XCTAssertTrue(app.buttons["nameSaveButton"].exists)

        app.buttons["nameLaterButton"].tap()
        XCTAssertFalse(app.buttons["nameLaterButton"].waitForExistence(timeout: 2))

        app.buttons["leaderboardButton"].tap()
        let offline = app.staticTexts["boardOffline"]
        XCTAssertTrue(offline.waitForExistence(timeout: 10))
        XCTAssertEqual(offline.label, "you're offline. the board will load when you're back online.")
        XCTAssertEqual(app.staticTexts["boardLocalBest"].label, "local best 0")
        XCTAssertTrue(app.staticTexts["boardCaption"].label.contains("toronto time"))

        app.buttons["leaderboardBackButton"].tap()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["boardOffline"].exists)
    }

    func testReportSheetOpensAndSavesOffline() {
        let app = XCUIApplication()
        app.launchArguments = ["-paperGlideResetStore"]
        app.launch()

        let report = app.buttons["reportButton"]
        XCTAssertTrue(report.waitForExistence(timeout: 15))
        XCTAssertTrue(report.isEnabled)
        XCTAssertEqual(report.label, "Report a problem")
        if !report.isHittable {
            app.swipeUp()
        }
        report.tap()

        let title = app.staticTexts["reportTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Report a problem")
        XCTAssertEqual(app.staticTexts["reportLine"].label, "tell us what went wrong. we'll read every one.")
        XCTAssertEqual(
            app.staticTexts["reportSmallPrint"].label,
            "we'll include your app version and device model. no other info."
        )
        let send = app.buttons["reportSend"]
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled)

        app.buttons["reportCategory-Something looks wrong"].tap()
        XCTAssertTrue(send.isEnabled)
        send.tap()

        let toast = app.staticTexts["reportToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 8))
        XCTAssertEqual(toast.label, "saved. we'll send it when you're back online")
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
    }

    func testLeaderboardQueueCountsTabBackAndOneScroll() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-paperGlideResetStore",
            "-paperGlideAnalyticsReadout",
            "-paperGlideLeaderboardFixture"
        ]
        app.launch()
        if app.buttons["nameLaterButton"].waitForExistence(timeout: 15) {
            app.buttons["nameLaterButton"].tap()
        }
        app.buttons["leaderboardButton"].tap()
        XCTAssertTrue(app.buttons["boardRow"].waitForExistence(timeout: 10))

        let readout = app.staticTexts["analyticsQueue"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertEqual(queueCount(readout.label, "Today"), 0)
        XCTAssertEqual(queueCount(readout.label, "scroll"), 0)

        app.swipeUp()
        XCTAssertTrue(waitForQueue(readout, control: "scroll", count: 1))
        XCTAssertEqual(queueCount(readout.label, "scroll"), 1)

        let week = app.segmentedControls["boardPicker"].buttons["This week"]
        if week.waitForExistence(timeout: 2) {
            week.tap()
        } else {
            app.buttons["This week"].tap()
        }
        XCTAssertTrue(waitForQueue(readout, control: "This week", count: 1))
        XCTAssertEqual(queueCount(readout.label, "Today"), 0)

        app.buttons["leaderboardBackButton"].tap()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForQueue(readout, control: "back", count: 1))
        XCTAssertEqual(queueCount(readout.label, "scroll"), 1)
        XCTAssertEqual(queueCount(readout.label, "This week"), 1)
    }

    private func queueCount(_ label: String, _ control: String) -> Int {
        for part in label.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pieces.count == 2, pieces[0] == control {
                return Int(pieces[1]) ?? -1
            }
        }
        return -1
    }

    private func waitForQueue(_ readout: XCUIElement, control: String, count: Int) -> Bool {
        let expected = "\(control)=\(count)"
        let predicate = NSPredicate(format: "label CONTAINS %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: readout)
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }
}
