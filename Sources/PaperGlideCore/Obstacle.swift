/// A building window scrolling left. The opening is empty; the frame above and below is solid.
public struct Obstacle: Equatable, Identifiable {
    public let id: Int
    public var left: Double
    public var width: Double
    public var gapCenterY: Double
    public var gapHeight: Double
    public var scored: Bool

    public init(
        id: Int,
        left: Double,
        width: Double,
        gapCenterY: Double,
        gapHeight: Double,
        scored: Bool = false
    ) {
        self.id = id
        self.left = left
        self.width = width
        self.gapCenterY = gapCenterY
        self.gapHeight = gapHeight
        self.scored = scored
    }

    public var right: Double { left + width }

    /// First edge the plane meets as the frame scrolls left.
    public var leadingX: Double { left }

    /// Last edge the plane must pass. The plane's tail has to clear this edge.
    public var trailingX: Double { right }

    public var gapBottom: Double { gapCenterY - gapHeight / 2 }
    public var gapTop: Double { gapCenterY + gapHeight / 2 }

    /// Solid window frame above and below the opening.
    public func solidFrames(worldHeight: Double) -> [AABB] {
        var frames: [AABB] = []
        if gapBottom > 0 {
            frames.append(AABB(minX: left, minY: 0, maxX: right, maxY: gapBottom))
        }
        if worldHeight - gapTop > 0 {
            frames.append(AABB(minX: left, minY: gapTop, maxX: right, maxY: worldHeight))
        }
        return frames
    }
}
