import PaperGlideCore
import XCTest

final class GameSessionTests: XCTestCase {
    func testStandardRunSpawnsWindows() {
        let session = GameSession(config: .standard, storage: InMemoryGameStorage(), seed: 7)
        XCTAssertFalse(session.snapshot.obstacles.isEmpty)
        XCTAssertEqual(session.snapshot.phase, .playing)
        XCTAssertEqual(session.snapshot.score, 0)
        XCTAssertEqual(session.snapshot.plane.x, GameConfig.standard.planeX)
    }

    func testSameSeedProducesTheSameRun() {
        let first = GameSession(config: .standard, storage: InMemoryGameStorage(), seed: 42)
        let second = GameSession(config: .standard, storage: InMemoryGameStorage(), seed: 42)
        XCTAssertEqual(first.snapshot, second.snapshot)
        for _ in 0..<120 {
            first.tap()
            second.tap()
            first.step(dt: 1.0 / 60.0)
            second.step(dt: 1.0 / 60.0)
        }
        XCTAssertEqual(first.snapshot, second.snapshot)
    }

    func testDifferentSeedsOpenDifferentWindows() {
        let first = GameSession(config: .standard, storage: InMemoryGameStorage(), seed: 1)
        let second = GameSession(config: .standard, storage: InMemoryGameStorage(), seed: 2)
        XCTAssertNotEqual(
            first.snapshot.obstacles.map(\.gapCenterY),
            second.snapshot.obstacles.map(\.gapCenterY)
        )
    }

    func testGapCentersFallBackToMidHeightWhenTheOpeningCannotFit() {
        let config = makeConfig(
            worldWidth: 300,
            worldHeight: 200,
            obstacleGapHeight: 180,
            obstacleSpacing: 100,
            gapMargin: 40,
            initialLead: 50,
            spawningEnabled: true
        )
        let session = GameSession(config: config, storage: InMemoryGameStorage(), seed: 1)
        XCTAssertFalse(session.snapshot.obstacles.isEmpty)
        for window in session.snapshot.obstacles {
            XCTAssertEqual(window.gapCenterY, 100, accuracy: 1e-9)
        }
    }

    func testScoreWaitsForTheTrailingEdgeAndCountsOnce() {
        let harness = makeHarness(config: makeConfig(scrollSpeed: 120))
        harness.session.applyLayout(
            RunLayout(
                planeY: 250,
                velocityY: 0,
                obstacles: [makeObstacle(left: 140, width: 50)]
            )
        )

        var sawNoseOnly = false
        var scored = false
        for _ in 0..<600 {
            let before = harness.session.snapshot
            harness.session.step(dt: 1.0 / 60.0)
            let after = harness.session.snapshot
            XCTAssertEqual(after.phase, .playing)
            XCTAssertEqual(after.plane.x, before.plane.x)
            guard let window = after.obstacles.first else {
                XCTFail("Window despawned before it was scored")
                return
            }
            if after.score == 0 {
                XCTAssertLessThanOrEqual(after.plane.trailingX, window.trailingX)
                if after.plane.leadingX > window.leadingX {
                    sawNoseOnly = true
                }
            }
            if before.score == 0, after.score == 1 {
                XCTAssertGreaterThan(after.plane.trailingX, window.trailingX)
                scored = true
                break
            }
            XCTAssertLessThan(after.score, 2)
        }

        XCTAssertTrue(sawNoseOnly)
        XCTAssertTrue(scored)
        for _ in 0..<40 {
            harness.session.step(dt: 1.0 / 60.0)
        }
        XCTAssertEqual(harness.session.snapshot.score, 1)
        XCTAssertEqual(harness.session.snapshot.phase, .playing)
    }

    func testEachClearedWindowScoresOnce() {
        let harness = makeHarness(config: makeConfig(scrollSpeed: 100))
        harness.session.applyLayout(
            RunLayout(
                planeY: 250,
                velocityY: 0,
                obstacles: [
                    makeObstacle(id: 1, left: 70, width: 20),
                    makeObstacle(id: 2, left: 360, width: 40)
                ]
            )
        )
        harness.session.step(dt: 0.2)
        XCTAssertEqual(harness.session.snapshot.phase, .playing)
        XCTAssertEqual(harness.session.snapshot.score, 1)

        var steps = 0
        while harness.session.snapshot.score < 2
            && harness.session.snapshot.phase == .playing
            && steps < 40 {
            harness.session.step(dt: 0.25)
            steps += 1
        }
        XCTAssertEqual(harness.session.snapshot.phase, .playing)
        XCTAssertEqual(harness.session.snapshot.score, 2)
        harness.session.step(dt: 0.25)
        XCTAssertEqual(harness.session.snapshot.score, 2)
    }

