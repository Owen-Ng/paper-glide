package com.paperglide.core

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.Instant

class CoreTests {
    @Test
    fun gravityAndFlapMatchTheShippedEulerStep() {
        val drop = FlightPhysics.integrate(300.0, 0.0, 0.1, 1000.0, false, 400.0, 1000.0, 1000.0)
        assertEquals(-100.0, drop.second, 1e-9)
        assertEquals(290.0, drop.first, 1e-9)
        val flap = FlightPhysics.integrate(300.0, -400.0, 0.1, 1000.0, true, 400.0, 1000.0, 1000.0)
        assertEquals(300.0, flap.second, 1e-9)
        assertEquals(330.0, flap.first, 1e-9)
        val capped = FlightPhysics.integrate(300.0, 0.0, 0.1, 0.0, true, 800.0, 500.0, 1000.0)
        assertEquals(500.0, capped.second, 1e-9)
        assertEquals(350.0, capped.first, 1e-9)
    }

    @Test
    fun rampReachesTheShippedCaps() {
        val open = DifficultyRamp.standardLevel(0)
        assertEquals(0, open.stepIndex)
        assertEquals(218.0, open.gapHeight, 0.0)
        assertEquals(148.0, open.scrollSpeed, 0.0)
        val sixty = DifficultyRamp.standardLevel(60)
        assertEquals(12, sixty.stepIndex)
        assertEquals(168.0, sixty.gapHeight, 0.0)
        assertEquals(196.0, sixty.scrollSpeed, 0.0)
        assertEquals(DifficultyRamp.standardLevel(100), DifficultyRamp.standardLevel(60))
    }

    @Test
    fun usernameRulesMatchTheSharedBlocklist() {
        assertEquals(UsernameRejection.TooShort, UsernameRules.problem("ab"))
        assertEquals(UsernameRejection.MustStartWithLetter, UsernameRules.problem("1owen"))
        assertEquals(UsernameRejection.Unavailable, UsernameRules.problem("adm1n"))
        assertEquals(UsernameRejection.Unavailable, UsernameRules.problem("appl3"))
        assertEquals(UsernameRejection.Unavailable, UsernameRules.problem("pap_erglide"))
        assertNull(UsernameRules.problem("Owen"))
        assertEquals("owen", UsernameRules.normalize("  Owen "))
        assertEquals(NameCopy.taken, NameCopy.message(UsernameRejection.Taken))
    }

    @Test
    fun shareCopyIsLocked() {
        assertEquals("I scored 12 in Paper Glide", ShareMessage.text(12, null))
        assertEquals("I scored 12 in Paper Glide", ShareMessage.text(12, "  "))
        assertEquals("I scored 27 in Paper Glide as owen", ShareMessage.text(27, "owen"))
        assertEquals("Paper Glide", ShareMessage.subject)
        val card = ShareCard.copy(4096, "skyward_pilot_01")
        assertEquals("skyward_pilot_01 scored", card.scoredLine)
        assertEquals("4096", card.scoreText)
        assertEquals("I scored 0 in Paper Glide", ShareCard.copy(0, null).caption)
        val text = ShareCard.offer(27, "owen", null)
        assertTrue(text is ShareOffer.Text)
        val png = ShareCard.offer(27, "owen", byteArrayOf(1))
        assertTrue(png is ShareOffer.Card)
        assertEquals("I scored 27 in Paper Glide as owen", (png as ShareOffer.Card).caption)
    }

