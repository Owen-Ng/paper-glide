import PaperGlideCore
import XCTest

final class RunRulesTests: XCTestCase {
    func testScoreRateSlackAndCeiling() {
        XCTAssertFalse(RunRules.exceedsScoreRate(score: 3, durationSeconds: 0))
        XCTAssertTrue(RunRules.exceedsScoreRate(score: 4, durationSeconds: 0))
        XCTAssertFalse(RunRules.exceedsScoreRate(score: 9, durationSeconds: 10))
        XCTAssertTrue(RunRules.exceedsScoreRate(score: 10, durationSeconds: 10))
        XCTAssertFalse(RunRules.exceedsScoreRate(score: 2403, durationSeconds: 3600))
        XCTAssertTrue(RunRules.exceedsScoreRate(score: 2404, durationSeconds: 3600))
        XCTAssertTrue(RunRules.exceedsScoreRate(score: 0, durationSeconds: 3600.01))
        XCTAssertTrue(RunRules.exceedsScoreRate(score: 2501, durationSeconds: 3600))
        XCTAssertTrue(RunRules.exceedsScoreRate(score: -1, durationSeconds: 10))
        XCTAssertTrue(RunRules.exceedsScoreRate(score: 1, durationSeconds: .nan))
        XCTAssertTrue(RunRules.exceedsScoreRate(score: 1, durationSeconds: -1))
    }

    func testPlayedAtWindowIsExclusiveAtTheEdges() {
        let now = TestTime.iso("2026-11-09T15:00:00Z")
        XCTAssertFalse(RunRules.isOutsidePlayedAtWindow(playedAt: now.addingTimeInterval(24 * 3600), now: now))
        XCTAssertTrue(RunRules.isOutsidePlayedAtWindow(playedAt: now.addingTimeInterval(24 * 3600 + 1), now: now))
        XCTAssertFalse(RunRules.isOutsidePlayedAtWindow(playedAt: now.addingTimeInterval(-30 * 24 * 3600), now: now))
        XCTAssertTrue(RunRules.isOutsidePlayedAtWindow(playedAt: now.addingTimeInterval(-30 * 24 * 3600 - 1), now: now))
    }

    func testLateRunDropsClosedTorontoPeriodsOnly() {
        let sundayNight = TestTime.iso("2026-11-02T04:30:00Z")
        let monday = TestTime.iso("2026-11-02T05:30:00Z")
        XCTAssertFalse(RunRules.counts(period: .daily, playedAt: sundayNight, syncedAt: monday))
        XCTAssertFalse(RunRules.counts(period: .weekly, playedAt: sundayNight, syncedAt: monday))
        XCTAssertTrue(RunRules.counts(period: .allTime, playedAt: sundayNight, syncedAt: monday))

        XCTAssertTrue(RunRules.counts(period: .daily, playedAt: sundayNight, syncedAt: sundayNight))
        XCTAssertTrue(RunRules.counts(period: .weekly, playedAt: sundayNight, syncedAt: sundayNight))
    }

    func testLocalBestNeverDecreases() {
        let storage = InMemoryGameStorage(bestScore: 0)
        func finish(_ score: Int) {
            let previous = storage.loadBestScore()
            if BestScore.isNewRecord(score: score, previousBest: previous) {
                storage.saveBestScore(score)
            }
        }
        finish(5)
        finish(3)
        finish(5)
        XCTAssertEqual(storage.loadBestScore(), 5)
        finish(0)
        XCTAssertEqual(storage.loadBestScore(), 5)
    }
}
