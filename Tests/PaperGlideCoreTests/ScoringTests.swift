import PaperGlideCore
import XCTest

final class ScoringTests: XCTestCase {
    func testEqualTrailingEdgesAreNotYetCleared() {
        let body = makePlane(x: 100, width: 40)
        let window = makeObstacle(left: 40, width: 40)
        XCTAssertEqual(body.trailingX, 80)
        XCTAssertEqual(window.trailingX, 80)
        XCTAssertFalse(Scoring.hasFullyCleared(plane: body, obstacle: window))
    }

    func testClearanceRequiresTheTailPastTheFarEdge() {
        let body = makePlane(x: 100, width: 40)
        let window = makeObstacle(left: 39, width: 40)
        XCTAssertEqual(window.trailingX, 79)
        XCTAssertTrue(Scoring.hasFullyCleared(plane: body, obstacle: window))
    }

    func testNosePassingTheLeadingEdgeDoesNotScore() {
        let body = makePlane(x: 100, width: 40)
        let window = makeObstacle(left: 90, width: 50)
        XCTAssertGreaterThan(body.leadingX, window.leadingX)
        XCTAssertLessThan(body.trailingX, window.trailingX)
        XCTAssertFalse(Scoring.hasFullyCleared(plane: body, obstacle: window))
    }
}
