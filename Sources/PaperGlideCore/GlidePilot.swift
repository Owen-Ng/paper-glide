/// Deterministic tap/coast choices for the shipped physics.
/// A tap is requested when the plane is below the next opening's center.
public enum GlidePilot {
    public static func upcomingGapCenter(
        plane: PlaneState,
        obstacles: [Obstacle],
        fallback: Double
    ) -> Double {
        let tail = plane.trailingX
        if let window = obstacles.first(where: { $0.trailingX > tail - 5 }) {
            return window.gapCenterY
        }
        return fallback
    }

    public static func shouldTap(snapshot: GameSnapshot, fallbackTarget: Double) -> Bool {
        let target = upcomingGapCenter(
            plane: snapshot.plane,
            obstacles: snapshot.obstacles,
            fallback: fallbackTarget
        )
        return snapshot.plane.y < target
    }

    /// One optional impulse, then `stride` seconds of the real simulation.
    /// `step` caps each slice at `maxFrameDelta`, so this loops until the stride is consumed.
    public static func advance(_ session: GameSession, stride: Double, tap: Bool) {
        guard stride.isFinite, stride > 0 else { return }
        if tap {
            session.tap()
        }
        var remaining = stride
        while remaining > 1e-9, session.snapshot.phase == .playing {
            let slice = min(remaining, session.config.maxFrameDelta)
            session.step(dt: slice)
            remaining -= slice
        }
    }
}
