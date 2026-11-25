import Foundation

/// Shared golden-run oracle. The generator writes these values to
/// `fixtures/golden/*.json`. Tests replay `tapSteps` and compare.
/// Field names and `format` are a contract for the Kotlin port.
public enum GoldenFixture {
    public static let format = 1

    public static func capture(
        name: String,
        seed: UInt64,
        tapSteps: [Int],
        maxSteps: Int,
        config: GameConfig = .standard
    ) -> GoldenFile {
        run(
            name: name,
            seed: seed,
            explicitTaps: tapSteps,
            stopScore: nil,
            maxSteps: maxSteps,
            config: config
        )
    }

    /// Chooses taps with `GlidePilot` and records the step indexes it used.
    /// Replay uses those indexes, not the pilot.
    public static func capturePilot(
        name: String,
        seed: UInt64,
        stopScore: Int,
        maxSteps: Int,
        config: GameConfig = .standard
    ) -> GoldenFile {
        run(
            name: name,
            seed: seed,
            explicitTaps: nil,
            stopScore: stopScore,
            maxSteps: maxSteps,
            config: config
        )
    }

    private static func run(
        name: String,
        seed: UInt64,
        explicitTaps: [Int]?,
        stopScore: Int?,
        maxSteps: Int,
        config: GameConfig
    ) -> GoldenFile {
        let session = GameSession(config: config, storage: InMemoryGameStorage(), seed: seed)
        var steps = [makeStep(0, session.snapshot, config)]
        var taps: [Int] = []
        let explicit = Set(explicitTaps ?? [])
        var index = 0
        while session.snapshot.phase == .playing, index < maxSteps {
            if let stopScore, session.snapshot.score >= stopScore {
                break
            }
            index += 1
            let tap = explicitTaps == nil
                ? GlidePilot.shouldTap(snapshot: session.snapshot, fallbackTarget: config.planeStartY)
                : explicit.contains(index)
            if tap {
                taps.append(index)
                session.tap()
            }
            session.step(dt: config.physicsStep)
            steps.append(makeStep(index, session.snapshot, config))
        }
        return GoldenFile(
            format: format,
            name: name,
            timestep: config.physicsStep,
            seed: seed,
            tapSteps: taps,
            tolerance: .standard,
            config: GoldenConfig(config),
            steps: steps
        )
    }

    private static func makeStep(_ index: Int, _ snapshot: GameSnapshot, _ config: GameConfig) -> GoldenStep {
        let level = DifficultyRamp.level(
            score: snapshot.score,
            baseGap: config.obstacleGapHeight,
            baseScroll: config.scrollSpeed
        )
        let ordered = snapshot.obstacles.sorted { lhs, rhs in
            if lhs.left == rhs.left { return lhs.id < rhs.id }
            return lhs.left < rhs.left
        }
        var obstacles: [GoldenObstacle] = []
        var previousLeft: Double?
        for obstacle in ordered {
            let spacing = previousLeft.map { obstacle.left - $0 }
            previousLeft = obstacle.left
            obstacles.append(GoldenObstacle(
                id: obstacle.id,
                left: obstacle.left,
                width: obstacle.width,
                gapCenterY: obstacle.gapCenterY,
                gapHeight: obstacle.gapHeight,
                spacingFromPrevious: spacing
            ))
        }
        return GoldenStep(
            step: index,
            flightTime: snapshot.flightTime,
            score: snapshot.score,
            phase: snapshot.phase == .playing ? "playing" : "dead",
            plane: GoldenPlane(
                x: snapshot.plane.x,
                y: snapshot.plane.y,
                velocityY: snapshot.plane.velocityY
            ),
            scrollSpeed: snapshot.scrollSpeed,
            spawnGapHeight: snapshot.spawnGapHeight,
            ramp: GoldenRamp(
                stepIndex: level.stepIndex,
                gapHeight: level.gapHeight,
                scrollSpeed: level.scrollSpeed
            ),
            obstacles: obstacles
        )
    }
}

public struct GoldenTolerance: Codable, Equatable {
    public var position: Double
    public var velocity: Double
    public var time: Double
    public var gap: Double
    public var scroll: Double
    public var spacing: Double

    public static let standard = GoldenTolerance(
        position: 1e-6,
        velocity: 1e-6,
        time: 1e-9,
        gap: 1e-6,
        scroll: 1e-6,
        spacing: 1e-6
    )
}

public struct GoldenConfig: Codable, Equatable {
    public var worldWidth: Double
    public var worldHeight: Double
    public var gravity: Double
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

    public init(_ config: GameConfig) {
        worldWidth = config.worldWidth
        worldHeight = config.worldHeight
        gravity = config.gravity
        flapVelocity = config.flapVelocity
        maxUpwardSpeed = config.maxUpwardSpeed
        maxDownwardSpeed = config.maxDownwardSpeed
        planeX = config.planeX
        planeWidth = config.planeWidth
        planeHeight = config.planeHeight
        planeStartY = config.planeStartY
        obstacleWidth = config.obstacleWidth
        obstacleGapHeight = config.obstacleGapHeight
        obstacleSpacing = config.obstacleSpacing
        scrollSpeed = config.scrollSpeed
        gapMargin = config.gapMargin
        initialLead = config.initialLead
        despawnMargin = config.despawnMargin
        physicsStep = config.physicsStep
    }
}

public struct GoldenPlane: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var velocityY: Double
}

public struct GoldenRamp: Codable, Equatable {
    public var stepIndex: Int
    public var gapHeight: Double
    public var scrollSpeed: Double
}

public struct GoldenObstacle: Codable, Equatable {
    public var id: Int
    public var left: Double
    public var width: Double
    public var gapCenterY: Double
    public var gapHeight: Double
    public var spacingFromPrevious: Double?
}

public struct GoldenStep: Codable, Equatable {
    public var step: Int
    public var flightTime: Double
    public var score: Int
    public var phase: String
    public var plane: GoldenPlane
    public var scrollSpeed: Double
    public var spawnGapHeight: Double
    public var ramp: GoldenRamp
    public var obstacles: [GoldenObstacle]
}

public struct GoldenFile: Codable, Equatable {
    public var format: Int
    public var name: String
    public var timestep: Double
    public var seed: UInt64
    public var tapSteps: [Int]
    public var tolerance: GoldenTolerance
    public var config: GoldenConfig
    public var steps: [GoldenStep]
}
