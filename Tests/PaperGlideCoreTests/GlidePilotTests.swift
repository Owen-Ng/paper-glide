import PaperGlideCore
import XCTest

private let pilotStride = 0.1
private let pilotSeeds: [UInt64] = [1, 2, 3, 7, 11, 42, 99, 12_345]

final class GlidePilotTests: XCTestCase {
    /// Decisions every 0.1s, tapping when the plane is below the next opening, clear
    /// several gaps with the shipped flap-velocity constants. The old 0.2s UI stride
    /// was too coarse for the previous impulse; it is not a reason to change this feel.
    /// Score 3 is still the opening step: gap 228, scroll 148.
    func testStartOfRunClearsAtLeastThreeGaps() {
        XCTAssertEqual(GameConfig.standard.obstacleGapHeight, 228)
        XCTAssertEqual(GameConfig.standard.scrollSpeed, 148)
        for seed in pilotSeeds {
            let session = GameSession(config: .standard, storage: InMemoryGameStorage(), seed: seed)
            XCTAssertEqual(session.snapshot.spawnGapHeight, 228)
            XCTAssertEqual(session.snapshot.scrollSpeed, 148)
            let actions = flyPilot(session, untilScore: 3)
            XCTAssertGreaterThanOrEqual(
                session.snapshot.score,
                3,
                "seed \(seed) cleared \(session.snapshot.score) after \(actions) strides at y=\(session.snapshot.plane.y)"
            )
            XCTAssertEqual(session.snapshot.phase, .playing, "seed \(seed) died before three gaps")
            XCTAssertEqual(session.snapshot.scrollSpeed, 148, accuracy: 1e-9)
            for window in session.snapshot.obstacles {
                XCTAssertEqual(window.gapHeight, 228, accuracy: 1e-9, "seed \(seed)")
            }
        }
    }

    /// The held pair (score 60 and after), flown from the first window so a miss is
    /// about that pair and not about surviving the climb. Stride stays 0.1s.
    func testCapClearsAtLeastOneGap() {
        let held = DifficultyRamp.standardLevel(score: 60)
        XCTAssertEqual(held.gapHeight, 168)
        XCTAssertEqual(held.scrollSpeed, 196)
        var config = GameConfig.standard
        config.obstacleGapHeight = held.gapHeight
        config.scrollSpeed = held.scrollSpeed
        for seed in pilotSeeds {
            let session = GameSession(config: config, storage: InMemoryGameStorage(), seed: seed)
            XCTAssertEqual(session.snapshot.spawnGapHeight, 168, accuracy: 1e-9)
            XCTAssertEqual(session.snapshot.scrollSpeed, 196, accuracy: 1e-9)
            let actions = flyPilot(session, untilScore: 1, limit: 400)
            XCTAssertGreaterThanOrEqual(
                session.snapshot.score,
                1,
                "cap seed \(seed) score \(session.snapshot.score) phase \(session.snapshot.phase) y=\(session.snapshot.plane.y) after \(actions) strides"
            )
        }
    }

    func testCoastingAfterClearsEndsInACollisionWithoutLosingTheScore() {
        let session = GameSession(config: .standard, storage: InMemoryGameStorage(), seed: 1)
        var actions = 0
        while session.snapshot.phase == .playing, session.snapshot.score < 3, actions < 250 {
            let tap = GlidePilot.shouldTap(
                snapshot: session.snapshot,
                fallbackTarget: session.config.planeStartY
            )
            GlidePilot.advance(session, stride: pilotStride, tap: tap)
            actions += 1
        }
        let cleared = session.snapshot.score
        XCTAssertGreaterThanOrEqual(cleared, 3)
        var coasts = 0
        while session.snapshot.phase == .playing, coasts < 80 {
            GlidePilot.advance(session, stride: 0.1, tap: false)
            coasts += 1
        }
        XCTAssertEqual(session.snapshot.phase, .dead)
        XCTAssertGreaterThanOrEqual(session.snapshot.score, cleared)
    }
}

@discardableResult
private func flyPilot(_ session: GameSession, untilScore score: Int, limit: Int = 250) -> Int {
    var actions = 0
    while session.snapshot.phase == .playing, session.snapshot.score < score, actions < limit {
        let tap = GlidePilot.shouldTap(
            snapshot: session.snapshot,
            fallbackTarget: session.config.planeStartY
        )
        GlidePilot.advance(session, stride: pilotStride, tap: tap)
        actions += 1
    }
    return actions
}
