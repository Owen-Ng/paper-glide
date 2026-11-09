import Foundation

/// Local runs, the anonymous session, and the leaderboard cache.
///
/// `record` writes the run before any network call, so a finished glide is kept
/// even if a request is still in flight. The server dedupes by run id.
/// This type does not read or write the local best.
public final class AccountSync: @unchecked Sendable {
    private let backend: AccountBackend
    private let sessions: SessionStore
    private let store: CloudStore
    public let configured: Bool
    private let makeID: () -> String
    private let lock = NSLock()
    private let gate = AsyncLock()

    private var session: StoredSession?
    private var username: String?
    private var runs: [StoredRun] = []
    private var boards: [BoardPeriod: CachedBoard] = [:]
    private var syncing = false
    private var online = false
    private var launchPromptDismissed = false
    private var deathPromptVisible = false
    private var deathPromptUsed = false
    private var launchedWithoutNetwork = false
    private var lastFlushFailed = false
    private var loading: Set<BoardPeriod> = []
    private var loadFailed: Set<BoardPeriod> = []
    private var nameError: String?
    private var lastRunState: RunSyncState?
    private var now: Date

    public init(
        backend: AccountBackend,
        sessions: SessionStore,
        store: CloudStore,
        configured: Bool,
        now: Date = Date(),
        makeID: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.backend = backend
        self.sessions = sessions
        self.store = store
        self.configured = configured
        self.now = now
        self.makeID = makeID
        session = sessions.load()
        username = store.loadUsername()
        runs = store.loadRuns()
        if let session, store.loadUserID() != session.userID {
            username = nil
            store.saveUsername(nil)
            store.saveUserID(session.userID)
        }
        for period in BoardPeriod.allCases {
            boards[period] = store.loadBoard(period)
        }
    }

    public func setNow(_ date: Date) {
        withLock { now = date }
    }

    public func prepare(online pathOnline: Bool) -> AccountSnapshot {
        withLock {
            online = pathOnline && configured
            launchedWithoutNetwork = !online
            return snapshotLocked()
        }
    }

    public func bootstrap() async -> AccountSnapshot {
        await gate.lock()
        defer { gate.unlock() }
        return await bootstrapUnlocked()
    }

    public func setOnline(_ pathOnline: Bool) async -> AccountSnapshot {
        await gate.lock()
        defer { gate.unlock() }
        let becameOnline = withLock { () -> Bool in
            let next = pathOnline && configured
            let became = next && !online
            online = next
            return became
        }
        if becameOnline {
            return await bootstrapUnlocked()
        }
        return withLock { snapshotLocked() }
    }

    @discardableResult
    public func record(score: Int, durationSeconds: Double, playedAt: Date) -> AccountSnapshot {
        withLock {
            let run = StoredRun(
                id: makeID(),
                score: score,
                durationSeconds: durationSeconds,
                playedAt: playedAt,
                state: .pending
            )
            runs.append(run)
            lastRunState = .pending
            persistRunsLocked()
            return snapshotLocked()
        }
    }

    @discardableResult
    public func noteNewBest() -> AccountSnapshot {
        withLock {
            let offer = username == nil && !deathPromptUsed && (launchPromptDismissed || launchedWithoutNetwork)
            if offer {
                deathPromptVisible = true
                deathPromptUsed = true
            }
            return snapshotLocked()
        }
    }

    @discardableResult
    public func dismissLaunchPrompt() -> AccountSnapshot {
        withLock {
            launchPromptDismissed = true
            return snapshotLocked()
        }
    }

    @discardableResult
    public func dismissDeathPrompt() -> AccountSnapshot {
        withLock {
            deathPromptVisible = false
            return snapshotLocked()
        }
    }

    public func clearNameError() -> AccountSnapshot {
        withLock {
            nameError = nil
            return snapshotLocked()
        }
    }

