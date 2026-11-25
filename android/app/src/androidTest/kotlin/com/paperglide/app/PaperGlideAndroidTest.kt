package com.paperglide.app

import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.paperglide.core.ShareCard
import com.paperglide.core.ShareMessage
import com.paperglide.core.ShareOffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runner.RunWith
import org.junit.runners.model.Statement
import java.io.File
import kotlin.math.abs
import kotlin.math.max

@Suppress("DEPRECATION")
private fun nestedIntent(intent: Intent): Intent? =
    if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
    else intent.getParcelableExtra(Intent.EXTRA_INTENT)

@Suppress("DEPRECATION")
private fun streamOf(intent: Intent): android.net.Uri? =
    if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, android.net.Uri::class.java)
    else intent.getParcelableExtra(Intent.EXTRA_STREAM)

private fun profile(): String =
    InstrumentationRegistry.getArguments().getString("profile") ?: "device"

private fun shot(name: String) {
    val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
    val bitmap = automation.takeScreenshot() ?: return
    val dir = InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir("screenshots")
        ?: return
    dir.mkdirs()
    val file = File(dir, "android-$name-${profile()}-api${Build.VERSION.SDK_INT}.png")
    file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
    bitmap.recycle()
}

class Flags(private val apply: () -> Unit) : TestRule {
    override fun apply(base: Statement, description: Description) = object : Statement() {
        override fun evaluate() {
            DebugLaunch.clear()
            apply()
            try {
                base.evaluate()
            } finally {
                DebugLaunch.clear()
            }
        }
    }
}

@RunWith(AndroidJUnit4::class)
class StartAndBackTest {
    @get:Rule(order = 0)
    val flags = Flags { DebugLaunch.resetStore = true }

    @get:Rule(order = 1)
    val compose = createAndroidComposeRule<MainActivity>()

    @After fun shots() = shot("start")

    @Test fun startShowsActionsAndSystemBackDoesNotAskToExit() {
        compose.onNodeWithTag("playButton").assertIsDisplayed().assertHeightIsAtLeast(48.dp)
        compose.onNodeWithTag("leaderboardButton").assertHeightIsAtLeast(48.dp)
        compose.onNodeWithTag("reportButton").assertIsDisplayed()
        compose.onNodeWithTag("deleteDataButton").assertIsDisplayed()
        compose.onNodeWithTag("paperSurface").assertIsDisplayed()
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.onNodeWithText("exit?", ignoreCase = true).assertDoesNotExist()
        shot("start-back")
    }

    @Test fun playBackPausesAndBackResumes() {
        compose.onNodeWithTag("playButton").performClick()
        compose.onNodeWithTag("playImmersive").assertIsDisplayed()
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.onNodeWithTag("pausedTitle").assertIsDisplayed()
        compose.onNodeWithText("Paused").assertIsDisplayed()
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.onNodeWithTag("pausedTitle").assertDoesNotExist()
        shot("play-pause")
    }

    @Test fun reportBackWithTextAsksToDiscard() {
        compose.onNodeWithTag("reportButton").performClick()
        compose.onNodeWithTag("reportText").performTextInput("the sky tore")
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.onNodeWithText("Discard report?").assertIsDisplayed()
        compose.onNodeWithTag("keepEditing").performClick()
        compose.onNodeWithTag("reportSheet").assertIsDisplayed()
        shot("report-discard")
    }

    @Test fun emptyReportBackCloses() {
        compose.onNodeWithTag("reportButton").performClick()
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.onNodeWithTag("reportSheet").assertDoesNotExist()
    }

    @Test fun deleteBackCancelsAndOfflineCopyLeavesState() {
        compose.onNodeWithTag("deleteDataButton").performClick()
        compose.onNodeWithText("Delete your data?").assertIsDisplayed()
        compose.onNodeWithText(com.paperglide.core.DeleteCopy.body).assertIsDisplayed()
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.onNodeWithText("Delete your data?").assertDoesNotExist()
        compose.onNodeWithTag("startBestScore").assertIsDisplayed()
        compose.onNodeWithTag("deleteDataButton").performClick()
        compose.onNodeWithTag("deleteConfirm").performClick()
        compose.onNodeWithText("You're offline. Connect and try again.").assertIsDisplayed()
        compose.onNodeWithTag("startBestScore").assertIsDisplayed()
        shot("delete-offline")
    }
}

@RunWith(AndroidJUnit4::class)
class DeathLayoutTest {
    @get:Rule(order = 0)
    val flags = Flags {
        DebugLaunch.resetStore = true
        DebugLaunch.worstCaseDeath = true
    }

    @get:Rule(order = 1)
    val compose = createAndroidComposeRule<MainActivity>()

    @Test fun fourButtonsFitAndDeathBackGoesHome() {
        for (tag in listOf("retryButton", "shareButton", "homeButton", "deathLeaderboardButton")) {
            compose.onNodeWithTag(tag).assertIsDisplayed().assertHeightIsAtLeast(48.dp)
        }
        compose.onNodeWithTag("newBestLabel").assertIsDisplayed()
        compose.onNodeWithTag("deathSyncNote").assertIsDisplayed()
        compose.onNodeWithTag("nameHelper").assertIsDisplayed()
        shot("death-worst")
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.onNodeWithTag("playButton").assertIsDisplayed()
        compose.onNodeWithTag("retryButton").assertDoesNotExist()
    }

    @Test fun boardsBackKeepsTheDeathScore() {
        compose.onNodeWithTag("deathLeaderboardButton").performClick()
        compose.onNodeWithTag("boardsScreen").assertIsDisplayed()
        compose.onNodeWithTag("period-Today").performClick()
        compose.onNodeWithTag("leaderboardBackButton").performClick()
        compose.onNodeWithTag("deathScore").assertIsDisplayed()
        compose.onNodeWithText("4").assertIsDisplayed()
        shot("boards")
    }

