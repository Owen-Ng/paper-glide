package com.paperglide.core

/** Tunable rules. Distances are logical points. Time is seconds. Mirrors GameConfig.swift. */
data class GameConfig(
    var worldWidth: Double = 390.0,
    var worldHeight: Double = 760.0,
    var gravity: Double = 1484.0,
    var flapVelocity: Double = 500.0,
    var maxUpwardSpeed: Double = 500.0,
    var maxDownwardSpeed: Double = 720.0,
    var planeX: Double = 108.0,
    var planeWidth: Double = 46.0,
    var planeHeight: Double = 22.0,
    var planeStartY: Double = 390.0,
    var obstacleWidth: Double = 70.0,
    var obstacleGapHeight: Double = 218.0,
    var obstacleSpacing: Double = 300.0,
    var scrollSpeed: Double = 148.0,
    var gapMargin: Double = 78.0,
    var initialLead: Double = 120.0,
    var despawnMargin: Double = 80.0,
    var physicsStep: Double = 1.0 / 120.0,
    var maxFrameDelta: Double = 1.0 / 20.0,
    var spawningEnabled: Boolean = true,
) {
    companion object {
        val standard = GameConfig()
    }
}

object FlightPhysics {
    fun integrate(
        y: Double,
        velocityY: Double,
        dt: Double,
        gravity: Double,
        applyFlap: Boolean,
        flapVelocity: Double,
        maxUpwardSpeed: Double,
        maxDownwardSpeed: Double,
    ): Pair<Double, Double> {
        var vy = velocityY
        if (applyFlap) vy = flapVelocity
        if (vy > maxUpwardSpeed) vy = maxUpwardSpeed
        vy -= gravity * dt
        if (vy < -maxDownwardSpeed) vy = -maxDownwardSpeed
        return (y + vy * dt) to vy
    }
}

data class AABB(val minX: Double, val minY: Double, val maxX: Double, val maxY: Double) {
    fun intersects(other: AABB): Boolean =
        minX <= other.maxX && maxX >= other.minX && minY <= other.maxY && maxY >= other.minY
}

data class PlaneState(
    var x: Double,
    var y: Double,
    var velocityY: Double,
    var width: Double,
    var height: Double,
) {
    val trailingX: Double get() = x - width / 2
    val leadingX: Double get() = x + width / 2
    val aabb: AABB
        get() = AABB(trailingX, y - height / 2, leadingX, y + height / 2)
}

data class Obstacle(
    val id: Int,
    var left: Double,
    var width: Double,
    var gapCenterY: Double,
    var gapHeight: Double,
    var scored: Boolean = false,
) {
    val right: Double get() = left + width
    val trailingX: Double get() = right
    val gapBottom: Double get() = gapCenterY - gapHeight / 2
    val gapTop: Double get() = gapCenterY + gapHeight / 2

    fun solidFrames(worldHeight: Double): List<AABB> {
        val frames = ArrayList<AABB>(2)
        if (gapBottom > 0) frames += AABB(left, 0.0, right, gapBottom)
        if (worldHeight - gapTop > 0) frames += AABB(left, gapTop, right, worldHeight)
        return frames
    }
}

object Collision {
    fun overlapsFrame(plane: PlaneState, obstacle: Obstacle, worldHeight: Double): Boolean {
        val body = plane.aabb
        return obstacle.solidFrames(worldHeight).any { body.intersects(it) }
    }

    fun hitsWorldBounds(plane: PlaneState, worldHeight: Double): Boolean {
        val body = plane.aabb
        return body.minY <= 0 || body.maxY >= worldHeight
    }
}

object Scoring {
    fun hasFullyCleared(plane: PlaneState, obstacle: Obstacle): Boolean =
        plane.trailingX > obstacle.trailingX
}

data class DifficultyLevel(val stepIndex: Int, val gapHeight: Double, val scrollSpeed: Double)

object DifficultyRamp {
    const val pointsPerStep = 5
    const val maxStepIndex = 12
    const val gapDropPerStep = 5.0
    const val scrollGainPerStep = 4.0
    const val minimumGapHeight = 168.0
    const val maximumScrollSpeed = 196.0

    fun standardLevel(score: Int): DifficultyLevel =
        level(score, GameConfig.standard.obstacleGapHeight, GameConfig.standard.scrollSpeed)

