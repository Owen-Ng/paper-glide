import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GoTrue anonymous session plus PostgREST RPCs.
/// The anon key travels as `apikey`. The service-role key is never read.
public final class SupabaseHTTPBackend: AccountBackend {
    public let baseURL: URL
    public let anonKey: String
    public let urlSession: URLSession
    public var now: () -> Date

    public init(baseURL: URL, anonKey: String, urlSession: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.urlSession = urlSession
        self.now = now
    }

    public func signInAnonymously() async throws -> StoredSession {
        let data = try await send(path: "/auth/v1/signup", token: nil, body: [:], allowEmpty: true)
        return try decodeSession(data)
    }

    public func refresh(refreshToken: String) async throws -> StoredSession {
        let data = try await send(
            path: "/auth/v1/token?grant_type=refresh_token",
            token: nil,
            body: ["refresh_token": refreshToken]
        )
        return try decodeSession(data)
    }

    public func fetchUsername(accessToken: String) async throws -> String? {
        let data = try await send(path: "/rest/v1/rpc/my_username", token: accessToken, body: [:])
        let json = try jsonObject(data)
        guard truth(json["ok"]) else { throw AccountTransportError.badResponse }
        return json["username"] as? String
    }

    public func claimUsername(_ name: String, accessToken: String) async throws -> UsernameClaim {
        let data = try await send(
            path: "/rest/v1/rpc/claim_username",
            token: accessToken,
            body: ["raw_name": name]
        )
        let json = try jsonObject(data)
        if truth(json["ok"]), let saved = json["username"] as? String, !saved.isEmpty {
            if json["result"] as? String == "already_named" {
                return .alreadyNamed(saved)
            }
            return .saved(saved)
        }
        guard let code = json["error"] as? String, let rejection = UsernameRejection(rawValue: snake(code)) else {
            throw AccountTransportError.badResponse
        }
        return .rejected(rejection)
    }

    public func submitRun(_ run: StoredRun, accessToken: String) async throws -> SubmitAck {
        let data = try await send(
            path: "/rest/v1/rpc/submit_run",
            token: accessToken,
            body: [
                "run_id": run.id,
                "score": run.score,
                "duration_seconds": run.durationSeconds,
                "played_at": iso8601(run.playedAt)
            ]
        )
        let json = try jsonObject(data)
        if truth(json["ok"]) {
            return (json["result"] as? String) == "duplicate" ? .duplicate : .stored
        }
        switch json["error"] as? String {
        case "rejected": return .rejected
        case "rate_limited": return .rateLimited
        case "needs_name": return .needsName
        case "stale": return .stale
        default: throw AccountTransportError.badResponse
        }
    }

    public func leaderboard(_ period: BoardPeriod, accessToken: String) async throws -> LeaderboardPage {
        let data = try await send(
            path: "/rest/v1/rpc/leaderboard",
            token: accessToken,
            body: ["period": period.rawValue]
        )
        let json = try jsonObject(data)
        guard truth(json["ok"]) else { throw AccountTransportError.badResponse }
        let fetchedAt = date(from: json["fetched_at"]) ?? now()
        let entries = (json["entries"] as? [Any] ?? []).compactMap(entry(from:))
        let you = entry(from: json["you"])
        return LeaderboardPage(entries: entries, you: you, fetchedAt: fetchedAt)
    }

    private func send(path: String, token: String?, body: [String: Any], allowEmpty: Bool = false) async throws -> Data {
        let root = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard let url = URL(string: root + path) else { throw AccountTransportError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? anonKey)", forHTTPHeaderField: "Authorization")
        if body.isEmpty && allowEmpty {
            request.httpBody = Data("{}".utf8)
        } else {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AccountTransportError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw AccountTransportError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AccountTransportError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else { throw AccountTransportError.badResponse }
        return data
    }

    private func decodeSession(_ data: Data) throws -> StoredSession {
        let json = try jsonObject(data)
        guard
            let access = json["access_token"] as? String,
            let refresh = json["refresh_token"] as? String,
            let user = json["user"] as? [String: Any],
            let userID = user["id"] as? String
        else {
            throw AccountTransportError.badResponse
        }
        let expiresAt: Date
        if let stamp = json["expires_at"] as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: stamp)
        } else if let stamp = json["expires_at"] as? Int {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(stamp))
        } else if let seconds = json["expires_in"] as? TimeInterval {
            expiresAt = now().addingTimeInterval(seconds)
        } else if let seconds = json["expires_in"] as? Int {
            expiresAt = now().addingTimeInterval(TimeInterval(seconds))
        } else {
            expiresAt = now().addingTimeInterval(3600)
        }
        return StoredSession(
            userID: userID,
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresAt
        )
    }

    private func entry(from value: Any?) -> BoardEntry? {
        guard let json = value as? [String: Any],
              let username = json["username"] as? String,
              let score = intValue(json["score"]),
              let rank = intValue(json["rank"]) else {
            return nil
        }
        return BoardEntry(rank: rank, username: username, score: score, isYou: false)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func date(from value: Any?) -> Date? {
        if let value = value as? TimeInterval { return Date(timeIntervalSince1970: value) }
        if let value = value as? Int { return Date(timeIntervalSince1970: TimeInterval(value)) }
        if let value = value as? NSNumber { return Date(timeIntervalSince1970: value.doubleValue) }
        if let value = value as? String { return parseISO(value) }
        return nil
    }

    private func parseISO(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AccountTransportError.badResponse
        }
        return json
    }

    private func truth(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }

    private func snake(_ code: String) -> String {
        switch code {
        case "too_short": return "tooShort"
        case "must_start_with_letter": return "mustStartWithLetter"
        case "invalid": return "invalid"
        case "taken": return "taken"
        case "unavailable": return "unavailable"
        default: return code
        }
    }
}
