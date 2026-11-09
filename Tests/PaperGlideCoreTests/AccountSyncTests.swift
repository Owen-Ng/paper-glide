import PaperGlideCore
import XCTest

final class AccountSyncTests: XCTestCase {
    func testRunsWaitForANameThenDedupeByRunID() async {
        let harness = SyncHarness(ids: ["run-1", "run-1"])
        harness.sync.prepare(online: true)
        let beforeName = harness.sync.record(score: 6, durationSeconds: 12, playedAt: harness.fake.now)
        XCTAssertEqual(beforeName.pendingCount, 1)
        XCTAssertTrue(harness.fake.runs.isEmpty)

        let claimed = await harness.sync.claim("Pilot")
        XCTAssertEqual(claimed.username, "pilot")
        XCTAssertEqual(harness.fake.claimedNames, ["pilot"])
        XCTAssertEqual(harness.fake.runs.count, 1)
        XCTAssertEqual(claimed.pendingCount, 0)

        harness.sync.record(score: 99, durationSeconds: 12, playedAt: harness.fake.now)
        let again = await harness.sync.flush()
        XCTAssertEqual(harness.fake.runs.count, 1)
        XCTAssertEqual(harness.fake.runs[0].score, 6)
        XCTAssertEqual(again.pendingCount, 0)
        XCTAssertFalse(again.showsLaunchPrompt)
        XCTAssertFalse(again.deathPromptVisible)
    }

    func testTakenAndBlockedNamesDoNotEcho() async {
        let first = SyncHarness()
        first.sync.prepare(online: true)
        _ = await first.sync.bootstrap()
        _ = await first.sync.claim("pilot")

        let second = SyncHarness(fake: first.fake)
        second.sync.prepare(online: true)
        _ = await second.sync.bootstrap()
        let taken = await second.sync.claim("PILOT")
        XCTAssertEqual(taken.nameError, "that name's taken. try another")
        XCTAssertFalse(taken.nameError?.lowercased().contains("pilot") ?? false)
        XCTAssertNil(taken.username)

        let blocked = await second.sync.claim("adm1n")
        XCTAssertEqual(blocked.nameError, "that name isn't available. try another")
        XCTAssertFalse(blocked.nameError?.contains("adm1n") ?? true)
        XCTAssertTrue(second.fake.runs.isEmpty)
    }

    func testShapeErrorsStayLocalAndOfflineDefersToTheServer() async {
        let harness = SyncHarness()
        harness.sync.prepare(online: true)
        let short = await harness.sync.claim("ab")
        XCTAssertEqual(short.nameError, "at least 3 characters")
        let digit = await harness.sync.claim("1abc")
        XCTAssertEqual(digit.nameError, "start with a letter")
        let junk = await harness.sync.claim("ab!")
        XCTAssertEqual(junk.nameError, "that name won't work. try another")
        XCTAssertTrue(harness.fake.claimedNames.isEmpty)

        harness.sync.prepare(online: false)
        let offline = await harness.sync.claim("pilot")
        XCTAssertEqual(offline.nameError, "you're offline. we'll check this name when you're back")
        XCTAssertFalse(offline.nameError?.contains("pilot") ?? true)
    }

    func testNoRenameAndPromptRules() async {
        let harness = SyncHarness()
        let start = harness.sync.prepare(online: false)
        XCTAssertTrue(start.showsLaunchPrompt)
        XCTAssertTrue(start.deathPromptVisible == false)
        let dismissed = harness.sync.dismissLaunchPrompt()
        XCTAssertFalse(dismissed.showsLaunchPrompt)
        let death = harness.sync.noteNewBest()
        XCTAssertTrue(death.deathPromptVisible)
        XCTAssertFalse(harness.sync.noteNewBest().deathPromptVisible == false)

        harness.sync.prepare(online: true)
        _ = await harness.sync.bootstrap()
        let named = await harness.sync.claim("pilot")
        XCTAssertEqual(named.username, "pilot")
        let again = await harness.sync.claim("othername")
        XCTAssertEqual(again.username, "pilot")
        XCTAssertNil(again.nameError)
        XCTAssertFalse(again.showsLaunchPrompt)
        XCTAssertFalse(harness.sync.noteNewBest().deathPromptVisible)
    }

    func testOnlineLaunchDoesNotOfferTheDeathPromptUntilDismissed() async {
        let harness = SyncHarness()
        harness.sync.prepare(online: true)
        _ = await harness.sync.bootstrap()
        XCTAssertFalse(harness.sync.noteNewBest().deathPromptVisible)
        _ = harness.sync.dismissLaunchPrompt()
        XCTAssertTrue(harness.sync.noteNewBest().deathPromptVisible)
    }

