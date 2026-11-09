import PaperGlideCore
import XCTest

final class LeaderboardMathTests: XCTestCase {
    func testLateRunAcrossTheFallBackWeekBoundary() {
        let sundayNight = TestTime.iso("2026-11-02T04:30:00Z")
        let monday = TestTime.iso("2026-11-02T05:30:00Z")
        let runs = [
            RankedRun(userID: "late", username: "pilot", score: 12, playedAt: sundayNight),
            RankedRun(userID: "fresh", username: "ada", score: 4, playedAt: monday)
        ]
        let daily = LeaderboardMath.page(runs: runs, period: .daily, at: monday, viewerID: "late")
        let weekly = LeaderboardMath.page(runs: runs, period: .weekly, at: monday, viewerID: "late")
        let allTime = LeaderboardMath.page(runs: runs, period: .allTime, at: monday, viewerID: "late")

        XCTAssertEqual(daily.entries.map(\.username), ["ada"])
        XCTAssertNil(daily.you)
        XCTAssertEqual(weekly.entries.map(\.username), ["ada"])
        XCTAssertNil(weekly.you)
        XCTAssertEqual(allTime.entries.map(\.username), ["pilot", "ada"])
        XCTAssertEqual(allTime.you?.rank, 1)
        XCTAssertEqual(allTime.you?.score, 12)
    }

    func testOwnRankOutsideTheTop50() {
        var runs: [RankedRun] = (1...60).map { index in
            RankedRun(
                userID: "p\(index)",
                username: String(format: "p%02d", index),
                score: 1000 - index,
                playedAt: TestTime.iso("2026-11-02T05:30:00Z")
            )
        }
        runs.append(RankedRun(
            userID: "me",
            username: "me",
            score: 1,
            playedAt: TestTime.iso("2026-11-02T06:00:00Z")
        ))
        let page = LeaderboardMath.page(
            runs: runs,
            period: .allTime,
            at: TestTime.iso("2026-11-02T12:00:00Z"),
            viewerID: "me"
        )
        XCTAssertEqual(page.entries.count, 50)
        XCTAssertFalse(page.entries.contains { $0.username == "me" })
        XCTAssertEqual(page.you?.rank, 61)
        XCTAssertEqual(page.you.map { BoardCopy.outside(rank: $0.rank) }, "#61 — you")
    }

    func testTiesShareARank() {
        let when = TestTime.iso("2026-06-01T15:00:00Z")
        let runs = [
            RankedRun(userID: "a", username: "ada", score: 10, playedAt: when),
            RankedRun(userID: "b", username: "bea", score: 10, playedAt: when.addingTimeInterval(5)),
            RankedRun(userID: "c", username: "cy", score: 9, playedAt: when)
        ]
        let page = LeaderboardMath.page(runs: runs, period: .allTime, at: when, viewerID: "c")
        XCTAssertEqual(page.entries.map(\.rank), [1, 1, 3])
        XCTAssertEqual(page.entries.map(\.username), ["ada", "bea", "cy"])
        XCTAssertEqual(page.you?.rank, 3)
    }
}
