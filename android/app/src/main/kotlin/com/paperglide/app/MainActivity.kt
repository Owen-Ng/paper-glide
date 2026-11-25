package com.paperglide.app

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.mandatorySystemGestures
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
class MainActivity : ComponentActivity() {
    private lateinit var model: PaperModel

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        AppContext.holder = applicationContext
        enableEdgeToEdge()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            window.decorView.isForceDarkAllowed = false
        }
        model = PaperModel(applicationContext, lifecycleScope, intent)
        setContent {
            val bars = WindowInsets.systemBars.union(WindowInsets.displayCutout).union(WindowInsets.mandatorySystemGestures)
            PaperTheme {
                Box(Modifier.fillMaxSize().windowInsetsPadding(bars).padding()) {
                    AndroidView(
                        factory = { GameSurface(it, model) },
                        modifier = Modifier.fillMaxSize(),
                    )
                    BackHandler(enabled = backEnabled(model)) { model.back() }
                    PaperApp(model)
                    LaunchedEffect(model.screen, model.paused) {
                        val play = model.screen == Screen.Play
                        model.immersive = play
                        val controller = WindowInsetsControllerCompat(window, window.decorView)
                        if (play) {
                            controller.hide(WindowInsetsCompat.Type.systemBars())
                            controller.systemBarsBehavior =
                                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                        } else {
                            controller.show(WindowInsetsCompat.Type.systemBars())
                            controller.isAppearanceLightStatusBars = true
                            controller.isAppearanceLightNavigationBars = true
                        }
                    }
                    LaunchedEffect(model.shareRequested) {
                        if (!model.shareRequested) return@LaunchedEffect
                        val launch = Sharing.intent(this@MainActivity, model.score, model.claimedName())
                        model.shareRequested = false
                        startActivity(launch)
                    }
                }
            }
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onPause() {
        super.onPause()
        if (::model.isInitialized) model.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus && ::model.isInitialized) model.onPause()
    }
}

private fun backEnabled(model: PaperModel): Boolean {
    if (model.deleteOpen || model.reportOpen || model.discardReport || model.showName) return true
    return model.screen != Screen.Start
}
