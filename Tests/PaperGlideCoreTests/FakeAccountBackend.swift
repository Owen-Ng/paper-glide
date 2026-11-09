import Foundation
import PaperGlideCore

/// In-memory stand-in for the SQL RPCs. Unit tests run this instead of a live project.
final class FakeAccountBackend: AccountBackend {
    struct User {
        var id: String
        var username: String?
        var lastSubmitAt: Date?
        var submitDay: String?
        var submitCount = 0
    }

    struct Row {
        var id: String
        var userID: String
        var score: Int
        var durationSeconds: Double
        var playedAt: Date
    }

    var now = Date(timeIntervalSince1970: 0)
    var users: [String: User] = [:]
    var runs: [Row] = []
    var accessTokens: [String: String] = [:]
    var refreshTokens: [String: String] = [:]
    var claimedNames: [String] = []
    var seenAPIKeys: [String] = []
    var failNextSignIn = false
    private var minted = 0

    func signInAnonymously() async throws -> StoredSession { try signInNow() }
    func refresh(refreshToken: String) async throws -> StoredSession { try refreshNow(refreshToken) }
    func fetchUsername(accessToken: String) async throws -> String? { try usernameNow(accessToken) }
    func claimUsername(_ name: String, accessToken: String) async throws -> UsernameClaim {
        try claimNow(name, accessToken: accessToken)
    }
    func submitRun(_ run: StoredRun, accessToken: String) async throws -> SubmitAck {
        try submitNow(run, accessToken: accessToken)
    }
    func leaderboard(_ period: BoardPeriod, accessToken: String) async throws -> LeaderboardPage {
        try boardNow(period, accessToken: accessToken)
    }

    func signInNow() throws -> StoredSession {
        if failNextSignIn {
            failNextSignIn = false
            throw AccountTransportError.unreachable
        }
        minted += 1
        let id = "user-\(minted)"
        users[id] = User(id: id)
        return issue(for: id)
    }

    func refreshNow(_ refreshToken: String) throws -> StoredSession {
        guard let userID = refreshTokens[refreshToken] else { throw AccountTransportError.unauthorized }
        return issue(for: userID)
    }

    func usernameNow(_ accessToken: String) throws -> String? {
        try user(for: accessToken).username
    }

    func claimNow(_ name: String, accessToken: String) throws -> UsernameClaim {
        let userID = try user(for: accessToken).id
        claimedNames.append(name)
        if let existing = users[userID]?.username {
            return .alreadyNamed(existing)
        }
        if let problem = UsernameRules.problem(name) {
            return .rejected(problem)
        }
        let normalized = UsernameRules.normalize(name)
        if users.values.contains(where: { $0.username == normalized }) {
            return .rejected(.taken)
        }
        users[userID]?.username = normalized
        return .saved(normalized)
    }

    func submitNow(_ run: StoredRun, accessToken: String) throws -> SubmitAck {
        let userID = try user(for: accessToken).id
        guard users[userID]?.username != nil else { return .needsName }
        if let existing = runs.first(where: { $0.id == run.id }) {
            return existing.userID == userID ? .duplicate : .rejected
        }
        if let previous = users[userID]?.lastSubmitAt, now.timeIntervalSince(previous) < RunRules.minSubmitGap {
            return .rateLimited
        }
        if RunRules.isOutsidePlayedAtWindow(playedAt: run.playedAt, now: now) {
            users[userID]?.lastSubmitAt = now
            return .stale
        }
        if RunRules.exceedsScoreRate(score: run.score, durationSeconds: run.durationSeconds) {
            users[userID]?.lastSubmitAt = now
            return .rejected
        }
        let today = TorontoPeriod.dayKey(for: now)
        var count = users[userID]?.submitCount ?? 0
        if users[userID]?.submitDay != today {
            count = 0
        }
        if count >= RunRules.dailySubmitCap {
            return .rateLimited
        }
        runs.append(Row(
            id: run.id,
            userID: userID,
            score: run.score,
            durationSeconds: run.durationSeconds,
            playedAt: run.playedAt
        ))
        users[userID]?.lastSubmitAt = now
        users[userID]?.submitDay = today
        users[userID]?.submitCount = count + 1
        return .stored
    }

    func boardNow(_ period: BoardPeriod, accessToken: String) throws -> LeaderboardPage {
        let viewer = try user(for: accessToken).id
        let ranked = runs.compactMap { row -> RankedRun? in
            guard let username = users[row.userID]?.username else { return nil }
            return RankedRun(userID: row.userID, username: username, score: row.score, playedAt: row.playedAt)
        }
        return LeaderboardMath.page(runs: ranked, period: period, at: now, viewerID: viewer)
    }

    private func user(for accessToken: String) throws -> User {
        guard let userID = accessTokens[accessToken], let user = users[userID] else {
            throw AccountTransportError.unauthorized
        }
        return user
    }

    private func issue(for userID: String) -> StoredSession {
        minted += 1
        let access = "access-\(userID)-\(minted)"
        let refresh = "refresh-\(userID)-\(minted)"
        accessTokens[access] = userID
        refreshTokens[refresh] = userID
        return StoredSession(
            userID: userID,
            accessToken: access,
            refreshToken: refresh,
            expiresAt: now.addingTimeInterval(3600)
        )
    }
}

enum TestTime {
    static func iso(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }
}