    public func claim(_ typed: String) async -> AccountSnapshot {
        await gate.lock()
        defer { gate.unlock() }
        let name = UsernameRules.normalize(typed)
        if let shape = UsernameRules.shapeProblem(name) {
            return withLock {
                nameError = NameCopy.message(for: shape)
                return snapshotLocked()
            }
        }
        let ready = withLock { online && configured }
        guard ready else {
            return withLock {
                nameError = NameCopy.offline
                return snapshotLocked()
            }
        }
        await ensureSessionUnlocked()
        let token = withLock { session?.accessToken }
        guard let token else {
            return withLock {
                nameError = NameCopy.saveFailed
                return snapshotLocked()
            }
        }
        do {
            let result = try await backend.claimUsername(name, accessToken: token)
            switch result {
            case .saved(let saved), .alreadyNamed(let saved):
                withLock {
                    username = saved
                    nameError = nil
                    launchPromptDismissed = true
                    deathPromptVisible = false
                    store.saveUsername(saved)
                }
                return await flushUnlocked()
            case .rejected(let reason):
                return withLock {
                    nameError = NameCopy.message(for: reason)
                    return snapshotLocked()
                }
            }
        } catch {
            return withLock {
                nameError = NameCopy.saveFailed
                return snapshotLocked()
            }
        }
    }

    public func retry() async -> AccountSnapshot {
        await flush()
    }

    public func flush() async -> AccountSnapshot {
        await gate.lock()
        defer { gate.unlock() }
        return await flushUnlocked()
    }

    public func refresh(_ period: BoardPeriod) async -> AccountSnapshot {
        await gate.lock()
        defer { gate.unlock() }
        let token = withLock { () -> String? in
            guard online, configured else { return nil }
            loading.insert(period)
            return session?.accessToken
        }
        guard let token else {
            return withLock {
                loading.remove(period)
                return snapshotLocked()
            }
        }
        do {
            let page = try await backend.leaderboard(period, accessToken: token)
            let named = withLock { username }
            let marked = page.marking(username: named)
            return withLock {
                let cached = CachedBoard(page: marked)
                boards[period] = cached
                store.saveBoard(cached, period: period)
                loading.remove(period)
                loadFailed.remove(period)
                return snapshotLocked()
            }
        } catch {
            return withLock {
                loading.remove(period)
                loadFailed.insert(period)
                return snapshotLocked()
            }
        }
    }

    public func snapshot() -> AccountSnapshot {
        withLock { snapshotLocked() }
    }

    private struct FlushContext {
        var token: String
        var pending: [StoredRun]
        var clock: Date
    }

    private func bootstrapUnlocked() async -> AccountSnapshot {
        let shouldSync = withLock { online && configured }
        guard shouldSync else { return withLock { snapshotLocked() } }
        await ensureSessionUnlocked()
        await refreshUsernameFromServer()
        return await flushUnlocked()
    }

    private func flushUnlocked() async -> AccountSnapshot {
        let context = withLock { () -> FlushContext? in
            guard online, configured, username != nil, let session else {
                lastFlushFailed = username != nil && runs.contains { $0.state == .pending } && !online
                return nil
            }
            let pending = runs.filter { $0.state == .pending }
            guard !pending.isEmpty else {
                lastFlushFailed = false
                syncing = false
                return nil
            }
            syncing = true
            return FlushContext(token: session.accessToken, pending: pending, clock: now)
        }
        guard let context else { return withLock { snapshotLocked() } }

        var failed = false
        for run in context.pending {
            if RunRules.isOutsidePlayedAtWindow(playedAt: run.playedAt, now: context.clock) {
                withLock { mark(run.id, .localOnly) }
                continue
            }
            do {
                let ack = try await submit(run, token: context.token)
                switch ack {
                case .stored, .duplicate:
                    withLock { mark(run.id, .synced) }
                case .rejected:
                    withLock { mark(run.id, .rejected) }
                case .stale:
                    withLock { mark(run.id, .localOnly) }
                case .needsName:
                    failed = true
                case .rateLimited:
                    return withLock {
                        lastFlushFailed = true
                        syncing = false
                        persistRunsLocked()
                        return snapshotLocked()
                    }
                }
            } catch {
                failed = true
                break
            }
        }
        return withLock {
            syncing = false
            let stillPending = runs.contains { $0.state == .pending }
            lastFlushFailed = failed && stillPending
            if let last = runs.last {
                lastRunState = last.state
            }
            persistRunsLocked()
            return snapshotLocked()
        }
    }

