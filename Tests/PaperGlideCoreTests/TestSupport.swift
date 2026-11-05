import PaperGlideCore

func makeConfig(
    worldWidth: Double = 400,
    worldHeight: Double = 500,
    gravity: Double = 0,
    tapImpulse: Double = 400,
    maxUpwardSpeed: Double = 1000,
    maxDownwardSpeed: Double = 1000,
    planeX: Double = 100,
    planeWidth: Double = 40,
    planeHeight: Double = 20,
    planeStartY: Double = 250,
    obstacleWidth: Double = 40,
    obstacleGapHeight: Double = 200,
    obstacleSpacing: Double = 280,
    scrollSpeed: Double = 100,
    gapMargin: Double = 40,
    initialLead: Double = 120,
    despawnMargin: Double = 40,
    physicsStep: Double = 1,
    maxFrameDelta: Double = 1,
    spawningEnabled: Bool = false
) -> GameConfig {
    GameConfig(
        worldWidth: worldWidth,
        worldHeight: worldHeight,
        gravity: gravity,
        tapImpulse: tapImpulse,
        maxUpwardSpeed: maxUpwardSpeed,
        maxDownwardSpeed: maxDownwardSpeed,
        planeX: planeX,
        planeWidth: planeWidth,
        planeHeight: planeHeight,
        planeStartY: planeStartY,
        obstacleWidth: obstacleWidth,
        obstacleGapHeight: obstacleGapHeight,
        obstacleSpacing: obstacleSpacing,
        scrollSpeed: scrollSpeed,
        gapMargin: gapMargin,
        initialLead: initialLead,
        despawnMargin: despawnMargin,
        physicsStep: physicsStep,
        maxFrameDelta: maxFrameDelta,
        spawningEnabled: spawningEnabled
    )
}

struct Harness {
    let session: GameSession
    let storage: InMemoryGameStorage
}

func makeHarness(
    config: GameConfig = makeConfig(),
    seed: UInt64 = 1,
    best: Int = 0,
    coachCompleted: Bool = false
) -> Harness {
    let storage = InMemoryGameStorage(bestScore: best, coachCompleted: coachCompleted)
    let session = GameSession(config: config, storage: storage, seed: seed)
    return Harness(session: session, storage: storage)
}

func makePlane(
    x: Double = 100,
    y: Double = 250,
    velocityY: Double = 0,
    width: Double = 40,
    height: Double = 20
) -> PlaneState {
    PlaneState(x: x, y: y, velocityY: velocityY, width: width, height: height)
}

func makeObstacle(
    id: Int = 1,
    left: Double,
    width: Double = 40,
    gapCenterY: Double = 250,
    gapHeight: Double = 200,
    scored: Bool = false
) -> Obstacle {
    Obstacle(
        id: id,
        left: left,
        width: width,
        gapCenterY: gapCenterY,
        gapHeight: gapHeight,
        scored: scored
    )
}
