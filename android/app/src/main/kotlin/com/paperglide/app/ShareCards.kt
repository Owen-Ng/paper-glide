package com.paperglide.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import com.paperglide.core.ShareCard
import com.paperglide.core.ShareCardBackdrop
import com.paperglide.core.ShareCardCopy
import java.io.ByteArrayOutputStream

object ShareCards {
    @Volatile var forceFail: Boolean = false

    fun render(copy: ShareCardCopy): Bitmap? {
        if (forceFail) return null
        val fraunces = typeface(R.font.fraunces_variable, "'wght' 600, 'SOFT' 100, 'opsz' 9, 'WONK' 0") ?: return null
        val scoreFace = typeface(R.font.fraunces_variable, "'wght' 800, 'SOFT' 100, 'opsz' 9, 'WONK' 0") ?: return null
        val nunito = typeface(R.font.nunito_variable, "'wght' 700") ?: return null
        val bitmap = Bitmap.createBitmap(ShareCard.pixelWidth, ShareCard.pixelHeight, Bitmap.Config.ARGB_8888)
        val pixels = ShareCardBackdrop.paint()
        bitmap.setPixels(toArgb(pixels), 0, ShareCard.pixelWidth, 0, 0, ShareCard.pixelWidth, ShareCard.pixelHeight)
        val canvas = Canvas(bitmap)
        drawMark(canvas)
        drawLine(canvas, copy.title, fraunces, ShareCard.titlePointSize, 0.0, ShareCard.titleTop, Color.rgb(73, 58, 51), inkBox = false)
        drawLine(canvas, copy.scoredLine, nunito, ShareCard.scoredPointSize, ShareCard.scoredShrinkStep, ShareCard.scoredTop, Color.rgb(214, 107, 91), inkBox = false)
        drawLine(canvas, copy.scoreText, scoreFace, ShareCard.scorePointSize, ShareCard.scoreShrinkStep, ShareCard.scoreInkTop, Color.rgb(73, 58, 51), inkBox = true)
        return bitmap
    }

    fun png(bitmap: Bitmap): ByteArray {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    private fun typeface(font: Int, variation: String): Typeface? {
        val app = AppContext.holder ?: return null
        return try {
            val file = java.io.File(app.cacheDir, "font-$font.ttf")
            if (!file.exists() || file.length() == 0L) {
                app.resources.openRawResource(font).use { input ->
                    file.outputStream().use { input.copyTo(it) }
                }
            }
            Typeface.Builder(file).setFontVariationSettings(variation).build()
        } catch (_: Exception) {
            null
        }
    }

    private fun drawLine(
        canvas: Canvas,
        text: String,
        face: Typeface,
        starting: Double,
        step: Double,
        anchorTop: Double,
        color: Int,
        inkBox: Boolean,
    ) {
        val size = if (step <= 0) starting else ShareCard.pointSize(starting, step, ShareCard.maxTextWidth) { point ->
            measure(text, face, point.toFloat()).first.toDouble()
        }
        val paint = paint(face, size.toFloat(), color)
        val (advance, bounds) = measure(text, face, size.toFloat())
        val penX: Float
        val baseline: Float
        if (inkBox) {
            val inkWidth = (bounds.right - bounds.left).toFloat()
            penX = (ShareCard.pixelWidth - inkWidth) / 2f - bounds.left
            baseline = anchorTop.toFloat() - bounds.top
        } else {
            penX = (ShareCard.pixelWidth - advance) / 2f
            baseline = anchorTop.toFloat() - paint.fontMetrics.ascent
        }
        canvas.drawText(text, penX, baseline, paint)
    }

    private fun measure(text: String, face: Typeface, size: Float): Pair<Float, Rect> {
        val paint = paint(face, size, Color.BLACK)
        val bounds = Rect()
        paint.getTextBounds(text, 0, text.length, bounds)
        return paint.measureText(text) to bounds
    }

    private fun paint(face: Typeface, size: Float, color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = face
        textSize = size
        this.color = color
        isSubpixelText = true
    }

    private fun drawMark(canvas: Canvas) {
        val scale = 4
        val side = ShareCard.logoSide.toInt() * scale
        val mark = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val local = Canvas(mark)
        val s = side.toFloat()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.rgb(214, 107, 91)
        val frame = RectF(s * 0.18f, s * 0.14f, s * 0.50f, s * 0.86f)
        local.drawRoundRect(frame, s * 0.05f, s * 0.05f, paint)
        paint.xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.CLEAR)
        val hole = RectF(s * 0.26f, s * 0.32f, s * 0.42f, s * 0.68f)
        local.drawRoundRect(hole, s * 0.025f, s * 0.025f, paint)
        paint.xfermode = null
        fun point(x: Float, yFromTop: Float) = android.graphics.PointF(x, yFromTop)
        val nose = point(s * 0.86f, s * 0.50f)
        val tailTop = point(s * 0.30f, s * 0.40f)
        val tailBottom = point(s * 0.30f, s * 0.62f)
        val fold = point(s * 0.42f, s * 0.51f)
        val path = Path()
        path.moveTo(tailTop.x, tailTop.y)
        path.lineTo(nose.x, nose.y)
        path.lineTo(tailBottom.x, tailBottom.y)
        path.lineTo(fold.x, fold.y)
        path.close()
        paint.color = Color.rgb(252, 248, 239)
        paint.style = Paint.Style.FILL
        local.drawPath(path, paint)
        paint.style = Paint.Style.STROKE
        paint.color = Color.rgb(73, 58, 51)
        paint.strokeJoin = Paint.Join.ROUND
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeWidth = (s * 0.014f).toInt().toFloat().coerceAtLeast(1f)
        local.drawPath(path, paint)
        paint.color = Color.argb(200, 73, 58, 51)
        paint.strokeWidth = (s * 0.008f).toInt().toFloat().coerceAtLeast(1f)
        local.drawLine(fold.x, fold.y, nose.x, nose.y, paint)
        val logo = ShareCard.logoSide.toFloat()
        val left = (ShareCard.pixelWidth - logo) / 2f
        canvas.drawBitmap(mark, null, RectF(left, ShareCard.logoTop.toFloat(), left + logo, ShareCard.logoTop.toFloat() + logo), Paint(Paint.FILTER_BITMAP_FLAG))
        mark.recycle()
    }

    private fun toArgb(pixels: ByteArray): IntArray {
        val out = IntArray(ShareCard.pixelWidth * ShareCard.pixelHeight)
        var index = 0
        for (i in out.indices) {
            val r = pixels[index].toInt() and 255
            val g = pixels[index + 1].toInt() and 255
            val b = pixels[index + 2].toInt() and 255
            val a = pixels[index + 3].toInt() and 255
            out[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
            index += 4
        }
        return out
    }
}

/** Holds the application context so the card renderer can open the bundled fonts off the activity. */
object AppContext {
    @Volatile var holder: android.content.Context? = null
}
