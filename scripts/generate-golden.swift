import Foundation

/// Executes PaperGlideCore (compiled into this same module) and writes
/// fixtures/golden/*.json. Doubles are stored as decimal text plus the IEEE
/// bit pattern so a Kotlin port can compare within a stated tolerance.

struct Step: Codable {
    var dt: Double
    var tap: Bool
}

struct ObstacleOut: Codable {
    var id: Int
    var left: Double
    var width: Double
    var gapCenterY: Double
    var gapHeight: Double
    var scored: Bool
}

struct PlaneOut: Codable {
    var x: Double
    var y: Double
    var velocityY: Double
}

struct SnapshotOut: Codable {
    var phase: String
    var score: Int
    var bestScore: Int
    var isNewBest: Bool
    var showCoach: Bool
    var flightTime: Double
    var scrollSpeed: Double
    var spawnGapHeight: Double
    var plane: PlaneOut
    var obstacles: [ObstacleOut]
}

struct CaseOut: Codable {
    var name: String
    var seed: UInt64
    var spawning: Bool
    var coachCompleted: Bool
    var bestScore: Int
    var steps: [Step]
    var expect: SnapshotOut
    var checkpoints: [SnapshotOut]
}

func snap(_ session: GameSession) -> SnapshotOut {
    let s = session.snapshot
    return SnapshotOut(
        phase: s.phase == .playing ? "playing" : "dead",
        score: s.score,
        bestScore: s.bestScore,
        isNewBest: s.isNewBest,
        showCoach: s.showCoach,
        flightTime: s.flightTime,
        scrollSpeed: s.scrollSpeed,
        spawnGapHeight: s.spawnGapHeight,
        plane: PlaneOut(x: s.plane.x, y: s.plane.y, velocityY: s.plane.velocityY),
        obstacles: s.obstacles.map {
            ObstacleOut(
                id: $0.id,
                left: $0.left,
                width: $0.width,
                gapCenterY: $0.gapCenterY,
                gapHeight: $0.gapHeight,
                scored: $0.scored
            )
        }
    )
}

func run(name: String, seed: UInt64, spawning: Bool, coach: Bool, best: Int, steps: [Step]) -> CaseOut {
    var config = GameConfig.standard
    config.spawningEnabled = spawning
    let storage = InMemoryGameStorage(bestScore: best, coachCompleted: coach)
    let session = GameSession(config: config, storage: storage, seed: seed)
    var checkpoints: [SnapshotOut] = [snap(session)]
    var accumulated = 0.0
    var nextMark = 0.5
    for step in steps {
        if step.tap { session.tap() }
        session.step(dt: step.dt)
        accumulated += step.dt
        if accumulated + 1e-9 >= nextMark || session.snapshot.phase == .dead {
            checkpoints.append(snap(session))
            while nextMark <= accumulated + 1e-9 { nextMark += 0.5 }
            if session.snapshot.phase == .dead { break }
        }
    }
    return CaseOut(
        name: name,
        seed: seed,
        spawning: spawning,
        coachCompleted: coach,
        bestScore: best,
        steps: steps,
        expect: snap(session),
        checkpoints: checkpoints
    )
}

func hzSteps(hz: Double, seconds: Double, tapsAt: [Double]) -> [Step] {
    let dt = 1.0 / hz
    let count = Int((seconds / dt).rounded())
    var steps: [Step] = []
    for index in 0..<count {
        let t = Double(index) * dt
        let tap = tapsAt.contains { abs($0 - t) < dt * 0.5 }
        steps.append(Step(dt: dt, tap: tap))
    }
    return steps
}

struct RampRow: Codable {
    var score: Int
    var stepIndex: Int
    var gapHeight: Double
    var scrollSpeed: Double
}

struct SkyRow: Codable {
    var flightTime: Double
    var top: [Double]
    var bottom: [Double]
    var sunAltitude: Double
    var sunX: Double
    var sunAlpha: Double
    var moonAlpha: Double
    var starAlpha: Double
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: url)
}

@main
enum GenerateGolden {
    static func main() throws {
        try generate()
    }
}

