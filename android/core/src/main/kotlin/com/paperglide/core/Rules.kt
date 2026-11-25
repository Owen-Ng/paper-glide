package com.paperglide.core

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
object ShareMessage {
    const val subject = "Paper Glide"

    fun text(score: Int, username: String?): String {
        val name = username?.trim().orEmpty()
        return if (name.isEmpty()) {
            "I scored $score in Paper Glide"
        } else {
            "I scored $score in Paper Glide as $name"
        }
    }
}

data class ShareCardCopy(
    val title: String,
    val scoredLine: String,
    val scoreText: String,
    val caption: String,
    val subject: String,
)

sealed class ShareOffer {
    data class Card(val png: ByteArray, val caption: String) : ShareOffer()
    data class Text(val caption: String) : ShareOffer()
}

object ShareCard {
    const val pixelWidth = 1080
    const val pixelHeight = 1350
    const val maxTextWidth = 920.0
    const val logoSide = 240.0
    const val logoTop = 210.0
    const val titlePointSize = 84.0
    const val scoredPointSize = 58.0
    const val scoredShrinkStep = 2.0
    const val scorePointSize = 300.0
    const val scoreShrinkStep = 10.0
    const val titleTop = 490.0
    const val scoredTop = 640.0
    const val scoreInkTop = 750.0

    fun copy(score: Int, username: String?): ShareCardCopy {
        val name = username?.trim().orEmpty()
        val scoredLine = if (name.isEmpty()) "I scored" else "$name scored"
        return ShareCardCopy(
            title = ShareMessage.subject,
            scoredLine = scoredLine,
            scoreText = score.toString(),
            caption = ShareMessage.text(score, username),
            subject = ShareMessage.subject,
        )
    }

    fun offer(score: Int, username: String?, renderedPNG: ByteArray?): ShareOffer {
        val caption = ShareMessage.text(score, username)
        if (renderedPNG != null && renderedPNG.isNotEmpty()) return ShareOffer.Card(renderedPNG, caption)
        return ShareOffer.Text(caption)
    }

    fun pointSize(starting: Double, step: Double, maxWidth: Double, width: (Double) -> Double): Double {
        if (step <= 0 || maxWidth <= 0) return starting
        var size = starting
        var steps = 0
        while (width(size) > maxWidth && size > step && steps < 400) {
            size -= step
            steps += 1
        }
        return size
    }
}

enum class UsernameRejection {
    TooShort, MustStartWithLetter, Invalid, Taken, Unavailable,
}

object NameCopy {
    const val helper = "pick a name. letters, numbers and _ only. you can't change it later."
    const val tooShort = "at least 3 characters"
    const val startWithLetter = "start with a letter"
    const val taken = "that name's taken. try another"
    const val unavailable = "that name isn't available. try another"
    const val invalid = "that name won't work. try another"
    const val offline = "you're offline. we'll check this name when you're back"
    const val saveFailed = "couldn't save. try again"

    fun message(rejection: UsernameRejection): String = when (rejection) {
        UsernameRejection.TooShort -> tooShort
        UsernameRejection.MustStartWithLetter -> startWithLetter
        UsernameRejection.Invalid -> invalid
        UsernameRejection.Taken -> taken
        UsernameRejection.Unavailable -> unavailable
    }
}

object UsernameRules {
    const val minimumLength = 3
    const val maximumLength = 16
    val reserved = listOf("admin", "paperglide", "support", "moderator", "apple", "official")

    fun normalize(raw: String): String = raw.trim().lowercase()

    fun shapeProblem(raw: String): UsernameRejection? {
        val name = normalize(raw)
        if (name.length < minimumLength) return UsernameRejection.TooShort
        val first = name.firstOrNull()
        if (first == null || !isAsciiLetter(first)) return UsernameRejection.MustStartWithLetter
        if (name.length > maximumLength || !name.all { isAllowed(it) }) return UsernameRejection.Invalid
        return null
    }

    fun problem(raw: String): UsernameRejection? {
        shapeProblem(raw)?.let { return it }
        if (blocks(normalize(raw))) return UsernameRejection.Unavailable
        return null
    }

