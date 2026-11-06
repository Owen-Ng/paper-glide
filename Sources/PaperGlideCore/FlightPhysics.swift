/// One explicit Euler step in a y-up world.
/// A flap assigns `flapVelocity` (it does not add to the current speed), then gravity
/// accelerates downward. Upward speed is limited before gravity; downward speed after.
public enum FlightPhysics {
    public static func integrate(
        y: Double,
        velocityY: Double,
        dt: Double,
        gravity: Double,
        applyFlap: Bool,
        flapVelocity: Double,
        maxUpwardSpeed: Double,
        maxDownwardSpeed: Double
    ) -> (y: Double, velocityY: Double) {
        var vy = velocityY
        if applyFlap {
            vy = flapVelocity
        }
        if vy > maxUpwardSpeed {
            vy = maxUpwardSpeed
        }
        vy -= gravity * dt
        if vy < -maxDownwardSpeed {
            vy = -maxDownwardSpeed
        }
        return (y + vy * dt, vy)
    }
}
