package com.paperglide.core

import java.time.Instant
import java.util.UUID

enum class RunSyncState { Pending, Synced, Rejected, LocalOnly }

data class StoredRun(
    val id: String,
    val score: Int,
    val durationSeconds: Double,
    val playedAt: Instant,
    var state: RunSyncState,
)

data class StoredSession(
    val userID: String,
    val accessToken: String,
    val refreshToken: String,
    val expiresAt: Instant,
)

sealed class UsernameClaim {
    data class Saved(val name: String) : UsernameClaim()
    data class AlreadyNamed(val name: String) : UsernameClaim()
    data class Rejected(val reason: UsernameRejection) : UsernameClaim()
}

enum class SubmitAck { Stored, Duplicate, Rejected, RateLimited, NeedsName, Stale }

sealed class AccountTransportError : Exception() {
    data object Unauthorized : AccountTransportError()
    data object Unreachable : AccountTransportError()
    data object BadResponse : AccountTransportError()
}

interface AccountBackend {
    suspend fun signInAnonymously(): StoredSession
    suspend fun refresh(refreshToken: String): StoredSession
    suspend fun fetchUsername(accessToken: String): String?
    suspend fun claimUsername(name: String, accessToken: String): UsernameClaim
    suspend fun submitRun(run: StoredRun, accessToken: String, platform: String): SubmitAck
    suspend fun leaderboard(period: BoardPeriod, accessToken: String): LeaderboardPage
    suspend fun deleteMyData(accessToken: String): Boolean
}

interface SessionStore {
    fun load(): StoredSession?
    fun save(session: StoredSession)
    fun clear()
}

interface CloudStore {
    fun loadRuns(): List<StoredRun>
    fun saveRuns(runs: List<StoredRun>)
    fun loadUsername(): String?
    fun saveUsername(username: String?)
    fun loadUserID(): String?
    fun saveUserID(userID: String?)
    fun loadBoard(period: BoardPeriod): CachedBoard?
    fun saveBoard(board: CachedBoard?, period: BoardPeriod)
    fun clear()
}

class MemorySessionStore(var session: StoredSession? = null) : SessionStore {
    override fun load(): StoredSession? = session
    override fun save(session: StoredSession) { this.session = session }
    override fun clear() { session = null }
}

class MemoryCloudStore : CloudStore {
    var runs: List<StoredRun> = emptyList()
    var username: String? = null
    var userID: String? = null
    val boards = mutableMapOf<BoardPeriod, CachedBoard>()
    override fun loadRuns() = runs
    override fun saveRuns(runs: List<StoredRun>) { this.runs = runs }
    override fun loadUsername() = username
    override fun saveUsername(username: String?) { this.username = username }
    override fun loadUserID() = userID
    override fun saveUserID(userID: String?) { this.userID = userID }
    override fun loadBoard(period: BoardPeriod) = boards[period]
    override fun saveBoard(board: CachedBoard?, period: BoardPeriod) {
        if (board == null) boards.remove(period) else boards[period] = board
    }
    override fun clear() {
        runs = emptyList()
        username = null
        userID = null
        boards.clear()
    }
}

data class AccountSnapshot(
    val username: String? = null,
    val userID: String? = null,
    val syncing: Boolean = false,
    val online: Boolean = false,
    val configured: Boolean = false,
    val pendingCount: Int = 0,
    val lastFlushFailed: Boolean = false,
    val showsLaunchPrompt: Boolean = false,
    val deathPromptVisible: Boolean = false,
    val lastRunState: RunSyncState? = null,
    val nameError: String? = null,
    val boards: Map<BoardPeriod, CachedBoard> = emptyMap(),
    val loading: Set<BoardPeriod> = emptySet(),
    val loadFailed: Set<BoardPeriod> = emptySet(),
)

enum class DeleteResult { Deleted, Offline, Failed }

/**
 * Local runs and the anonymous session. [platform] is sent with every score.
 * Deletion is live only: offline and transport failures leave every store untouched.
 */
