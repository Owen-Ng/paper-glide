import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaperGlideCore
import XCTest

final class OfflineTransport: AnalyticsTransport {
    var offline = true
    var stored: [String: [QueuedEvent]] = [:]

    func submitBatch(id: String, events: [QueuedEvent], accessToken: String) async throws -> AnalyticsAck {
        if offline { throw AnalyticsTransportError.unreachable }
        if stored[id] != nil { return .duplicate }
        stored[id] = events
        return .stored
    }

    var all: [QueuedEvent] { stored.values.flatMap { $0 } }
}

final class FakeAnalyticsTransport: AnalyticsTransport {
    var stored: [String: [QueuedEvent]] = [:]
    var calls: [String] = []
    var failNext = false
    var acceptThenFail = false
    var delayNanos: UInt64 = 0
    var tokenSeen: [String] = []

    func submitBatch(id: String, events: [QueuedEvent], accessToken: String) async throws -> AnalyticsAck {
        tokenSeen.append(accessToken)
        if delayNanos > 0 {
            try await Task.sleep(nanoseconds: delayNanos)
        }
        calls.append(id)
        if acceptThenFail {
            acceptThenFail = false
            if stored[id] == nil {
                stored[id] = events
            }
            throw AnalyticsTransportError.unreachable
        }
        if failNext {
            failNext = false
            throw AnalyticsTransportError.unreachable
        }
        if stored[id] != nil {
            return .duplicate
        }
        stored[id] = events
        return .stored
    }

    var allEvents: [QueuedEvent] {
        stored.values.flatMap { $0 }
    }
}

final class AnalyticsQueueTests: XCTestCase {
    private let context = AnalyticsContext(appVersion: "1.0", iosVersion: "18.0", deviceModel: "iPhone")

    private func makeClient(
        store: AnalyticsStateStore = MemoryAnalyticsStore(),
        transport: FakeAnalyticsTransport = FakeAnalyticsTransport(),
        token: String? = "token",
        ids: ArraySlice<String>? = nil
    ) -> (AnalyticsClient, FakeAnalyticsTransport) {
        var remaining = ids.map { Array($0) } ?? []
        let client = AnalyticsClient(
            store: store,
            transport: transport,
            context: context,
            token: { token },
            makeID: {
                if remaining.isEmpty { return UUID().uuidString.lowercased() }
                return remaining.removeFirst()
            }
        )
        return (client, transport)
    }

    func testQueuedClickCountKeepsMemoryUntilTheBatchIsSent() async {
        let (client, transport) = makeClient()
        client.recordClick(page: "leaderboard", control: "Today")
        XCTAssertEqual(client.queuedClickCount(page: "leaderboard", control: "Today"), 1)
        await client.flushNow()
        XCTAssertEqual(transport.allEvents.filter { $0.control == "Today" }.first?.count, 1)
        XCTAssertEqual(client.queuedClickCount(page: "leaderboard", control: "Today"), 0)
    }

    func testClicksStayInMemoryUntilDrain() async {
        let (client, transport) = makeClient()
        for _ in 0..<40 {
            client.recordClick(page: "playing", control: "flap")
        }
        XCTAssertEqual(client.queuedEventCount, 0)
        XCTAssertTrue(transport.calls.isEmpty)
        await client.flushNow()
        let clicks = transport.allEvents.filter { $0.kind == .click }
        XCTAssertEqual(clicks.count, 1)
        XCTAssertEqual(clicks[0].page, "playing")
        XCTAssertEqual(clicks[0].control, "flap")
        XCTAssertEqual(clicks[0].count, 40)
        XCTAssertNil(clicks[0].text)
    }

    func testFlushAtFiftyEvents() async {
        let (client, transport) = makeClient()
        for index in 0..<49 {
            await client.absorb(event(index))
        }
        XCTAssertTrue(transport.calls.isEmpty)
        XCTAssertEqual(client.queuedEventCount, 49)
        await client.absorb(event(49))
        XCTAssertEqual(transport.calls.count, 1)
        XCTAssertEqual(transport.allEvents.count, 50)
        XCTAssertEqual(client.queuedEventCount, 0)
    }