    @Test
    fun torontoKeysMatchTheSwiftSuite() {
        fun iso(value: String) = Instant.parse(value)
        assertEquals("2026-03-08", TorontoPeriod.dayKey(iso("2026-03-08T06:30:00Z")))
        assertEquals("2026-03-08", TorontoPeriod.dayKey(iso("2026-03-08T07:30:00Z")))
        assertEquals("2026-03-02", TorontoPeriod.weekKey(iso("2026-03-08T06:30:00Z")))
        assertEquals("2026-03-07", TorontoPeriod.dayKey(iso("2026-03-08T04:30:00Z")))
        assertEquals("2026-03-08", TorontoPeriod.dayKey(iso("2026-03-08T05:30:00Z")))
        assertEquals("2026-03-08", TorontoPeriod.dayKey(iso("2026-03-09T03:30:00Z")))
        assertEquals("2026-03-09", TorontoPeriod.dayKey(iso("2026-03-09T04:00:00Z")))
        assertEquals("2026-03-02", TorontoPeriod.weekKey(iso("2026-03-09T03:30:00Z")))
        assertEquals("2026-03-09", TorontoPeriod.weekKey(iso("2026-03-09T04:00:00Z")))
        assertEquals("2026-11-01", TorontoPeriod.dayKey(iso("2026-11-01T05:30:00Z")))
        assertEquals("2026-11-01", TorontoPeriod.dayKey(iso("2026-11-01T06:30:00Z")))
        assertEquals("2026-10-26", TorontoPeriod.weekKey(iso("2026-11-01T06:30:00Z")))
        assertEquals("2026-11-01", TorontoPeriod.dayKey(iso("2026-11-02T04:30:00Z")))
        assertEquals("2026-11-02", TorontoPeriod.dayKey(iso("2026-11-02T05:30:00Z")))
        assertEquals("2026-10-26", TorontoPeriod.weekKey(iso("2026-11-02T04:30:00Z")))
        assertEquals("2026-11-02", TorontoPeriod.weekKey(iso("2026-11-02T05:30:00Z")))
        assertEquals("2026-11", TorontoPeriod.monthKey(iso("2026-11-01T05:30:00Z")))
        assertEquals("2026-11-01", TorontoPeriod.monthStartKey(iso("2026-11-01T06:30:00Z")))
        assertEquals("2026-07-15", TorontoPeriod.dayKey(iso("2026-07-16T03:30:00Z")))
        assertEquals("2026-07-13", TorontoPeriod.weekKey(iso("2026-07-16T03:30:00Z")))
        assertEquals("2026-07-01", TorontoPeriod.bucketKey(iso("2026-07-16T03:30:00Z"), TorontoGrouping.Month))
    }

    @Test
    fun placeholderConfigAndServiceRoleStayOffline() {
        assertFalse(SupabaseConfig.load("https://abc.supabase.co", "anon-key").isConfigured.not())
        assertFalse(SupabaseConfig.load("https://YOUR_PROJECT.supabase.co", "anon").isConfigured)
        assertFalse(SupabaseConfig.load("https://abc.supabase.co", "service_role-secret").isConfigured)
        assertFalse(SupabaseConfig.load("http://abc.supabase.co", "anon").isConfigured)
        assertEquals("https://paperglide.app/delete", PaperGlideLinks.dataDeletionUrl)
    }

    @Test
    fun deleteMyDataWipesOnlyAfterALiveOk() = kotlinx.coroutines.runBlocking {
        val backend = FakeBackend()
        val sessions = MemorySessionStore(StoredSession("user-1", "access", "refresh", Instant.parse("2099-01-01T00:00:00Z")))
        val store = MemoryCloudStore()
        store.username = "owen"
        store.userID = "user-1"
        store.runs = listOf(StoredRun("run", 4, 3.0, Instant.parse("2026-01-01T00:00:00Z"), RunSyncState.Pending))
        val sync = AccountSync(backend, sessions, store, configured = true, now = Instant.parse("2026-01-02T00:00:00Z"))
        sync.prepare(true)
        backend.online = false
        assertEquals(DeleteResult.Offline, sync.deleteMyData())
        assertEquals("owen", store.username)
        assertEquals(1, store.runs.size)
        backend.online = true
        backend.deleteOk = false
        assertEquals(DeleteResult.Failed, sync.deleteMyData())
        assertEquals("owen", store.username)
        backend.deleteOk = true
        assertEquals(DeleteResult.Deleted, sync.deleteMyData())
        assertNull(store.username)
        assertTrue(store.runs.isEmpty())
        assertNull(sessions.session)
        assertTrue(sync.snapshot().showsLaunchPrompt)
    }

