import PaperGlideCore
import XCTest

final class FlightPhysicsTests: XCTestCase {
    func testGravityPullsThePlaneDown() {
        let step = FlightPhysics.integrate(
            y: 300,
            velocityY: 0,
            dt: 0.1,
            gravity: 1000,
            applyFlap: false,
            flapVelocity: 400,
            maxUpwardSpeed: 1000,
            maxDownwardSpeed: 1000
        )
        XCTAssertEqual(step.velocityY, -100, accuracy: 1e-9)
        XCTAssertEqual(step.y, 290, accuracy: 1e-9)
    }

    func testFlapAssignsUpwardSpeedBeforeGravity() {
        let step = FlightPhysics.integrate(
            y: 300,
            velocityY: 0,
            dt: 0.1,
            gravity: 1000,
            applyFlap: true,
            flapVelocity: 400,
            maxUpwardSpeed: 1000,
            maxDownwardSpeed: 1000
        )
        XCTAssertEqual(step.velocityY, 300, accuracy: 1e-9)
        XCTAssertEqual(step.y, 330, accuracy: 1e-9)
    }

    /// A falling plane receives the same upward speed as a plane at rest.
    /// Adding the flap onto the current speed left a late tap almost on the ground.
    func testFlapReplacesDownwardSpeed() {
        let falling = FlightPhysics.integrate(
            y: 300,
            velocityY: -400,
            dt: 0.1,
            gravity: 1000,
            applyFlap: true,
            flapVelocity: 400,
            maxUpwardSpeed: 1000,
            maxDownwardSpeed: 1000
        )
        let resting = FlightPhysics.integrate(
            y: 300,
            velocityY: 0,
            dt: 0.1,
            gravity: 1000,
            applyFlap: true,
            flapVelocity: 400,
            maxUpwardSpeed: 1000,
            maxDownwardSpeed: 1000
        )
        XCTAssertEqual(falling.velocityY, 300, accuracy: 1e-9)
        XCTAssertEqual(falling.y, 330, accuracy: 1e-9)
        XCTAssertEqual(falling.velocityY, resting.velocityY, accuracy: 1e-9)
    }

    func testUpwardSpeedIsCapped() {
        let step = FlightPhysics.integrate(
            y: 300,
            velocityY: 0,
            dt: 0.1,
            gravity: 0,
            applyFlap: true,
            flapVelocity: 800,
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
            applyFlap: false,
            flapVelocity: 0,
            maxUpwardSpeed: 1000,
            maxDownwardSpeed: 50
        )
        XCTAssertEqual(step.velocityY, -50, accuracy: 1e-9)
        XCTAssertEqual(step.y, 295, accuracy: 1e-9)
    }

    /// flappybird.gg design aspect: gravity 5 and flap 1.55 on a 2.56-unit visible height.
    /// Scaled into the 760-point world and rounded to the nearest point.
    func testShippedRatesMatchTheScaledReference() {
        let config = GameConfig.standard
        let scale = config.worldHeight / 2.56
        XCTAssertEqual(config.gravity, (5 * scale).rounded(), accuracy: 1e-9)
        XCTAssertEqual(config.flapVelocity, (1.55 * scale).rounded(), accuracy: 1e-9)
        XCTAssertEqual(config.maxUpwardSpeed, config.flapVelocity, accuracy: 1e-9)
        XCTAssertEqual(config.maxDownwardSpeed, 720, accuracy: 1e-9)
        XCTAssertEqual(config.obstacleGapHeight, 228, accuracy: 1e-9)
        XCTAssertEqual(config.scrollSpeed, 148, accuracy: 1e-9)
    }

    func testShippedFlapRisesTheSameFromAFallAsFromRest() {
        let config = GameConfig.standard
        let rest = hop(from: 0, config: config)
        let falling = hop(from: -config.maxDownwardSpeed, config: config)
        XCTAssertEqual(rest.speedAfterFlap, falling.speedAfterFlap, accuracy: 1e-6)
        XCTAssertEqual(rest.apexGain, falling.apexGain, accuracy: 1e-6)
        XCTAssertGreaterThan(rest.speedAfterFlap, 400)
        XCTAssertGreaterThan(rest.apexGain, 60)
        XCTAssertLessThan(rest.apexGain, 80)
    }

    private func hop(from velocityY: Double, config: GameConfig) -> (speedAfterFlap: Double, apexGain: Double) {
        let dt = config.physicsStep
        var integrated = FlightPhysics.integrate(
            y: config.planeStartY,
            velocityY: velocityY,
            dt: dt,
            gravity: config.gravity,
            applyFlap: true,
            flapVelocity: config.flapVelocity,
            maxUpwardSpeed: config.maxUpwardSpeed,
            maxDownwardSpeed: config.maxDownwardSpeed
        )
        let speedAfterFlap = integrated.velocityY
        var peak = integrated.y
        var steps = 0
        while integrated.velocityY > 0, steps < 500 {
            integrated = FlightPhysics.integrate(
                y: integrated.y,
                velocityY: integrated.velocityY,
                dt: dt,
                gravity: config.gravity,
                applyFlap: false,
                flapVelocity: config.flapVelocity,
                maxUpwardSpeed: config.maxUpwardSpeed,
                maxDownwardSpeed: config.maxDownwardSpeed
            )
            peak = max(peak, integrated.y)
            steps += 1
        }
        return (speedAfterFlap, peak - config.planeStartY)
    }
}