    func testFlushEverySixtySecondsAndOnBackground() async {
        let transport = FakeAnalyticsTransport()
        let (client, _) = makeClient(transport: transport)
        let start = TestTime.iso("2026-07-15T15:00:00Z")
        XCTAssertEqual(client.beginLaunch(at: start), .clean)
        await client.absorb(event(1))
        await client.flushIfDue(at: start.addingTimeInterval(59))
        XCTAssertTrue(transport.calls.isEmpty)
        await client.flushIfDue(at: start.addingTimeInterval(60))
        XCTAssertEqual(transport.calls.count, 1)

        let later = FakeAnalyticsTransport()
        let (second, _) = makeClient(transport: later)
        _ = second.beginLaunch(at: start)
        await second.absorb(event(2))
        await second.enteredBackground(at: start.addingTimeInterval(5))
        XCTAssertEqual(later.calls.count, 1)
        XCTAssertTrue(later.allEvents.contains { $0.id == "event-2" })
    }

    func testBatchPersistsAndServerDuplicateDoesNotDoubleApply() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-glide-analytics-\(UUID().uuidString)")
        let store = FileAnalyticsStore(directory: directory)
        let transport = FakeAnalyticsTransport()
        transport.acceptThenFail = true
        let (client, _) = makeClient(store: store, transport: transport, ids: ["batch-should-not-be-used", "event-7"].dropFirst(0))
        await client.absorb(event(7))
        await client.flushNow()
        XCTAssertEqual(transport.stored.count, 1)
        XCTAssertNotNil(client.inflightBatchID)
        let batchID = client.inflightBatchID

        let revived = AnalyticsClient(store: store, transport: transport, context: context, token: { "token" })
        XCTAssertEqual(revived.inflightBatchID, batchID)
        await revived.flushNow()
        XCTAssertEqual(transport.calls.count, 2)
        XCTAssertEqual(transport.stored.count, 1)
        XCTAssertEqual(transport.allEvents.count, 1)
        XCTAssertNil(revived.inflightBatchID)
        await revived.flushNow()
        XCTAssertEqual(transport.allEvents.count, 1)
        try? FileManager.default.removeItem(at: directory)
    }

    func testOfflineReportSurvivesRelaunchAndSendsOnce() async {
        let store = MemoryAnalyticsStore()
        let transport = FakeAnalyticsTransport()
        transport.failNext = true
        let (client, _) = makeClient(store: store, transport: transport)
        let result = await client.sendReport(
            category: ReportCategory.crashed.rawValue,
            text: "froze on the second window",
            at: TestTime.iso("2026-07-15T16:00:00Z"),
            timeout: 2
        )
        XCTAssertEqual(result, .savedOffline)
        XCTAssertTrue(transport.stored.isEmpty)
        XCTAssertGreaterThan(client.queuedEventCount, 0)

        let revivedTransport = transport
        revivedTransport.failNext = false
        let revived = AnalyticsClient(store: store, transport: revivedTransport, context: context, token: { "token" })
        await revived.flushNow()
        let reports = revivedTransport.allEvents.filter { $0.kind == .report }
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].text, "froze on the second window")
        XCTAssertEqual(reports[0].category, "The game crashed or froze")
        await revived.flushNow()
        XCTAssertEqual(revivedTransport.allEvents.filter { $0.kind == .report }.count, 1)
    }

    func testSlowSendIsTreatedAsOfflineAndStillDeliversOnce() async {
        let store = MemoryAnalyticsStore()
        let transport = FakeAnalyticsTransport()
        transport.delayNanos = 400_000_000
        let (client, _) = makeClient(store: store, transport: transport)
        let result = await client.sendReport(
            category: ReportCategory.idea.rawValue,
            text: "a softer landing",
            timeout: 0.05
        )
        XCTAssertEqual(result, .savedOffline)
        try? await Task.sleep(nanoseconds: 700_000_000)
        let reports = transport.allEvents.filter { $0.kind == .report }
        XCTAssertEqual(reports.count, 1)
        await client.flushNow()
        XCTAssertEqual(transport.allEvents.filter { $0.kind == .report }.count, 1)
    }

    func testReportTextIsAbsentFromClickEvents() async {
        let (client, transport) = makeClient()
        client.recordClick(page: "start", control: "report")
        _ = await client.sendReport(
            category: ReportCategory.other.rawValue,
            text: "the sky flickered",
            timeout: 2
        )
        let clicks = transport.allEvents.filter { $0.kind == .click }
        XCTAssertEqual(clicks.count, 1)
        XCTAssertNil(clicks[0].text)
        XCTAssertEqual(clicks[0].control, "report")
        let encoded = SupabaseAnalyticsTransport.json(clicks[0])
        XCTAssertNil(encoded["text"])
        XCTAssertFalse(encoded.values.contains { "\($0)".contains("flickered") })
        let report = transport.allEvents.first { $0.kind == .report }
        XCTAssertEqual(report?.text, "the sky flickered")
        XCTAssertEqual(SupabaseAnalyticsTransport.json(report!)["text"] as? String, "the sky flickered")
    }

    func testOfflineFlapsSurviveBackgroundThenForceQuit() async {
        let store = MemoryAnalyticsStore()
        let net = OfflineTransport()
        let first = AnalyticsClient(store: store, transport: net)
        _ = first.beginLaunch(at: Date())
        await first.flushNow()
        for _ in 0..<10 {
            first.recordClick(page: "playing", control: "flap")
        }
        await first.enteredBackground(at: Date())
        net.offline = false
        let second = AnalyticsClient(store: store, transport: net)
        _ = second.beginLaunch(at: Date())
        await second.flushNow()
        let flaps = net.all.filter { $0.kind == .click }.compactMap { $0.count }.reduce(0, +)
        XCTAssertEqual(net.all.filter { $0.kind == .sessionStart }.count, 2)
        XCTAssertEqual(flaps, 10)
    }

    func testReturnAfterThirtyMinutesStartsASession() async {
        let store = MemoryAnalyticsStore()
        let net = OfflineTransport()
        net.offline = false
        let client = AnalyticsClient(store: store, transport: net)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        _ = client.beginLaunch(at: start)
        await client.enteredBackground(at: start.addingTimeInterval(60))
        client.enteredForeground(at: start.addingTimeInterval(60 + 31 * 60 * 24))
        await client.flushNow()
        XCTAssertEqual(net.all.filter { $0.kind == .sessionStart }.count, 2)
    }

    func testReturnBeforeThirtyMinutesKeepsTheSession() async {
        let store = MemoryAnalyticsStore()
        let net = OfflineTransport()
        net.offline = false
        let client = AnalyticsClient(store: store, transport: net)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        _ = client.beginLaunch(at: start)
        await client.enteredBackground(at: start.addingTimeInterval(60))
        client.enteredForeground(at: start.addingTimeInterval(60 + 29 * 60))
        await client.flushNow()
        XCTAssertEqual(net.all.filter { $0.kind == .sessionStart }.count, 1)
    }

    func testMissingTokenKeepsTheQueue() async {
        let (client, transport) = makeClient(token: nil)
        await client.absorb(event(3))
        await client.flushNow()
        XCTAssertTrue(transport.calls.isEmpty)
        XCTAssertEqual(client.queuedEventCount, 1)
    }

    private func event(_ index: Int) -> QueuedEvent {
        QueuedEvent(
            id: "event-\(index)",
            kind: .click,
            occurredAt: TestTime.iso("2026-07-15T15:00:00Z"),
            sessionID: "session-1",
            page: "start",
            control: "play",
            count: 1
        )
    }
}

