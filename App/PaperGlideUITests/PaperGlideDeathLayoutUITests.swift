import UIKit
import XCTest

/// Worst-case death screen: new best, sync note, and the name prompt.
/// The test does not scroll. Retry, Share, Home, and Leaderboard have to sit
/// inside the window on the first frame.
final class PaperGlideDeathLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWorstCaseActionsFitWithoutScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["-paperGlideResetStore", "-paperGlideWorstCaseDeath"]
        app.launch()

        let retry = app.buttons["retryButton"]
        let share = app.buttons["shareButton"]
        let home = app.buttons["homeButton"]
        let board = app.buttons["deathLeaderboardButton"]
        let score = app.staticTexts["deathScore"]
        let newBest = app.staticTexts["newBestLabel"]
        let best = app.staticTexts["bestScoreLabel"]
        let note = app.staticTexts["deathSyncNote"]
        let prompt = app.staticTexts["nameHelper"]

        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertTrue(newBest.waitForExistence(timeout: 10))
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        XCTAssertEqual(newBest.label, "New best!")
        XCTAssertEqual(note.label, "saved, will sync")
        XCTAssertTrue(share.exists)
        XCTAssertTrue(home.exists)
        XCTAssertTrue(board.exists)
        XCTAssertTrue(share.isEnabled)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        save("death-worst-\(deviceSlug(window.frame))")
        for (name, button) in [("Retry", retry), ("Share", share), ("Home", home), ("Leaderboard", board)] {
            assertFullyVisible(button, in: window, name: name)
        }

        XCTAssertLessThan(score.frame.maxY, newBest.frame.minY)
        XCTAssertLessThan(newBest.frame.maxY, best.frame.minY)
        XCTAssertLessThan(best.frame.maxY, retry.frame.minY)
        XCTAssertLessThan(retry.frame.maxY, share.frame.minY)
        XCTAssertLessThan(share.frame.maxY, home.frame.minY)
        XCTAssertLessThan(home.frame.maxY, board.frame.minY)
        XCTAssertLessThan(board.frame.maxY, note.frame.minY)
        XCTAssertLessThan(note.frame.maxY, prompt.frame.minY)
    }

    private func assertFullyVisible(_ element: XCUIElement, in window: XCUIElement, name: String) {
        XCTAssertTrue(element.exists, name)
        XCTAssertTrue(waitUntilHittable(element), "\(name) is not hittable without scrolling")
        let button = element.frame
        let bounds = window.frame
        XCTAssertGreaterThanOrEqual(button.minX, bounds.minX - 1, name)
        XCTAssertGreaterThanOrEqual(button.minY, bounds.minY - 1, name)
        XCTAssertLessThanOrEqual(button.maxX, bounds.maxX + 1, name)
        XCTAssertLessThanOrEqual(button.maxY, bounds.maxY + 1, name)
    }

    private func waitUntilHittable(_ element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.isHittable
    }

    private func deviceSlug(_ bounds: CGRect) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = UIDevice.current.name.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        var slug = String(scalars)
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let width = Int(bounds.width.rounded())
        let height = Int(bounds.height.rounded())
        return "\(slug)-\(width)x\(height)"
    }

    private func save(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