class AccountSync(
    private val backend: AccountBackend,
    private val sessions: SessionStore,
    private val store: CloudStore,
    val configured: Boolean,
    private val platform: String = PaperGlideLinks.platform,
    private var now: Instant = Instant.now(),
    private val makeID: () -> String = { UUID.randomUUID().toString().lowercase() },
    var pause: suspend (Double) -> Unit = {},
) {
    private val gate = Any()
    private var session: StoredSession? = sessions.load()
    private var username: String? = store.loadUsername()
    private var runs: MutableList<StoredRun> = store.loadRuns().toMutableList()
    private val boards = mutableMapOf<BoardPeriod, CachedBoard>()
    private var syncing = false
    private var online = false
    private var launchPromptDismissed = false
    private var deathPromptVisible = false
    private var deathPromptUsed = false
    private var launchedWithoutNetwork = false
    private var lastFlushFailed = false
    private val loading = mutableSetOf<BoardPeriod>()
    private val loadFailed = mutableSetOf<BoardPeriod>()
    private var nameError: String? = null
    private var lastRunState: RunSyncState? = null

    init {
        val current = session
        if (current != null && store.loadUserID() != current.userID) {
            username = null
            store.saveUsername(null)
            store.saveUserID(current.userID)
        }
        for (period in BoardPeriod.entries) {
            store.loadBoard(period)?.let { boards[period] = it }
        }
    }

    fun setNow(instant: Instant) { now = instant }

    fun prepare(pathOnline: Boolean): AccountSnapshot {
        online = pathOnline && configured
        launchedWithoutNetwork = !online
        return snapshot()
    }

    fun record(score: Int, durationSeconds: Double, playedAt: Instant): AccountSnapshot {
        runs += StoredRun(makeID(), score, durationSeconds, playedAt, RunSyncState.Pending)
        lastRunState = RunSyncState.Pending
        store.saveRuns(runs.toList())
        return snapshot()
    }

    fun noteNewBest(): AccountSnapshot {
        val offer = username == null && !deathPromptUsed && (launchPromptDismissed || launchedWithoutNetwork)
        if (offer) {
            deathPromptVisible = true
            deathPromptUsed = true
        }
        return snapshot()
    }

    fun dismissLaunchPrompt(): AccountSnapshot {
        launchPromptDismissed = true
        return snapshot()
    }

    fun dismissDeathPrompt(): AccountSnapshot {
        deathPromptVisible = false
        return snapshot()
    }

    suspend fun claim(typed: String): AccountSnapshot {
        val name = UsernameRules.normalize(typed)
        val shape = UsernameRules.shapeProblem(name)
        if (shape != null) {
            nameError = NameCopy.message(shape)
            return snapshot()
        }
        if (!(online && configured)) {
            nameError = NameCopy.offline
            return snapshot()
        }
        ensureSession()
        val token = session?.accessToken
        if (token == null) {
            nameError = NameCopy.saveFailed
            return snapshot()
        }
        return try {
            when (val result = backend.claimUsername(name, token)) {
                is UsernameClaim.Saved, is UsernameClaim.AlreadyNamed -> {
                    val saved = when (result) {
                        is UsernameClaim.Saved -> result.name
                        is UsernameClaim.AlreadyNamed -> result.name
                        else -> name
                    }
                    username = saved
                    nameError = null
                    launchPromptDismissed = true
                    deathPromptVisible = false
                    store.saveUsername(saved)
                    flush()
                }
                is UsernameClaim.Rejected -> {
                    nameError = NameCopy.message(result.reason)
                    snapshot()
                }
            }
        } catch (_: Exception) {
            nameError = NameCopy.saveFailed
            snapshot()
        }
    }

    suspend fun flush(): AccountSnapshot {
        if (!(online && configured && username != null && session != null)) {
            lastFlushFailed = username != null && runs.any { it.state == RunSyncState.Pending } && !online
            syncing = false
            return snapshot()
        }
        val token = session?.accessToken ?: return snapshot()
        val pending = runs.filter { it.state == RunSyncState.Pending }
        if (pending.isEmpty()) {
            lastFlushFailed = false
            syncing = false
            return snapshot()
        }
        syncing = true
        var failed = false
        for (run in pending) {
            if (RunRules.isOutsidePlayedAtWindow(run.playedAt, now)) {
                mark(run.id, RunSyncState.LocalOnly)
                continue
            }
            try {
                when (backend.submitRun(run, token, platform)) {
                    SubmitAck.Stored, SubmitAck.Duplicate -> mark(run.id, RunSyncState.Synced)
                    SubmitAck.Rejected -> mark(run.id, RunSyncState.Rejected)
                    SubmitAck.Stale -> mark(run.id, RunSyncState.LocalOnly)
                    SubmitAck.NeedsName -> failed = true
                    SubmitAck.RateLimited -> {
                        pause(RunRules.minSubmitGapSeconds)
                        break
                    }
                }
            } catch (_: Exception) {
                failed = true
                break
            }
        }
        syncing = false
        val stillPending = runs.any { it.state == RunSyncState.Pending }
        lastFlushFailed = failed && stillPending
        runs.lastOrNull()?.let { lastRunState = it.state }
        store.saveRuns(runs.toList())
        return snapshot()
    }

    suspend fun refresh(period: BoardPeriod): AccountSnapshot {
        val token = session?.accessToken
        if (!(online && configured) || token == null) {
            loading.remove(period)
            return snapshot()
        }
        loading += period
        return try {
            val page = backend.leaderboard(period, token).marking(username)
            val cached = CachedBoard(page)
            boards[period] = cached
            store.saveBoard(cached, period)
            loading.remove(period)
            loadFailed.remove(period)
            snapshot()
        } catch (_: Exception) {
            loading.remove(period)
            loadFailed += period
            snapshot()
        }
    }

    /**
     * Confirmed live. A failure or an offline path does not clear the session,
     * the name, the score queue, or the best score.
     */
    suspend fun deleteMyData(): DeleteResult {
        if (!(online && configured)) return DeleteResult.Offline
        ensureSession()
        val token = session?.accessToken ?: return DeleteResult.Failed
        val ok = try {
            backend.deleteMyData(token)
        } catch (error: AccountTransportError.Unreachable) {
            return DeleteResult.Offline
        } catch (_: Exception) {
            return DeleteResult.Failed
        }
        if (!ok) return DeleteResult.Failed
        wipeIdentity()
        return DeleteResult.Deleted
    }

    fun snapshot(): AccountSnapshot = AccountSnapshot(
        username = username,
        userID = session?.userID,
        syncing = syncing,
        online = online,
        configured = configured,
        pendingCount = runs.count { it.state == RunSyncState.Pending },
        lastFlushFailed = lastFlushFailed,
        showsLaunchPrompt = username == null && !launchPromptDismissed,
        deathPromptVisible = deathPromptVisible,
        lastRunState = lastRunState,
        nameError = nameError,
        boards = boards.toMap(),
        loading = loading.toSet(),
        loadFailed = loadFailed.toSet(),
    )

    private suspend fun ensureSession() {
        val existing = session
        if (existing != null && existing.expiresAt.epochSecond - now.epochSecond > 60) return
        if (existing != null) {
            try {
                adopt(backend.refresh(existing.refreshToken), existing.userID)
                return
            } catch (_: Exception) {
                // A dead session starts a new anonymous account.
            }
        }
        try {
            adopt(backend.signInAnonymously(), existing?.userID)
        } catch (_: Exception) {
            if (username != null && runs.any { it.state == RunSyncState.Pending }) lastFlushFailed = true
        }
    }

    private fun adopt(next: StoredSession, previousID: String?) {
        if (previousID != next.userID) {
            username = null
            store.saveUsername(null)
            boards.clear()
            for (period in BoardPeriod.entries) store.saveBoard(null, period)
        }
        session = next
        sessions.save(next)
        store.saveUserID(next.userID)
    }

    private fun mark(id: String, state: RunSyncState) {
        val index = runs.indexOfFirst { it.id == id && it.state == RunSyncState.Pending }
        if (index >= 0) runs[index] = runs[index].copy(state = state)
    }

    private fun wipeIdentity() {
        session = null
        username = null
        runs.clear()
        boards.clear()
        loading.clear()
        loadFailed.clear()
        nameError = null
        lastRunState = null
        lastFlushFailed = false
        syncing = false
        launchPromptDismissed = false
        deathPromptVisible = false
        deathPromptUsed = false
        sessions.clear()
        store.clear()
    }
}

