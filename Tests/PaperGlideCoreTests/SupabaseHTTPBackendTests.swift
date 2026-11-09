import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaperGlideCore
import XCTest

final class SupabaseHTTPBackendTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SupabaseURLStub.reset()
        SupabaseURLStub.fake.now = TestTime.iso("2026-11-09T15:00:00Z")
    }

    override func tearDown() {
        SupabaseURLStub.reset()
        super.tearDown()
    }

    func testClientSignsInClaimsSubmitsAndDedupesAgainstTheFake() async throws {
        let backend = makeBackend()
        let session = try await backend.signInAnonymously()
        let saved = try await backend.claimUsername("Ada", accessToken: session.accessToken)
        XCTAssertEqual(saved, .saved("ada"))

        let runID = "6f1b3a2e-7c44-4d2a-9a11-0c5e8b7d4a21"
        let run = StoredRun(
            id: runID,
            score: 6,
            durationSeconds: 12,
            playedAt: SupabaseURLStub.fake.now,
            state: .pending
        )
        let stored = try await backend.submitRun(run, accessToken: session.accessToken)
        XCTAssertEqual(stored, .stored)
        let duplicate = try await backend.submitRun(
            StoredRun(id: runID, score: 99, durationSeconds: 12, playedAt: SupabaseURLStub.fake.now, state: .pending),
            accessToken: session.accessToken
        )
        XCTAssertEqual(duplicate, .duplicate)
        XCTAssertEqual(SupabaseURLStub.fake.runs.count, 1)
        XCTAssertEqual(SupabaseURLStub.fake.runs[0].score, 6)

        let blocked = try await backend.claimUsername("4dm1n", accessToken: session.accessToken)
        XCTAssertEqual(blocked, .alreadyNamed("ada"))

        let board = try await backend.leaderboard(.daily, accessToken: session.accessToken)
        XCTAssertEqual(board.entries.map(\.username), ["ada"])
        XCTAssertEqual(board.you?.score, 6)

        XCTAssertFalse(SupabaseURLStub.capturedAPIKeys.contains { $0.contains("service_role") })
        XCTAssertEqual(Set(SupabaseURLStub.capturedAPIKeys), ["test-anon-key"])
        XCTAssertTrue(SupabaseURLStub.capturedPaths.contains("/auth/v1/signup"))
        XCTAssertTrue(SupabaseURLStub.capturedPaths.contains("/rest/v1/rpc/submit_run"))
    }

    func testTakenResponseDoesNotEchoTheName() async throws {
        let backend = makeBackend()
        let first = try await backend.signInAnonymously()
        _ = try await backend.claimUsername("pilot", accessToken: first.accessToken)
        let second = try await backend.signInAnonymously()
        let taken = try await backend.claimUsername("pilot", accessToken: second.accessToken)
        XCTAssertEqual(taken, .rejected(.taken))
        let body = SupabaseURLStub.claimBodies.last ?? ""
        XCTAssertFalse(body.contains("pilot"))
    }

    func testSyncEngineUsesTheHTTPClient() async throws {
        let backend = makeBackend()
        let sync = AccountSync(
            backend: backend,
            sessions: MemorySessionStore(),
            store: MemoryCloudStore(),
            configured: true,
            now: SupabaseURLStub.fake.now,
            makeID: { "3b1f0a74-6d2e-4c8b-8f55-91a0c6d27e10" }
        )
        sync.prepare(online: true)
        _ = await sync.bootstrap()
        let named = await sync.claim("pilot")
        XCTAssertEqual(named.username, "pilot")
        sync.record(score: 5, durationSeconds: 12, playedAt: SupabaseURLStub.fake.now)
        let flushed = await sync.flush()
        XCTAssertEqual(flushed.pendingCount, 0)
        sync.record(score: 9, durationSeconds: 12, playedAt: SupabaseURLStub.fake.now)
        _ = await sync.flush()
        XCTAssertEqual(SupabaseURLStub.fake.runs.count, 1)
        XCTAssertEqual(SupabaseURLStub.fake.runs[0].score, 5)
        let board = await sync.refresh(.allTime)
        XCTAssertEqual(board.boards[.allTime]?.page.you?.score, 5)
    }

    private func makeBackend() -> SupabaseHTTPBackend {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SupabaseURLStub.self]
        let session = URLSession(configuration: configuration)
        return SupabaseHTTPBackend(
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "test-anon-key",
            urlSession: session,
            now: { SupabaseURLStub.fake.now }
        )
    }
}

final class SupabaseURLStub: URLProtocol {
    static var fake = FakeAccountBackend()
    static var capturedAPIKeys: [String] = []
    static var capturedPaths: [String] = []
    static var claimBodies: [String] = []

