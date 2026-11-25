import XCTest

/// Confirm and cancel for Delete my data. The app has no Supabase project in CI,
/// so an unstubbed confirm is offline. `-paperGlideDeleteStub` stands in for the RPC.
final class PaperGlideDeleteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCancelLeavesTheDeviceAlone() {
        let app = launch()
        dismissName(app)
        openDelete(app)
        XCTAssertEqual(app.staticTexts["deleteTitle"].label, "Delete your data?")
        XCTAssertEqual(
            app.staticTexts["deleteBody"].label,
            "This removes your name, scores and reports from Paper Glide's servers and resets this device. Your name becomes free for anyone to take. This can't be undone."
        )
        XCTAssertTrue(app.buttons["deleteCancel"].isEnabled)
        XCTAssertTrue(app.buttons["deleteConfirm"].isEnabled)
        app.buttons["deleteCancel"].tap()
        XCTAssertFalse(app.otherElements["deleteDialog"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["nameHelper"].exists)
        XCTAssertEqual(app.staticTexts["startBestScore"].label, "Best score 9")
        XCTAssertTrue(app.buttons["deleteDataButton"].exists)
        XCTAssertFalse(app.staticTexts["deleteToast"].exists)
    }

    func testConfirmOfflineDeletesNothing() {
        let app = launch()
        dismissName(app)
        openDelete(app)
        app.buttons["deleteConfirm"].tap()
        let toast = app.staticTexts["deleteToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, "You're offline. Connect and try again.")
        XCTAssertFalse(app.staticTexts["nameHelper"].exists)
        XCTAssertEqual(app.staticTexts["startBestScore"].label, "Best score 9")
    }

    func testConfirmSuccessResetsAndFailureLeavesData() {
        let success = XCUIApplication()
        success.launchArguments = [
            "-paperGlideResetStore",
            "-paperGlidePresetBest", "9",
            "-paperGlideDeleteStub", "success"
        ]
        success.launch()
        dismissName(success)
        openDelete(success)
        success.buttons["deleteConfirm"].tap()
        let progress = success.staticTexts["deleteProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertEqual(progress.label, "Deleting...")
        XCTAssertFalse(success.buttons["deleteCancel"].isEnabled)
        XCTAssertFalse(success.buttons["deleteConfirm"].isEnabled)
        let done = success.staticTexts["deleteToast"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "Your data is deleted.")
        XCTAssertTrue(success.staticTexts["nameHelper"].waitForExistence(timeout: 5))
        XCTAssertEqual(success.staticTexts["startBestScore"].label, "Best score 0")

        success.terminate()
        let failure = XCUIApplication()
        failure.launchArguments = [
            "-paperGlideResetStore",
            "-paperGlidePresetBest", "9",
            "-paperGlideDeleteStub", "failure"
        ]
        failure.launch()
        dismissName(failure)
        openDelete(failure)
        failure.buttons["deleteConfirm"].tap()
        let failed = failure.staticTexts["deleteProgress"]
        XCTAssertTrue(failed.waitForExistence(timeout: 3))
        let toast = failure.staticTexts["deleteToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, "Something went wrong. Nothing was deleted. Try again.")
        XCTAssertFalse(failure.staticTexts["nameHelper"].exists)
        XCTAssertEqual(failure.staticTexts["startBestScore"].label, "Best score 9")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-paperGlideResetStore", "-paperGlidePresetBest", "9"]
        app.launch()
        return app
    }

    private func dismissName(_ app: XCUIApplication) {
        let later = app.buttons["nameLaterButton"]
        XCTAssertTrue(later.waitForExistence(timeout: 15))
        later.tap()
    }

    private func openDelete(_ app: XCUIApplication) {
        let link = app.buttons["deleteDataButton"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertEqual(link.label, "Delete my data")
        if !link.isHittable {
            app.swipeUp()
        }
        link.tap()
        XCTAssertTrue(app.otherElements["deleteDialog"].waitForExistence(timeout: 5))
    }
}