    fun blocks(raw: String): Boolean {
        val folded = normalize(raw).filter { it != '_' }.toList()
        return reserved.any { contains(folded, it.toList()) }
    }

    private fun contains(folded: List<Char>, word: List<Char>): Boolean {
        if (word.isEmpty() || folded.size < word.size) return false
        val lastStart = folded.size - word.size
        for (start in 0..lastStart) {
            var matched = true
            for (offset in word.indices) {
                if (!letter(word[offset], folded[start + offset])) {
                    matched = false
                    break
                }
            }
            if (matched) return true
        }
        return false
    }

    private fun letter(letter: Char, ch: Char): Boolean = when (letter) {
        'a' -> ch == 'a' || ch == '4'
        'b' -> ch == 'b' || ch == '8'
        'e' -> ch == 'e' || ch == '3'
        'g' -> ch == 'g' || ch == '6' || ch == '9'
        'i' -> ch == 'i' || ch == '1'
        'l' -> ch == 'l' || ch == '1'
        'o' -> ch == 'o' || ch == '0'
        's' -> ch == 's' || ch == '5'
        't' -> ch == 't' || ch == '7'
        'z' -> ch == 'z' || ch == '2'
        else -> ch == letter
    }

    private fun isAsciiLetter(ch: Char): Boolean = ch in 'a'..'z'
    private fun isAllowed(ch: Char): Boolean = ch == '_' || ch in 'a'..'z' || ch in '0'..'9'
}

object RunRules {
    const val slack = 3.0
    const val maxDurationSeconds = 3600.0
    const val hardCeiling = 2500
    const val minSubmitGapSeconds = 10.0
    const val dailySubmitCap = 500
    const val futureLimitSeconds = 24 * 60 * 60.0
    const val ageLimitSeconds = 30 * 24 * 60 * 60.0

    fun exceedsScoreRate(score: Int, durationSeconds: Double): Boolean {
        if (score < 0 || !durationSeconds.isFinite() || durationSeconds < 0) return true
        if (durationSeconds > maxDurationSeconds) return true
        if (score > hardCeiling) return true
        return score.toDouble() > durationSeconds / 1.5 + slack
    }

    fun isOutsidePlayedAtWindow(playedAt: Instant, now: Instant): Boolean {
        val delta = playedAt.epochSecond - now.epochSecond +
            (playedAt.nano - now.nano) / 1_000_000_000.0
        return delta > futureLimitSeconds || -delta > ageLimitSeconds
    }

    fun counts(period: BoardPeriod, playedAt: Instant, syncedAt: Instant): Boolean = when (period) {
        BoardPeriod.AllTime -> true
        BoardPeriod.Daily -> TorontoPeriod.dayKey(playedAt) == TorontoPeriod.dayKey(syncedAt)
        BoardPeriod.Weekly -> TorontoPeriod.weekKey(playedAt) == TorontoPeriod.weekKey(syncedAt)
    }
}

enum class BoardPeriod(val wire: String) {
    Daily("daily"),
    Weekly("weekly"),
    AllTime("all_time"),
}

object TorontoPeriod {
    const val identifier = "America/Toronto"
    private val zone: ZoneId = ZoneId.of(identifier)

    fun dayKey(instant: Instant): String {
        val date = ZonedDateTime.ofInstant(instant, zone).toLocalDate()
        return "%04d-%02d-%02d".format(date.year, date.monthValue, date.dayOfMonth)
    }

    fun weekKey(instant: Instant): String {
        val date = ZonedDateTime.ofInstant(instant, zone).toLocalDate()
        val daysFromMonday = (date.dayOfWeek.value + 6) % 7
        val monday = date.minusDays(daysFromMonday.toLong())
        return "%04d-%02d-%02d".format(monday.year, monday.monthValue, monday.dayOfMonth)
    }

    fun monthKey(instant: Instant): String {
        val date = ZonedDateTime.ofInstant(instant, zone).toLocalDate()
        return "%04d-%02d".format(date.year, date.monthValue)
    }

    fun monthStartKey(instant: Instant): String = monthKey(instant) + "-01"

