package com.paperglide.app

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.paperglide.core.AccountBackend
import com.paperglide.core.AccountSync
import com.paperglide.core.AccountTransportError
import com.paperglide.core.AnalyticsJson
import com.paperglide.core.AnalyticsKind
import com.paperglide.core.BoardCopy
import com.paperglide.core.BoardPeriod
import com.paperglide.core.BoardPresenter
import com.paperglide.core.DeleteCopy
import com.paperglide.core.DeleteResult
import com.paperglide.core.GameConfig
import com.paperglide.core.GameSession
import com.paperglide.core.GlidePilot
import com.paperglide.core.NameCopy
import com.paperglide.core.PaperGlideLinks
import com.paperglide.core.QueuedEvent
import com.paperglide.core.ReportCopy
import com.paperglide.core.RunPhase
import com.paperglide.core.StoredRun
import com.paperglide.core.StoredSession
import com.paperglide.core.SubmitAck
import com.paperglide.core.SupabaseConfig
import com.paperglide.core.UsernameClaim
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

enum class Screen { Start, Play, Death, Boards }

class PaperModel(
    context: Context,
    private val scope: CoroutineScope,
    launch: Intent?,
) {
    private val gamePrefs = context.getSharedPreferences("paper_glide_state", Context.MODE_PRIVATE)
    private val storage = PrefGameStorage(gamePrefs)
    private val secure = KeystorePrefs(context)
    val sessionStore = PrefSessionStore(secure.prefs)
    private val cloud = MemoryCloud()

    var screen by mutableStateOf(Screen.Start)
    var paused by mutableStateOf(false)
    var score by mutableStateOf(0)
    var best by mutableStateOf(0)
    var newBest by mutableStateOf(false)
    var showCoach by mutableStateOf(false)
    var banner by mutableStateOf<String?>(null)
    var deathNote by mutableStateOf<String?>(null)
    var showName by mutableStateOf(false)
    var nameError by mutableStateOf<String?>(null)
    var reportOpen by mutableStateOf(false)
    var reportText by mutableStateOf("")
    var reportCategory by mutableStateOf<String?>(null)
    var discardReport by mutableStateOf(false)
    var deleteOpen by mutableStateOf(false)
    var deleting by mutableStateOf(false)
    var keyboardOpen by mutableStateOf(false)
    var nameDraft by mutableStateOf("")
    var shareRequested by mutableStateOf(false)
    var period by mutableStateOf(BoardPeriod.Daily)
    var boardLines by mutableStateOf<List<String>>(emptyList())
    var boardEmpty by mutableStateOf<String?>(null)
    var immersive by mutableStateOf(false)
    private var boardsFrom = Screen.Start
    val endScore: Int? = extraInt(launch, "paperGlideEndScore") ?: DebugLaunch.endScore
    val guidedStride: Double? = extraDouble(launch, "paperGlideGuidedStride") ?: DebugLaunch.guidedStride
    private val seed: ULong = (extraLong(launch, "paperGlideSeed") ?: DebugLaunch.seed ?: (System.nanoTime() and 0xffff)).toULong()

    val session: GameSession

    private val accounts: AccountSync
    private val events = ArrayList<QueuedEvent>()

    init {
        val reset = launch?.getBooleanExtra("paperGlideResetStore", false) == true || DebugLaunch.resetStore
        if (reset) {
            storage.clear()
            sessionStore.clear()
            gamePrefs.edit().clear().commit()
            secure.clear()
        }
        ShareCards.forceFail = launch?.getBooleanExtra("paperGlideForceShareFail", false) == true || DebugLaunch.forceShareFail
        val config = SupabaseConfig.load(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY)
        val offline = launch?.getBooleanExtra("paperGlideOffline", false) == true || DebugLaunch.offline
        val fake = DebugLaunch.fakeDelete
        val backend: AccountBackend = when {
            fake != null -> FakeDeleteBackend(fake)
            config.isConfigured && !offline -> SupabaseAccountBackend(context, config)
            else -> OfflineBackend
        }
        val configured = fake != null || (config.isConfigured && !offline)
        accounts = AccountSync(backend, sessionStore, cloud, configured)
        if (fake == "offline" || offline || !config.isConfigured && fake == null) accounts.prepare(false) else accounts.prepare(configured)
        session = GameSession(config = GameConfig.standard, storage = storage, seed = seed)
        best = storage.loadBestScore()
        val worst = launch?.getBooleanExtra("paperGlideWorstCaseDeath", false) == true || DebugLaunch.worstCaseDeath
        if (worst) {
            session.endRun(4)
            val snap = session.snapshot
            score = snap.score
            best = snap.bestScore
            newBest = snap.isNewBest
            screen = Screen.Death
            deathNote = BoardCopy.deathPending
            showName = true
        } else {
            showName = accounts.snapshot().showsLaunchPrompt
            publishSnapshot()
        }
        record(AnalyticsKind.SessionStart, page = null, control = null)
    }

    fun publishSnapshot() {
        val snap = session.snapshot
        score = snap.score
        best = snap.bestScore
        newBest = snap.isNewBest
        showCoach = snap.showCoach
        if (snap.phase == RunPhase.Dead && screen == Screen.Play) {
            screen = Screen.Death
            paused = false
            immersive = false
            deathNote = if (accounts.snapshot().pendingCount > 0) BoardCopy.deathPending else null
            if (snap.isNewBest) accounts.noteNewBest()
            showName = accounts.snapshot().deathPromptVisible || accounts.snapshot().showsLaunchPrompt
            scope.launch { accounts.record(snap.score, snap.flightTime, Instant.now()); accounts.flush() }
        }
    }

    fun play() {
        recordClick("start", "play")
        session.reset(seed xor (System.nanoTime() and 0xffffffffL).toULong())
        if (endScore == null && guidedStride == null) {
            // a fresh seed each play keeps the run from repeating, except scripted launches
        }
        score = 0
        newBest = false
        paused = false
        screen = Screen.Play
        immersive = true
        publishSnapshot()
    }

    fun flap() {
        if (screen != Screen.Play || paused) return
        recordClick("playing", "flap")
        if (endScore != null) {
            session.endRun(endScore)
            publishSnapshot()
            return
        }
        if (guidedStride != null) {
            val tap = true
            GlidePilot.advance(session, guidedStride, tap)
            publishSnapshot()
            return
        }
        session.tap()
    }

    fun pause() {
        if (screen != Screen.Play || paused) return
        paused = true
    }

    fun resume() {
        if (screen != Screen.Play) return
        paused = false
    }

    fun home() {
        paused = false
        immersive = false
        screen = Screen.Start
        best = storage.loadBestScore()
        showName = accounts.snapshot().username == null && showName
    }

    fun openBoards(from: Screen) {
        recordClick(if (from == Screen.Start) "start" else "leaderboard", "leaderboard")
        boardsFrom = if (from == Screen.Death) Screen.Death else Screen.Start
        screen = Screen.Boards
        immersive = false
        refreshBoard()
    }

    fun closeBoards() {
        recordClick("leaderboard", "back")
        screen = boardsFrom
        immersive = screen == Screen.Play
    }

    fun selectPeriod(next: BoardPeriod) {
        if (next == period) return
        recordClick("leaderboard", com.paperglide.core.ClickMap.leaderboardPeriod(next))
        period = next
        refreshBoard()
    }

    fun retryRun() {
        play()
    }

    fun onPause() {
        if (screen == Screen.Play) paused = true
    }

    fun back(): Boolean {
        if (deleteOpen) {
            if (!deleting) deleteOpen = false
            return true
        }
        if (discardReport) {
            discardReport = false
            return true
        }
        if (reportOpen) {
            if (keyboardOpen) {
                keyboardOpen = false
                return true
            }
            if (reportText.isNotEmpty()) discardReport = true else reportOpen = false
            return true
        }
        if (showName && (screen == Screen.Start || screen == Screen.Death)) {
            if (keyboardOpen) {
                keyboardOpen = false
                return true
            }
            showName = false
            nameError = null
            accounts.dismissLaunchPrompt()
            accounts.dismissDeathPrompt()
            return true
        }
        when (screen) {
            Screen.Play -> {
                if (paused) resume() else pause()
                return true
            }
            Screen.Death -> {
                home()
                return true
            }
            Screen.Boards -> {
                closeBoards()
                return true
            }
            Screen.Start -> return false
        }
    }

    fun claim(name: String) {
        scope.launch {
            val snap = accounts.claim(name)
            nameError = snap.nameError
            if (snap.username != null) showName = false
        }
    }

    fun delete() {
        if (deleting) return
        deleting = true
        scope.launch {
            when (accounts.deleteMyData()) {
                DeleteResult.Deleted -> {
                    storage.clear()
                    events.clear()
                    sessionStore.clear()
                    deleting = false
                    deleteOpen = false
                    showName = true
                    nameError = null
                    deathNote = null
                    score = 0
                    best = 0
                    newBest = false
                    banner = DeleteCopy.success
                    screen = Screen.Start
                    immersive = false
                }
                DeleteResult.Offline -> {
                    deleting = false
                    banner = DeleteCopy.offline
                }
                DeleteResult.Failed -> {
                    deleting = false
                    banner = DeleteCopy.failure
                }
            }
        }
    }

    fun sendReport() {
        val category = reportCategory ?: return
        val text = reportText
        record(
            AnalyticsKind.Report,
            page = null,
            control = null,
            category = category,
            text = text,
        )
        reportOpen = false
        reportText = ""
        reportCategory = null
        banner = ReportCopy.saved
    }

    fun recordClickPublic(page: String, control: String) = recordClick(page, control)

    fun claimedName(): String? = accounts.snapshot().username

    fun refreshBoard() {
        val snap = accounts.snapshot()
        val presentation = BoardPresenter.present(
            period = period,
            cached = snap.boards[period],
            loading = period in snap.loading,
            online = snap.online,
            loadFailed = period in snap.loadFailed,
            syncFailed = snap.lastFlushFailed,
            username = snap.username,
            localBest = best,
            cacheTimeText = null,
        )
        boardLines = presentation.entries.map { "#${it.rank}  ${it.username}  ${it.score}" } +
            listOfNotNull(presentation.outsideLine, presentation.caption) + presentation.banners
        boardEmpty = presentation.emptyTitle ?: if (presentation.showOfflineEmpty) BoardCopy.offlineEmpty else null
        scope.launch {
            accounts.refresh(period)
            val again = accounts.snapshot()
            val shown = BoardPresenter.present(
                period, again.boards[period], period in again.loading, again.online,
                period in again.loadFailed, again.lastFlushFailed, again.username, best, null,
            )
            boardLines = shown.entries.map { "#${it.rank}  ${it.username}  ${it.score}" } +
                listOfNotNull(shown.outsideLine, shown.caption) + shown.banners
            boardEmpty = shown.emptyTitle ?: if (shown.showOfflineEmpty) BoardCopy.offlineEmpty else null
        }
    }

    private fun recordClick(page: String, control: String) = record(AnalyticsKind.Click, page, control, count = 1)

    private fun record(
        kind: AnalyticsKind,
        page: String?,
        control: String?,
        count: Int? = null,
        category: String? = null,
        text: String? = null,
    ) {
        events += QueuedEvent(
            id = UUID.randomUUID().toString(),
            kind = kind,
            occurredAt = Instant.now(),
            page = page,
            control = control,
            count = count,
            category = category,
            text = text,
        )
    }

    fun analyticsPlatforms(): List<String> = events.map { AnalyticsJson.event(it)["platform"].toString() }

    companion object {
        private fun extraInt(intent: Intent?, name: String): Int? =
            intent?.getStringExtra(name)?.toIntOrNull() ?: intent?.takeIf { it.hasExtra(name) }?.getIntExtra(name, Int.MIN_VALUE)?.takeIf { it != Int.MIN_VALUE }
        private fun extraLong(intent: Intent?, name: String): Long? =
            intent?.getStringExtra(name)?.toLongOrNull()
        private fun extraDouble(intent: Intent?, name: String): Double? =
            intent?.getStringExtra(name)?.toDoubleOrNull()
    }
}

