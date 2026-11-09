import PaperGlideCore
import XCTest

/// The shipped silent steps. Index is `score / 5`, held at the last pair.
private let rampGaps = [228.0, 223, 218, 213, 208, 203, 198, 193, 188, 183, 178, 173, 168]
private let rampScrolls = [148.0, 152, 156, 160, 164, 168, 172, 176, 180, 184, 188, 192, 196]

private func expectedRamp(score: Int) -> (gap: Double, scroll: Double) {
    let step = min(max(score, 0) / 5, rampGaps.count - 1)
    return (rampGaps[step], rampScrolls[step])
}

final class DifficultyRampTests: XCTestCase {
    func testFeelTuneStaysLocked() {
        let config = GameConfig.standard
        XCTAssertEqual(config.gravity, 1484)
        XCTAssertEqual(config.flapVelocity, 460)
        XCTAssertEqual(config.maxUpwardSpeed, 460)
        XCTAssertEqual(config.maxDownwardSpeed, 720)
        XCTAssertEqual(config.planeHeight, 22)
        XCTAssertEqual(config.obstacleSpacing, 300)
        XCTAssertEqual(config.worldHeight, 760)
        XCTAssertEqual(config.obstacleGapHeight, 228)
        XCTAssertEqual(config.scrollSpeed, 148)
    }

    func testRampTableMatchesTheSilentSteps() {
        XCTAssertEqual(rampGaps.count, 13)
        XCTAssertEqual(rampScrolls.count, 13)
        for score in 0...80 {
            let level = DifficultyRamp.standardLevel(score: score)
            let table = expectedRamp(score: score)
            XCTAssertEqual(level.gapHeight, table.gap, "score \(score)")
            XCTAssertEqual(level.scrollSpeed, table.scroll, "score \(score)")
            XCTAssertEqual(level.stepIndex, min(score / 5, 12), "score \(score)")
        }
        let held = DifficultyRamp.standardLevel(score: 60)
        XCTAssertEqual(held.gapHeight, 168)
        XCTAssertEqual(held.scrollSpeed, 196)
        XCTAssertEqual(DifficultyRamp.standardLevel(score: 61), held)
        XCTAssertEqual(DifficultyRamp.standardLevel(score: 100), held)
        XCTAssertGreaterThanOrEqual(held.gapHeight, DifficultyRamp.minimumGapHeight)
        XCTAssertLessThanOrEqual(held.scrollSpeed, DifficultyRamp.maximumScrollSpeed)
    }

    func testCapsDoNotRewriteABaseThatAlreadySitsOutsideThem() {
        let fast = DifficultyRamp.level(score: 0, baseGap: 180, baseScroll: 1000)
        XCTAssertEqual(fast.gapHeight, 180)
        XCTAssertEqual(fast.scrollSpeed, 1000)

        let later = DifficultyRamp.level(score: 60, baseGap: 180, baseScroll: 1000)
        XCTAssertEqual(later.gapHeight, 168)
        XCTAssertEqual(later.scrollSpeed, 1048)

        let inside = DifficultyRamp.level(score: 60, baseGap: 200, baseScroll: 100)
        XCTAssertEqual(inside.gapHeight, 168)
        XCTAssertEqual(inside.scrollSpeed, 148)
    }

    func testStandardRunOpensAtTheFirstStep() {
        let session = GameSession(config: .standard, storage: InMemoryGameStorage(), seed: 11)
        XCTAssertEqual(session.snapshot.flightTime, 0)
        XCTAssertEqual(session.snapshot.score, 0)
        XCTAssertEqual(session.snapshot.scrollSpeed, 148)
        XCTAssertEqual(session.snapshot.spawnGapHeight, 228)
        XCTAssertFalse(session.snapshot.obstacles.isEmpty)
        for window in session.snapshot.obstacles {
            XCTAssertEqual(window.gapHeight, 228)
        }
    }

