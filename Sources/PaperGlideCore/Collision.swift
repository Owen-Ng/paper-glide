public enum Collision {
    public static func overlapsFrame(
        plane: PlaneState,
        obstacle: Obstacle,
        worldHeight: Double
    ) -> Bool {
        let body = plane.aabb
        for frame in obstacle.solidFrames(worldHeight: worldHeight) where body.intersects(frame) {
            return true
        }
        return false
    }

    /// The page edges. Touching y = 0 or y = worldHeight ends the run.
    public static func hitsWorldBounds(plane: PlaneState, worldHeight: Double) -> Bool {
        let body = plane.aabb
        return body.minY <= 0 || body.maxY >= worldHeight
    }
}