    fun level(score: Int, baseGap: Double, baseScroll: Double): DifficultyLevel {
        val stepIndex = minOf(maxOf(score, 0) / pointsPerStep, maxStepIndex)
        var gap = baseGap - gapDropPerStep * stepIndex.toDouble()
        var scroll = baseScroll + scrollGainPerStep * stepIndex.toDouble()
        if (baseGap >= minimumGapHeight) gap = maxOf(minimumGapHeight, gap)
        if (baseScroll <= maximumScrollSpeed) scroll = minOf(maximumScrollSpeed, scroll)
        return DifficultyLevel(stepIndex, gap, scroll)
    }
}

/** SplitMix64. Window openings are reproducible from the run seed. */
class SeededGenerator(seed: ULong) {
    private var state: ULong = seed

    fun next(): ULong {
        state += 0x9E3779B97F4A7C15u
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9u
        z = (z xor (z shr 27)) * 0x94D049BB133111EBu
        return z xor (z shr 31)
    }

    fun nextUnit(): Double {
        val bits = next() shr 11
        return bits.toDouble() / (1UL shl 53).toDouble()
    }
}

object BestScore {
    fun isNewRecord(score: Int, previousBest: Int): Boolean = score > previousBest
}

interface GameStorage {
    fun loadBestScore(): Int
    fun saveBestScore(score: Int)
    fun loadCoachCompleted(): Boolean
    fun saveCoachCompleted(completed: Boolean)
    fun clear()
}

class InMemoryGameStorage(
    bestScore: Int = 0,
    coachCompleted: Boolean = false,
) : GameStorage {
    private var bestScore = bestScore
    private var coachCompleted = coachCompleted

    override fun loadBestScore(): Int = bestScore
    override fun saveBestScore(score: Int) { bestScore = score }
    override fun loadCoachCompleted(): Boolean = coachCompleted
    override fun saveCoachCompleted(completed: Boolean) { coachCompleted = completed }
    override fun clear() {
        bestScore = 0
        coachCompleted = false
    }
}

enum class RunPhase { Playing, Dead }

data class GameSnapshot(
    val phase: RunPhase,
    val score: Int,
    val bestScore: Int,
    val isNewBest: Boolean,
    val showCoach: Boolean,
    val plane: PlaneState,
    val obstacles: List<Obstacle>,
    val flightTime: Double,
    val runID: Int,
    val runSeed: ULong,
    val scrollSpeed: Double,
    val spawnGapHeight: Double,
)

data class RunLayout(val planeY: Double, val velocityY: Double, val obstacles: List<Obstacle>)

/**
 * Fixed-step simulation. [step] clamps a frame to [GameConfig.maxFrameDelta] and
 * integrates in [GameConfig.physicsStep] quanta, matching GameSession.swift.
 * Callers that need a longer stride loop until it is consumed, the way GlidePilot does.
 */
