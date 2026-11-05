import XCTest

/// Launches Paper Glide in the simulator and keeps screenshots of the main screens.
/// `-paperGlideEndScore` holds physics on the coach screen, then the first tap
/// finishes the run through the real new-best rule.
final class PaperGlideScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureRunScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paperGlideResetStore", "-paperGlideEndScore", "1"]
        app.launch()

        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        save("01-start")

        play.tap()
        let coach = app.staticTexts["coachLabel"]
        XCTAssertTrue(coach.waitForExistence(timeout: 10))
        XCTAssertEqual(coach.label, "tap to glide")
        save("02-first-run-coach")

        let glide = app.buttons["glideTapArea"]
        XCTAssertTrue(glide.waitForExistence(timeout: 5))
        glide.tap()

        let newBest = app.staticTexts["newBestLabel"]
        XCTAssertTrue(newBest.waitForExistence(timeout: 10))
        XCTAssertEqual(newBest.label, "New best!")
        let best = app.staticTexts["bestScoreLabel"]
        XCTAssertTrue(best.exists)
        XCTAssertEqual(best.label, "Best score 1")
        save("03-death-new-best")

        app.buttons["shareButton"].tap()
        let shareText = app.staticTexts["I scored 1 in Paper Glide"]
        _ = shareText.waitForExistence(timeout: 5)
        save("04-share-sheet")
        dismissShareSheet(app)

        app.buttons["retryButton"].tap()
        let score = app.staticTexts["scoreLabel"]
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        XCTAssertEqual(score.label, "Score 0")
        XCTAssertFalse(app.staticTexts["coachLabel"].exists)
        XCTAssertFalse(app.staticTexts["newBestLabel"].exists)
        save("05-after-retry")
    }

    private func dismissShareSheet(_ app: XCUIApplication) {
        if app.buttons["Close"].waitForExistence(timeout: 2) {
            app.buttons["Close"].tap()
            return
        }
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
            return
        }
        app.swipeDown()
    }

    private func save(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["PAPERGLIDE_SCREENSHOT_DIR"],
              directory.isEmpty == false else {
            return
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            XCTFail("Could not write \(name): \(error)", file: file, line: line)
        }
    }
}
