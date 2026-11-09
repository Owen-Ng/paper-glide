import PaperGlideCore
import XCTest

final class BoardPresenterTests: XCTestCase {
    func testOfflineWithoutCacheShowsLocalBest() {
        let view = BoardPresenter.present(
            period: .daily,
            cached: nil,
            loading: false,
            online: false,
            loadFailed: false,
            syncFailed: true,
            username: "ada",
            localBest: 7,
            cacheTimeText: nil
        )
        XCTAssertTrue(view.showOfflineEmpty)
        XCTAssertEqual(view.localBestLine, "local best 7")
        XCTAssertEqual(view.banners, ["couldn't sync your scores. retry"])
        XCTAssertFalse(view.canPullToRefresh)
        XCTAssertEqual(view.caption, "resets at midnight, toronto time")
        XCTAssertFalse(view.showSkeleton)
    }

    func testOfflineCacheNamesTheFetchTime() {
        let page = LeaderboardPage(entries: [], you: nil, fetchedAt: TestTime.iso("2026-11-09T15:00:00Z"))
        let view = BoardPresenter.present(
            period: .weekly,
            cached: CachedBoard(page: page),
            loading: false,
            online: false,
            loadFailed: false,
            syncFailed: false,
            username: "ada",
            localBest: 0,
            cacheTimeText: "Nov 9, 3:00 PM"
        )
        XCTAssertEqual(view.banners, ["offline. showing scores from Nov 9, 3:00 PM"])
        XCTAssertEqual(view.emptyTitle, "no score this week yet")
        XCTAssertEqual(view.caption, "resets monday at midnight, toronto time")
        XCTAssertFalse(view.showOfflineEmpty)
    }

    func testEmptyDailyCopyAndUnnamedPrompt() {
        let page = LeaderboardPage(entries: [], you: nil, fetchedAt: Date())
        let named = BoardPresenter.present(
            period: .daily,
            cached: CachedBoard(page: page),
            loading: false,
            online: true,
            loadFailed: false,
            syncFailed: false,
            username: "ada",
            localBest: 0,
            cacheTimeText: nil
        )
        XCTAssertEqual(named.emptyTitle, "no score today yet")
        XCTAssertEqual(named.emptyDetail, "no scores yet today. be the first")

        let unnamed = BoardPresenter.present(
            period: .daily,
            cached: CachedBoard(page: page),
            loading: false,
            online: true,
            loadFailed: false,
            syncFailed: false,
            username: nil,
            localBest: 0,
            cacheTimeText: nil
        )
        XCTAssertEqual(unnamed.emptyTitle, "pick a name to join the board")
    }

    func testLoadingStates() {
        let skeleton = BoardPresenter.present(
            period: .allTime,
            cached: nil,
            loading: true,
            online: true,
            loadFailed: false,
            syncFailed: false,
            username: nil,
            localBest: 0,
            cacheTimeText: nil
        )
        XCTAssertTrue(skeleton.showSkeleton)
        XCTAssertNil(skeleton.caption)

        let page = LeaderboardPage(entries: [], you: nil, fetchedAt: Date())
        let refreshing = BoardPresenter.present(
            period: .daily,
            cached: CachedBoard(page: page),
            loading: true,
            online: true,
            loadFailed: false,
            syncFailed: false,
            username: "ada",
            localBest: 0,
            cacheTimeText: nil
        )
        XCTAssertEqual(refreshing.emptyTitle, "syncing...")
        XCTAssertFalse(refreshing.showSkeleton)
        XCTAssertTrue(refreshing.canPullToRefresh)
    }

    func testLoadFailureKeepsCachedRowsAndOutsideLine() {
        let you = BoardEntry(rank: 128, username: "ada", score: 3, isYou: true)
        let page = LeaderboardPage(
            entries: [BoardEntry(rank: 1, username: "bea", score: 40, isYou: false)],
            you: you,
            fetchedAt: Date()
        )
        let view = BoardPresenter.present(
            period: .allTime,
            cached: CachedBoard(page: page),
            loading: false,
            online: true,
            loadFailed: true,
            syncFailed: false,
            username: "ada",
            localBest: 3,
            cacheTimeText: nil
        )
        XCTAssertEqual(view.entries.map(\.username), ["bea"])
        XCTAssertEqual(view.outsideLine, "#128 — you")
        XCTAssertEqual(view.outsideScore, 3)
        XCTAssertEqual(view.banners, ["couldn't load the board. Retry"])
    }
}