    @Test
    fun submitRunSendsPlatformAndroid() = kotlinx.coroutines.runBlocking {
        val backend = FakeBackend()
        val sessions = MemorySessionStore(StoredSession("user-1", "access", "refresh", Instant.parse("2099-01-01T00:00:00Z")))
        val store = MemoryCloudStore().apply { username = "owen"; userID = "user-1" }
        val sync = AccountSync(backend, sessions, store, configured = true, now = Instant.parse("2026-01-02T00:00:00Z"))
        sync.prepare(true)
        sync.record(4, 8.0, Instant.parse("2026-01-02T00:00:00Z"))
        sync.flush()
        assertEquals("android", backend.lastPlatform)
        assertEquals(RunSyncState.Synced, store.runs.single().state)
    }

    @Test
    fun analyticsEventCarriesPlatform() {
        val event = QueuedEvent(
            id = "11111111-1111-1111-1111-111111111111",
            kind = AnalyticsKind.Click,
            occurredAt = Instant.parse("2026-01-02T00:00:00Z"),
            sessionID = "22222222-2222-2222-2222-222222222222",
            page = "start",
            control = "play",
            count = 1,
            context = AnalyticsContext("1", "16", "sdk_gphone64"),
        )
        val json = AnalyticsJson.event(event)
        assertEquals("android", json["platform"])
        assertEquals("click", json["kind"])
        assertEquals("play", json["control"])
        assertEquals("16", json["ios_version"])
        assertFalse(json.containsKey("text"))
    }

    @Test
    fun backdropSamplePixelsMatchTheIosGolden() {
        val pixels = ShareCardBackdrop.paint()
        val golden = javax.imageio.ImageIO.read(
            File(goldenRoot(), "../../evidence/219cd379d9c6a7d334962c28bba55c47ead6cbe0/death-card-owen-27.png"),
        )
        val samples = listOf(
            Triple(20, 20, "sky"),
            Triple(111, 1300, "facade"),
            Triple(112, 1300, "gap"),
            Triple(40, 1241, "facade top"),
            Triple(40, 1240, "above facade"),
            Triple(150, 170, "cloud"),
        )
        for ((x, y, label) in samples) {
            val got = ShareCardBackdrop.sample(pixels, x, y)
            val expect = golden.getRGB(x, y)
            val er = (expect shr 16) and 255
            val eg = (expect shr 8) and 255
            val eb = expect and 255
            assertEquals("$label r", er, got.first)
            assertEquals("$label g", eg, got.second)
            assertEquals("$label b", eb, got.third)
        }
    }

    @Test
    fun goldenFixturesMatchPaperGlideCore() {
        val root = goldenRoot()
        for (name in listOf("no-tap-fall", "fixed-taps", "pilot-ramp")) {
            replayFormat1(File(root, "$name.json"))
        }
    }

    @Test
    fun morningSkyMatchesTheShippedWash() {
        val morning = SkyCycle.sample(0.0)
        assertEquals(0.74, morning.top.r, 1e-9)
        assertEquals(0.86, morning.top.g, 1e-9)
        assertEquals(0.93, morning.top.b, 1e-9)
        assertEquals(0.34, morning.sunAltitude, 1e-9)
        assertEquals(0.62, morning.sunX, 1e-9)
        val wrapped = SkyCycle.sample(75.0)
        assertEquals(morning.top.r, wrapped.top.r, 1e-9)
        assertEquals(morning.sunAltitude, wrapped.sunAltitude, 1e-9)
    }

    @Test
    fun sixtyAndOneTwentyMatchAndNinetyStaysWithinTwoPoints() {
        val y60 = glideAt(1.0 / 60.0).plane.y
        val y90 = glideAt(1.0 / 90.0).plane.y
        val y120 = glideAt(1.0 / 120.0).plane.y
        assertEquals(y60, y120, 1e-6)
        assertEquals(y60, y90, 2.0)
        assertTrue(kotlin.math.abs(y60 - y90) > 0.5)
    }

