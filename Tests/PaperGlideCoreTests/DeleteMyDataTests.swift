import PaperGlideCore
import XCTest

final class DeleteMyDataTests: XCTestCase {
    func testOfflineDeleteDoesNotCallOrClear() async {
        let backend = FakeAccountBackend()
        let store = MemoryCloudStore()
        let sync = AccountSync(
            backend: backend,
            sessions: MemorySessionStore(),
            store: store,
            configured: false
        )
        sync.prepare(online: true)
        sync.record(score: 4, durationSeconds: 8, playedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let (result, snapshot) = await sync.deleteMyData()
        XCTAssertEqual(result, .offline)
        XCTAssertEqual(backend.deleteCalls, 0)
        XCTAssertEqual(snapshot.pendingCount, 1)
        XCTAssertEqual(store.loadRuns().count, 1)
    }

    func testSuccessfulDeleteWipesOnlyTheCaller() async throws {
        let backend = FakeAccountBackend()
        backend.now = Date(timeIntervalSince1970: 1_700_000_000)
        let other = try backend.signInNow()
        _ = try backend.claimNow("other", accessToken: other.accessToken)
        _ = try backend.submitNow(
            StoredRun(id: "other-run", score: 3, durationSeconds: 9, playedAt: backend.now, state: .pending),
            accessToken: other.accessToken
        )

        let sessions = MemorySessionStore()
        let store = MemoryCloudStore()
        let sync = AccountSync(
            backend: backend,
            sessions: sessions,
            store: store,
            configured: true,
            now: backend.now,
            makeID: { "run-caller" }
        )
        sync.prepare(online: true)
        _ = await sync.bootstrap()
        let named = await sync.claim("pilot")
        XCTAssertEqual(named.username, "pilot")
        sync.record(score: 5, durationSeconds: 12, playedAt: backend.now)
        let (result, snapshot) = await sync.deleteMyData()
        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(backend.deleteCalls, 1)
        XCTAssertNil(snapshot.username)
        XCTAssertNil(snapshot.userID)
        XCTAssertEqual(snapshot.pendingCount, 0)
        XCTAssertTrue(snapshot.showsLaunchPrompt)
        XCTAssertNil(sessions.load())
        XCTAssertEqual(store.loadRuns(), [])
        XCTAssertNil(store.loadUsername())
        XCTAssertNil(store.loadUserID())
        XCTAssertEqual(backend.users[other.userID]?.username, "other")
        XCTAssertEqual(backend.runs.map(\.id), ["other-run"])
    }

    func testFailedDeleteLeavesLocalRows() async {
        let backend = FakeAccountBackend()
        backend.failDelete = true
        backend.now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions = MemorySessionStore()
        let store = MemoryCloudStore()
        let sync = AccountSync(
            backend: backend,
            sessions: sessions,
            store: store,
            configured: true,
            now: backend.now
        )
        sync.prepare(online: true)
        _ = await sync.bootstrap()
        sync.record(score: 2, durationSeconds: 6, playedAt: backend.now)
        let (result, snapshot) = await sync.deleteMyData()
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(snapshot.pendingCount, 1)
        XCTAssertEqual(store.loadRuns().count, 1)
        XCTAssertNotNil(sessions.load())
    }

    func testDiscardClearsTheQueueWithoutSending() async {
        let transport = CountingAnalyticsTransport()
        let client = AnalyticsClient(
            store: MemoryAnalyticsStore(),
            transport: transport,
            token: { "token" },
            makeID: { "queued-event" }
        )
        await client.absorb(QueuedEvent(
            id: "queued-event",
            kind: .report,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            category: "Something else",
            text: "keep me until delete"
        ))
        XCTAssertEqual(client.queuedEventCount, 1)
        await client.holdSends()
        client.discardLocalQueue()
        XCTAssertEqual(client.queuedEventCount, 0)
        await client.flushNow()
        XCTAssertEqual(transport.batches, 0)
    }
}

private final class CountingAnalyticsTransport: AnalyticsTransport {
    var batches = 0

    func submitBatch(id: String, events: [QueuedEvent], accessToken: String) async throws -> AnalyticsAck {
        batches += 1
        return .stored
    }
}
