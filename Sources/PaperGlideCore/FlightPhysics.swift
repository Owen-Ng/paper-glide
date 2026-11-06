/// One explicit Euler step. A tap adds an upward impulse, then gravity accelerates downward.
public enum FlightPhysics {
    public static func integrate(
        y: Double,
        velocityY: Double,
        dt: Double,
        gravity: Double,
        applyImpulse: Bool,
        impulse: Double,
        maxUpwardSpeed: Double,
        maxDownwardSpeed: Double
    ) -> (y: Double, velocityY: Double) {
        var vy = velocityY
        if applyImpulse {
            vy += impulse
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