class GameSession(
    val config: GameConfig = GameConfig.standard,
    private val storage: GameStorage,
    seed: ULong,
) {
    private var rng = SeededGenerator(seed)
    private var nextObstacleID = 1
    private var pendingTap = false
    private var plane = PlaneState(config.planeX, config.planeStartY, 0.0, config.planeWidth, config.planeHeight)
    private val obstacles = ArrayList<Obstacle>()
    private var score = 0
    private var bestScore = 0
    private var isNewBest = false
    private var showCoach = false
    private var phase = RunPhase.Playing
    private var flightTime = 0.0
    private var runID = 0
    private var runSeed: ULong = 0u
    private var scrollSpeed = 0.0
    private var spawnGapHeight = 0.0

    init {
        beginRun(seed)
    }

    val snapshot: GameSnapshot
        get() = GameSnapshot(
            phase, score, bestScore, isNewBest, showCoach,
            plane.copy(), obstacles.map { it.copy() },
            flightTime, runID, runSeed, scrollSpeed, spawnGapHeight,
        )

    fun reset(seed: ULong) = beginRun(seed)

    fun tap() {
        if (phase != RunPhase.Playing) return
        if (showCoach) {
            showCoach = false
            storage.saveCoachCompleted(true)
        }
        pendingTap = true
    }

    fun step(dt: Double) {
        if (phase != RunPhase.Playing || !dt.isFinite() || dt <= 0) return
        val frame = minOf(dt, config.maxFrameDelta)
        var remaining = frame
        var applyFlap = pendingTap
        pendingTap = false
        val minimumQuantum = 1.0 / 240.0
        while (remaining > 1e-9) {
            val quantum = maxOf(config.physicsStep, minimumQuantum)
            val h = minOf(quantum, remaining)
            flightTime += h
            val integrated = FlightPhysics.integrate(
                plane.y, plane.velocityY, h, config.gravity, applyFlap,
                config.flapVelocity, config.maxUpwardSpeed, config.maxDownwardSpeed,
            )
            applyFlap = false
            plane.y = integrated.first
            plane.velocityY = integrated.second
            val dx = scrollSpeed * h
            for (index in obstacles.indices) obstacles[index].left -= dx
            for (index in obstacles.indices) {
                if (!obstacles[index].scored && Scoring.hasFullyCleared(plane, obstacles[index])) {
                    obstacles[index].scored = true
                    score += 1
                }
            }
            applyDifficulty()
            if (collided()) {
                die()
                return
            }
            val margin = config.despawnMargin
            obstacles.removeAll { it.right < -margin }
            maintainSpawns()
            remaining -= h
        }
    }

    fun applyLayout(layout: RunLayout) {
        if (!layout.planeY.isFinite() || !layout.velocityY.isFinite()) return
        plane.y = layout.planeY
        plane.velocityY = layout.velocityY
        obstacles.clear()
        obstacles.addAll(layout.obstacles)
        score = 0
        phase = RunPhase.Playing
        isNewBest = false
        pendingTap = false
        applyDifficulty()
    }

    fun endRun(finalScore: Int) {
        if (phase != RunPhase.Playing) return
        score = maxOf(0, finalScore)
        applyDifficulty()
        die()
    }

    private fun beginRun(seed: ULong) {
        rng = SeededGenerator(seed)
        runSeed = seed
        nextObstacleID = 1
        pendingTap = false
        score = 0
        flightTime = 0.0
        runID += 1
        phase = RunPhase.Playing
        isNewBest = false
        bestScore = storage.loadBestScore()
        showCoach = !storage.loadCoachCompleted()
        plane = PlaneState(config.planeX, config.planeStartY, 0.0, config.planeWidth, config.planeHeight)
        obstacles.clear()
        applyDifficulty()
        maintainSpawns()
    }

    private fun applyDifficulty() {
        val level = DifficultyRamp.level(score, config.obstacleGapHeight, config.scrollSpeed)
        scrollSpeed = level.scrollSpeed
        spawnGapHeight = level.gapHeight
    }

    private fun die() {
        phase = RunPhase.Dead
        pendingTap = false
        val previousBest = storage.loadBestScore()
        isNewBest = BestScore.isNewRecord(score, previousBest)
        if (isNewBest) {
            storage.saveBestScore(score)
            bestScore = score
        } else {
            bestScore = previousBest
        }
    }

    private fun collided(): Boolean {
        if (Collision.hitsWorldBounds(plane, config.worldHeight)) return true
        return obstacles.any { Collision.overlapsFrame(plane, it, config.worldHeight) }
    }

    private fun maintainSpawns() {
        if (!config.spawningEnabled || config.obstacleSpacing <= 0) return
        if (obstacles.isEmpty()) spawn(config.worldWidth + config.initialLead)
        val horizon = config.worldWidth + config.obstacleSpacing
        while (obstacles.isNotEmpty() && obstacles.last().left < horizon) {
            spawn(obstacles.last().left + config.obstacleSpacing)
        }
    }

    private fun spawn(left: Double) {
        obstacles += Obstacle(
            id = nextObstacleID,
            left = left,
            width = config.obstacleWidth,
            gapCenterY = randomGapCenter(),
            gapHeight = spawnGapHeight,
        )
        nextObstacleID += 1
    }

    private fun randomGapCenter(): Double {
        val half = spawnGapHeight / 2
        val low = config.gapMargin + half
        val high = config.worldHeight - config.gapMargin - half
        if (high <= low) return config.worldHeight / 2
        return low + (high - low) * rng.nextUnit()
    }
}

object GlidePilot {
    fun upcomingGapCenter(plane: PlaneState, obstacles: List<Obstacle>, fallback: Double): Double {
        val tail = plane.trailingX
        return obstacles.firstOrNull { it.trailingX > tail - 5 }?.gapCenterY ?: fallback
    }

    fun shouldTap(snapshot: GameSnapshot, fallbackTarget: Double): Boolean {
        val target = upcomingGapCenter(snapshot.plane, snapshot.obstacles, fallbackTarget)
        return snapshot.plane.y < target
    }

    fun advance(session: GameSession, stride: Double, tap: Boolean) {
        if (!stride.isFinite() || stride <= 0) return
        if (tap) session.tap()
        var remaining = stride
        while (remaining > 1e-9 && session.snapshot.phase == RunPhase.Playing) {
            val slice = minOf(remaining, session.config.maxFrameDelta)
            session.step(slice)
            remaining -= slice
        }
    }
}