    @Test fun nameCardBackDropsTheDraft() {
        compose.onNodeWithTag("nameField").performTextInput("temp_name")
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.onNodeWithTag("nameCard").assertDoesNotExist()
        compose.onNodeWithText("temp_name").assertDoesNotExist()
    }

    @Test fun shareIntentCarriesTheCardAndSaveWritesAPicture() {
        compose.onNodeWithTag("shareButton").performClick()
        compose.waitUntil(8_000) { Sharing.lastIntent != null }
        val intent = Sharing.lastIntent!!
        val send = if (intent.action == Intent.ACTION_CHOOSER) nestedIntent(intent) else intent
        assertNotNull(send)
        assertEquals(ShareMessage.subject, send!!.getStringExtra(Intent.EXTRA_SUBJECT))
        assertTrue(send.getStringExtra(Intent.EXTRA_TEXT)!!.contains("I scored 4 in Paper Glide"))
        if (send.type == "image/png") {
            assertNotNull(streamOf(send))
            assertNotNull(send.clipData)
        }
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val png = ShareCards.png(ShareCards.render(com.paperglide.core.ShareCard.copy(4, null))!!)
        if (Build.VERSION.SDK_INT <= 28) {
            InstrumentationRegistry.getInstrumentation().uiAutomation
                .executeShellCommand("pm grant ${context.packageName} android.permission.WRITE_EXTERNAL_STORAGE")
                .close()
        }
        assertTrue(Sharing.save(context, png, 4))
        shot("share")
    }
}

@RunWith(AndroidJUnit4::class)
class DeleteSuccessTest {
    @get:Rule(order = 0)
    val flags = Flags {
        DebugLaunch.resetStore = true
        DebugLaunch.fakeDelete = "ok"
    }

    @get:Rule(order = 1)
    val compose = createAndroidComposeRule<MainActivity>()

    @Test fun confirmedDeleteReturnsToAFreshStart() {
        compose.onNodeWithTag("deleteDataButton").performClick()
        compose.onNodeWithTag("deleteConfirm").performClick()
        compose.onNodeWithText("Your data is deleted.").assertIsDisplayed()
        compose.onNodeWithTag("nameHelper").assertIsDisplayed()
        compose.onNodeWithTag("startBestScore").assertIsDisplayed()
    }
}

@RunWith(AndroidJUnit4::class)
class ShareCardPixelTest {
    @Test fun fourCasesStayNearTheIosGolden() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        AppContext.holder = context
        ShareCards.forceFail = false
        val cases = listOf(
            Triple("death-card-noname-0.png", 0, null as String?),
            Triple("death-card-owen-27.png", 27, "owen"),
            Triple("death-card-longname-4096.png", 4096, "skyward_pilot_01"),
        )
        for ((file, score, name) in cases) {
            val rendered = ShareCards.render(ShareCard.copy(score, name))
            assertNotNull(rendered)
            assertEquals(1080, rendered!!.width)
            assertEquals(1350, rendered.height)
            val golden = context.assets.open("golden/$file").use { BitmapFactory.decodeStream(it) }
            val mae = meanError(rendered, golden)
            assertTrue("$file mae=${mae.first} within=${mae.second}", mae.first <= 18.0 && mae.second >= 0.80)
            golden.recycle()
            rendered.recycle()
        }
        val twelve = ShareCards.render(ShareCard.copy(12, null))
        assertNotNull(twelve)
        assertEquals(1080, twelve!!.width)
        assertEquals(1350, twelve.height)
        val offer = com.paperglide.core.ShareCard.offer(12, null, ShareCards.png(twelve))
        assertTrue(offer is ShareOffer.Card)
        assertEquals("I scored 12 in Paper Glide", (offer as ShareOffer.Card).caption)
        twelve.recycle()
        ShareCards.forceFail = true
        val failed = Sharing.intent(context, 12, null)
        assertEquals("text/plain", failed.type)
        assertEquals("I scored 12 in Paper Glide", failed.getStringExtra(Intent.EXTRA_TEXT))
    }

    private fun meanError(actual: android.graphics.Bitmap, golden: android.graphics.Bitmap): Pair<Double, Double> {
        var total = 0.0
        var close = 0
        var count = 0
        val step = 2
        var y = 0
        while (y < actual.height) {
            var x = 0
            while (x < actual.width) {
                val a = actual.getPixel(x, y)
                val g = golden.getPixel(x, y)
                val d = max(max(abs(((a shr 16) and 255) - ((g shr 16) and 255)), abs(((a shr 8) and 255) - ((g shr 8) and 255))), abs((a and 255) - (g and 255)))
                total += d
                if (d <= 32) close += 1
                count += 1
                x += step
            }
            y += step
        }
        return (total / count) to (close.toDouble() / count)
    }
}

@RunWith(AndroidJUnit4::class)
class FontScaleDeathTest {
    @get:Rule(order = 0)
    val flags = Flags {
        DebugLaunch.resetStore = true
        DebugLaunch.worstCaseDeath = true
        InstrumentationRegistry.getInstrumentation().uiAutomation
            .executeShellCommand("settings put system font_scale 1.3").close()
    }

    @get:Rule(order = 1)
    val compose = createAndroidComposeRule<MainActivity>()

    @After fun restore() {
        InstrumentationRegistry.getInstrumentation().uiAutomation
            .executeShellCommand("settings put system font_scale 1.0").close()
    }

    @Test fun largeFontKeepsLabelsReachable() {
        for (tag in listOf("retryButton", "shareButton", "homeButton", "deathLeaderboardButton")) {
            compose.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
        }
        shot("death-font-1-3")
    }
}