func generate() throws {
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/golden", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

let physicsSteps: [Step] = [
    Step(dt: 1.0 / 120.0, tap: true)
] + Array(repeating: Step(dt: 1.0 / 120.0, tap: false), count: 59)

let cases = [
    run(name: "physics-one-flap-half-second", seed: 1, spawning: false, coach: true, best: 0, steps: physicsSteps),
    run(
        name: "seed1-pilot-until-death",
        seed: 1,
        spawning: true,
        coach: true,
        best: 3,
        steps: pilotSteps(seed: 1, stride: 0.1, limit: 40)
    ),
    run(
        name: "seed7-scripted-taps",
        seed: 7,
        spawning: true,
        coach: true,
        best: 0,
        steps: hzSteps(hz: 60, seconds: 6, tapsAt: [0, 0.35, 0.7, 1.2, 1.8, 2.4, 3.1, 3.8, 4.6, 5.3])
    ),
    run(name: "rate-60", seed: 3, spawning: true, coach: true, best: 0, steps: hzSteps(hz: 60, seconds: 1.5, tapsAt: [0, 0.5, 1.0])),
    run(name: "rate-90", seed: 3, spawning: true, coach: true, best: 0, steps: hzSteps(hz: 90, seconds: 1.5, tapsAt: [0, 0.5, 1.0])),
    run(name: "rate-120", seed: 3, spawning: true, coach: true, best: 0, steps: hzSteps(hz: 120, seconds: 1.5, tapsAt: [0, 0.5, 1.0]))
]

for item in cases {
    try writeJSON(item, to: root.appendingPathComponent("\(item.name).json"))
}

let rampScores = [0, 4, 5, 9, 10, 59, 60, 61, 100]
let ramp = rampScores.map { score -> RampRow in
    let level = DifficultyRamp.standardLevel(score: score)
    return RampRow(score: score, stepIndex: level.stepIndex, gapHeight: level.gapHeight, scrollSpeed: level.scrollSpeed)
}
try writeJSON(ramp, to: root.appendingPathComponent("ramp.json"))

let skyTimes = [0.0, 7.5, 15, 20, 35, 47, 52, 56, 65, 71, 75, 80, 90.25]
let sky = skyTimes.map { time -> SkyRow in
    let sample = SkyMath.sample(at: time)
    return SkyRow(
        flightTime: time,
        top: [sample.top.r, sample.top.g, sample.top.b],
        bottom: [sample.bottom.r, sample.bottom.g, sample.bottom.b],
        sunAltitude: sample.sunAltitude,
        sunX: sample.sunX,
        sunAlpha: sample.sunAlpha,
        moonAlpha: sample.moonAlpha,
        starAlpha: sample.starAlpha
    )
}
try writeJSON(sky, to: root.appendingPathComponent("sky.json"))
}

func pilotSteps(seed: UInt64, stride: Double, limit: Double) -> [Step] {
    let storage = InMemoryGameStorage(bestScore: 0, coachCompleted: true)
    let session = GameSession(config: .standard, storage: storage, seed: seed)
    var steps: [Step] = []
    var elapsed = 0.0
    while elapsed < limit, session.snapshot.phase == .playing {
        let tap = GlidePilot.shouldTap(snapshot: session.snapshot, fallbackTarget: session.config.planeStartY)
        var remaining = stride
        var first = true
        while remaining > 1e-9, session.snapshot.phase == .playing {
            let slice = min(remaining, session.config.maxFrameDelta)
            let doTap = first && tap
            steps.append(Step(dt: slice, tap: doTap))
            first = false
            if doTap { session.tap() }
            session.step(dt: slice)
            remaining -= slice
        }
        elapsed += stride
    }
    return steps
}