    func testLateRunAcrossTorontoDSTCountsOnlyAllTime() async {
        let sundayNight = TestTime.iso("2026-11-02T04:30:00Z")
        let monday = TestTime.iso("2026-11-02T05:30:00Z")
        let harness = SyncHarness()
        harness.set(sundayNight)
        harness.sync.prepare(online: true)
        _ = await harness.sync.bootstrap()
        _ = await harness.sync.claim("pilot")

        harness.sync.prepare(online: false)
        harness.sync.record(score: 8, durationSeconds: 20, playedAt: sundayNight)
        harness.set(monday)
        _ = await harness.sync.setOnline(true)

        let daily = await harness.sync.refresh(.daily)
        let weekly = await harness.sync.refresh(.weekly)
        let allTime = await harness.sync.refresh(.allTime)
        XCTAssertEqual(daily.boards[.daily]?.page.entries.count, 0)
        XCTAssertNil(daily.boards[.daily]?.page.you)
        XCTAssertEqual(weekly.boards[.weekly]?.page.entries.count, 0)
        XCTAssertEqual(allTime.boards[.allTime]?.page.you?.score, 8)
        XCTAssertEqual(allTime.boards[.allTime]?.page.entries.map(\.username), ["pilot"])
        XCTAssertEqual(harness.fake.runs.count, 1)
    }

    func testOpenPeriodStillCountsAndASecondSyncDoesNotDuplicate() async {
        let sundayNight = TestTime.iso("2026-11-02T04:30:00Z")
        let harness = SyncHarness(ids: ["dst-run"])
        harness.set(sundayNight)
        harness.sync.prepare(online: true)
        _ = await harness.sync.bootstrap()
        _ = await harness.sync.claim("pilot")
        harness.sync.record(score: 5, durationSeconds: 12, playedAt: sundayNight)
        _ = await harness.sync.flush()
        let daily = await harness.sync.refresh(.daily)
        XCTAssertEqual(daily.boards[.daily]?.page.you?.score, 5)
        let weekly = await harness.sync.refresh(.weekly)
        XCTAssertEqual(weekly.boards[.weekly]?.page.you?.score, 5)
        _ = await harness.sync.flush()
        XCTAssertEqual(harness.fake.runs.count, 1)
    }

    func testValidationRateLimitAndStaleRuns() async {
        let harness = SyncHarness()
        let now = TestTime.iso("2026-11-09T15:00:00Z")
        harness.set(now)
        harness.sync.prepare(online: true)
        _ = await harness.sync.bootstrap()
        _ = await harness.sync.claim("pilot")

        harness.sync.record(score: 40, durationSeconds: 1, playedAt: now)
        let rejected = await harness.sync.flush()
        XCTAssertEqual(rejected.pendingCount, 0)
        XCTAssertTrue(harness.fake.runs.isEmpty)
        XCTAssertEqual(rejected.lastRunState, .rejected)

        harness.set(now.addingTimeInterval(11))
        harness.sync.record(score: 3, durationSeconds: 10, playedAt: now.addingTimeInterval(-31 * 24 * 3600))
        let stale = await harness.sync.flush()
        XCTAssertEqual(stale.pendingCount, 0)
        XCTAssertTrue(harness.fake.runs.isEmpty)
        XCTAssertEqual(stale.lastRunState, .localOnly)

        harness.set(now.addingTimeInterval(22))
        harness.sync.record(score: 4, durationSeconds: 10, playedAt: now.addingTimeInterval(22))
        let stored = await harness.sync.flush()
        XCTAssertEqual(stored.pendingCount, 0)
        XCTAssertEqual(harness.fake.runs.count, 1)

        harness.sync.record(score: 4, durationSeconds: 10, playedAt: now.addingTimeInterval(22))
        let drained = await harness.sync.flush()
        XCTAssertEqual(drained.pendingCount, 0)
        XCTAssertFalse(drained.lastFlushFailed)
        XCTAssertEqual(harness.fake.runs.map(\.score), [4, 4])
    }