    fun bucketKey(instant: Instant, grouping: TorontoGrouping): String = when (grouping) {
        TorontoGrouping.Day -> dayKey(instant)
        TorontoGrouping.Week -> weekKey(instant)
        TorontoGrouping.Month -> monthStartKey(instant)
    }
}

enum class TorontoGrouping { Day, Week, Month }

data class PaperRGB(val r: Double, val g: Double, val b: Double) {
    fun mix(other: PaperRGB, t: Double): PaperRGB {
        val c = t.coerceIn(0.0, 1.0)
        return PaperRGB(r + (other.r - r) * c, g + (other.g - g) * c, b + (other.b - b) * c)
    }
}

/** Morning → day → sunset → night → sunrise. 75 seconds of flight time, not wall time. */
object SkyCycle {
    const val duration = 75.0
    const val horizonFraction = 0.655
    const val zenithFraction = 0.90
    const val moonXFraction = 0.16
    const val moonYFraction = 0.86

    data class Sample(
        val top: PaperRGB,
        val bottom: PaperRGB,
        val sun: PaperRGB,
        val sunAlpha: Double,
        val sunAltitude: Double,
        val sunX: Double,
        val moonAlpha: Double,
        val starAlpha: Double,
    )

    val collagePapers = listOf(
        PaperRGB(0.78, 0.74, 0.68),
        PaperRGB(0.73, 0.76, 0.78),
        PaperRGB(0.76, 0.72, 0.74),
        PaperRGB(0.80, 0.76, 0.70),
        PaperRGB(0.72, 0.74, 0.70),
        PaperRGB(0.77, 0.73, 0.69),
        PaperRGB(0.74, 0.75, 0.77),
    )

    private data class Phase(val duration: Double, val top: PaperRGB, val bottom: PaperRGB)
    private val phases = listOf(
        Phase(15.0, PaperRGB(0.74, 0.86, 0.93), PaperRGB(0.97, 0.94, 0.86)),
        Phase(20.0, PaperRGB(0.48, 0.74, 0.95), PaperRGB(0.82, 0.92, 0.98)),
        Phase(15.0, PaperRGB(0.46, 0.34, 0.55), PaperRGB(0.96, 0.67, 0.48)),
        Phase(15.0, PaperRGB(0.31, 0.37, 0.56), PaperRGB(0.47, 0.52, 0.68)),
        Phase(10.0, PaperRGB(0.63, 0.74, 0.88), PaperRGB(0.98, 0.84, 0.78)),
    )

    private data class SunKey(val time: Double, val altitude: Double, val x: Double, val alpha: Double, val color: PaperRGB)
    private val sunKeys = listOf(
        SunKey(0.0, 0.34, 0.62, 1.0, PaperRGB(1.00, 0.93, 0.70)),
        SunKey(15.0, 0.78, 0.70, 1.0, PaperRGB(1.00, 0.90, 0.60)),
        SunKey(25.0, 1.00, 0.76, 1.0, PaperRGB(1.00, 0.96, 0.72)),
        SunKey(35.0, 0.68, 0.82, 1.0, PaperRGB(1.00, 0.76, 0.42)),
        SunKey(47.0, 0.22, 0.87, 1.0, PaperRGB(0.98, 0.58, 0.34)),
        SunKey(52.0, -0.05, 0.88, 0.0, PaperRGB(0.93, 0.48, 0.32)),
        SunKey(65.0, -0.18, 0.56, 0.0, PaperRGB(0.99, 0.84, 0.72)),
        SunKey(71.0, 0.10, 0.58, 0.7, PaperRGB(1.00, 0.88, 0.70)),
        SunKey(75.0, 0.34, 0.62, 1.0, PaperRGB(1.00, 0.93, 0.70)),
    )