enum SkyMath {
    struct RGB {
        var r: Double
        var g: Double
        var b: Double
        func mix(_ other: RGB, _ t: Double) -> RGB {
            let c = min(1, max(0, t))
            return RGB(r: r + (other.r - r) * c, g: g + (other.g - g) * c, b: b + (other.b - b) * c)
        }
    }
    struct Sample {
        var top: RGB
        var bottom: RGB
        var sunAltitude: Double
        var sunX: Double
        var sunAlpha: Double
        var moonAlpha: Double
        var starAlpha: Double
    }
    static let duration = 75.0
    struct Phase { var duration: Double; var top: RGB; var bottom: RGB }
    static let phases: [Phase] = [
        Phase(duration: 15, top: RGB(r: 0.74, g: 0.86, b: 0.93), bottom: RGB(r: 0.97, g: 0.94, b: 0.86)),
        Phase(duration: 20, top: RGB(r: 0.48, g: 0.74, b: 0.95), bottom: RGB(r: 0.82, g: 0.92, b: 0.98)),
        Phase(duration: 15, top: RGB(r: 0.46, g: 0.34, b: 0.55), bottom: RGB(r: 0.96, g: 0.67, b: 0.48)),
        Phase(duration: 15, top: RGB(r: 0.31, g: 0.37, b: 0.56), bottom: RGB(r: 0.47, g: 0.52, b: 0.68)),
        Phase(duration: 10, top: RGB(r: 0.63, g: 0.74, b: 0.88), bottom: RGB(r: 0.98, g: 0.84, b: 0.78))
    ]
    struct SunKey { var time: Double; var altitude: Double; var x: Double; var alpha: Double; var color: RGB }
    static let sunKeys: [SunKey] = [
        SunKey(time: 0, altitude: 0.34, x: 0.62, alpha: 1, color: RGB(r: 1.00, g: 0.93, b: 0.70)),
        SunKey(time: 15, altitude: 0.78, x: 0.70, alpha: 1, color: RGB(r: 1.00, g: 0.90, b: 0.60)),
        SunKey(time: 25, altitude: 1.00, x: 0.76, alpha: 1, color: RGB(r: 1.00, g: 0.96, b: 0.72)),
        SunKey(time: 35, altitude: 0.68, x: 0.82, alpha: 1, color: RGB(r: 1.00, g: 0.76, b: 0.42)),
        SunKey(time: 47, altitude: 0.22, x: 0.87, alpha: 1, color: RGB(r: 0.98, g: 0.58, b: 0.34)),
        SunKey(time: 52, altitude: -0.05, x: 0.88, alpha: 0, color: RGB(r: 0.93, g: 0.48, b: 0.32)),
        SunKey(time: 65, altitude: -0.18, x: 0.56, alpha: 0, color: RGB(r: 0.99, g: 0.84, b: 0.72)),
        SunKey(time: 71, altitude: 0.10, x: 0.58, alpha: 0.7, color: RGB(r: 1.00, g: 0.88, b: 0.70)),
        SunKey(time: 75, altitude: 0.34, x: 0.62, alpha: 1, color: RGB(r: 1.00, g: 0.93, b: 0.70))
    ]
    struct ScalarKey { var time: Double; var value: Double }
    static let moonKeys: [ScalarKey] = [
        ScalarKey(time: 0, value: 0), ScalarKey(time: 40, value: 0), ScalarKey(time: 50, value: 0.65),
        ScalarKey(time: 56, value: 1), ScalarKey(time: 64, value: 1), ScalarKey(time: 69, value: 0),
        ScalarKey(time: 75, value: 0)
    ]
    static let starKeys: [ScalarKey] = [
        ScalarKey(time: 0, value: 0), ScalarKey(time: 46, value: 0), ScalarKey(time: 54, value: 0.55),
        ScalarKey(time: 62, value: 0.55), ScalarKey(time: 68, value: 0), ScalarKey(time: 75, value: 0)
    ]
    static func sample(at flightTime: Double) -> Sample {
        let colors = skyColors(at: flightTime)
        let sun = sunState(at: flightTime)
        return Sample(
            top: colors.0, bottom: colors.1,
            sunAltitude: sun.0, sunX: sun.1, sunAlpha: sun.2,
            moonAlpha: scalar(moonKeys, at: flightTime),
            starAlpha: scalar(starKeys, at: flightTime)
        )
    }
    static func skyColors(at time: Double) -> (RGB, RGB) {
        let t = wrapped(time)
        var cursor = 0.0
        for index in phases.indices {
            let phase = phases[index]
            let end = cursor + phase.duration
            if t < end || index == phases.count - 1 {
                let local = min(max(0, t - cursor), phase.duration)
                let blend = phase.duration * 0.30
                let hold = phase.duration - blend
                let next = phases[(index + 1) % phases.count]
                if local <= hold || blend <= 0 { return (phase.top, phase.bottom) }
                let eased = smooth((local - hold) / blend)
                return (phase.top.mix(next.top, eased), phase.bottom.mix(next.bottom, eased))
            }
            cursor = end
        }
        return (phases[0].top, phases[0].bottom)
    }
    static func sunState(at time: Double) -> (Double, Double, Double) {
        let t = wrapped(time)
        if t <= sunKeys[0].time { return (sunKeys[0].altitude, sunKeys[0].x, sunKeys[0].alpha) }
        for index in 1..<sunKeys.count {
            let right = sunKeys[index]
            if t <= right.time {
                let left = sunKeys[index - 1]
                let span = right.time - left.time
                let eased = smooth(span > 0 ? (t - left.time) / span : 0)
                return (
                    left.altitude + (right.altitude - left.altitude) * eased,
                    left.x + (right.x - left.x) * eased,
                    left.alpha + (right.alpha - left.alpha) * eased
                )
            }
        }
        let key = sunKeys[sunKeys.count - 1]
        return (key.altitude, key.x, key.alpha)
    }
    static func scalar(_ keys: [ScalarKey], at time: Double) -> Double {
        let t = wrapped(time)
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.time { return first.value }
        if t >= last.time { return last.value }
        for index in 1..<keys.count {
            let right = keys[index]
            if t <= right.time {
                let left = keys[index - 1]
                let span = right.time - left.time
                let eased = smooth(span > 0 ? (t - left.time) / span : 0)
                return left.value + (right.value - left.value) * eased
            }
        }
        return last.value
    }
    static func wrapped(_ time: Double) -> Double {
        guard duration > 0 else { return 0 }
        var t = time.truncatingRemainder(dividingBy: duration)
        if t < 0 { t += duration }
        return t
    }
    static func smooth(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }
}