private object OfflineBackend : AccountBackend {
    override suspend fun signInAnonymously() = throw AccountTransportError.Unreachable
    override suspend fun refresh(refreshToken: String) = throw AccountTransportError.Unreachable
    override suspend fun fetchUsername(accessToken: String): String? = throw AccountTransportError.Unreachable
    override suspend fun claimUsername(name: String, accessToken: String) = throw AccountTransportError.Unreachable
    override suspend fun submitRun(run: StoredRun, accessToken: String, platform: String) = throw AccountTransportError.Unreachable
    override suspend fun leaderboard(period: BoardPeriod, accessToken: String) = throw AccountTransportError.Unreachable
    override suspend fun deleteMyData(accessToken: String) = throw AccountTransportError.Unreachable
}

private class FakeDeleteBackend(private val mode: String) : AccountBackend {
    private val session = StoredSession("user-test", "access", "refresh", Instant.parse("2099-01-01T00:00:00Z"))
    override suspend fun signInAnonymously() = session
    override suspend fun refresh(refreshToken: String) = session
    override suspend fun fetchUsername(accessToken: String) = "owen"
    override suspend fun claimUsername(name: String, accessToken: String) = UsernameClaim.Saved(name)
    override suspend fun submitRun(run: StoredRun, accessToken: String, platform: String) = SubmitAck.Stored
    override suspend fun leaderboard(period: BoardPeriod, accessToken: String) =
        com.paperglide.core.LeaderboardPage(emptyList(), null, Instant.parse("2026-01-02T00:00:00Z"))
    override suspend fun deleteMyData(accessToken: String): Boolean = when (mode) {
        "ok" -> true
        "fail" -> false
        else -> throw AccountTransportError.Unreachable
    }
}
