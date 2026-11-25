package com.paperglide.app

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.paperglide.core.BoardPeriod
import com.paperglide.core.CachedBoard
import com.paperglide.core.CloudStore
import com.paperglide.core.GameStorage
import com.paperglide.core.SessionStore
import com.paperglide.core.StoredRun
import com.paperglide.core.StoredSession
import org.json.JSONObject
import java.time.Instant

/** Keystore-backed prefs. This file is excluded from Auto Backup and device transfer. */
class KeystorePrefs(context: Context) {
    val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        FILE,
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun clear() {
        prefs.edit().clear().commit()
    }

    companion object {
        const val FILE = "paper_glide_secure"
    }
}

class PrefSessionStore(private val secure: SharedPreferences) : SessionStore {
    override fun load(): StoredSession? {
        val user = secure.getString(USER, null) ?: return null
        val access = secure.getString(ACCESS, null) ?: return null
        val refresh = secure.getString(REFRESH, null) ?: return null
        val expires = secure.getLong(EXPIRES, 0L)
        if (expires == 0L) return null
        return StoredSession(user, access, refresh, Instant.ofEpochMilli(expires))
    }

    override fun save(session: StoredSession) {
        secure.edit()
            .putString(USER, session.userID)
            .putString(ACCESS, session.accessToken)
            .putString(REFRESH, session.refreshToken)
            .putLong(EXPIRES, session.expiresAt.toEpochMilli())
            .commit()
    }

    override fun clear() {
        secure.edit().remove(USER).remove(ACCESS).remove(REFRESH).remove(EXPIRES).commit()
    }

    companion object {
        const val USER = "user_id"
        const val ACCESS = "access_token"
        const val REFRESH = "refresh_token"
        const val EXPIRES = "expires_at"
    }
}

class PrefGameStorage(private val prefs: SharedPreferences) : GameStorage {
    override fun loadBestScore(): Int = prefs.getInt(BEST, 0)
    override fun saveBestScore(score: Int) { prefs.edit().putInt(BEST, score).apply() }
    override fun loadCoachCompleted(): Boolean = prefs.getBoolean(COACH, false)
    override fun saveCoachCompleted(completed: Boolean) { prefs.edit().putBoolean(COACH, completed).apply() }
    override fun clear() { prefs.edit().remove(BEST).remove(COACH).apply() }

    companion object {
        const val BEST = "paperGlide.bestScore"
        const val COACH = "paperGlide.coachCompleted"
    }
}

class MemoryCloud : CloudStore {
    private var runs = emptyList<StoredRun>()
    private var username: String? = null
    private var userID: String? = null
    override fun loadRuns() = runs
    override fun saveRuns(runs: List<StoredRun>) { this.runs = runs }
    override fun loadUsername() = username
    override fun saveUsername(username: String?) { this.username = username }
    override fun loadUserID() = userID
    override fun saveUserID(userID: String?) { this.userID = userID }
    override fun loadBoard(period: BoardPeriod): CachedBoard? = null
    override fun saveBoard(board: CachedBoard?, period: BoardPeriod) = Unit
    override fun clear() {
        runs = emptyList()
        username = null
        userID = null
    }
}

fun userIdFromJwt(token: String): String? {
    val parts = token.split('.')
    if (parts.size < 2) return null
    return try {
        val payload = Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        JSONObject(String(payload)).optString("sub").ifBlank { null }
    } catch (_: Exception) {
        null
    }
}