final class ClickMappingTests: XCTestCase {
    func testLockedControlNames() {
        XCTAssertEqual(ClickMap.start, ["play", "leaderboard", "report", "other"])
        XCTAssertEqual(ClickMap.playing, ["flap"])
        XCTAssertEqual(ClickMap.leaderboard, ["Today", "This week", "All time", "back", "other", "scroll"])
        XCTAssertEqual(ClickMap.leaderboardPeriod(.daily), "Today")
        XCTAssertEqual(ClickMap.leaderboardPeriod(.weekly), "This week")
        XCTAssertEqual(ClickMap.leaderboardPeriod(.allTime), "All time")
    }

    func testStartHitTesting() {
        let play = TapRect(x: 0, y: 0, width: 10, height: 10)
        let board = TapRect(x: 20, y: 0, width: 10, height: 10)
        let report = TapRect(x: 40, y: 0, width: 10, height: 10)
        XCTAssertEqual(ClickHit.startControl(at: TapPoint(x: 1, y: 1), play: play, leaderboard: board, report: report), "play")
        XCTAssertEqual(ClickHit.startControl(at: TapPoint(x: 25, y: 2), play: play, leaderboard: board, report: report), "leaderboard")
        XCTAssertEqual(ClickHit.startControl(at: TapPoint(x: 45, y: 2), play: play, leaderboard: board, report: report), "report")
        XCTAssertEqual(ClickHit.startControl(at: TapPoint(x: 15, y: 2), play: play, leaderboard: board, report: report), "other")
    }

