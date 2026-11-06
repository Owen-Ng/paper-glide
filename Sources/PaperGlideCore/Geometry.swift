/// Axis-aligned box in a y-up world. Touching edges count as an intersection.
public struct AABB: Equatable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public func intersects(_ other: AABB) -> Bool {
        minX <= other.maxX
            && maxX >= other.minX
            && minY <= other.maxY
            && maxY >= other.minY
    }
}

/// The paper plane. It stays at a fixed x while window frames scroll toward -x.
public struct PlaneState: Equatable {
    public var x: Double
    public var y: Double
    public var velocityY: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, velocityY: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.velocityY = velocityY
        self.width = width
        self.height = height
    }

    /// Left edge. This is the trailing edge because the plane points toward +x.
    public var trailingX: Double { x - width / 2 }

    /// Right edge (the nose).
    public var leadingX: Double { x + width / 2 }

    public var aabb: AABB {
        AABB(
            minX: trailingX,
            minY: y - height / 2,
            maxX: leadingX,
            maxY: y + height / 2
        )
    }
}