    func testHittingEitherFrameEndsTheRunWithoutAPoint() {
        for planeY in [100.0, 400.0] {
            let harness = makeHarness(config: makeConfig(scrollSpeed: 0))
            harness.session.applyLayout(
                RunLayout(
                    planeY: planeY,
                    velocityY: 0,
                    obstacles: [makeObstacle(left: 80, width: 60)]
                )
            )
            harness.session.step(dt: 0.05)
            XCTAssertEqual(harness.session.snapshot.phase, .dead)
            XCTAssertEqual(harness.session.snapshot.score, 0)
        }
    }

    func testSubstepsBlockTunnelingThroughAFrame() {
        let harness = makeHarness(
            config: makeConfig(scrollSpeed: 1000, physicsStep: 0.01, maxFrameDelta: 1)
        )
        harness.session.applyLayout(
            RunLayout(
                planeY: 420,
                velocityY: 0,
                obstacles: [makeObstacle(left: 130, width: 40, gapCenterY: 250, gapHeight: 200)]
            )
        )
        harness.session.step(dt: 0.2)
        XCTAssertEqual(harness.session.snapshot.phase, .dead)
        XCTAssertEqual(harness.session.snapshot.score, 0)
    }

    func testPassingThroughTheOpeningScoresAndStaysAlive() {
        let harness = makeHarness(
            config: makeConfig(scrollSpeed: 1000, physicsStep: 0.01, maxFrameDelta: 1)
        )
        harness.session.applyLayout(
            RunLayout(
                planeY: 250,
                velocityY: 0,
                obstacles: [makeObstacle(left: 130, width: 40)]
            )
        )
        harness.session.step(dt: 0.2)
        XCTAssertEqual(harness.session.snapshot.phase, .playing)
        XCTAssertEqual(harness.session.snapshot.score, 1)
    }

    func testTopAndBottomBoundsEndTheRun() {
        let bottom = makeHarness()
        bottom.session.applyLayout(RunLayout(planeY: 10, velocityY: 0, obstacles: []))
        bottom.session.step(dt: 0.05)
        XCTAssertEqual(bottom.session.snapshot.phase, .dead)
        XCTAssertEqual(bottom.session.snapshot.score, 0)

        let top = makeHarness()
        top.session.applyLayout(RunLayout(planeY: 490, velocityY: 0, obstacles: []))
        top.session.step(dt: 0.05)
        XCTAssertEqual(top.session.snapshot.phase, .dead)

        let inside = makeHarness()
        inside.session.applyLayout(RunLayout(planeY: 250, velocityY: 0, obstacles: []))
        inside.session.step(dt: 0.05)
        XCTAssertEqual(inside.session.snapshot.phase, .playing)
    }

    func testAClearedWindowStillCountsIfThePlaneLaterLeavesThePage() {
        let harness = makeHarness(config: makeConfig(tapImpulse: 400, maxUpwardSpeed: 400))
        harness.session.applyLayout(
            RunLayout(
                planeY: 250,
                velocityY: 0,
                obstacles: [makeObstacle(left: 90, width: 30, gapCenterY: 250, gapHeight: 320)]
            )
        )
        var steps = 0
        while harness.session.snapshot.score == 0 && harness.session.snapshot.phase == .playing && steps < 400 {
            harness.session.step(dt: 0.05)
            steps += 1
        }
        XCTAssertEqual(harness.session.snapshot.score, 1)
        XCTAssertEqual(harness.session.snapshot.phase, .playing)

        var climbed = 0
        while harness.session.snapshot.phase == .playing && climbed < 80 {
            harness.session.tap()
            harness.session.step(dt: 0.05)
            climbed += 1
        }
        XCTAssertEqual(harness.session.snapshot.phase, .dead)
        XCTAssertEqual(harness.session.snapshot.score, 1)
        XCTAssertTrue(harness.session.snapshot.isNewBest)
        XCTAssertEqual(harness.session.snapshot.bestScore, 1)
        XCTAssertEqual(harness.storage.loadBestScore(), 1)

        let relaunch = GameSession(config: harness.session.config, storage: harness.storage, seed: 9)
        XCTAssertEqual(relaunch.snapshot.bestScore, 1)
        XCTAssertEqual(relaunch.snapshot.score, 0)
        XCTAssertFalse(relaunch.snapshot.isNewBest)
    }

