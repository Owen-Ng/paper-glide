import Foundation

/// Server-side score checks. The SQL migration uses these same numbers.
///
/// A finished run is always kept on the device. `localOnly` runs (played too
/// far from the clock) and `reject` runs (impossible score or duration) do not
/// land on a board. A late but otherwise valid run still counts for all-time.
public enum RunRules {
    /// Added to `duration / 1.5` so the opening window can score before the
    /// steady spacing settles. The shipped ramp never clears a window faster
    /// than about one point per 1.53 seconds once scroll is capped.
    public static let slack = 3.0
    public static let maxDurationSeconds = 3600.0
    public static let hardCeiling = 2500
    public static let minSubmitGap: TimeInterval = 10
    public static let dailySubmitCap = 500
    public static let futureLimit: TimeInterval = 24 * 60 * 60
    public static let ageLimit: TimeInterval = 30 * 24 * 60 * 60

    public static func exceedsScoreRate(score: Int, durationSeconds: Double) -> Bool {
        guard score >= 0, durationSeconds.isFinite, durationSeconds >= 0 else { return true }
        if durationSeconds > maxDurationSeconds { return true }
        if score > hardCeiling { return true }
        return Double(score) > durationSeconds / 1.5 + slack
    }

    public static func isOutsidePlayedAtWindow(playedAt: Date, now: Date) -> Bool {
        playedAt > now.addingTimeInterval(futureLimit) || playedAt < now.addingTimeInterval(-ageLimit)
    }

    /// Whether a stored, accepted run counts for `period` when the board is opened at `syncedAt`.
    /// Daily and weekly require the Toronto period to still be open. All-time does not.
    public static func counts(period: BoardPeriod, playedAt: Date, syncedAt: Date) -> Bool {
        switch period {
        case .allTime:
            return true
        case .daily:
            return TorontoPeriod.dayKey(for: playedAt) == TorontoPeriod.dayKey(for: syncedAt)
        case .weekly:
            return TorontoPeriod.weekKey(for: playedAt) == TorontoPeriod.weekKey(for: syncedAt)
        }
    }
}

public enum BoardPeriod: String, Codable, CaseIterable, Hashable {
    case daily
    case weekly
    case allTime = "all_time"
}
