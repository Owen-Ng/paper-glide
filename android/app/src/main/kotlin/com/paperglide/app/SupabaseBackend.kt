package com.paperglide.app

import android.content.Context
import com.paperglide.core.AccountBackend
import com.paperglide.core.AccountTransportError
import com.paperglide.core.BoardEntry
import com.paperglide.core.BoardPeriod
import com.paperglide.core.LeaderboardPage
import com.paperglide.core.StoredRun
import com.paperglide.core.StoredSession
import com.paperglide.core.SubmitAck
import com.paperglide.core.SupabaseConfig
import com.paperglide.core.UsernameClaim
import com.paperglide.core.UsernameRejection
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.user.UserSession
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.postgrest
import io.ktor.client.plugins.HttpRequestTimeoutException
import io.ktor.utils.io.errors.IOException
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import java.time.Instant
import kotlin.time.Clock

class SupabaseAccountBackend(
    context: Context,
    private val config: SupabaseConfig,
) : AccountBackend {
    private val sessions = PrefSessionStore(KeystorePrefs(context).prefs)
    private val client = createSupabaseClient(config.url, config.anonKey) {
        install(Auth) {
            alwaysAutoRefresh = false
            autoLoadFromStorage = false
            autoSaveToStorage = false
        }
        install(Postgrest)
    }

    override suspend fun signInAnonymously(): StoredSession {
        try {
            client.auth.signInAnonymously()
        } catch (error: Exception) {
            throw map(error)
        }
        return currentSession()
    }

    override suspend fun refresh(refreshToken: String): StoredSession {
        try {
            client.auth.refreshSession(refreshToken)
        } catch (error: Exception) {
            throw map(error)
        }
        return currentSession()
    }

    override suspend fun fetchUsername(accessToken: String): String? = rpc("my_username", buildJsonObject {}, accessToken).let { json ->
        if (json.bool("ok") != true) throw AccountTransportError.BadResponse
        json.string("username")
    }

    override suspend fun claimUsername(name: String, accessToken: String): UsernameClaim {
        val json = rpc("claim_username", buildJsonObject { put("raw_name", JsonPrimitive(name)) }, accessToken)
        if (json.bool("ok") == true) {
            val saved = json.string("username").orEmpty()
            if (saved.isEmpty()) throw AccountTransportError.BadResponse
            return if (json.string("result") == "already_named") UsernameClaim.AlreadyNamed(saved) else UsernameClaim.Saved(saved)
        }
        val code = json.string("error") ?: throw AccountTransportError.BadResponse
        val rejection = when (code) {
            "too_short" -> UsernameRejection.TooShort
            "must_start_with_letter" -> UsernameRejection.MustStartWithLetter
            "invalid" -> UsernameRejection.Invalid
            "taken" -> UsernameRejection.Taken
            "unavailable" -> UsernameRejection.Unavailable
            else -> throw AccountTransportError.BadResponse
        }
        return UsernameClaim.Rejected(rejection)
    }

    override suspend fun submitRun(run: StoredRun, accessToken: String, platform: String): SubmitAck {
        val json = rpc(
            "submit_run",
            buildJsonObject {
                put("run_id", JsonPrimitive(run.id))
                put("score", JsonPrimitive(run.score))
                put("duration_seconds", JsonPrimitive(run.durationSeconds))
                put("played_at", JsonPrimitive(run.playedAt.toString()))
                put("platform", JsonPrimitive(platform))
            },
            accessToken,
        )
        if (json.bool("ok") == true) {
            return if (json.string("result") == "duplicate") SubmitAck.Duplicate else SubmitAck.Stored
        }
        return when (json.string("error")) {
            "rejected" -> SubmitAck.Rejected
            "rate_limited" -> SubmitAck.RateLimited
            "needs_name" -> SubmitAck.NeedsName
            "stale" -> SubmitAck.Stale
            else -> throw AccountTransportError.BadResponse
        }
    }

    override suspend fun leaderboard(period: BoardPeriod, accessToken: String): LeaderboardPage {
        val json = rpc("leaderboard", buildJsonObject { put("period", JsonPrimitive(period.wire)) }, accessToken)
        if (json.bool("ok") != true) throw AccountTransportError.BadResponse
        val entries = json["entries"]?.let { element ->
            (element as? kotlinx.serialization.json.JsonArray)?.mapNotNull { row ->
                val obj = row.jsonObject
                val username = obj.string("username") ?: return@mapNotNull null
                val score = obj.int("score") ?: return@mapNotNull null
                val rank = obj.int("rank") ?: return@mapNotNull null
                BoardEntry(rank, username, score, false)
            }
        }.orEmpty()
        val you = json["you"]?.jsonObject?.let { obj ->
            val username = obj.string("username") ?: return@let null
            val score = obj.int("score") ?: return@let null
            val rank = obj.int("rank") ?: return@let null
            BoardEntry(rank, username, score, false)
        }
        val fetched = json.string("fetched_at")?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: Instant.now()
        return LeaderboardPage(entries, you, fetched)
    }

    override suspend fun deleteMyData(accessToken: String): Boolean {
        val json = rpc("delete_my_data", buildJsonObject {}, accessToken)
        return json.bool("ok") == true && json.string("result") == "deleted"
    }

    private suspend fun rpc(name: String, body: JsonObject, accessToken: String): JsonObject {
        import(accessToken)
        val result = try {
            client.postgrest.rpc(name, body)
        } catch (error: Exception) {
            throw map(error)
        }
        return kotlinx.serialization.json.Json.parseToJsonElement(result.data).jsonObject
    }

    private suspend fun import(accessToken: String) {
        val stored = sessions.load()
        if (stored != null && stored.accessToken == accessToken) {
            val expiresIn = (stored.expiresAt.epochSecond - Clock.System.now().epochSeconds).coerceAtLeast(1)
            client.auth.importSession(
                UserSession(
                    accessToken = stored.accessToken,
                    refreshToken = stored.refreshToken,
                    expiresIn = expiresIn,
                    tokenType = "bearer",
                    expiresAt = kotlin.time.Instant.fromEpochMilliseconds(stored.expiresAt.toEpochMilli()),
                ),
            )
        }
    }

    private fun currentSession(): StoredSession {
        val session = client.auth.currentSessionOrNull() ?: throw AccountTransportError.BadResponse
        val userID = session.user?.id ?: userIdFromJwt(session.accessToken) ?: throw AccountTransportError.BadResponse
        val expires = Instant.ofEpochMilli(session.expiresAt.toEpochMilliseconds())
        val stored = StoredSession(userID, session.accessToken, session.refreshToken, expires)
        sessions.save(stored)
        return stored
    }

    private fun map(error: Exception): AccountTransportError {
        if (error is AccountTransportError) return error
        val text = error.message.orEmpty()
        if (error is IOException || error is HttpRequestTimeoutException || text.contains("Unable to resolve", true)) {
            return AccountTransportError.Unreachable
        }
        if (text.contains("401") || text.contains("403")) return AccountTransportError.Unauthorized
        return AccountTransportError.BadResponse
    }
}

private fun JsonObject.bool(key: String): Boolean? = this[key]?.jsonPrimitive?.booleanOrNull
    ?: this[key]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull()

private fun JsonObject.string(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull

private fun JsonObject.int(key: String): Int? = this[key]?.jsonPrimitive?.intOrNull
    ?: this[key]?.jsonPrimitive?.longOrNull?.toInt()
    ?: this[key]?.jsonPrimitive?.contentOrNull?.toDoubleOrNull()?.toInt()