    func testLowerScoreDoesNotReplaceTheBest() {
        let harness = makeHarness(best: 5)
        harness.session.applyLayout(RunLayout(planeY: 10, velocityY: 0, obstacles: []))
        harness.session.step(dt: 0.05)
        XCTAssertEqual(harness.session.snapshot.phase, .dead)
        XCTAssertEqual(harness.session.snapshot.score, 0)
        XCTAssertFalse(harness.session.snapshot.isNewBest)
        XCTAssertEqual(harness.session.snapshot.bestScore, 5)
        XCTAssertEqual(harness.storage.loadBestScore(), 5)
    }

    func testHigherScoreIsANewBestAndUpdatesTheStore() {
        let harness = makeHarness(best: 1)
        harness.session.endRun(withScore: 3)
        XCTAssertEqual(harness.session.snapshot.phase, .dead)
        XCTAssertEqual(harness.session.snapshot.score, 3)
        XCTAssertTrue(harness.session.snapshot.isNewBest)
        XCTAssertEqual(harness.session.snapshot.bestScore, 3)
        XCTAssertEqual(harness.storage.loadBestScore(), 3)
    }

    func testTieIsNotANewBest() {
        let harness = makeHarness(best: 2)
        harness.session.endRun(withScore: 2)
        XCTAssertEqual(harness.session.snapshot.phase, .dead)
        XCTAssertFalse(harness.session.snapshot.isNewBest)
        XCTAssertEqual(harness.session.snapshot.bestScore, 2)
        XCTAssertEqual(harness.storage.loadBestScore(), 2)
    }

    func testLowerScoreIsNotANewBestAndLeavesTheStoredBest() {
        let harness = makeHarness(best: 5)
        harness.session.endRun(withScore: 1)
        XCTAssertEqual(harness.session.snapshot.phase, .dead)
        XCTAssertFalse(harness.session.snapshot.isNewBest)
        XCTAssertEqual(harness.session.snapshot.score, 1)
        XCTAssertEqual(harness.session.snapshot.bestScore, 5)
        XCTAssertEqual(harness.storage.loadBestScore(), 5)
    }

    func testFirstRunScoringZeroIsNotANewBest() {
        let harness = makeHarness(best: 0)
        harness.session.endRun(withScore: 0)
        XCTAssertEqual(harness.session.snapshot.phase, .dead)
        XCTAssertFalse(harness.session.snapshot.isNewBest)
        XCTAssertEqual(harness.session.snapshot.bestScore, 0)
        XCTAssertEqual(harness.storage.loadBestScore(), 0)
    }

    func testNewBestPersistsWhenTheStoreIsReloaded() {
        let harness = makeHarness(best: 0)
        harness.session.endRun(withScore: 4)
        XCTAssertTrue(harness.session.snapshot.isNewBest)
        XCTAssertEqual(harness.storage.loadBestScore(), 4)

        let reloaded = GameSession(config: harness.session.config, storage: harness.storage, seed: 8)
        XCTAssertEqual(reloaded.snapshot.bestScore, 4)
        XCTAssertEqual(reloaded.snapshot.score, 0)
        XCTAssertFalse(reloaded.snapshot.isNewBest)

        reloaded.endRun(withScore: 4)
        XCTAssertFalse(reloaded.snapshot.isNewBest)
        XCTAssertEqual(reloaded.snapshot.bestScore, 4)
        XCTAssertEqual(harness.storage.loadBestScore(), 4)

        let later = GameSession(config: harness.session.config, storage: harness.storage, seed: 9)
        later.endRun(withScore: 2)
        XCTAssertFalse(later.snapshot.isNewBest)
        XCTAssertEqual(later.snapshot.bestScore, 4)
        XCTAssertEqual(harness.storage.loadBestScore(), 4)
    }