    func testLiveRunKeepsOldGapsAndSpawnsTheNextStep() {
        let session = makeOpeningRampSession()
        var born: [Int: (gap: Double, center: Double, width: Double)] = [:]
        var gapsAtFour: [Int: Double] = [:]
        var sawScoreFour = false
        var checkedTheFifthPoint = false
        var sawSpawnAfterFirstStep = false
        var sawSpawnAtTheCap = false
        var steps = 0

        func note(_ snap: GameSnapshot, file: StaticString = #filePath, line: UInt = #line) {
            let table = expectedRamp(score: snap.score)
            XCTAssertEqual(snap.spawnGapHeight, table.gap, accuracy: 1e-9, "score \(snap.score)", file: file, line: line)
            XCTAssertEqual(snap.scrollSpeed, table.scroll, accuracy: 1e-9, "score \(snap.score)", file: file, line: line)
            let planeLow = snap.plane.y - snap.plane.height / 2
            let planeHigh = snap.plane.y + snap.plane.height / 2
            for window in snap.obstacles {
                XCTAssertGreaterThan(planeLow, window.gapBottom, "score \(snap.score)", file: file, line: line)
                XCTAssertLessThan(planeHigh, window.gapTop, "score \(snap.score)", file: file, line: line)
                if let previous = born[window.id] {
                    XCTAssertEqual(window.gapHeight, previous.gap, accuracy: 1e-9, "resized \(window.id)", file: file, line: line)
                    XCTAssertEqual(window.gapCenterY, previous.center, accuracy: 1e-9, "moved \(window.id)", file: file, line: line)
                    XCTAssertEqual(window.width, previous.width, accuracy: 1e-9, file: file, line: line)
                } else {
                    born[window.id] = (window.gapHeight, window.gapCenterY, window.width)
                    XCTAssertEqual(window.gapHeight, table.gap, accuracy: 1e-9, "new \(window.id) at \(snap.score)", file: file, line: line)
                    if (5...9).contains(snap.score) {
                        sawSpawnAfterFirstStep = true
                    }
                    if snap.score >= 60 {
                        sawSpawnAtTheCap = true
                    }
                }
            }
        }

        note(session.snapshot)
        var previousScore = session.snapshot.score
        while session.snapshot.score < 70 && session.snapshot.phase == .playing && steps < 2500 {
            session.step(dt: 0.2)
            steps += 1
            let snap = session.snapshot
            if snap.score == 4 {
                sawScoreFour = true
                gapsAtFour = Dictionary(uniqueKeysWithValues: snap.obstacles.map { ($0.id, $0.gapHeight) })
            }
            note(snap)
            if previousScore <= 4, snap.score >= 5, !checkedTheFifthPoint {
                checkedTheFifthPoint = true
                let survivors = snap.obstacles.filter { gapsAtFour[$0.id] != nil }
                XCTAssertFalse(survivors.isEmpty, "the window on screen at the step despawned in the same slice")
                for window in survivors {
                    XCTAssertEqual(window.gapHeight, gapsAtFour[window.id] ?? -1, accuracy: 1e-9)
                    XCTAssertEqual(window.gapHeight, 228, accuracy: 1e-9)
                }
            }
            previousScore = snap.score
        }

        XCTAssertEqual(session.snapshot.phase, .playing)
        XCTAssertGreaterThanOrEqual(session.snapshot.score, 70)
        XCTAssertTrue(sawScoreFour)
        XCTAssertTrue(checkedTheFifthPoint)
        XCTAssertTrue(sawSpawnAfterFirstStep, "no window spawned on the 223 opening")
        XCTAssertTrue(sawSpawnAtTheCap, "no window spawned after the ramp held")
        XCTAssertEqual(session.snapshot.spawnGapHeight, 168, accuracy: 1e-9)
        XCTAssertEqual(session.snapshot.scrollSpeed, 196, accuracy: 1e-9)
        for window in session.snapshot.obstacles where born[window.id]?.gap == 168 {
            XCTAssertEqual(window.gapHeight, 168, accuracy: 1e-9)
        }
    }

    func testScrollSpeedChangesOnTheStepAndIsWhatMovesTheWindows() {
        let session = makeOpeningRampSession()
        XCTAssertEqual(session.snapshot.scrollSpeed, 148, accuracy: 1e-9)
        assertScrollApplies(session)

        pump(session, untilScore: 5)
        XCTAssertEqual(session.snapshot.scrollSpeed, 152, accuracy: 1e-9)
        XCTAssertEqual(session.snapshot.spawnGapHeight, 223, accuracy: 1e-9)
        assertScrollApplies(session)

        pump(session, untilScore: 60)
        XCTAssertEqual(session.snapshot.scrollSpeed, 196, accuracy: 1e-9)
        XCTAssertEqual(session.snapshot.spawnGapHeight, 168, accuracy: 1e-9)
        assertScrollApplies(session)

        pump(session, untilScore: 70)
        XCTAssertEqual(session.snapshot.scrollSpeed, 196, accuracy: 1e-9)
        XCTAssertEqual(session.snapshot.spawnGapHeight, 168, accuracy: 1e-9)
        assertScrollApplies(session)
    }

    func testResetReturnsToTheOpeningGapScrollAndMorning() {
        let session = makeOpeningRampSession()
        pump(session, untilScore: 10)
        XCTAssertEqual(session.snapshot.scrollSpeed, 156, accuracy: 1e-9)
        XCTAssertEqual(session.snapshot.spawnGapHeight, 218, accuracy: 1e-9)
        XCTAssertGreaterThan(session.snapshot.flightTime, 0)

        session.reset(seed: 4)
        XCTAssertEqual(session.snapshot.phase, .playing)
        XCTAssertEqual(session.snapshot.score, 0)
        XCTAssertEqual(session.snapshot.flightTime, 0)
        XCTAssertEqual(session.snapshot.scrollSpeed, 148, accuracy: 1e-9)
        XCTAssertEqual(session.snapshot.spawnGapHeight, 228, accuracy: 1e-9)
        XCTAssertFalse(session.snapshot.obstacles.isEmpty)
        for window in session.snapshot.obstacles {
            XCTAssertEqual(window.gapHeight, 228, accuracy: 1e-9)
        }
    }