    /** Same taps at t = 0, 0.5, and 1.0, then coast to 1.5 s. Not a golden file. */
    private fun glideAt(dt: Double): GameSnapshot {
        val session = GameSession(GameConfig.standard, InMemoryGameStorage(0, true), 3u)
        val taps = doubleArrayOf(0.0, 0.5, 1.0)
        var time = 0.0
        while (time < 1.5 - 1e-12 && session.snapshot.phase == RunPhase.Playing) {
            if (taps.any { kotlin.math.abs(it - time) < dt * 0.5 }) session.tap()
            session.step(dt)
            time += dt
        }
        return session.snapshot
    }

    /**
     * Format version 1 from PR #8. One recorded step is one `physicsStep`.
     * `tapSteps` are 1-based indexes of the integration that consumes the flap.
     */
    private fun replayFormat1(file: File) {
        val json = JSONObject(file.readText())
        assertEquals(1, json.getInt("format"))
        val tolerance = json.getJSONObject("tolerance")
        val position = tolerance.getDouble("position")
        val velocity = tolerance.getDouble("velocity")
        val time = tolerance.getDouble("time")
        val scroll = tolerance.getDouble("scroll")
        val gap = tolerance.getDouble("gap")
        val spacing = tolerance.getDouble("spacing")
        val configJson = json.getJSONObject("config")
        val config = GameConfig.standard.copy(
            worldWidth = configJson.getDouble("worldWidth"),
            worldHeight = configJson.getDouble("worldHeight"),
            gravity = configJson.getDouble("gravity"),
            flapVelocity = configJson.getDouble("flapVelocity"),
            maxUpwardSpeed = configJson.getDouble("maxUpwardSpeed"),
            maxDownwardSpeed = configJson.getDouble("maxDownwardSpeed"),
            planeX = configJson.getDouble("planeX"),
            planeWidth = configJson.getDouble("planeWidth"),
            planeHeight = configJson.getDouble("planeHeight"),
            planeStartY = configJson.getDouble("planeStartY"),
            obstacleWidth = configJson.getDouble("obstacleWidth"),
            obstacleGapHeight = configJson.getDouble("obstacleGapHeight"),
            obstacleSpacing = configJson.getDouble("obstacleSpacing"),
            scrollSpeed = configJson.getDouble("scrollSpeed"),
            gapMargin = configJson.getDouble("gapMargin"),
            initialLead = configJson.getDouble("initialLead"),
            despawnMargin = configJson.getDouble("despawnMargin"),
            physicsStep = configJson.getDouble("physicsStep"),
        )
        val session = GameSession(config, InMemoryGameStorage(), json.getLong("seed").toULong())
        val taps = json.getJSONArray("tapSteps").let { array ->
            buildSet { for (i in 0 until array.length()) add(array.getInt(i)) }
        }
        val timestep = json.getDouble("timestep")
        val steps = json.getJSONArray("steps")
        val name = json.getString("name")
        compareStep(name, 0, steps.getJSONObject(0), session.snapshot, position, velocity, time, scroll, gap, spacing)
        for (index in 1 until steps.length()) {
            if (index in taps) session.tap()
            session.step(timestep)
            compareStep(name, index, steps.getJSONObject(index), session.snapshot, position, velocity, time, scroll, gap, spacing)
        }
    }

