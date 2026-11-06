import PaperGlideCore
import XCTest

final class CollisionTests: XCTestCase {
    private let worldHeight = 500.0

    func testOpenWindowDoesNotHitTheFrame() {
        let body = makePlane(y: 250)
        let window = makeObstacle(left: 80, width: 60)
        XCTAssertFalse(Collision.overlapsFrame(plane: body, obstacle: window, worldHeight: worldHeight))
    }

    func testBottomFrameHit() {
        let body = makePlane(y: 100)
        let window = makeObstacle(left: 80, width: 60)
        XCTAssertTrue(Collision.overlapsFrame(plane: body, obstacle: window, worldHeight: worldHeight))
    }

    func testTopFrameHit() {
        let body = makePlane(y: 400)
        let window = makeObstacle(left: 80, width: 60)
        XCTAssertTrue(Collision.overlapsFrame(plane: body, obstacle: window, worldHeight: worldHeight))
    }

    func testTouchingTheFrameEdgeCounts() {
        let window = makeObstacle(left: 80, width: 60)
        let touchingBottom = makePlane(y: 160)
        XCTAssertEqual(touchingBottom.aabb.minY, window.gapBottom)
        XCTAssertTrue(Collision.overlapsFrame(plane: touchingBottom, obstacle: window, worldHeight: worldHeight))

        let justInside = makePlane(y: 160.1)
        XCTAssertFalse(Collision.overlapsFrame(plane: justInside, obstacle: window, worldHeight: worldHeight))
    }

    func testTouchingTheTopFrameEdgeCounts() {
        let window = makeObstacle(left: 80, width: 60)
        let touchingTop = makePlane(y: 340)
        XCTAssertEqual(touchingTop.aabb.maxY, window.gapTop)
        XCTAssertTrue(Collision.overlapsFrame(plane: touchingTop, obstacle: window, worldHeight: worldHeight))

        let justInside = makePlane(y: 339.9)
        XCTAssertFalse(Collision.overlapsFrame(plane: justInside, obstacle: window, worldHeight: worldHeight))
    }

    func testFrameDoesNotHitWhenTheWindowIsStillAhead() {
        let body = makePlane(y: 40)
        let window = makeObstacle(left: 400, width: 40)
        XCTAssertFalse(Collision.overlapsFrame(plane: body, obstacle: window, worldHeight: worldHeight))
    }

    func testWorldBoundsAreInclusive() {
        XCTAssertTrue(Collision.hitsWorldBounds(plane: makePlane(y: 10), worldHeight: worldHeight))
        XCTAssertTrue(Collision.hitsWorldBounds(plane: makePlane(y: 490), worldHeight: worldHeight))
        XCTAssertFalse(Collision.hitsWorldBounds(plane: makePlane(y: 10.1), worldHeight: worldHeight))
        XCTAssertFalse(Collision.hitsWorldBounds(plane: makePlane(y: 489.9), worldHeight: worldHeight))
    }
}