    private data class ScalarKey(val time: Double, val value: Double)
    private val moonKeys = listOf(
        ScalarKey(0.0, 0.0), ScalarKey(40.0, 0.0), ScalarKey(50.0, 0.65),
        ScalarKey(56.0, 1.0), ScalarKey(64.0, 1.0), ScalarKey(69.0, 0.0), ScalarKey(75.0, 0.0),
    )
    private val starKeys = listOf(
        ScalarKey(0.0, 0.0), ScalarKey(46.0, 0.0), ScalarKey(54.0, 0.55),
        ScalarKey(62.0, 0.55), ScalarKey(68.0, 0.0), ScalarKey(75.0, 0.0),
    )

    fun sample(flightTime: Double): Sample {
        val colors = skyColors(flightTime)
        val sun = sunState(flightTime)
        return Sample(colors.first, colors.second, sun.color, sun.alpha, sun.altitude, sun.x, scalar(moonKeys, flightTime), scalar(starKeys, flightTime))
    }

    fun sunHeightFraction(sample: Sample): Double =
        horizonFraction + sample.sunAltitude * (zenithFraction - horizonFraction)

    fun cloudTint(sample: Sample): PaperRGB = PaperRGB(0.99, 0.98, 0.96).mix(sample.bottom, 0.34)

    fun buildingTint(base: PaperRGB, sample: Sample): PaperRGB =
        base.mix(sample.bottom, 0.50).mix(PaperRGB(0.90, 0.87, 0.82), 0.30)

    private fun skyColors(time: Double): Pair<PaperRGB, PaperRGB> {
        val t = wrapped(time)
        var cursor = 0.0
        for (index in phases.indices) {
            val phase = phases[index]
            val end = cursor + phase.duration
            if (t < end || index == phases.lastIndex) {
                val local = (t - cursor).coerceIn(0.0, phase.duration)
                val blend = phase.duration * 0.30
                val hold = phase.duration - blend
                val next = phases[(index + 1) % phases.size]
                if (local <= hold || blend <= 0) return phase.top to phase.bottom
                val eased = smooth((local - hold) / blend)
                return phase.top.mix(next.top, eased) to phase.bottom.mix(next.bottom, eased)
            }
            cursor = end
        }
        return phases[0].top to phases[0].bottom
    }

    private data class SunState(val altitude: Double, val x: Double, val alpha: Double, val color: PaperRGB)

    private fun sunState(time: Double): SunState {
        val t = wrapped(time)
        if (t <= sunKeys[0].time) {
            val key = sunKeys[0]
            return SunState(key.altitude, key.x, key.alpha, key.color)
        }
        for (index in 1 until sunKeys.size) {
            val right = sunKeys[index]
            if (t <= right.time) {
                val left = sunKeys[index - 1]
                val span = right.time - left.time
                val eased = smooth(if (span > 0) (t - left.time) / span else 0.0)
                return SunState(
                    left.altitude + (right.altitude - left.altitude) * eased,
                    left.x + (right.x - left.x) * eased,
                    left.alpha + (right.alpha - left.alpha) * eased,
                    left.color.mix(right.color, eased),
                )
            }
        }
        val key = sunKeys.last()
        return SunState(key.altitude, key.x, key.alpha, key.color)
    }

    private fun scalar(keys: List<ScalarKey>, time: Double): Double {
        val t = wrapped(time)
        val first = keys.first()
        val last = keys.last()
        if (t <= first.time) return first.value
        if (t >= last.time) return last.value
        for (index in 1 until keys.size) {
            val right = keys[index]
            if (t <= right.time) {
                val left = keys[index - 1]
                val span = right.time - left.time
                val eased = smooth(if (span > 0) (t - left.time) / span else 0.0)
                return left.value + (right.value - left.value) * eased
            }
        }
        return last.value
    }

    private fun wrapped(time: Double): Double {
        if (duration <= 0) return 0.0
        var t = time % duration
        if (t < 0) t += duration
        return t
    }

    private fun smooth(t: Double): Double {
        val x = t.coerceIn(0.0, 1.0)
        return x * x * (3 - 2 * x)
    }
}

