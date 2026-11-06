/// Tunable rules for a run. Distances are logical points. Time is seconds.
public struct GameConfig: Equatable {
    public var worldWidth: Double
    public var worldHeight: Double
    public var gravity: Double
    public var tapImpulse: Double
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
        gravity: Double = 1600,
        tapImpulse: Double = 490,
        maxUpwardSpeed: Double = 580,
        maxDownwardSpeed: Double = 720,
        planeX: Double = 108,
        planeWidth: Double = 46,
        planeHeight: Double = 22,
        planeStartY: Double = 390,
        obstacleWidth: Double = 70,
        obstacleGapHeight: Double = 228,
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
        self.tapImpulse = tapImpulse
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
