import PaperGlideCore
import XCTest

final class GlidePilotTests: XCTestCase {
    /// The UI test's old 0.2s stride bangs the impulse too coarsely and dies under the
    /// first window. Decisions every 0.1s, tapping when the plane is below the next
    /// opening, clear several gaps with the shipped constants and stay alive.
    func testShippedConstantsClearSeveralGaps() {
        for seed in [UInt64(1), 7] {
            let session = GameSession(config: .standard, storage: InMemoryGameStorage(), seed: seed)
            var actions = 0
            while session.snapshot.phase == .playing, session.snapshot.score < 3, actions < 250 {
                let snapshot = session.snapshot
                let tap = GlidePilot.shouldTap(
                    snapshot: snapshot,
                    fallbackTarget: session.config.planeStartY
                )
                GlidePilot.advance(session, stride: 0.1, tap: tap)
                actions += 1
            }
            XCTAssertGreaterThanOrEqual(
                session.snapshot.score,
                3,
                "seed \(seed) cleared \(session.snapshot.score) after \(actions) strides at y=\(session.snapshot.plane.y)"
            )
            XCTAssertEqual(session.snapshot.phase, .playing, "seed \(seed) died before three gaps")
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
            GlidePilot.advance(session, stride: 0.1, tap: tap)
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