    func testCoachShowsUntilTheFirstTapAndThenStaysHidden() {
        let harness = makeHarness()
        XCTAssertTrue(harness.session.snapshot.showCoach)
        XCTAssertFalse(harness.storage.loadCoachCompleted())

        harness.session.tap()
        XCTAssertFalse(harness.session.snapshot.showCoach)
        XCTAssertTrue(harness.storage.loadCoachCompleted())

        harness.session.reset(seed: 4)
        XCTAssertFalse(harness.session.snapshot.showCoach)

        let relaunch = GameSession(config: harness.session.config, storage: harness.storage, seed: 5)
        XCTAssertFalse(relaunch.snapshot.showCoach)
    }

    func testDyingWithoutATapKeepsTheCoachForTheNextRun() {
        let harness = makeHarness()
        harness.session.applyLayout(RunLayout(planeY: 10, velocityY: 0, obstacles: []))
        harness.session.step(dt: 0.05)
        XCTAssertEqual(harness.session.snapshot.phase, .dead)
        harness.session.tap()
        XCTAssertFalse(harness.storage.loadCoachCompleted())

        let relaunch = GameSession(config: harness.session.config, storage: harness.storage, seed: 6)
        XCTAssertTrue(relaunch.snapshot.showCoach)
    }

    func testTwoTapsBeforeAStepAreOneImpulse() {
        let harness = makeHarness()
        harness.session.applyLayout(RunLayout(planeY: 250, velocityY: 0, obstacles: []))
        harness.session.tap()
        harness.session.tap()
        harness.session.step(dt: 0.1)
        XCTAssertEqual(harness.session.snapshot.plane.velocityY, 400, accuracy: 1e-9)
        XCTAssertEqual(harness.session.snapshot.plane.y, 290, accuracy: 1e-9)
    }

    func testNonPositiveDeltaDoesNotAdvanceTheRun() {
        let harness = makeHarness(config: makeConfig(scrollSpeed: 80))
        harness.session.applyLayout(
            RunLayout(planeY: 250, velocityY: 20, obstacles: [makeObstacle(left: 220)])
        )
        let before = harness.session.snapshot
        harness.session.step(dt: 0)
        harness.session.step(dt: -1)
        harness.session.step(dt: .nan)
        XCTAssertEqual(harness.session.snapshot, before)
    }

    func testALongFrameIsCapped() {
        let config = makeConfig(scrollSpeed: 100, physicsStep: 0.01, maxFrameDelta: 0.05)
        let harness = makeHarness(config: config)
        harness.session.applyLayout(
            RunLayout(planeY: 250, velocityY: 0, obstacles: [makeObstacle(left: 300)])
        )
        let before = harness.session.snapshot.obstacles[0].left
        harness.session.step(dt: 5)
        let moved = before - harness.session.snapshot.obstacles[0].left
        XCTAssertEqual(moved, 5, accuracy: 0.02)
        XCTAssertEqual(harness.session.snapshot.plane.x, config.planeX)
    }

    func testResetClearsTheScore() {
        let harness = makeHarness(config: makeConfig(scrollSpeed: 100))
        harness.session.applyLayout(
            RunLayout(planeY: 250, velocityY: 0, obstacles: [makeObstacle(left: 70, width: 20)])
        )
        harness.session.step(dt: 0.3)
        XCTAssertEqual(harness.session.snapshot.score, 1)
        harness.session.reset(seed: 11)
        XCTAssertEqual(harness.session.snapshot.score, 0)
        XCTAssertEqual(harness.session.snapshot.phase, .playing)
    }

    func testInMemoryStorageRoundTrip() {
        let storage = InMemoryGameStorage()
        XCTAssertEqual(storage.loadBestScore(), 0)
        XCTAssertFalse(storage.loadCoachCompleted())
        storage.saveBestScore(6)
        storage.saveCoachCompleted(true)
        XCTAssertEqual(storage.loadBestScore(), 6)
        XCTAssertTrue(storage.loadCoachCompleted())
    }

    func testShareMessageNamesTheScoreAndPaperGlide() {
        XCTAssertEqual(ShareText.message(score: 12), "I scored 12 in Paper Glide")
        XCTAssertEqual(ShareText.message(score: 0), "I scored 0 in Paper Glide")
    }
}
