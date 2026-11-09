/// Tunable rules for a run. Distances are logical points. Time is seconds.
///
/// A tap assigns `flapVelocity` instead of adding a hop. `gravity` (points/s²) and
/// `flapVelocity` (points/s) are the flappybird.gg design-aspect rates — 5 units/s²
/// and 1.55 units/s on a 2.56-unit visible height — scaled by `worldHeight / 2.56`
/// and rounded to the nearest point. `maxUpwardSpeed` equals the flap so taps cannot stack.
///
/// `obstacleGapHeight` and `scrollSpeed` are the opening of a run. `DifficultyRamp`
/// tightens later windows and the live scroll. Gravity, flap, and the speed caps
/// stay at these values for the whole run.
public struct GameConfig: Equatable {
    public var worldWidth: Double
    public var worldHeight: Double
    public var gravity: Double
    /// Upward speed a tap assigns, in points per second.
    public var flapVelocity: Double
    public var maxUpwardSpeed: Double
    public var maxDownwardSpeed: Double
    public var planeX: Double
    public var planeWidth: Double
    public var planeHeight: Double
    public var planeStartY: Double
    public var obstacleWidth: Double
    public var obstacleGapHeight: Double
    public var obstacleSpacing: Double
    public var scrollSpeed: Double
    public var gapMargin: Double
    public var initialLead: Double
    public var despawnMargin: Double
    public var physicsStep: Double
    public var maxFrameDelta: Double
    public var spawningEnabled: Bool

    public init(
        worldWidth: Double = 390,
        worldHeight: Double = 760,
        gravity: Double = 1484,
        flapVelocity: Double = 500,
        maxUpwardSpeed: Double = 500,
        maxDownwardSpeed: Double = 720,
        planeX: Double = 108,
        planeWidth: Double = 46,
        planeHeight: Double = 22,
        planeStartY: Double = 390,
        obstacleWidth: Double = 70,
        obstacleGapHeight: Double = 218,
        obstacleSpacing: Double = 300,
        scrollSpeed: Double = 148,
        gapMargin: Double = 78,
        initialLead: Double = 120,
        despawnMargin: Double = 80,
        physicsStep: Double = 1.0 / 120.0,
        maxFrameDelta: Double = 1.0 / 20.0,
        spawningEnabled: Bool = true
    ) {
        self.worldWidth = worldWidth
        self.worldHeight = worldHeight
        self.gravity = gravity
        self.flapVelocity = flapVelocity
        self.maxUpwardSpeed = maxUpwardSpeed
        self.maxDownwardSpeed = maxDownwardSpeed
        self.planeX = planeX
        self.planeWidth = planeWidth
        self.planeHeight = planeHeight
        self.planeStartY = planeStartY
        self.obstacleWidth = obstacleWidth
        self.obstacleGapHeight = obstacleGapHeight
        self.obstacleSpacing = obstacleSpacing
        self.scrollSpeed = scrollSpeed
        self.gapMargin = gapMargin
        self.initialLead = initialLead
        self.despawnMargin = despawnMargin
        self.physicsStep = physicsStep
        self.maxFrameDelta = maxFrameDelta
        self.spawningEnabled = spawningEnabled
    }

    /// Values used by the iOS app. The deployment target is iOS 16; this config is platform-neutral.
    public static let standard = GameConfig()
}
