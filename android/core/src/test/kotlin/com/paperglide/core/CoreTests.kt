package com.paperglide.core

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
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
        for (name in listOf(
            "physics-one-flap-half-second",
            "seed1-pilot-until-death",
            "seed7-scripted-taps",
            "rate-60",
            "rate-90",
            "rate-120",
        )) {
            replay(root, name)
        }
    }

    @Test
    fun rampAndSkyFixturesMatch() {
        val root = goldenRoot()
        val ramp = JSONArray(File(root, "ramp.json").readText())
        for (index in 0 until ramp.length()) {
            val row = ramp.getJSONObject(index)
            val level = DifficultyRamp.standardLevel(row.getInt("score"))
            assertEquals(row.getInt("stepIndex"), level.stepIndex)
            assertEquals(row.getDouble("gapHeight"), level.gapHeight, 1e-9)
            assertEquals(row.getDouble("scrollSpeed"), level.scrollSpeed, 1e-9)
        }
        val sky = JSONArray(File(root, "sky.json").readText())
        for (index in 0 until sky.length()) {
            val row = sky.getJSONObject(index)
            val sample = SkyCycle.sample(row.getDouble("flightTime"))
            assertClose(row.getJSONArray("top"), sample.top)
            assertClose(row.getJSONArray("bottom"), sample.bottom)
            assertEquals(row.getDouble("sunAltitude"), sample.sunAltitude, 1e-9)
            assertEquals(row.getDouble("sunX"), sample.sunX, 1e-9)
            assertEquals(row.getDouble("sunAlpha"), sample.sunAlpha, 1e-9)
            assertEquals(row.getDouble("moonAlpha"), sample.moonAlpha, 1e-9)
            assertEquals(row.getDouble("starAlpha"), sample.starAlpha, 1e-9)
        }
    }

    @Test
    fun sixtyAndOneTwentyMatchAndNinetyStaysWithinTwoPoints() {
        val root = goldenRoot()
        val y60 = replay(root, "rate-60").plane.y
        val y90 = replay(root, "rate-90").plane.y
        val y120 = replay(root, "rate-120").plane.y
        assertEquals(y60, y120, 1e-6)
        assertEquals(y60, y90, 2.0)
        assertTrue(kotlin.math.abs(y60 - y90) > 0.5)
    }

    private fun replay(root: File, name: String): GameSnapshot {
        val json = JSONObject(File(root, "$name.json").readText())
        val config = GameConfig.standard.copy(spawningEnabled = json.getBoolean("spawning"))
        val storage = InMemoryGameStorage(json.getInt("bestScore"), json.getBoolean("coachCompleted"))
        val session = GameSession(config, storage, json.getLong("seed").toULong())
        val steps = json.getJSONArray("steps")
        for (index in 0 until steps.length()) {
            val step = steps.getJSONObject(index)
            if (step.getBoolean("tap")) session.tap()
            session.step(step.getDouble("dt"))
        }
        val actual = session.snapshot
        expectSnapshot(name, json.getJSONObject("expect"), actual)
        return actual
    }

    private fun expectSnapshot(name: String, expect: JSONObject, actual: GameSnapshot) {
        val phase = if (expect.getString("phase") == "playing") RunPhase.Playing else RunPhase.Dead
        assertEquals("$name phase", phase, actual.phase)
        assertEquals("$name score", expect.getInt("score"), actual.score)
        assertEquals("$name best", expect.getInt("bestScore"), actual.bestScore)
        assertEquals("$name newBest", expect.getBoolean("isNewBest"), actual.isNewBest)
        assertEquals("$name coach", expect.getBoolean("showCoach"), actual.showCoach)
        assertEquals("$name time", expect.getDouble("flightTime"), actual.flightTime, 1e-6)
        assertEquals("$name scroll", expect.getDouble("scrollSpeed"), actual.scrollSpeed, 1e-6)
        assertEquals("$name gap", expect.getDouble("spawnGapHeight"), actual.spawnGapHeight, 1e-6)
        val plane = expect.getJSONObject("plane")
        assertEquals("$name x", plane.getDouble("x"), actual.plane.x, 1e-6)
        assertEquals("$name y", plane.getDouble("y"), actual.plane.y, 1e-6)
        assertEquals("$name vy", plane.getDouble("velocityY"), actual.plane.velocityY, 1e-6)
        val obstacles = expect.getJSONArray("obstacles")
        assertEquals("$name obstacles", obstacles.length(), actual.obstacles.size)
        for (index in 0 until obstacles.length()) {
            val row = obstacles.getJSONObject(index)
            val got = actual.obstacles[index]
            assertEquals(row.getInt("id"), got.id)
            assertEquals(row.getDouble("left"), got.left, 1e-6)
            assertEquals(row.getDouble("gapCenterY"), got.gapCenterY, 1e-6)
            assertEquals(row.getDouble("gapHeight"), got.gapHeight, 1e-6)
            assertEquals(row.getBoolean("scored"), got.scored)
        }
    }

    private fun assertClose(row: JSONArray, color: PaperRGB) {
        assertEquals(row.getDouble(0), color.r, 1e-9)
        assertEquals(row.getDouble(1), color.g, 1e-9)
        assertEquals(row.getDouble(2), color.b, 1e-9)
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