    func testClaimDrainsEveryQueuedRunAcrossTheRateGap() async {
        let harness = SyncHarness()
        let now = TestTime.iso("2026-11-09T15:00:00Z")
        harness.set(now)
        harness.sync.prepare(online: true)
        _ = await harness.sync.bootstrap()
        harness.sync.record(score: 1, durationSeconds: 12, playedAt: now)
        harness.sync.record(score: 2, durationSeconds: 12, playedAt: now)
        harness.sync.record(score: 9, durationSeconds: 12, playedAt: now)
        XCTAssertEqual(harness.fake.runs.count, 0)

        let claimed = await harness.sync.claim("pilot")
        XCTAssertEqual(claimed.username, "pilot")
        XCTAssertEqual(claimed.pendingCount, 0)
        XCTAssertEqual(harness.fake.runs.map(\.score), [1, 2, 9])
        XCTAssertEqual(harness.fake.now.timeIntervalSince(now), 20, accuracy: 0.001)

        let daily = await harness.sync.refresh(.daily)
        XCTAssertEqual(daily.boards[.daily]?.page.you?.score, 9)
    }

    func testRejectedRunDoesNotConsumeTheRateSlot() async {
        let harness = SyncHarness()
        let now = TestTime.iso("2026-11-09T15:00:00Z")
        harness.set(now)
        harness.sync.prepare(online: true)
        _ = await harness.sync.bootstrap()
        _ = await harness.sync.claim("pilot")

        harness.sync.record(score: 40, durationSeconds: 1, playedAt: now)
        harness.sync.record(score: 4, durationSeconds: 12, playedAt: now)
        let flushed = await harness.sync.flush()
        XCTAssertEqual(flushed.pendingCount, 0)
        XCTAssertEqual(harness.fake.runs.map(\.score), [4])
        XCTAssertEqual(flushed.lastRunState, .synced)
        XCTAssertEqual(harness.fake.now, now)
    }

    func testDailyCapAndReconnect() async {
        let fake = FakeAccountBackend()
        fake.now = TestTime.iso("2026-11-09T15:00:00Z")
        let session = try! await fake.signInAnonymously()
        _ = try! await fake.claimUsername("pilot", accessToken: session.accessToken)
        for index in 0..<RunRules.dailySubmitCap {
            fake.now = fake.now.addingTimeInterval(11)
            let ack = try! await fake.submitRun(
                StoredRun(
                    id: "cap-\(index)",
                    score: 1,
                    durationSeconds: 5,
                    playedAt: fake.now,
                    state: .pending
                ),
                accessToken: session.accessToken
            )
            XCTAssertEqual(ack, .stored)
        }
        fake.now = fake.now.addingTimeInterval(11)
        let blocked = try! await fake.submitRun(
            StoredRun(id: "cap-over", score: 1, durationSeconds: 5, playedAt: fake.now, state: .pending),
            accessToken: session.accessToken
        )
        XCTAssertEqual(blocked, .rateLimited)
        XCTAssertEqual(fake.runs.count, RunRules.dailySubmitCap)

        let duplicate = try! await fake.submitRun(
            StoredRun(id: "cap-0", score: 50, durationSeconds: 5, playedAt: fake.now, state: .pending),
            accessToken: session.accessToken
        )
        XCTAssertEqual(duplicate, .duplicate)
        XCTAssertEqual(fake.runs[0].score, 1)
    }

    func testReconnectSubmitsTheQueuedRun() async {
        let harness = SyncHarness()
        harness.sync.prepare(online: true)
        _ = await harness.sync.bootstrap()
        _ = await harness.sync.claim("pilot")
        _ = await harness.sync.setOnline(false)
        harness.sync.record(score: 2, durationSeconds: 6, playedAt: harness.fake.now)
        XCTAssertTrue(harness.fake.runs.isEmpty)
        let back = await harness.sync.setOnline(true)
        XCTAssertEqual(back.pendingCount, 0)
        XCTAssertEqual(harness.fake.runs.map(\.score), [2])
        XCTAssertFalse(back.lastFlushFailed)
    }
}

private final class IDSource {
    var ids: [String]
    init(_ ids: [String]) { self.ids = ids }
    func next() -> String {
        if ids.isEmpty { return UUID().uuidString.lowercased() }
        return ids.removeFirst()
    }
}

private final class SyncHarness {
    let fake: FakeAccountBackend
    let sync: AccountSync

    init(fake: FakeAccountBackend? = nil, ids: [String] = []) {
        let backend = fake ?? FakeAccountBackend()
        let source = IDSource(ids)
        self.fake = backend
        sync = AccountSync(
            backend: backend,
            sessions: MemorySessionStore(),
            store: MemoryCloudStore(),
            configured: true,
            now: backend.now,
            makeID: { source.next() }
        )
        sync.pause = { [self] seconds in
            backend.now = backend.now.addingTimeInterval(seconds)
            self.sync.setNow(backend.now)
        }
    }

    func set(_ date: Date) {
        fake.now = date
        sync.setNow(date)
    }
}
