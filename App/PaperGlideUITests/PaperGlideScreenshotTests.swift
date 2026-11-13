import XCTest

/// Simulator screenshots.
///
/// `hook-*` uses `-paperGlideEndScore`. That is a test hook: physics does not run,
/// and the first tap calls `endRun(withScore:)`.
///
/// `sim-*` uses seed 1 and a 0.1s guided stride. Each Glide tap is one real flap
/// plus 0.1s of the real simulation. Coast is the same simulation with no flap.
/// The test taps when the plane is below the next opening, the same rule
/// as GlidePilot. After one real clear it only coasts into a collision.
/// Nothing in that test forces the score.
final class PaperGlideScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureHookedScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paperGlideResetStore", "-paperGlideEndScore", "1"]
        app.launch()

        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        save("hook-01-start")

        play.tap()
        let coach = app.staticTexts["coachLabel"]
        XCTAssertTrue(coach.waitForExistence(timeout: 10))
        XCTAssertEqual(coach.label, "tap to glide")
        save("hook-02-first-run-coach")

        let glide = app.buttons["glideTapArea"]
        XCTAssertTrue(glide.waitForExistence(timeout: 5))
        glide.tap()

        let newBest = app.staticTexts["newBestLabel"]
        XCTAssertTrue(newBest.waitForExistence(timeout: 10))
        XCTAssertEqual(newBest.label, "New best!")
        let bestBeforeShare = app.staticTexts["bestScoreLabel"].label
        XCTAssertEqual(bestBeforeShare, "Best score 1")
        save("hook-03-death-new-best-HOOK")

        let expectedShare = "I scored 1 in Paper Glide"
        tapShare(app)
        var shareLabel = shareSheetLabel(app, contains: expectedShare, timeout: 15)
        if shareLabel == nil {
            tapShare(app)
            shareLabel = shareSheetLabel(app, contains: expectedShare, timeout: 15)
        }
        guard let shareLabel else {
            XCTFail("Share sheet did not show \"I scored 1 in Paper Glide\". Nearby labels: \(nearbyShareLabels(app))")
            return
        }
        save("hook-04-share-sheet")
        XCTAssertTrue(shareLabel.contains("Paper Glide"))
        XCTAssertFalse(shareLabel.contains("http"))
        XCTAssertFalse(shareLabel.lowercased().contains("rank"))
        dismissShareSheet(app)

        let deathScore = app.staticTexts["deathScore"]
        XCTAssertTrue(deathScore.waitForExistence(timeout: 5))
        XCTAssertEqual(deathScore.label, "Score 1")
        XCTAssertEqual(app.staticTexts["newBestLabel"].label, "New best!")
        let home = app.buttons["homeButton"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        let hittableDeadline = Date().addingTimeInterval(8)
        while Date() < hittableDeadline && !home.isHittable {
            dismissShareSheet(app)
        }
        XCTAssertTrue(home.isHittable)
        let best = app.staticTexts["bestScoreLabel"]
        XCTAssertTrue(best.exists)
        XCTAssertEqual(best.label, bestBeforeShare)
        let retry = app.buttons["retryButton"]
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(retry.isHittable)
        home.tap()
        let startBest = app.staticTexts["startBestScore"]
        XCTAssertTrue(startBest.waitForExistence(timeout: 10))
        XCTAssertEqual(startBest.label, "Best score 1")
        XCTAssertTrue(app.buttons["playButton"].exists)
        XCTAssertFalse(app.staticTexts["newBestLabel"].exists)
        save("hook-05-home-best-score")
    }

    func testRealSimulationClearsAGapThenCollides() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-paperGlideResetStore",
            "-paperGlideSeed", "1",
            "-paperGlideGuidedStride", "0.1"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 15))
        app.buttons["playButton"].tap()
        XCTAssertTrue(app.staticTexts["coachLabel"].waitForExistence(timeout: 10))
        save("sim-01-coach")

        let glide = app.buttons["glideTapArea"]
        let coast = app.buttons["coastButton"]
        XCTAssertTrue(glide.waitForExistence(timeout: 5))
        XCTAssertTrue(coast.waitForExistence(timeout: 5))

        var rose = false
        var fell = false
        var savedImpulse = false
        var savedDrop = false
        var savedClear = false
        var frameIndex = 0

        for step in 0..<160 {
            if app.staticTexts["deathScore"].exists {
                break
            }
            let before = try flightState(app)
            if !savedClear, before.score >= 1 {
                save("sim-04-gap-cleared")
                savedClear = true
            }
            if step % 4 == 0 {
                save(String(format: "sim-frame-%02d", frameIndex))
                frameIndex += 1
            }
            if savedClear || before.advice != "tap" {
                coast.tap()
            } else {
                glide.tap()
            }
            if app.staticTexts["deathScore"].exists {
                break
            }
            let after = try flightState(app)
            if before.advice == "tap", after.y > before.y + 0.5 {
                rose = true
                if !savedImpulse {
                    save("sim-02-after-impulse")
                    savedImpulse = true
                }
            }
            if before.advice == "coast", after.y < before.y - 0.5 {
                fell = true
                if !savedDrop {
                    save("sim-03-gravity-drop")
                    savedDrop = true
                }
            }
        }

        let deathScore = app.staticTexts["deathScore"]
        XCTAssertTrue(deathScore.waitForExistence(timeout: 2), "Guided flight did not end in a collision")
        XCTAssertTrue(rose, "No Glide tap moved the plane upward")
        XCTAssertTrue(fell, "No Coast step let gravity pull the plane down")
        XCTAssertTrue(savedClear, "The plane never cleared a real window")
        let scoreLabel = deathScore.label
        let score = scoreValue(from: scoreLabel)
        XCTAssertGreaterThanOrEqual(score, 1)
        XCTAssertTrue(app.staticTexts["newBestLabel"].exists)
        save("sim-05-collision-death")

        tap(app.buttons["homeButton"], in: app)
        let startBest = app.staticTexts["startBestScore"]
        XCTAssertTrue(startBest.waitForExistence(timeout: 10))
        XCTAssertEqual(startBest.label, "Best score \(score)")
        XCTAssertTrue(app.buttons["playButton"].exists)
        save("sim-06-home-after-real-run")
    }

    private func flightState(_ app: XCUIApplication) throws -> (advice: String, y: Double, target: Double, score: Int) {
        let element = app.staticTexts["flightState"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let raw = element.label
        var fields: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pieces.count == 2 {
                fields[pieces[0]] = pieces[1]
            }
        }
        guard let advice = fields["advice"],
              let y = fields["y"].flatMap(Double.init),
              let target = fields["target"].flatMap(Double.init),
              let score = fields["score"].flatMap(Int.init) else {
            XCTFail("Unreadable flight state: \(raw)")
            return ("coast", 0, 0, 0)
        }
        return (advice, y, target, score)
    }

    private func scoreValue(from label: String) -> Int {
        Int(label.split(separator: " ").last.map(String.init) ?? "") ?? -1
    }

    private func shareSheetLabel(_ app: XCUIApplication, contains expected: String, timeout: TimeInterval) -> String? {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let caption = app.otherElements["LP.CaptionBar.BottomCaption"]
            if caption.exists {
                if caption.label.contains(expected) { return caption.label }
                if let value = caption.value as? String, value.contains(expected) { return value }
            }
            for host in shareHosts(app) {
                let match = host.descendants(matching: .any).matching(predicate).firstMatch
                if match.exists {
                    if match.label.contains(expected) { return match.label }
                    if let value = match.value as? String, value.contains(expected) { return value }
                    return match.label
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    private func nearbyShareLabels(_ app: XCUIApplication) -> [String] {
        let hint = NSPredicate(format: "label CONTAINS 'Glide' OR label CONTAINS 'score' OR label CONTAINS 'Share'")
        var nearby: [String] = []
        for host in shareHosts(app) {
            let matches = host.descendants(matching: .any).matching(hint)
            for index in 0..<min(matches.count, 12) {
                nearby.append(matches.element(boundBy: index).label)
            }
        }
        return nearby
    }

    private func shareHosts(_ app: XCUIApplication) -> [XCUIApplication] {
        [
            app,
            XCUIApplication(bundleIdentifier: "com.apple.springboard")
        ]
    }

    private func dismissShareSheet(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = ["Close", "Cancel", "Done", "Dismiss"]
        for host in [app, springboard] {
            for label in labels where host.buttons[label].exists {
                host.buttons[label].tap()
                return
            }
        }
        let caption = app.otherElements["LP.CaptionBar.BottomCaption"]
        if caption.exists {
            let start = caption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            start.press(forDuration: 0.05, thenDragTo: end)
            return
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }

    private func tapShare(_ app: XCUIApplication) {
        let share = app.buttons["shareButton"]
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && !share.isHittable {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        if share.isHittable {
            share.tap()
        } else if share.exists {
            share.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        var swipes = 0
        while !element.isHittable && swipes < 3 {
            app.swipeUp()
            swipes += 1
        }
        element.tap()
    }

    private func save(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