    static func reset() {
        fake = FakeAccountBackend()
        capturedAPIKeys = []
        capturedPaths = []
        claimBodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let query = request.url?.query.map { "?\($0)" } ?? ""
        Self.capturedPaths.append(path + query)
        if let key = request.value(forHTTPHeaderField: "apikey") {
            Self.capturedAPIKeys.append(key)
        }
        let body = Self.bodyData(request)
        do {
            let (status, payload) = try respond(path: path, body: body)
            finish(status, payload)
        } catch {
            finish(500, ["message": "stub failed"])
        }
    }

    override func stopLoading() {}

    private func respond(path: String, body: Data) throws -> (Int, Any) {
        let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        if path.hasSuffix("/auth/v1/signup") {
            let session = try Self.fake.signInNow()
            return (200, sessionJSON(session))
        }
        if path.hasSuffix("/auth/v1/token") {
            let session = try Self.fake.refreshNow(json["refresh_token"] as? String ?? "")
            return (200, sessionJSON(session))
        }
        let token = bearer(request)
        if path.hasSuffix("/rpc/my_username") {
            let name = try Self.fake.usernameNow(token)
            let payload: [String: Any] = ["ok": true, "username": name ?? NSNull()]
            return (200, payload)
        }
        if path.hasSuffix("/rpc/claim_username") {
            let raw = json["raw_name"] as? String ?? ""
            let result = try Self.fake.claimNow(raw, accessToken: token)
            switch result {
            case .saved(let name):
                return (200, ["ok": true, "result": "saved", "username": name])
            case .alreadyNamed(let name):
                return (200, ["ok": true, "result": "already_named", "username": name])
            case .rejected(let reason):
                Self.claimBodies.append(rejectionJSON(reason))
                return (200, ["ok": false, "error": wire(reason)])
            }
        }
        if path.hasSuffix("/rpc/submit_run") {
            let run = StoredRun(
                id: json["run_id"] as? String ?? "",
                score: integer(json["score"]),
                durationSeconds: double(json["duration_seconds"]),
                playedAt: parseISO(json["played_at"] as? String ?? "") ?? Self.fake.now,
                state: .pending
            )
            let ack = try Self.fake.submitNow(run, accessToken: token)
            switch ack {
            case .stored: return (200, ["ok": true, "result": "stored"])
            case .duplicate: return (200, ["ok": true, "result": "duplicate"])
            case .rejected: return (200, ["ok": false, "error": "rejected"])
            case .rateLimited: return (200, ["ok": false, "error": "rate_limited"])
            case .needsName: return (200, ["ok": false, "error": "needs_name"])
            case .stale: return (200, ["ok": false, "error": "stale"])
            }
        }
        if path.hasSuffix("/rpc/leaderboard") {
            let period = BoardPeriod(rawValue: json["period"] as? String ?? "") ?? .daily
            let page = try Self.fake.boardNow(period, accessToken: token)
            var payload: [String: Any] = [
                "ok": true,
                "fetched_at": page.fetchedAt.timeIntervalSince1970,
                "entries": page.entries.map { ["rank": $0.rank, "username": $0.username, "score": $0.score] }
            ]
            if let you = page.you {
                payload["you"] = ["rank": you.rank, "username": you.username, "score": you.score]
            } else {
                payload["you"] = NSNull()
            }
            return (200, payload)
        }
        return (404, ["message": "unknown"])
    }

    private func sessionJSON(_ session: StoredSession) -> [String: Any] {
        [
            "access_token": session.accessToken,
            "refresh_token": session.refreshToken,
            "expires_at": session.expiresAt.timeIntervalSince1970,
            "user": ["id": session.userID]
        ]
    }

    private func rejectionJSON(_ reason: UsernameRejection) -> String {
        switch reason {
        case .tooShort: return "{\"ok\":false,\"error\":\"too_short\"}"
        case .mustStartWithLetter: return "{\"ok\":false,\"error\":\"must_start_with_letter\"}"
        case .invalid: return "{\"ok\":false,\"error\":\"invalid\"}"
        case .taken: return "{\"ok\":false,\"error\":\"taken\"}"
        case .unavailable: return "{\"ok\":false,\"error\":\"unavailable\"}"
        }
    }

    private func wire(_ reason: UsernameRejection) -> String {
        switch reason {
        case .tooShort: return "too_short"
        case .mustStartWithLetter: return "must_start_with_letter"
        case .invalid: return "invalid"
        case .taken: return "taken"
        case .unavailable: return "unavailable"
        }
    }

    private func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }

    private func bearer(_ request: URLRequest) -> String {
        let header = request.value(forHTTPHeaderField: "Authorization") ?? ""
        return header.replacingOccurrences(of: "Bearer ", with: "")
    }

    private func parseISO(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func finish(_ status: Int, _ payload: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.supabase.co")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func fail(_ status: Int, _ payload: [String: Any]) {
        finish(status, payload)
    }

    private static func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
