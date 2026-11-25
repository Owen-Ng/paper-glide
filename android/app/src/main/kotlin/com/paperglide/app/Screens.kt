package com.paperglide.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.paperglide.core.BoardCopy
import com.paperglide.core.BoardPeriod
import com.paperglide.core.DeleteCopy
import com.paperglide.core.NameCopy
import com.paperglide.core.ReportCategory
import com.paperglide.core.ReportCopy

private val Ink = Color(0xFF4A3B33)
private val Coral = Color(0xFFD66B5C)
private val Paper = Color(0xFFFCF8F0)
private val Sky = Color(0xFFBDDBED)
private val Nunito = FontFamily(Font(R.font.nunito_variable))
private val Fraunces = FontFamily(Font(R.font.fraunces_variable))

@Composable
fun PaperTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Coral,
            onPrimary = Color.White,
            background = Sky,
            surface = Paper,
            onBackground = Ink,
            onSurface = Ink,
        ),
        content = content,
    )
}

@Composable
fun PaperApp(model: PaperModel, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier
            .fillMaxSize()
            .testTag("paperSurface")
            .semantics { contentDescription = "theme=paper-light" },
        color = if (model.screen == Screen.Play) Color.Transparent else Sky,
    ) {
        when (model.screen) {
            Screen.Start -> StartScreen(model)
            Screen.Play -> PlayScreen(model)
            Screen.Death -> DeathScreen(model)
            Screen.Boards -> BoardsScreen(model)
        }
        if (model.reportOpen) ReportSheet(model)
        if (model.deleteOpen) DeleteDialog(model)
        if (model.discardReport) DiscardDialog(model)
        model.banner?.let { text ->
            Text(
                text,
                modifier = Modifier
                    .padding(24.dp)
                    .testTag("banner")
                    .background(Paper, RoundedCornerShape(24.dp))
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                color = Ink,
                fontFamily = Nunito,
            )
        }
    }
}

@Composable
private fun StartScreen(model: PaperModel) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 12.dp)
            .testTag("startScreen"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Spacer(Modifier.height(24.dp))
        Text("Paper Glide", color = Ink, fontFamily = Fraunces, fontWeight = FontWeight.SemiBold, fontSize = 44.sp)
        Text(
            "Glide a paper plane through open windows.",
            color = Ink.copy(alpha = 0.75f),
            fontFamily = Nunito,
            textAlign = TextAlign.Center,
        )
        Text(
            "Best score ${model.best}",
            color = Ink,
            fontFamily = Nunito,
            fontSize = 22.sp,
            modifier = Modifier.testTag("startBestScore"),
        )
        PrimaryButton("Play", "playButton") { model.play() }
        SecondaryButton("Leaderboard", "leaderboardButton") { model.openBoards(Screen.Start) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = {
                model.recordClickPublic("start", "report")
                model.reportOpen = true
            }, modifier = Modifier.testTag("reportButton").heightIn(min = 48.dp)) {
                Text(ReportCopy.button, color = Ink.copy(alpha = 0.6f), fontFamily = Nunito)
            }
            TextButton(onClick = { model.deleteOpen = true }, modifier = Modifier.testTag("deleteDataButton").heightIn(min = 48.dp)) {
                Text(DeleteCopy.link, color = Ink.copy(alpha = 0.6f), fontFamily = Nunito)
            }
        }
        if (model.showName) NameCard(model, later = true)
    }
}

@Composable
private fun PlayScreen(model: PaperModel) {
    Column(Modifier.fillMaxSize().testTag(if (model.immersive) "playImmersive" else "playMenus")) {
        Text(
            "${model.score}",
            modifier = Modifier.padding(top = 8.dp).align(Alignment.CenterHorizontally).testTag("scoreLabel"),
            color = Ink,
            fontFamily = Fraunces,
            fontWeight = FontWeight.SemiBold,
            fontSize = 44.sp,
        )
        Spacer(Modifier.weight(1f))
        if (model.showCoach) {
            Text(
                "tap to glide",
                modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 28.dp).testTag("coachLabel"),
                color = Ink,
                fontFamily = Nunito,
                fontSize = 20.sp,
            )
        }
        if (model.paused) {
            Column(
                Modifier.fillMaxWidth().padding(24.dp).background(Paper.copy(alpha = 0.92f), RoundedCornerShape(20.dp)).padding(16.dp).testTag("pauseOverlay"),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("Paused", color = Ink, fontFamily = Fraunces, fontSize = 32.sp, modifier = Modifier.testTag("pausedTitle"))
                PrimaryButton("Resume", "resumeButton") { model.resume() }
                SecondaryButton("Home", "pauseHomeButton") { model.home() }
            }
        }
    }
}