    func testLeaderboardHitTestingAndOneScrollPerGesture() {
        let back = TapRect(x: 0, y: 0, width: 40, height: 20)
        let picker = TapRect(x: 0, y: 30, width: 90, height: 20)
        let list = TapRect(x: 0, y: 60, width: 90, height: 200)
        XCTAssertEqual(
            ClickHit.leaderboardControl(at: TapPoint(x: 10, y: 10), back: back, picker: picker, list: list, isDrag: false),
            "back"
        )
        XCTAssertEqual(
            ClickHit.leaderboardControl(at: TapPoint(x: 10, y: 40), back: back, picker: picker, list: list, isDrag: false),
            "Today"
        )
        XCTAssertEqual(
            ClickHit.leaderboardControl(at: TapPoint(x: 40, y: 40), back: back, picker: picker, list: list, isDrag: false),
            "This week"
        )
        XCTAssertEqual(
            ClickHit.leaderboardControl(at: TapPoint(x: 70, y: 40), back: back, picker: picker, list: list, isDrag: false),
            "All time"
        )
        XCTAssertEqual(
            ClickHit.leaderboardControl(at: TapPoint(x: 10, y: 80), back: back, picker: picker, list: list, isDrag: false),
            "other"
        )
        XCTAssertEqual(
            ClickHit.leaderboardControl(at: TapPoint(x: 10, y: 80), back: back, picker: picker, list: list, isDrag: true),
            "scroll"
        )
        XCTAssertNil(
            ClickHit.leaderboardControl(at: TapPoint(x: 10, y: 10), back: back, picker: picker, list: list, isDrag: true)
        )
    }
}

final class CrashClassificationTests: XCTestCase {
    private let context = AnalyticsContext(appVersion: "1.0 (1)", iosVersion: "18.1", deviceModel: "iPhone16,1")

    func testExitStates() {
        XCTAssertFalse(CrashExit.countsAsCrash(nil))
        XCTAssertFalse(CrashExit.countsAsCrash(.inactive))
        XCTAssertFalse(CrashExit.countsAsCrash(.background))
        XCTAssertFalse(CrashExit.countsAsCrash(.terminated))
        XCTAssertTrue(CrashExit.countsAsCrash(.active))
    }

    func testUserKillAndBackgroundTerminationAreNotCrashes() {
        for state in [SessionExit.inactive, SessionExit.background, SessionExit.terminated] {
            let store = MemoryAnalyticsStore(state: AnalyticsDiskState(
                exit: ExitRecord(sessionID: "old-session", state: state, startedAt: TestTime.iso("2026-07-15T12:00:00Z"), context: context)
            ))
            let transport = FakeAnalyticsTransport()
            let client = AnalyticsClient(store: store, transport: transport, context: context)
            let launch = client.beginLaunch(at: TestTime.iso("2026-07-15T18:00:00Z"))
            XCTAssertEqual(launch, .clean)
            XCTAssertFalse(client.noteMetricKit(diagnosticID: "diag-1", summary: "signal 11", details: "stack", at: TestTime.iso("2026-07-15T18:00:01Z")))
            let crashes = store.state.pending.filter { $0.kind == .crash }
            XCTAssertTrue(crashes.isEmpty)
        }
    }

    func testUncleanExitAndMetricKitShareOneSession() {
        let store = MemoryAnalyticsStore(state: AnalyticsDiskState(
            exit: ExitRecord(sessionID: "crashed-session", state: .active, startedAt: TestTime.iso("2026-07-15T12:00:00Z"), context: context)
        ))
        let client = AnalyticsClient(store: store, transport: FakeAnalyticsTransport(), context: context)
        let launch = client.beginLaunch(at: TestTime.iso("2026-07-15T18:00:00Z"))
        XCTAssertEqual(launch, .unclean(sessionID: "crashed-session"))
        XCTAssertTrue(client.noteMetricKit(
            diagnosticID: "diag-9",
            summary: "signal 11 exception 1/0",
            details: "call stack",
            at: TestTime.iso("2026-07-15T18:00:02Z")
        ))
        XCTAssertFalse(client.noteMetricKit(
            diagnosticID: "diag-9",
            summary: "again",
            details: "again",
            at: TestTime.iso("2026-07-15T18:00:03Z")
        ))
        let crashes = store.state.pending.filter { $0.kind == .crash }
        XCTAssertEqual(crashes.count, 2)
        XCTAssertEqual(Set(crashes.compactMap { $0.sessionID }), ["crashed-session"])
        XCTAssertEqual(crashes.compactMap { $0.crashKind }.sorted(), ["metrickit", "unclean_exit"])
    }