    private fun compareStep(
        name: String,
        index: Int,
        expect: JSONObject,
        actual: GameSnapshot,
        position: Double,
        velocity: Double,
        time: Double,
        scroll: Double,
        gap: Double,
        spacing: Double,
    ) {
        val where = "$name step $index"
        assertEquals(where, index, expect.getInt("step"))
        val phase = if (expect.getString("phase") == "playing") RunPhase.Playing else RunPhase.Dead
        assertEquals("$where phase", phase, actual.phase)
        assertEquals("$where score", expect.getInt("score"), actual.score)
        assertEquals("$where time", expect.getDouble("flightTime"), actual.flightTime, time)
        assertEquals("$where scroll", expect.getDouble("scrollSpeed"), actual.scrollSpeed, scroll)
        assertEquals("$where gap", expect.getDouble("spawnGapHeight"), actual.spawnGapHeight, gap)
        val ramp = expect.getJSONObject("ramp")
        val level = DifficultyRamp.level(actual.score, GameConfig.standard.obstacleGapHeight, GameConfig.standard.scrollSpeed)
        assertEquals("$where ramp", ramp.getInt("stepIndex"), level.stepIndex)
        assertEquals("$where ramp gap", ramp.getDouble("gapHeight"), level.gapHeight, gap)
        assertEquals("$where ramp scroll", ramp.getDouble("scrollSpeed"), level.scrollSpeed, scroll)
        val plane = expect.getJSONObject("plane")
        assertEquals("$where x", plane.getDouble("x"), actual.plane.x, position)
        assertEquals("$where y", plane.getDouble("y"), actual.plane.y, position)
        assertEquals("$where vy", plane.getDouble("velocityY"), actual.plane.velocityY, velocity)
        val obstacles = expect.getJSONArray("obstacles")
        val got = actual.obstacles.sortedWith(compareBy({ it.left }, { it.id }))
        assertEquals("$where obstacles", obstacles.length(), got.size)
        var previous: Double? = null
        for (i in 0 until obstacles.length()) {
            val row = obstacles.getJSONObject(i)
            assertEquals("$where id", row.getInt("id"), got[i].id)
            assertEquals("$where left", row.getDouble("left"), got[i].left, position)
            assertEquals("$where width", row.getDouble("width"), got[i].width, position)
            assertEquals("$where center", row.getDouble("gapCenterY"), got[i].gapCenterY, position)
            assertEquals("$where opening", row.getDouble("gapHeight"), got[i].gapHeight, gap)
            if (row.has("spacingFromPrevious") && !row.isNull("spacingFromPrevious")) {
                val expected = previous?.let { got[i].left - it }
                assertEquals("$where spacing", row.getDouble("spacingFromPrevious"), expected ?: Double.NaN, spacing)
            }
            previous = got[i].left
        }
    }

    private fun goldenRoot(): File {
        val env = System.getenv("PAPER_GLIDE_FIXTURES")
        if (!env.isNullOrBlank()) return File(env)
        var dir: File? = File(System.getProperty("user.dir"))
        repeat(6) {
            val candidate = File(dir, "fixtures/golden")
            if (candidate.isDirectory) return candidate
            dir = dir?.parentFile
        }
        error("fixtures/golden not found from ${System.getProperty("user.dir")}")
    }
}

private class FakeBackend : AccountBackend {
    var online = true
    var deleteOk = true
    var lastPlatform: String? = null
    override suspend fun signInAnonymously() = StoredSession("user-1", "access", "refresh", Instant.parse("2099-01-01T00:00:00Z"))
    override suspend fun refresh(refreshToken: String) = signInAnonymously()
    override suspend fun fetchUsername(accessToken: String) = "owen"
    override suspend fun claimUsername(name: String, accessToken: String) = UsernameClaim.Saved(name)
    override suspend fun submitRun(run: StoredRun, accessToken: String, platform: String): SubmitAck {
        lastPlatform = platform
        if (!online) throw AccountTransportError.Unreachable
        return SubmitAck.Stored
    }
    override suspend fun leaderboard(period: BoardPeriod, accessToken: String) =
        LeaderboardPage(emptyList(), null, Instant.parse("2026-01-02T00:00:00Z"))
    override suspend fun deleteMyData(accessToken: String): Boolean {
        if (!online) throw AccountTransportError.Unreachable
        return deleteOk
    }
}