@Composable
private fun DeathScreen(model: PaperModel) {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag("deathScreen"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("The glide is over", color = Ink, fontFamily = Fraunces, fontWeight = FontWeight.SemiBold, fontSize = 32.sp, textAlign = TextAlign.Center)
        Text("${model.score}", color = Ink, fontFamily = Fraunces, fontSize = 52.sp, modifier = Modifier.testTag("deathScore"))
        if (model.newBest) {
            Text(
                "New best!",
                color = Color.White,
                fontFamily = Nunito,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.background(Coral, RoundedCornerShape(50)).padding(horizontal = 16.dp, vertical = 4.dp).testTag("newBestLabel"),
            )
        }
        Text("Best ${model.best}", color = Ink.copy(alpha = 0.8f), fontFamily = Nunito, fontSize = 20.sp, modifier = Modifier.testTag("bestScoreLabel"))
        PrimaryButton("Retry", "retryButton") { model.retryRun() }
        SecondaryButton("Share", "shareButton") { model.shareRequested = true }
        SecondaryButton("Home", "homeButton") { model.home() }
        SecondaryButton("Leaderboard", "deathLeaderboardButton") { model.openBoards(Screen.Death) }
        model.deathNote?.let {
            Text(it, color = Ink.copy(alpha = 0.7f), fontFamily = Nunito, modifier = Modifier.testTag("deathSyncNote"))
        }
        if (model.showName) NameCard(model, later = true)
    }
}

@Composable
private fun BoardsScreen(model: PaperModel) {
    Column(Modifier.fillMaxSize().padding(16.dp).testTag("boardsScreen")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { model.closeBoards() }, modifier = Modifier.testTag("leaderboardBackButton").heightIn(min = 48.dp)) {
                Text("Back", color = Ink, fontFamily = Nunito)
            }
            Text("Leaderboard", modifier = Modifier.weight(1f), textAlign = TextAlign.Center, color = Ink, fontFamily = Fraunces, fontSize = 22.sp)
            Spacer(Modifier.height(48.dp))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PeriodChip("Today", BoardPeriod.Daily, model)
            PeriodChip("This week", BoardPeriod.Weekly, model)
            PeriodChip("All time", BoardPeriod.AllTime, model)
        }
        model.boardEmpty?.let { Text(it, color = Ink, fontFamily = Nunito, modifier = Modifier.padding(top = 16.dp).testTag("boardEmpty")) }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(top = 8.dp)) {
            model.boardLines.forEach { line ->
                Text(line, color = Ink, fontFamily = Nunito, modifier = Modifier.padding(vertical = 6.dp))
            }
        }
    }
}

@Composable
private fun PeriodChip(label: String, period: BoardPeriod, model: PaperModel) {
    val selected = model.period == period
    Button(
        onClick = { model.selectPeriod(period) },
        modifier = Modifier.heightIn(min = 48.dp).testTag("period-$label"),
        colors = ButtonDefaults.buttonColors(containerColor = if (selected) Coral else Paper, contentColor = if (selected) Color.White else Ink),
    ) { Text(label, fontFamily = Nunito) }
}

@Composable
private fun NameCard(model: PaperModel, later: Boolean) {
    Column(
        Modifier.fillMaxWidth().background(Paper, RoundedCornerShape(16.dp)).padding(14.dp).testTag("nameCard"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(NameCopy.helper, color = Ink.copy(alpha = 0.75f), fontFamily = Nunito, modifier = Modifier.testTag("nameHelper"))
        TextField(
            value = model.nameDraft,
            onValueChange = { model.nameDraft = it.lowercase() },
            modifier = Modifier.fillMaxWidth().testTag("nameField"),
            singleLine = true,
        )
        model.nameError?.let { Text(it, color = Coral, fontFamily = Nunito, modifier = Modifier.testTag("nameError")) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { model.claim(model.nameDraft) }, modifier = Modifier.heightIn(min = 48.dp).testTag("nameSaveButton")) {
                Text("save", fontFamily = Nunito)
            }
            if (later) {
                OutlinedButton(onClick = {
                    model.showName = false
                    model.nameError = null
                }, modifier = Modifier.heightIn(min = 48.dp).testTag("nameLaterButton")) {
                    Text("later", color = Ink, fontFamily = Nunito)
                }
            }
        }
    }
}

