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
        XCTAssertFalse(app.buttons["shareButton"].exists)
        XCTAssertEqual(helper.label, "pick a name. letters, numbers and _ only. you can't change it later.")
        XCTAssertTrue(app.buttons["playButton"].isHittable)
        XCTAssertTrue(app.textFields["nameField"].exists)
        XCTAssertTrue(app.buttons["nameSaveButton"].exists)

        app.buttons["nameLaterButton"].tap()
        XCTAssertFalse(app.buttons["nameLaterButton"].waitForExistence(timeout: 2))

        app.buttons["leaderboardButton"].tap()
        XCTAssertFalse(app.buttons["shareButton"].exists)
        let offline = app.staticTexts["boardOffline"]
        XCTAssertTrue(offline.waitForExistence(timeout: 10))
        XCTAssertEqual(offline.label, "you're offline. the board will load when you're back online.")
        XCTAssertEqual(app.staticTexts["boardLocalBest"].label, "local best 0")
        XCTAssertTrue(app.staticTexts["boardCaption"].label.contains("toronto time"))

        app.buttons["leaderboardBackButton"].tap()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["boardOffline"].exists)
    }
}
