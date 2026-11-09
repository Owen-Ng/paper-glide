/// Silent opening and scroll steps. Gravity, flap, and the speed caps are not levers.
///
/// From the start-of-run gap and scroll, every fifth point shortens the next
/// spawned window by 5 and speeds the page up by 4. Twelve steps hold: the
/// shipped 218 / 148 run reaches 168 / 196 at score 60 and stays there.
/// A base that already sits past a cap is left alone so test layouts can still
/// request a faster page. Windows that already exist are never rewritten.
public enum DifficultyRamp {
    public static let pointsPerStep = 5
    public static let maxStepIndex = 12
    public static let gapDropPerStep = 5.0
    public static let scrollGainPerStep = 4.0
    public static let minimumGapHeight = 168.0
    public static let maximumScrollSpeed = 196.0

    public static func standardLevel(score: Int) -> DifficultyLevel {
        level(
            score: score,
            baseGap: GameConfig.standard.obstacleGapHeight,
            baseScroll: GameConfig.standard.scrollSpeed
        )
    }

    public static func level(score: Int, baseGap: Double, baseScroll: Double) -> DifficultyLevel {
        let stepIndex = min(max(score, 0) / pointsPerStep, maxStepIndex)
        var gap = baseGap - gapDropPerStep * Double(stepIndex)
        var scroll = baseScroll + scrollGainPerStep * Double(stepIndex)
        if baseGap >= minimumGapHeight {
            gap = max(minimumGapHeight, gap)
        }
        if baseScroll <= maximumScrollSpeed {
            scroll = min(maximumScrollSpeed, scroll)
        }
        return DifficultyLevel(stepIndex: stepIndex, gapHeight: gap, scrollSpeed: scroll)
    }
}

public struct DifficultyLevel: Equatable {
    public var stepIndex: Int
    public var gapHeight: Double
    public var scrollSpeed: Double

    public init(stepIndex: Int, gapHeight: Double, scrollSpeed: Double) {
        self.stepIndex = stepIndex
        self.gapHeight = gapHeight
        self.scrollSpeed = scrollSpeed
    }
}