    func testInactiveExitIsNotACrashOnNextLaunch() {
        let store = MemoryAnalyticsStore(state: AnalyticsDiskState(
            exit: ExitRecord(sessionID: "switcher", state: .inactive, startedAt: TestTime.iso("2026-07-15T12:00:00Z"), context: context)
        ))
        let client = AnalyticsClient(store: store, transport: FakeAnalyticsTransport(), context: context)
        XCTAssertEqual(client.beginLaunch(at: TestTime.iso("2026-07-15T12:01:00Z")), .clean)
        XCTAssertTrue(store.state.pending.filter { $0.kind == .crash }.isEmpty)
    }
}

final class ReportDraftTests: XCTestCase {
    func testCopyAndLimits() {
        let banned = ["error", "ticket", "submit", "bug report"]
        for line in ReportCopy.surface {
            let lowered = line.lowercased()
            for word in banned {
                XCTAssertFalse(lowered.contains(word), "\(line) contains \(word)")
            }
        }
        XCTAssertEqual(ReportCopy.thanks, "thanks. we got it")
        XCTAssertEqual(ReportCopy.saved, "saved. we'll send it when you're back online")
        XCTAssertEqual(ReportCategory.allCases.count, 5)
        XCTAssertFalse(ReportDraftRules.sendEnabled(category: nil))
        XCTAssertTrue(ReportDraftRules.sendEnabled(category: ReportCategory.looks.rawValue))
        XCTAssertFalse(ReportDraftRules.showsCounter(String(repeating: "a", count: 399)))
        XCTAssertTrue(ReportDraftRules.showsCounter(String(repeating: "a", count: 400)))
        XCTAssertEqual(ReportDraftRules.counter(String(repeating: "a", count: 412)), "412/500")
        XCTAssertEqual(ReportDraftRules.clamped(String(repeating: "b", count: 640)).count, 500)
        XCTAssertFalse(ReportDraftRules.shouldConfirmDiscard(text: ""))
        XCTAssertTrue(ReportDraftRules.shouldConfirmDiscard(text: "oops"))
    }
}

final class AnalyticsHTTPTests: XCTestCase {
    func testBatchPostsTheAnonKeyAndBatchID() async throws {
        AnalyticsURLStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalyticsURLStub.self]
        let session = URLSession(configuration: configuration)
        let transport = SupabaseAnalyticsTransport(
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "test-anon-key",
            urlSession: session
        )
        let event = QueuedEvent(
            id: "11111111-1111-1111-1111-111111111111",
            kind: .sessionStart,
            occurredAt: TestTime.iso("2026-07-15T15:00:00Z"),
            sessionID: "22222222-2222-2222-2222-222222222222",
            context: AnalyticsContext(appVersion: "1.0", iosVersion: "18.0", deviceModel: "iPhone")
        )
        let ack = try await transport.submitBatch(
            id: "33333333-3333-3333-3333-333333333333",
            events: [event],
            accessToken: "user-token"
        )
        XCTAssertEqual(ack, .stored)
        XCTAssertEqual(AnalyticsURLStub.paths, ["/rest/v1/rpc/submit_analytics_batch"])
        XCTAssertEqual(AnalyticsURLStub.apiKeys, ["test-anon-key"])
        XCTAssertEqual(AnalyticsURLStub.authorizations, ["Bearer user-token"])
        XCTAssertTrue(AnalyticsURLStub.body.contains("33333333-3333-3333-3333-333333333333"))
        XCTAssertFalse(AnalyticsURLStub.body.contains("service_role"))
    }
}

private final class AnalyticsURLStub: URLProtocol {
    static var paths: [String] = []
    static var apiKeys: [String] = []
    static var authorizations: [String] = []
    static var body = ""

    static func reset() {
        paths = []
        apiKeys = []
        authorizations = []
        body = ""
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.paths.append(request.url?.path ?? "")
        Self.apiKeys.append(request.value(forHTTPHeaderField: "apikey") ?? "")
        Self.authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        Self.body = String(data: Self.bodyData(request), encoding: .utf8) ?? ""
        let payload: [String: Any] = ["ok": true, "result": "stored"]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
