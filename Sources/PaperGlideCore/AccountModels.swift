import Foundation

public enum RunSyncState: String, Codable, Equatable {
    case pending
    case synced
    case rejected
    case localOnly
}

public struct StoredRun: Codable, Equatable, Identifiable {
    public var id: String
    public var score: Int
    public var durationSeconds: Double
    public var playedAt: Date
    public var state: RunSyncState

    public init(id: String, score: Int, durationSeconds: Double, playedAt: Date, state: RunSyncState) {
        self.id = id
        self.score = score
        self.durationSeconds = durationSeconds
        self.playedAt = playedAt
        self.state = state
    }
}

public struct StoredSession: Codable, Equatable {
    public var userID: String
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(userID: String, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public enum UsernameClaim: Equatable {
    case saved(String)
    case alreadyNamed(String)
    case rejected(UsernameRejection)
}

public enum SubmitAck: Equatable {
    case stored
    case duplicate
    case rejected
    case rateLimited
    case needsName
    case stale
}

public enum AccountTransportError: Error, Equatable {
    case unauthorized
    case unreachable
    case badResponse
}

public protocol AccountBackend: AnyObject {
    func signInAnonymously() async throws -> StoredSession
    func refresh(refreshToken: String) async throws -> StoredSession
    func fetchUsername(accessToken: String) async throws -> String?
    func claimUsername(_ name: String, accessToken: String) async throws -> UsernameClaim
    func submitRun(_ run: StoredRun, accessToken: String) async throws -> SubmitAck
    func leaderboard(_ period: BoardPeriod, accessToken: String) async throws -> LeaderboardPage
}

public protocol SessionStore: AnyObject {
    func load() -> StoredSession?
    func save(_ session: StoredSession)
    func clear()
}

public protocol CloudStore: AnyObject {
    func loadRuns() -> [StoredRun]
    func saveRuns(_ runs: [StoredRun])
    func loadUsername() -> String?
    func saveUsername(_ username: String?)
    func loadUserID() -> String?
    func saveUserID(_ userID: String?)
    func loadBoard(_ period: BoardPeriod) -> CachedBoard?
    func saveBoard(_ board: CachedBoard?, period: BoardPeriod)
}

public final class MemorySessionStore: SessionStore {
    public var session: StoredSession?

    public init(session: StoredSession? = nil) {
        self.session = session
    }

    public func load() -> StoredSession? { session }

    public func save(_ session: StoredSession) { self.session = session }

    public func clear() { session = nil }
}

public final class MemoryCloudStore: CloudStore {
    public var runs: [StoredRun] = []
    public var username: String?
    public var userID: String?
    public var boards: [BoardPeriod: CachedBoard] = [:]

    public init() {}

    public func loadRuns() -> [StoredRun] { runs }
    public func saveRuns(_ runs: [StoredRun]) { self.runs = runs }
    public func loadUsername() -> String? { username }
    public func saveUsername(_ username: String?) { self.username = username }
    public func loadUserID() -> String? { userID }
    public func saveUserID(_ userID: String?) { self.userID = userID }
    public func loadBoard(_ period: BoardPeriod) -> CachedBoard? { boards[period] }
    public func saveBoard(_ board: CachedBoard?, period: BoardPeriod) { boards[period] = board }
}

public struct AccountSnapshot: Equatable {
    public var username: String?
    public var userID: String?
    public var syncing: Bool
    public var online: Bool
    public var configured: Bool
    public var pendingCount: Int
    public var lastFlushFailed: Bool
    public var showsLaunchPrompt: Bool
    public var deathPromptVisible: Bool
    public var lastRunState: RunSyncState?
    public var nameError: String?
    public var boards: [BoardPeriod: CachedBoard]
    public var loading: Set<BoardPeriod>
    public var loadFailed: Set<BoardPeriod>

    public init(
        username: String? = nil,
        userID: String? = nil,
        syncing: Bool = false,
        online: Bool = false,
        configured: Bool = false,
        pendingCount: Int = 0,
        lastFlushFailed: Bool = false,
        showsLaunchPrompt: Bool = false,
        deathPromptVisible: Bool = false,
        lastRunState: RunSyncState? = nil,
        nameError: String? = nil,
        boards: [BoardPeriod: CachedBoard] = [:],
        loading: Set<BoardPeriod> = [],
        loadFailed: Set<BoardPeriod> = []
    ) {
        self.username = username
        self.userID = userID
        self.syncing = syncing
        self.online = online
        self.configured = configured
        self.pendingCount = pendingCount
        self.lastFlushFailed = lastFlushFailed
        self.showsLaunchPrompt = showsLaunchPrompt
        self.deathPromptVisible = deathPromptVisible
        self.lastRunState = lastRunState
        self.nameError = nameError
        self.boards = boards
        self.loading = loading
        self.loadFailed = loadFailed
    }
}
