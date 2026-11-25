package com.paperglide.app

import android.app.Activity
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.paperglide.core.ShareCard
import com.paperglide.core.ShareMessage
import com.paperglide.core.ShareOffer
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object Sharing {
    const val SAVED = "Image saved"
    const val FAILED = "Couldn't save image"
    @Volatile var lastScore: Int = 0
    @Volatile var lastIntent: Intent? = null

    fun offer(context: Context, score: Int, username: String?): ShareOffer {
        val copy = ShareCard.copy(score, username)
        if (ShareCards.forceFail) return ShareOffer.Text(copy.caption)
        val bitmap = ShareCards.render(copy) ?: return ShareOffer.Text(copy.caption)
        val png = ShareCards.png(bitmap)
        bitmap.recycle()
        if (png.isEmpty()) return ShareOffer.Text(copy.caption)
        return ShareOffer.Card(png, copy.caption)
    }

    fun intent(context: Context, score: Int, username: String?): Intent {
        val built = offer(context, score, username)
        val caption = when (built) {
            is ShareOffer.Card -> built.caption
            is ShareOffer.Text -> built.caption
        }
        if (built is ShareOffer.Text) {
            return Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, caption)
                putExtra(Intent.EXTRA_SUBJECT, ShareMessage.subject)
            }.also { lastIntent = it }
        }
        lastScore = score
        val png = (built as ShareOffer.Card).png
        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        val file = File(dir, "paperglide_share.png")
        FileOutputStream(file).use { it.write(png) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, caption)
            putExtra(Intent.EXTRA_SUBJECT, ShareMessage.subject)
            clipData = android.content.ClipData.newUri(context.contentResolver, ShareMessage.subject, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(send, ShareMessage.subject).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val pending = PendingIntent.getBroadcast(
                context,
                0,
                Intent(context, SaveImageReceiver::class.java).setData(uri),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val action = android.service.chooser.ChooserAction.Builder(
                android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_share),
                context.getString(R.string.save_image),
                pending,
            ).build()
            chooser.putExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS, arrayOf(action))
        } else {
            val save = Intent(context, SaveImageActivity::class.java).apply {
                action = Intent.ACTION_SEND
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra("score", score)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, arrayOf(save))
        }
        lastIntent = chooser
        return chooser
    }

    fun save(context: Context, png: ByteArray, score: Int): Boolean {
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val name = "paperglide_${score}_$stamp.png"
        return try {
            if (Build.VERSION.SDK_INT >= 29) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Paper Glide")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: return false
                context.contentResolver.openOutputStream(uri)?.use { it.write(png) } ?: return false
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                context.contentResolver.update(uri, values, null, null)
                true
            } else {
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Paper Glide")
                if (!dir.exists() && !dir.mkdirs()) return false
                val file = File(dir, name)
                FileOutputStream(file).use { it.write(png) }
                val scan = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(file))
                context.sendBroadcast(scan)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    fun readUri(context: Context, uri: Uri): ByteArray? = try {
        context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
    } catch (_: Exception) {
        null
    }
}

class SaveImageActivity : Activity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = streamUri(intent)
        val score = intent.getIntExtra("score", 0)
        val png = uri?.let { Sharing.readUri(this, it) }
        val ok = png != null && Sharing.save(this, png, score)
        android.widget.Toast.makeText(this, if (ok) Sharing.SAVED else Sharing.FAILED, android.widget.Toast.LENGTH_SHORT).show()
        finish()
    }
}

class SaveImageReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val uri = intent.data
        val png = uri?.let { Sharing.readUri(context, it) }
        val ok = png != null && Sharing.save(context, png, Sharing.lastScore)
        android.widget.Toast.makeText(context, if (ok) Sharing.SAVED else Sharing.FAILED, android.widget.Toast.LENGTH_SHORT).show()
    }
}

private fun streamUri(intent: Intent): Uri? {
    val extra = if (Build.VERSION.SDK_INT >= 33) {
        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
    } else {
        @Suppress("DEPRECATION")
        intent.getParcelableExtra(Intent.EXTRA_STREAM)
    }
    return extra ?: intent.data
}