    private func submit(_ run: StoredRun, token: String) async throws -> SubmitAck {
        do {
            return try await backend.submitRun(run, accessToken: token)
        } catch AccountTransportError.unauthorized {
            await ensureSessionUnlocked()
            let refreshed = withLock { session?.accessToken }
            guard let refreshed else { throw AccountTransportError.unauthorized }
            return try await backend.submitRun(run, accessToken: refreshed)
        }
    }

    private func ensureSessionUnlocked() async {
        let existing = withLock { session }
        let clock = withLock { now }
        if let existing, existing.expiresAt.timeIntervalSince(clock) > 60 {
            return
        }
        if let existing {
            do {
                let refreshed = try await backend.refresh(refreshToken: existing.refreshToken)
                withLock { adopt(refreshed, replacing: existing.userID) }
                return
            } catch {
                // A dead session starts a new anonymous account. The old name stays taken.
            }
        }
        do {
            let created = try await backend.signInAnonymously()
            withLock { adopt(created, replacing: existing?.userID) }
        } catch {
            withLock {
                if username != nil && runs.contains(where: { $0.state == .pending }) {
                    lastFlushFailed = true
                }
            }
        }
    }

    private func refreshUsernameFromServer() async {
        let token = withLock { session?.accessToken }
        guard let token else { return }
        do {
            let remote = try await backend.fetchUsername(accessToken: token)
            withLock {
                if let remote {
                    username = remote
                    store.saveUsername(remote)
                    launchPromptDismissed = true
                    deathPromptVisible = false
                } else if session != nil {
                    username = nil
                    store.saveUsername(nil)
                }
            }
        } catch {
            // Keep the on-device name until the server answers.
        }
    }

    private func adopt(_ next: StoredSession, replacing previousID: String?) {
        if previousID != next.userID {
            username = nil
            store.saveUsername(nil)
            boards = [:]
            for period in BoardPeriod.allCases {
                store.saveBoard(nil, period: period)
            }
        }
        session = next
        sessions.save(next)
        store.saveUserID(next.userID)
    }

    private func mark(_ id: String, _ state: RunSyncState) {
        for index in runs.indices where runs[index].id == id && runs[index].state == .pending {
            runs[index].state = state
        }
    }

    private func persistRunsLocked() {
        store.saveRuns(runs)
    }

    private func snapshotLocked() -> AccountSnapshot {
        AccountSnapshot(
            username: username,
            userID: session?.userID,
            syncing: syncing,
            online: online,
            configured: configured,
            pendingCount: runs.filter { $0.state == .pending }.count,
            lastFlushFailed: lastFlushFailed,
            showsLaunchPrompt: username == nil && !launchPromptDismissed,
            deathPromptVisible: deathPromptVisible,
            lastRunState: lastRunState,
            nameError: nameError,
            boards: boards,
            loading: loading,
            loadFailed: loadFailed
        )
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Serializes anonymous sign-in and flushes without holding the data lock across the network.
final class AsyncLock: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        let acquired: Bool = {
            self.lock.lock()
            defer { self.lock.unlock() }
            if !busy {
                busy = true
                return true
            }
            return false
        }()
        if acquired { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.lock.lock()
            if !busy {
                busy = true
                self.lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            self.lock.unlock()
        }
    }

    func unlock() {
        lock.lock()
        if waiters.isEmpty {
            busy = false
            lock.unlock()
            return
        }
        let next = waiters.removeFirst()
        lock.unlock()
        next.resume()
    }
}