object BoardCopy {
    const val noScoreToday = "no score today yet"
    const val noScoreWeek = "no score this week yet"
    const val beFirst = "no scores yet today. be the first"
    const val pickName = "pick a name to join the board"
    const val syncing = "syncing..."
    const val dailyReset = "resets at midnight, toronto time"
    const val weeklyReset = "resets monday at midnight, toronto time"
    const val chipPending = "not synced. we'll keep trying"
    const val deathPending = "saved, will sync"
    const val syncRetry = "couldn't sync your scores. retry"
    const val offlineEmpty = "you're offline. the board will load when you're back online."
    const val loadFailed = "couldn't load the board. Retry"
    fun offlineCache(time: String) = "offline. showing scores from $time"
    fun outside(rank: Int) = "#$rank — you"
    fun localBest(score: Int) = "local best $score"
    fun caption(period: BoardPeriod): String? = when (period) {
        BoardPeriod.Daily -> dailyReset
        BoardPeriod.Weekly -> weeklyReset
        BoardPeriod.AllTime -> null
    }
}

object BoardTimeFormat {
    private val formatter = DateTimeFormatter.ofPattern("MMM d, h:mm a", java.util.Locale.US)
    fun string(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): String =
        formatter.format(ZonedDateTime.ofInstant(instant, zone))
}

data class BoardEntry(val rank: Int, val username: String, val score: Int, val isYou: Boolean)

data class LeaderboardPage(val entries: List<BoardEntry>, val you: BoardEntry?, val fetchedAt: Instant) {
    fun marking(username: String?): LeaderboardPage {
        if (username == null) {
            return copy(entries = entries.map { it.copy(isYou = false) }, you = null)
        }
        val marked = entries.map { it.copy(isYou = it.username == username) }
        val youEntry = when {
            you != null && you.username == username -> you.copy(isYou = true)
            else -> marked.firstOrNull { it.username == username }
        }
        return LeaderboardPage(marked, youEntry, fetchedAt)
    }
}

data class CachedBoard(val page: LeaderboardPage)

data class BoardPresentation(
    val showSkeleton: Boolean = false,
    val entries: List<BoardEntry> = emptyList(),
    val outsideLine: String? = null,
    val outsideScore: Int? = null,
    val emptyTitle: String? = null,
    val emptyDetail: String? = null,
    val banners: List<String> = emptyList(),
    val showOfflineEmpty: Boolean = false,
    val localBestLine: String? = null,
    val caption: String? = null,
    val canPullToRefresh: Boolean = false,
)

object BoardPresenter {
    fun present(
        period: BoardPeriod,
        cached: CachedBoard?,
        loading: Boolean,
        online: Boolean,
        loadFailed: Boolean,
        syncFailed: Boolean,
        username: String?,
        localBest: Int,
        cacheTimeText: String?,
    ): BoardPresentation {
        val banners = ArrayList<String>()
        if (syncFailed) banners += BoardCopy.syncRetry
        val caption = BoardCopy.caption(period)
        if (cached == null) {
            if (!online) {
                return BoardPresentation(
                    banners = banners,
                    showOfflineEmpty = true,
                    localBestLine = BoardCopy.localBest(localBest),
                    caption = caption,
                )
            }
            if (loading || !loadFailed) {
                return BoardPresentation(showSkeleton = true, caption = caption, canPullToRefresh = true)
            }
            banners += BoardCopy.loadFailed
            return BoardPresentation(banners = banners, caption = caption, canPullToRefresh = true)
        }
        if (!online && cacheTimeText != null) banners.add(0, BoardCopy.offlineCache(cacheTimeText))
        else if (loadFailed) banners += BoardCopy.loadFailed
        val entries = cached.page.entries
        var outsideLine: String? = null
        var outsideScore: Int? = null
        val you = cached.page.you
        if (you != null && entries.none { it.username == you.username }) {
            outsideLine = BoardCopy.outside(you.rank)
            outsideScore = you.score
        }
        var emptyTitle: String? = null
        var emptyDetail: String? = null
        if (entries.isEmpty()) {
            when {
                username == null -> emptyTitle = BoardCopy.pickName
                loading -> emptyTitle = BoardCopy.syncing
                period == BoardPeriod.Daily -> {
                    emptyTitle = BoardCopy.noScoreToday
                    emptyDetail = BoardCopy.beFirst
                }
                period == BoardPeriod.Weekly -> emptyTitle = BoardCopy.noScoreWeek
            }
        }
        return BoardPresentation(
            entries = entries,
            outsideLine = outsideLine,
            outsideScore = outsideScore,
            emptyTitle = emptyTitle,
            emptyDetail = emptyDetail,
            banners = banners,
            caption = caption,
            canPullToRefresh = online,
        )
    }
}