    func testFlightClockFollowsPlayTimeAndFreezesOnDeath() {
        let config = makeConfig(
            gravity: 0,
            planeStartY: 250,
            physicsStep: 0.05,
            maxFrameDelta: 0.4,
            spawningEnabled: false
        )
        let session = GameSession(config: config, storage: InMemoryGameStorage(), seed: 3)
        XCTAssertEqual(session.snapshot.flightTime, 0)
        session.step(dt: 1)
        XCTAssertEqual(session.snapshot.flightTime, 0.4, accuracy: 1e-9)
        session.step(dt: 0.1)
        XCTAssertEqual(session.snapshot.flightTime, 0.5, accuracy: 1e-9)

        session.applyLayout(RunLayout(planeY: 1, velocityY: 0, obstacles: []))
        let beforeDeath = session.snapshot.flightTime
        session.step(dt: 0.2)
        XCTAssertEqual(session.snapshot.phase, .dead)
        XCTAssertEqual(session.snapshot.score, 0)
        let frozen = session.snapshot.flightTime
        XCTAssertEqual(frozen, beforeDeath + config.physicsStep, accuracy: 1e-9)
        session.step(dt: 3)
        XCTAssertEqual(session.snapshot.flightTime, frozen, accuracy: 1e-9)

        session.reset(seed: 8)
        XCTAssertEqual(session.snapshot.flightTime, 0)
        XCTAssertEqual(session.snapshot.phase, .playing)
        XCTAssertEqual(session.snapshot.scrollSpeed, config.scrollSpeed, accuracy: 1e-9)
        XCTAssertEqual(session.snapshot.spawnGapHeight, config.obstacleGapHeight, accuracy: 1e-9)
    }

    func testCollisionsAndScoringIgnoreTheRamp() {
        let hit = makeHarness(config: makeConfig(gravity: 0, scrollSpeed: 0))
        hit.session.applyLayout(
            RunLayout(
                planeY: 400,
                velocityY: 0,
                obstacles: [makeObstacle(left: 80, width: 60)]
            )
        )
        hit.session.step(dt: 0.05)
        XCTAssertEqual(hit.session.snapshot.phase, .dead)
        XCTAssertEqual(hit.session.snapshot.score, 0)

        let clear = makeHarness(config: makeConfig(gravity: 0, scrollSpeed: 200))
        clear.session.applyLayout(
            RunLayout(
                planeY: 250,
                velocityY: 0,
                obstacles: [makeObstacle(left: 90, width: 30)]
            )
        )
        clear.session.step(dt: 0.4)
        XCTAssertEqual(clear.session.snapshot.phase, .playing)
        XCTAssertEqual(clear.session.snapshot.score, 1)
        clear.session.step(dt: 0.2)
        XCTAssertEqual(clear.session.snapshot.score, 1)
    }
}

/// Stationary plane, opening always contains it, shipped 228 / 148 bases.
/// The ramp can be read off the session without asking the pilot to survive to 60.
private func makeOpeningRampSession() -> GameSession {
    let config = makeConfig(
        worldWidth: 390,
        worldHeight: 300,
        gravity: 0,
        flapVelocity: 460,
        maxUpwardSpeed: 460,
        maxDownwardSpeed: 720,
        planeX: 108,
        planeWidth: 46,
        planeHeight: 22,
        planeStartY: 150,
        obstacleWidth: 70,
        obstacleGapHeight: 228,
        obstacleSpacing: 300,
        scrollSpeed: 148,
        gapMargin: 0,
        initialLead: 120,
        despawnMargin: 80,
        physicsStep: 1.0 / 120.0,
        maxFrameDelta: 0.25,
        spawningEnabled: true
    )
    return GameSession(config: config, storage: InMemoryGameStorage(), seed: 1)
}

private func pump(
    _ session: GameSession,
    untilScore score: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    var steps = 0
    while session.snapshot.score < score && session.snapshot.phase == .playing && steps < 2500 {
        session.step(dt: 0.2)
        steps += 1
    }
    XCTAssertEqual(session.snapshot.phase, .playing, "died at \(session.snapshot.score)", file: file, line: line)
    XCTAssertGreaterThanOrEqual(session.snapshot.score, score, file: file, line: line)
}

private func assertScrollApplies(
    _ session: GameSession,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let window = session.snapshot.obstacles.first else {
        XCTFail("expected a window", file: file, line: line)
        return
    }
    let speed = session.snapshot.scrollSpeed
    let left = window.left
    let id = window.id
    let dt = session.config.physicsStep
    session.step(dt: dt)
    guard let moved = session.snapshot.obstacles.first(where: { $0.id == id }) else {
        XCTFail("window despawned during a single physics slice", file: file, line: line)
        return
    }
    XCTAssertEqual(left - moved.left, speed * dt, accuracy: 1e-6, file: file, line: line)
}