enum class AnalyticsKind(val wire: String) {
    SessionStart("session_start"),
    Click("click"),
    Crash("crash"),
    Report("report"),
}

data class AnalyticsContext(val appVersion: String, val osVersion: String, val deviceModel: String)

data class QueuedEvent(
    val id: String,
    val kind: AnalyticsKind,
    val occurredAt: Instant,
    val sessionID: String? = null,
    val page: String? = null,
    val control: String? = null,
    val count: Int? = null,
    val category: String? = null,
    val text: String? = null,
    val context: AnalyticsContext? = null,
    val crashKind: String? = null,
    val crashSummary: String? = null,
    val crashDetails: String? = null,
)

/** Same keys as the iOS batch, plus platform=android. ios_version carries the OS release so the existing column is filled. */
object AnalyticsJson {
    fun event(event: QueuedEvent, platform: String = PaperGlideLinks.platform): Map<String, Any> {
        val body = linkedMapOf<String, Any>(
            "id" to event.id,
            "kind" to event.kind.wire,
            "occurred_at" to event.occurredAt.toString().let { iso ->
                if (iso.endsWith("Z") && !iso.contains('.')) iso else iso
            },
            "platform" to platform,
        )
        event.sessionID?.let { body["session_id"] = it }
        event.page?.let { body["page"] = it }
        event.control?.let { body["control"] = it }
        event.count?.let { body["count"] = it }
        event.category?.let { body["category"] = it }
        if (event.kind == AnalyticsKind.Report) event.text?.let { body["text"] = it }
        event.context?.let {
            body["app_version"] = it.appVersion
            body["ios_version"] = it.osVersion
            body["device_model"] = it.deviceModel
        }
        event.crashKind?.let { body["crash_kind"] = it }
        event.crashSummary?.let { body["crash_summary"] = it }
        event.crashDetails?.let { body["crash_details"] = it }
        return body
    }
}
