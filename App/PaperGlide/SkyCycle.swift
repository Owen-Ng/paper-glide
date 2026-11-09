import CoreGraphics
import SwiftUI
import UIKit

/// One paper-sky color. Blends are straight RGB; the cycle eases, it does not cut.
struct PaperRGB: Equatable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat

    func mix(_ other: PaperRGB, _ t: CGFloat) -> PaperRGB {
        let clamped = min(1, max(0, t))
        return PaperRGB(
            r: r + (other.r - r) * clamped,
            g: g + (other.g - g) * clamped,
            b: b + (other.b - b) * clamped
        )
    }

    var color: Color {
        Color(red: Double(r), green: Double(g), blue: Double(b))
    }

    var uiColor: UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}

/// Morning → day → sunset → night → sunrise, then morning again.
/// 15 + 20 + 15 + 15 + 10 seconds. The caller passes flight time, never wall time.
enum SkyCycle {
    static let duration = 75.0
    static let horizonFraction: CGFloat = 0.655
    static let zenithFraction: CGFloat = 0.90
    static let moonXFraction: CGFloat = 0.16
    static let moonYFraction: CGFloat = 0.86

    struct Sample: Equatable {
        var top: PaperRGB
        var bottom: PaperRGB
        var sun: PaperRGB
        var sunAlpha: CGFloat
        var sunAltitude: CGFloat
        var sunX: CGFloat
        var moonAlpha: CGFloat
        var starAlpha: CGFloat
    }

    static let collagePapers: [PaperRGB] = [
        PaperRGB(r: 0.78, g: 0.74, b: 0.68),
        PaperRGB(r: 0.73, g: 0.76, b: 0.78),
        PaperRGB(r: 0.76, g: 0.72, b: 0.74),
        PaperRGB(r: 0.80, g: 0.76, b: 0.70),
        PaperRGB(r: 0.72, g: 0.74, b: 0.70),
        PaperRGB(r: 0.77, g: 0.73, b: 0.69),
        PaperRGB(r: 0.74, g: 0.75, b: 0.77)
    ]

    static func sample(at flightTime: Double) -> Sample {
        let colors = skyColors(at: flightTime)
        let sun = sunState(at: flightTime)
        return Sample(
            top: colors.0,
            bottom: colors.1,
            sun: sun.color,
            sunAlpha: sun.alpha,
            sunAltitude: sun.altitude,
            sunX: sun.x,
            moonAlpha: scalar(moonKeys, at: flightTime),
            starAlpha: scalar(starKeys, at: flightTime)
        )
    }

    /// Y-up fraction of the world. Below the horizon the disc is not drawn.
    static func sunHeightFraction(_ sample: Sample) -> CGFloat {
        horizonFraction + sample.sunAltitude * (zenithFraction - horizonFraction)
    }

    static func cloudTint(_ sample: Sample) -> PaperRGB {
        PaperRGB(r: 0.99, g: 0.98, b: 0.96).mix(sample.bottom, 0.34)
    }

    static func buildingTint(_ base: PaperRGB, _ sample: Sample) -> PaperRGB {
        base.mix(sample.bottom, 0.50).mix(PaperRGB(r: 0.90, g: 0.87, b: 0.82), 0.30)
    }

    private struct Phase {
        var duration: Double
        var top: PaperRGB
        var bottom: PaperRGB
    }

    /// Holds, then eases across the last 30% into the next phase. t = 0 is pure morning.
    private static let phases: [Phase] = [
        Phase(
            duration: 15,
            top: PaperRGB(r: 0.74, g: 0.86, b: 0.93),
            bottom: PaperRGB(r: 0.97, g: 0.94, b: 0.86)
        ),
        Phase(
            duration: 20,
            top: PaperRGB(r: 0.48, g: 0.74, b: 0.95),
            bottom: PaperRGB(r: 0.82, g: 0.92, b: 0.98)
        ),
        Phase(
            duration: 15,
            top: PaperRGB(r: 0.46, g: 0.34, b: 0.55),
            bottom: PaperRGB(r: 0.96, g: 0.67, b: 0.48)
        ),
        Phase(
            duration: 15,
            top: PaperRGB(r: 0.31, g: 0.37, b: 0.56),
            bottom: PaperRGB(r: 0.47, g: 0.52, b: 0.68)
        ),
        Phase(
            duration: 10,
            top: PaperRGB(r: 0.63, g: 0.74, b: 0.88),
            bottom: PaperRGB(r: 0.98, g: 0.84, b: 0.78)
        )
    ]

    private struct SunKey {
        var time: Double
        var altitude: CGFloat
        var x: CGFloat
        var alpha: CGFloat
        var color: PaperRGB
    }

