package com.paperglide.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.view.Choreographer
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import com.paperglide.core.GameSnapshot
import com.paperglide.core.Obstacle
import com.paperglide.core.RunPhase
import com.paperglide.core.SkyCycle

class GameSurface(context: Context, private val model: PaperModel) :
    SurfaceView(context), SurfaceHolder.Callback, Choreographer.FrameCallback {

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG)
    private var lastFrame = 0L
    private var running = false

    init {
        holder.addCallback(this)
        stroke.style = Paint.Style.STROKE
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        running = true
        lastFrame = 0L
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        running = false
        Choreographer.getInstance().removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        val dt = if (lastFrame == 0L) 1.0 / 60.0 else (frameTimeNanos - lastFrame) / 1_000_000_000.0
        lastFrame = frameTimeNanos
        if (model.screen == Screen.Play && !model.paused && model.endScore == null && model.guidedStride == null && dt > 0) {
            model.session.step(dt)
            model.publishSnapshot()
        }
        drawFrame()
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN && model.screen == Screen.Play && !model.paused) {
            model.flap()
            return true
        }
        return super.onTouchEvent(event)
    }

    private fun drawFrame() {
        val canvas = holder.lockCanvas() ?: return
        try {
            val snapshot = model.session.snapshot
            val scale = canvas.height / snapshotHeight
            val worldWidth = 390f * scale
            val dx = (canvas.width - worldWidth) / 2f
            canvas.drawColor(Color.rgb(188, 219, 237))
            canvas.save()
            canvas.translate(dx, 0f)
            canvas.scale(scale, scale)
            canvas.translate(0f, snapshotHeight)
            canvas.scale(1f, -1f)
            paintWorld(canvas, snapshot)
            canvas.restore()
        } finally {
            holder.unlockCanvasAndPost(canvas)
        }
    }

    private fun paintWorld(canvas: Canvas, snapshot: GameSnapshot) {
        val sky = SkyCycle.sample(snapshot.flightTime)
        val bands = 24
        for (index in 0 until bands) {
            val t = index / (bands - 1).toFloat()
            val color = sky.bottom.mix(sky.top, t.toDouble())
            fill.color = Color.rgb((color.r * 255).toInt(), (color.g * 255).toInt(), (color.b * 255).toInt())
            val y0 = snapshotHeight * index / bands
            canvas.drawRect(0f, y0, 390f, y0 + snapshotHeight / bands + 1f, fill)
        }
        for (window in snapshot.obstacles) drawWindow(canvas, window)
        val plane = snapshot.plane
        canvas.save()
        canvas.translate(plane.x.toFloat(), plane.y.toFloat())
        val limit = 720.0
        val tilt = (plane.velocityY / limit).coerceIn(-1.0, 1.0)
        canvas.rotate(Math.toDegrees(tilt * 0.45).toFloat())
        val path = Path()
        val halfW = plane.width.toFloat() / 2f
        val halfH = plane.height.toFloat() / 2f
        path.moveTo(halfW, 0f)
        path.lineTo(-halfW, halfH)
        path.lineTo(-halfW * 0.32f, 0f)
        path.lineTo(-halfW, -halfH)
        path.close()
        fill.color = Color.rgb(252, 249, 240)
        canvas.drawPath(path, fill)
        stroke.color = Color.rgb(89, 84, 79)
        stroke.strokeWidth = 1.5f
        canvas.drawPath(path, stroke)
        canvas.restore()
    }

    private fun drawWindow(canvas: Canvas, window: Obstacle) {
        val palette = intArrayOf(
            Color.rgb(242, 194, 176),
            Color.rgb(194, 214, 194),
            Color.rgb(214, 199, 232),
            Color.rgb(250, 219, 179),
            Color.rgb(186, 212, 230),
        )
        fill.color = palette[Math.floorMod(window.id, palette.size)]
        val left = window.left.toFloat()
        val right = window.right.toFloat()
        val gapBottom = window.gapBottom.toFloat()
        val gapTop = window.gapTop.toFloat()
        canvas.drawRect(left, 0f, right, (gapBottom - 7f).coerceAtLeast(0f), fill)
        canvas.drawRect(left, gapTop + 7f, right, snapshotHeight, fill)
        fill.color = Color.rgb(252, 249, 238)
        canvas.drawRect(left, gapBottom - 7f, right, gapBottom, fill)
        canvas.drawRect(left, gapTop, right, gapTop + 7f, fill)
    }

    companion object {
        private const val snapshotHeight = 760f
    }
}
