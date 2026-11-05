public enum RunPhase: Equatable {
    case playing
    case dead
}

public struct GameSnapshot: Equatable {
    public var phase: RunPhase
    public var score: Int
    public var bestScore: Int
    public var showCoach: Bool
    public var plane: PlaneState
    public var obstacles: [Obstacle]

    public init(
        phase: RunPhase,
        score: Int,
        bestScore: Int,
        showCoach: Bool,
        plane: PlaneState,
        obstacles: [Obstacle]
    ) {
        self.phase = phase
        self.score = score
        self.bestScore = bestScore
        self.showCoach = showCoach
        self.plane = plane
        self.obstacles = obstacles
    }
}

/// A layout injected by tests. Spawning stays under `GameConfig.spawningEnabled`.
public struct RunLayout: Equatable {
    public var planeY: Double
    public var velocityY: Double
    public var obstacles: [Obstacle]

    public init(planeY: Double, velocityY: Double, obstacles: [Obstacle]) {
        self.planeY = planeY
        self.velocityY = velocityY
        self.obstacles = obstacles
    }
}

/// Paper Glide simulation.
///
/// The plane stays at `config.planeX` and points toward +x. Building windows scroll
/// toward -x. A tap adds one upward impulse on the next physics slice; gravity pulls
/// down. The run ends when the plane overlaps a window frame or the top or bottom
/// of the page. Score increases by one when the plane's trailing edge passes an
/// obstacle's trailing edge, and only once per window.
public final class GameSession {
    public let config: GameConfig
    private let storage: GameStorage
    private var rng: SeededGenerator
    private var nextObstacleID: Int
    private var pendingTap: Bool
    private var plane: PlaneState
    private var obstacles: [Obstacle]
    private var score: Int
    private var bestScore: Int
    private var showCoach: Bool
    private var phase: RunPhase

    public init(config: GameConfig = .standard, storage: GameStorage, seed: UInt64) {
        self.config = config
        self.storage = storage
        rng = SeededGenerator(seed: seed)
        nextObstacleID = 1
        pendingTap = false
        plane = PlaneState(
            x: config.planeX,
            y: config.planeStartY,
            velocityY: 0,
            width: config.planeWidth,
            height: config.planeHeight
        )
        obstacles = []
        score = 0
        bestScore = 0
        showCoach = false
        phase = .playing
        beginRun(seed: seed)
    }

    public var snapshot: GameSnapshot {
        GameSnapshot(
            phase: phase,
            score: score,
            bestScore: bestScore,
            showCoach: showCoach,
            plane: plane,
            obstacles: obstacles
        )
    }

    public func reset(seed: UInt64) {
        beginRun(seed: seed)
    }

    /// Records the coach as seen on the first tap of the first run, then queues one impulse.
    public func tap() {
        guard phase == .playing else { return }
        if showCoach {
            showCoach = false
            storage.saveCoachCompleted(true)
        }
        pendingTap = true
    }

    public func step(dt: Double) {
        guard phase == .playing, dt.isFinite, dt > 0 else { return }

        let frame = min(dt, config.maxFrameDelta)
        var remaining = frame
        var applyImpulse = pendingTap
        pendingTap = false
        let minimumQuantum = 1.0 / 240.0

        while remaining > 1e-9 {
            let quantum = max(config.physicsStep, minimumQuantum)
            let h = min(quantum, remaining)
            let integrated = FlightPhysics.integrate(
                y: plane.y,
                velocityY: plane.velocityY,
                dt: h,
                gravity: config.gravity,
                applyImpulse: applyImpulse,
                impulse: config.tapImpulse,
                maxUpwardSpeed: config.maxUpwardSpeed,
                maxDownwardSpeed: config.maxDownwardSpeed
            )
            applyImpulse = false
            plane.y = integrated.y
            plane.velocityY = integrated.velocityY

            let dx = config.scrollSpeed * h
            for index in obstacles.indices {
                obstacles[index].left -= dx
            }

            for index in obstacles.indices where obstacles[index].scored == false {
                if Scoring.hasFullyCleared(plane: plane, obstacle: obstacles[index]) {
                    obstacles[index].scored = true
                    score += 1
                }
            }

            if collided() {
                die()
                return
            }

            let margin = config.despawnMargin
            obstacles.removeAll { $0.right < -margin }
            maintainSpawns()
            remaining -= h
        }
    }

    /// Replaces the plane's vertical state and the window list. Score returns to zero
    /// and the run is playing again. Best score, coach flag, and the random stream stay.
    public func applyLayout(_ layout: RunLayout) {
        guard layout.planeY.isFinite, layout.velocityY.isFinite else { return }
        plane.y = layout.planeY
        plane.velocityY = layout.velocityY
        obstacles = layout.obstacles
        score = 0
        phase = .playing
        pendingTap = false
    }

    private func beginRun(seed: UInt64) {
        rng = SeededGenerator(seed: seed)
        nextObstacleID = 1
        pendingTap = false
        score = 0
        phase = .playing
        bestScore = storage.loadBestScore()
        showCoach = !storage.loadCoachCompleted()
        plane = PlaneState(
            x: config.planeX,
            y: config.planeStartY,
            velocityY: 0,
            width: config.planeWidth,
            height: config.planeHeight
        )
        obstacles = []
        maintainSpawns()
    }

    private func die() {
        phase = .dead
        pendingTap = false
        let stored = storage.loadBestScore()
        if score > stored {
            storage.saveBestScore(score)
            bestScore = score
        } else {
            bestScore = stored
        }
    }

    private func collided() -> Bool {
        if Collision.hitsWorldBounds(plane: plane, worldHeight: config.worldHeight) {
            return true
        }
        for obstacle in obstacles
            where Collision.overlapsFrame(plane: plane, obstacle: obstacle, worldHeight: config.worldHeight) {
            return true
        }
        return false
    }

    private func maintainSpawns() {
        guard config.spawningEnabled, config.obstacleSpacing > 0 else { return }
        if obstacles.isEmpty {
            spawn(atLeft: config.worldWidth + config.initialLead)
        }
        let horizon = config.worldWidth + config.obstacleSpacing
        while let last = obstacles.last, last.left < horizon {
            spawn(atLeft: last.left + config.obstacleSpacing)
        }
    }

    private func spawn(atLeft left: Double) {
        let obstacle = Obstacle(
            id: nextObstacleID,
            left: left,
            width: config.obstacleWidth,
            gapCenterY: randomGapCenter(),
            gapHeight: config.obstacleGapHeight
        )
        nextObstacleID += 1
        obstacles.append(obstacle)
    }

    private func randomGapCenter() -> Double {
        let half = config.obstacleGapHeight / 2
        let low = config.gapMargin + half
        let high = config.worldHeight - config.gapMargin - half
        guard high > low else {
            return config.worldHeight / 2
        }
        return low + (high - low) * rng.nextUnit()
    }
}
