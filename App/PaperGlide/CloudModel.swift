import Foundation
import Network
import PaperGlideCore

/// Anonymous account, run sync, and leaderboard cache for the screens.
/// Gameplay and the local best stay in `AppModel`.
@MainActor
final class CloudModel: ObservableObject {
    @Published private(set) var snapshot = AccountSnapshot()
    @Published var period: BoardPeriod = .daily
    @Published private(set) var busy = false

    private let sync: AccountSync
    let analytics: AnalyticsCenter
    private let monitor = NWPathMonitor()
    private var pathOnline = true
    private var started = false

    init() {
        let config = SupabaseConfig.load()
        let sessions = KeychainSessionStore()
        let store = UserDefaultsCloudStore()
        if LaunchOptions.resetsStoredProgress {
            UserDefaultsGameStorage.clearPersistedProgress()
            sessions.clear()
        }
        #if DEBUG
        if let preset = LaunchOptions.presetBest {
            UserDefaults.standard.set(preset, forKey: UserDefaultsGameStorage.bestScoreKey)
        }
        #endif
        let backend: AccountBackend
        if config.isConfigured, let url = config.url {
            backend = SupabaseHTTPBackend(baseURL: url, anonKey: config.anonKey)
        } else {
            backend = IdleAccountBackend()
        }
        let sync = AccountSync(
            backend: backend,
            sessions: sessions,
            store: store,
            configured: config.isConfigured
        )
        self.sync = sync
        analytics = AnalyticsCenter {
            await sync.accessToken()
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                self.pathOnline = online
                guard self.started else { return }
                #if DEBUG
                if LaunchOptions.forcesWorstCaseDeath { return }
                #endif
                self.snapshot = await self.sync.setOnline(online)
            }
        }
        let queue = DispatchQueue(label: "paperGlide.reachability")
        monitor.start(queue: queue)
        pathOnline = monitor.currentPath.status == .satisfied
        #if DEBUG
        if LaunchOptions.forcesWorstCaseDeath {
            presentWorstCaseDeath()
        }
        #endif
    }

    #if DEBUG
    /// Layout fixture for the death-screen reachability test. Release builds omit it.
    private func presentWorstCaseDeath() {
        snapshot = AccountSnapshot(
            username: nil,
            online: false,
            configured: false,
            pendingCount: 1,
            showsLaunchPrompt: false,
            deathPromptVisible: true,
            lastRunState: .pending
        )
    }
    #endif

    var chipText: String? {
        if busy || snapshot.syncing { return BoardCopy.syncing }
        if snapshot.pendingCount > 0 { return BoardCopy.chipPending }
        return nil
    }

    var deathNote: String? {
        snapshot.lastRunState == .pending ? BoardCopy.deathPending : nil
    }

    func start() async {
        guard !started else { return }
        started = true
        #if DEBUG
        if LaunchOptions.forcesWorstCaseDeath {
            presentWorstCaseDeath()
            return
        }
        #endif
        snapshot = sync.prepare(online: pathOnline)
        await analytics.boot()
        snapshot = await sync.bootstrap()
        await analytics.client.flushNow()
        guard snapshot.online else { return }
        busy = true
        for period in BoardPeriod.allCases {
            snapshot = await sync.refresh(period)
        }
        busy = false
    }

    func record(score: Int, duration: Double, isNewBest: Bool) async {
        var snap = sync.record(score: score, durationSeconds: duration, playedAt: Date())
        if isNewBest {
            snap = sync.noteNewBest()
        }
        snapshot = snap
        busy = snap.online && snap.username != nil && snap.pendingCount > 0
        snapshot = await sync.flush()
        if snapshot.online {
            for period in BoardPeriod.allCases {
                snapshot = await sync.refresh(period)
            }
        }
        busy = false
    }

    func claim(_ typed: String) async {
        busy = true
        snapshot = await sync.claim(typed)
        if snapshot.username != nil && snapshot.online {
            for period in BoardPeriod.allCases {
                snapshot = await sync.refresh(period)
            }
        }
        busy = false
    }

    func dismissLaunch() {
        snapshot = sync.dismissLaunchPrompt()
    }

    func dismissDeath() {
        snapshot = sync.dismissDeathPrompt()
    }

    func clearNameError() {
        snapshot = sync.clearNameError()
    }

    func retry() async {
        busy = snapshot.online
        snapshot = await sync.retry()
        if snapshot.online {
            snapshot = await sync.refresh(period)
        }
        busy = false
    }

    /// Confirmed live. Nothing is queued, and no analytics event is recorded.
    func deleteMyData() async -> DeleteMyDataResult {
        #if DEBUG
        if let stub = LaunchOptions.deleteStub {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            switch stub {
            case "success":
                await analytics.client.holdSends()
                analytics.client.discardLocalQueue()
                snapshot = sync.wipeLocalAccount()
                return .deleted
            case "failure":
                return .failed
            default:
                return .offline
            }
        }
        #endif
        let attempt = snapshot.online && snapshot.configured
        if attempt {
            await analytics.client.holdSends()
        }
        let (result, next) = await sync.deleteMyData()
        if result == .deleted {
            analytics.client.discardLocalQueue()
        } else if attempt {
            analytics.client.resumeSends()
        }
        snapshot = next
        return result
    }

    func refreshSelected() async {
        guard snapshot.online else { return }
        busy = true
        snapshot = await sync.refresh(period)
        busy = false
    }

    func presentation(localBest: Int) -> BoardPresentation {
        #if DEBUG
        if LaunchOptions.leaderboardFixture {
            let entries = (1...40).map { rank in
                BoardEntry(rank: rank, username: "pilot\(rank)", score: 200 - rank, isYou: false)
            }
            return BoardPresentation(
                entries: entries,
                caption: BoardCopy.caption(for: period),
                canPullToRefresh: false
            )
        }
        #endif
        let cached = snapshot.boards[period]
        let time = cached.map { BoardTimeFormat.string($0.fetchedAt) }
        return BoardPresenter.present(
            period: period,
            cached: cached,
            loading: busy || snapshot.loading.contains(period),
            online: snapshot.online,
            loadFailed: snapshot.loadFailed.contains(period),
            syncFailed: snapshot.lastFlushFailed && snapshot.pendingCount > 0,
            username: snapshot.username,
            localBest: localBest,
            cacheTimeText: time
        )
    }
}

/// Used when the xcconfig still has the placeholder. It never opens a connection.
final class IdleAccountBackend: AccountBackend {
    func signInAnonymously() async throws -> StoredSession { throw AccountTransportError.unreachable }
    func refresh(refreshToken: String) async throws -> StoredSession { throw AccountTransportError.unreachable }
    func fetchUsername(accessToken: String) async throws -> String? { throw AccountTransportError.unreachable }
    func claimUsername(_ name: String, accessToken: String) async throws -> UsernameClaim {
        throw AccountTransportError.unreachable
    }
    func submitRun(_ run: StoredRun, accessToken: String) async throws -> SubmitAck {
        throw AccountTransportError.unreachable
    }
    func leaderboard(_ period: BoardPeriod, accessToken: String) async throws -> LeaderboardPage {
        throw AccountTransportError.unreachable
    }
    func deleteMyData(accessToken: String) async throws {
        throw AccountTransportError.unreachable
    }
}
