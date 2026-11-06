/// Clearing rule: +1 only after the plane's tail passes the far edge of the window frame.
public enum Scoring {
    public static func hasFullyCleared(plane: PlaneState, obstacle: Obstacle) -> Bool {
        plane.trailingX > obstacle.trailingX
    }
}