    /// Arc sits right of center, low → high → low, then under the horizon.
    private static let sunKeys: [SunKey] = [
        SunKey(time: 0, altitude: 0.34, x: 0.62, alpha: 1, color: PaperRGB(r: 1.00, g: 0.93, b: 0.70)),
        SunKey(time: 15, altitude: 0.78, x: 0.70, alpha: 1, color: PaperRGB(r: 1.00, g: 0.90, b: 0.60)),
        SunKey(time: 25, altitude: 1.00, x: 0.76, alpha: 1, color: PaperRGB(r: 1.00, g: 0.96, b: 0.72)),
        SunKey(time: 35, altitude: 0.68, x: 0.82, alpha: 1, color: PaperRGB(r: 1.00, g: 0.76, b: 0.42)),
        SunKey(time: 47, altitude: 0.22, x: 0.87, alpha: 1, color: PaperRGB(r: 0.98, g: 0.58, b: 0.34)),
        SunKey(time: 52, altitude: -0.05, x: 0.88, alpha: 0, color: PaperRGB(r: 0.93, g: 0.48, b: 0.32)),
        SunKey(time: 65, altitude: -0.18, x: 0.56, alpha: 0, color: PaperRGB(r: 0.99, g: 0.84, b: 0.72)),
        SunKey(time: 71, altitude: 0.10, x: 0.58, alpha: 0.7, color: PaperRGB(r: 1.00, g: 0.88, b: 0.70)),
        SunKey(time: 75, altitude: 0.34, x: 0.62, alpha: 1, color: PaperRGB(r: 1.00, g: 0.93, b: 0.70))
    ]

    private struct ScalarKey {
        var time: Double
        var value: CGFloat
    }

    private static let moonKeys: [ScalarKey] = [
        ScalarKey(time: 0, value: 0),
        ScalarKey(time: 40, value: 0),
        ScalarKey(time: 50, value: 0.65),
        ScalarKey(time: 56, value: 1),
        ScalarKey(time: 64, value: 1),
        ScalarKey(time: 69, value: 0),
        ScalarKey(time: 75, value: 0)
    ]

    private static let starKeys: [ScalarKey] = [
        ScalarKey(time: 0, value: 0),
        ScalarKey(time: 46, value: 0),
        ScalarKey(time: 54, value: 0.55),
        ScalarKey(time: 62, value: 0.55),
        ScalarKey(time: 68, value: 0),
        ScalarKey(time: 75, value: 0)
    ]

    private static func skyColors(at time: Double) -> (PaperRGB, PaperRGB) {
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
                if local <= hold || blend <= 0 {
                    return (phase.top, phase.bottom)
                }
                let eased = smooth(CGFloat((local - hold) / blend))
                return (phase.top.mix(next.top, eased), phase.bottom.mix(next.bottom, eased))
            }
            cursor = end
        }
        return (phases[0].top, phases[0].bottom)
    }

    private static func sunState(at time: Double) -> (altitude: CGFloat, x: CGFloat, alpha: CGFloat, color: PaperRGB) {
        let t = wrapped(time)
        let keys = sunKeys
        if t <= keys[0].time {
            let key = keys[0]
            return (key.altitude, key.x, key.alpha, key.color)
        }
        for index in 1..<keys.count {
            let right = keys[index]
            if t <= right.time {
                let left = keys[index - 1]
                let span = right.time - left.time
                let eased = smooth(span > 0 ? CGFloat((t - left.time) / span) : 0)
                return (
                    left.altitude + (right.altitude - left.altitude) * eased,
                    left.x + (right.x - left.x) * eased,
                    left.alpha + (right.alpha - left.alpha) * eased,
                    left.color.mix(right.color, eased)
                )
            }
        }
        let key = keys[keys.count - 1]
        return (key.altitude, key.x, key.alpha, key.color)
    }

    private static func scalar(_ keys: [ScalarKey], at time: Double) -> CGFloat {
        let t = wrapped(time)
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.time { return first.value }
        if t >= last.time { return last.value }
        for index in 1..<keys.count {
            let right = keys[index]
            if t <= right.time {
                let left = keys[index - 1]
                let span = right.time - left.time
                let eased = smooth(span > 0 ? CGFloat((t - left.time) / span) : 0)
                return left.value + (right.value - left.value) * eased
            }
        }
        return last.value
    }

    private static func wrapped(_ time: Double) -> Double {
        guard duration > 0 else { return 0 }
        var t = time.truncatingRemainder(dividingBy: duration)
        if t < 0 { t += duration }
        return t
    }

    private static func smooth(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }
}
