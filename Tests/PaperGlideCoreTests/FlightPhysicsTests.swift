import PaperGlideCore
import XCTest

final class FlightPhysicsTests: XCTestCase {
    func testGravityPullsThePlaneDown() {
        let step = FlightPhysics.integrate(
            y: 300,
            velocityY: 0,
            dt: 0.1,
            gravity: 1000,
            applyImpulse: false,
            impulse: 400,
            maxUpwardSpeed: 1000,
            maxDownwardSpeed: 1000
        )
        XCTAssertEqual(step.velocityY, -100, accuracy: 1e-9)
        XCTAssertEqual(step.y, 290, accuracy: 1e-9)
    }

    func testTapAppliesAnUpwardImpulseBeforeGravity() {
        let step = FlightPhysics.integrate(
            y: 300,
            velocityY: 0,
            dt: 0.1,
            gravity: 1000,
            applyImpulse: true,
            impulse: 400,
            maxUpwardSpeed: 1000,
            maxDownwardSpeed: 1000
        )
        XCTAssertEqual(step.velocityY, 300, accuracy: 1e-9)
        XCTAssertEqual(step.y, 330, accuracy: 1e-9)
    }

    func testUpwardSpeedIsCapped() {
        let step = FlightPhysics.integrate(
            y: 300,
            velocityY: 0,
            dt: 0.1,
            gravity: 0,
            applyImpulse: true,
            impulse: 800,
            maxUpwardSpeed: 500,
            maxDownwardSpeed: 1000
        )
        XCTAssertEqual(step.velocityY, 500, accuracy: 1e-9)
        XCTAssertEqual(step.y, 350, accuracy: 1e-9)
    }

    func testDownwardSpeedIsCapped() {
        let step = FlightPhysics.integrate(
            y: 300,
            velocityY: 0,
            dt: 0.1,
            gravity: 1000,
            applyImpulse: false,
            impulse: 0,
            maxUpwardSpeed: 1000,
            maxDownwardSpeed: 50
        )
        XCTAssertEqual(step.velocityY, -50, accuracy: 1e-9)
        XCTAssertEqual(step.y, 295, accuracy: 1e-9)
    }
}