object ClickMap {
    val start = listOf("play", "leaderboard", "report", "other")
    val playing = listOf("flap")
    val leaderboard = listOf("Today", "This week", "All time", "back", "other", "scroll")
    val pages = listOf("start", "playing", "leaderboard")
    fun leaderboardPeriod(period: BoardPeriod): String = when (period) {
        BoardPeriod.Daily -> "Today"
        BoardPeriod.Weekly -> "This week"
        BoardPeriod.AllTime -> "All time"
    }
}

enum class ReportCategory(val label: String) {
    Crashed("The game crashed or froze"),
    Looks("Something looks wrong"),
    Leaderboard("Leaderboard or my name"),
    Idea("I have an idea"),
    Other("Something else"),
}

object ReportCopy {
    const val title = "Report a problem"
    const val line = "tell us what went wrong. we'll read every one."
    const val placeholder = "what happened? (optional)"
    const val smallPrint = "we'll include your app version and device model. no other info."
    const val send = "Send"
    const val cancel = "Cancel"
    const val discardTitle = "discard this report?"
    const val discard = "Discard"
    const val keepWriting = "Keep writing"
    const val thanks = "thanks. we got it"
    const val saved = "saved. we'll send it when you're back online"
    const val button = "Report a problem"

    /** Android system-back dialog. The sheet's own cancel keeps the iOS sentence. */
    const val backDiscardTitle = "Discard report?"
    const val backDiscard = "Discard"
    const val backKeepEditing = "Keep editing"
}

object ReportDraftRules {
    const val limit = 500
    const val counterFrom = 400
    fun clamped(text: String): String = if (text.length <= limit) text else text.take(limit)
    fun showsCounter(text: String): Boolean = text.length >= counterFrom
    fun counter(text: String): String = "${minOf(text.length, limit)}/$limit"
    fun sendEnabled(category: String?): Boolean = ReportCategory.entries.any { it.label == category }
    fun shouldConfirmDiscard(text: String): Boolean = text.isNotEmpty()
}

object DeleteCopy {
    const val link = "Delete my data"
    const val title = "Delete your data?"
    const val body = "This removes your name, scores and reports from Paper Glide's servers and resets this device. Your name becomes free for anyone to take. This can't be undone."
    const val cancel = "Cancel"
    const val delete = "Delete"
    const val progress = "Deleting..."
    const val success = "Your data is deleted."
    const val offline = "You're offline. Connect and try again."
    const val failure = "Something went wrong. Nothing was deleted. Try again."
}

/** The public deletion form ships later. The app only needs the URL. */
object PaperGlideLinks {
    const val dataDeletionUrl = "https://paperglide.app/delete"
    const val platform = "android"
}

/** Supabase config. A placeholder, or a service-role key, leaves the app offline. */
data class SupabaseConfig(val url: String, val anonKey: String, val isConfigured: Boolean) {
    companion object {
        fun load(url: String?, anonKey: String?): SupabaseConfig {
            val rawUrl = url?.trim().orEmpty()
            val key = anonKey?.trim().orEmpty()
            val host = runCatching { java.net.URI(rawUrl).host?.lowercase().orEmpty() }.getOrDefault("")
            val placeholderHost = host.isEmpty() || host.contains("your_project") || host.contains("example")
            val placeholderKey = key.isEmpty() ||
                key.contains("YOUR_SUPABASE", ignoreCase = true) ||
                key.contains("your-anon", ignoreCase = true) ||
                key.contains("service_role", ignoreCase = true)
            val configured = rawUrl.startsWith("https://") &&
                host.endsWith("supabase.co") &&
                !placeholderHost &&
                !placeholderKey
            return SupabaseConfig(rawUrl, key, configured)
        }
    }
}