@Composable
private fun ReportSheet(model: PaperModel) {
    Column(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.12f)).verticalScroll(rememberScrollState()).padding(20.dp).testTag("reportSheet"),
    ) {
        Column(Modifier.background(Paper, RoundedCornerShape(20.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(ReportCopy.title, color = Ink, fontFamily = Fraunces, fontSize = 24.sp, modifier = Modifier.testTag("reportTitle"))
            Text(ReportCopy.line, color = Ink.copy(alpha = 0.75f), fontFamily = Nunito)
            ReportCategory.entries.forEach { category ->
                OutlinedButton(
                    onClick = { model.reportCategory = category.label },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("reportCategory-${category.label}"),
                ) { Text(category.label, color = Ink, fontFamily = Nunito) }
            }
            TextField(
                value = model.reportText,
                onValueChange = { model.reportText = it.take(500) },
                modifier = Modifier.fillMaxWidth().testTag("reportText"),
                placeholder = { Text(ReportCopy.placeholder) },
            )
            Text(ReportCopy.smallPrint, color = Ink.copy(alpha = 0.6f), fontFamily = Nunito, fontSize = 12.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = {
                    if (model.reportText.isNotEmpty()) model.discardReport = true else model.reportOpen = false
                }, modifier = Modifier.heightIn(min = 48.dp)) { Text(ReportCopy.cancel, color = Ink) }
                Button(
                    onClick = { model.sendReport() },
                    enabled = model.reportCategory != null,
                    modifier = Modifier.heightIn(min = 48.dp).testTag("reportSend"),
                ) { Text(ReportCopy.send) }
            }
        }
    }
}

@Composable
private fun DiscardDialog(model: PaperModel) {
    AlertDialog(
        onDismissRequest = { model.discardReport = false },
        title = { Text(ReportCopy.backDiscardTitle, fontFamily = Nunito) },
        text = { Text("", fontFamily = Nunito) },
        confirmButton = {
            TextButton(onClick = {
                model.discardReport = false
                model.reportOpen = false
                model.reportText = ""
            }, modifier = Modifier.testTag("discardReport")) { Text(ReportCopy.backDiscard, color = Coral) }
        },
        dismissButton = {
            TextButton(onClick = { model.discardReport = false }, modifier = Modifier.testTag("keepEditing")) {
                Text(ReportCopy.backKeepEditing, color = Ink)
            }
        },
    )
}

@Composable
private fun DeleteDialog(model: PaperModel) {
    AlertDialog(
        onDismissRequest = { if (!model.deleting) model.deleteOpen = false },
        title = { Text(DeleteCopy.title, color = Ink, fontFamily = Fraunces, modifier = Modifier.testTag("deleteTitle")) },
        text = { Text(if (model.deleting) DeleteCopy.progress else DeleteCopy.body, color = Ink, fontFamily = Nunito, modifier = Modifier.testTag("deleteBody")) },
        dismissButton = {
            TextButton(onClick = { model.deleteOpen = false }, enabled = !model.deleting, modifier = Modifier.testTag("deleteCancel")) {
                Text(DeleteCopy.cancel, color = Ink)
            }
        },
        confirmButton = {
            TextButton(onClick = { model.delete() }, enabled = !model.deleting, modifier = Modifier.testTag("deleteConfirm")) {
                Text(DeleteCopy.delete, color = Coral)
            }
        },
    )
}

@Composable
private fun PrimaryButton(label: String, tag: String, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag)) {
        Text(label, fontFamily = Nunito, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
    }
}

@Composable
private fun SecondaryButton(label: String, tag: String, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag)) {
        Text(label, color = Ink, fontFamily = Nunito, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
    }
}
