package com.paperglide.core

import kotlin.math.floor
import kotlin.math.sqrt

/**
 * The 1080×1350 card backdrop from ShareCardRenderer.swift: sky wash, blurred
 * paper clouds, and the low-opacity facade skyline. Text and the logo mark
 * are drawn on top by the Android canvas.
 */
object ShareCardBackdrop {
    fun paint(): ByteArray {
        val width = ShareCard.pixelWidth
        val height = ShareCard.pixelHeight
        val pixels = ByteArray(width * height * 4)
        val sky = intArrayOf(188, 219, 237)
        val paper = intArrayOf(247, 239, 226)
        for (y in 0 until height) {
            val t = minOf(1.0, y.toDouble() / (height * 0.72))
            val rgb = IntArray(3)
            for (channel in 0 until 3) {
                val mixed = sky[channel] + (paper[channel] - sky[channel]) * t
                rgb[channel] = mixed.toInt()
            }
            for (x in 0 until width) {
                val index = (y * width + x) * 4
                pixels[index] = rgb[0].toByte()
                pixels[index + 1] = rgb[1].toByte()
                pixels[index + 2] = rgb[2].toByte()
                pixels[index + 3] = 255.toByte()
            }
        }
        var clouds = ByteArray(width * height * 4)
        var cursor = 0
        val runs = ShareCardGeometry.cloudRuns
        while (cursor + 2 < runs.size) {
            fill(runs[cursor], runs[cursor + 1], runs[cursor], runs[cursor + 2], clouds, width, height, 252, 248, 239, 200)
            cursor += 3
        }
        clouds = gaussianBlur(clouds, width, height)
        paste(clouds, pixels, width, height)
        val skyline = ByteArray(width * height * 4)
        for (block in ShareCardGeometry.facades) {
            val color = ShareCardGeometry.facadeColors[block.color]
            fill(block.y0, block.x0, block.y1, block.x1, skyline, width, height, color[0], color[1], color[2], 150)
            val windows = block.windows
            var w = 0
            while (w + 3 < windows.size) {
                fill(windows[w + 1], windows[w], windows[w + 3], windows[w + 2], skyline, width, height, 252, 248, 239, 120)
                w += 4
            }
        }
        paste(skyline, pixels, width, height)
        return pixels
    }

    fun sample(pixels: ByteArray, x: Int, y: Int): Triple<Int, Int, Int> {
        val index = (y * ShareCard.pixelWidth + x) * 4
        return Triple(pixels[index].toInt() and 255, pixels[index + 1].toInt() and 255, pixels[index + 2].toInt() and 255)
    }
}

private fun fill(
    y0: Int, x0: Int, y1: Int, x1: Int,
    buffer: ByteArray, width: Int, height: Int,
    red: Int, green: Int, blue: Int, alpha: Int,
) {
    val top = maxOf(0, minOf(y0, y1))
    val bottom = minOf(height - 1, maxOf(y0, y1))
    val left = maxOf(0, minOf(x0, x1))
    val right = minOf(width - 1, maxOf(x0, x1))
    if (top > bottom || left > right) return
    for (y in top..bottom) {
        for (x in left..right) {
            val index = (y * width + x) * 4
            buffer[index] = red.toByte()
            buffer[index + 1] = green.toByte()
            buffer[index + 2] = blue.toByte()
            buffer[index + 3] = alpha.toByte()
        }
    }
}

private fun paste(source: ByteArray, destination: ByteArray, width: Int, height: Int) {
    for (y in 0 until height) {
        for (x in 0 until width) {
            val index = (y * width + x) * 4
            val alpha = source[index + 3].toInt() and 255
            if (alpha == 0) continue
            for (channel in 0 until 3) {
                val src = source[index + channel].toInt() and 255
                val dst = destination[index + channel].toInt() and 255
                destination[index + channel] = ((src * alpha + dst * (255 - alpha) + 127) / 255).toByte()
            }
            destination[index + 3] = 255.toByte()
        }
    }
}

private fun gaussianBlur(source: ByteArray, width: Int, height: Int): ByteArray {
    val minX = 20
    val minY = 60
    val cropWidth = 1000
    val cropHeight = 260
    val crop = ByteArray(cropWidth * cropHeight * 4)
    for (row in 0 until cropHeight) {
        val from = ((row + minY) * width + minX) * 4
        val to = row * cropWidth * 4
        source.copyInto(crop, to, from, from + cropWidth * 4)
    }
    val blurred = blurBuffer(crop, cropWidth, cropHeight)
    val output = source.copyOf()
    for (row in 0 until cropHeight) {
        val from = row * cropWidth * 4
        val to = ((row + minY) * width + minX) * 4
        blurred.copyInto(output, to, from, from + cropWidth * 4)
    }
    return output
}

private fun blurBuffer(source: ByteArray, width: Int, height: Int): ByteArray {
    val passes = 3
    val sigma2 = 4.0 / passes
    val length = sqrt(12.0 * sigma2 + 1.0)
    val box = floor((length - 1.0) / 2.0)
    var fractional = (2 * box + 1) * (box * (box + 1) - 3 * sigma2)
    fractional /= 6 * (sigma2 - (box + 1) * (box + 1))
    val floatRadius = box + fractional
    val radius = floatRadius.toInt()
    val ww = (1.shl(24).toDouble() / (floatRadius * 2 + 1)).toInt()
    val fw = ((1 shl 24) - (radius * 2 + 1) * ww) / 2
    var current = source
    var scratch = ByteArray(source.size)
    repeat(passes) {
        blur(current, scratch, width, height, horizontal = true, radius, ww, fw)
        val swap = current
        current = scratch
        scratch = swap
    }
    repeat(passes) {
        blur(current, scratch, width, height, horizontal = false, radius, ww, fw)
        val swap = current
        current = scratch
        scratch = swap
    }
    return current
}

private fun blur(
    source: ByteArray, destination: ByteArray,
    width: Int, height: Int, horizontal: Boolean,
    radius: Int, ww: Int, fw: Int,
) {
    val lines = if (horizontal) height else width
    val count = if (horizontal) width else height
    for (line in 0 until lines) {
        for (channel in 0 until 4) {
            val origin = if (horizontal) line * width * 4 + channel else line * 4 + channel
            val stride = if (horizontal) 4 else width * 4
            blurLine(source, destination, origin, stride, count, radius, ww, fw)
        }
    }
}

private fun blurLine(
    source: ByteArray, destination: ByteArray,
    origin: Int, stride: Int, count: Int, radius: Int, ww: Int, fw: Int,
) {
    if (count <= 0) return
    val edgeA = minOf(radius + 1, count)
    val edgeB = maxOf(count - radius - 1, 0)
    val last = count - 1
    fun at(index: Int): Int = source[origin + index * stride].toInt() and 255
    fun put(index: Int, bulk: Int) {
        destination[origin + index * stride] = ((bulk + (1 shl 23)) shr 24).toByte()
    }
    var acc = at(0) * (radius + 1)
    val lead = maxOf(edgeA - 1, 0)
    if (lead > 0) {
        for (index in 0 until lead) acc += at(index)
    }
    acc += at(last) * (radius - edgeA + 1)
    fun far(left: Int, right: Int): Int = acc * ww + (at(left) + at(right)) * fw
    if (edgeA <= edgeB) {
        for (index in 0 until edgeA) {
            acc += at(index + radius) - at(0)
            put(index, far(0, index + radius + 1))
        }
        for (index in edgeA until edgeB) {
            acc += at(index + radius) - at(index - radius - 1)
            put(index, far(index - radius - 1, index + radius + 1))
        }
        if (last >= edgeB) {
            for (index in edgeB..last) {
                acc += at(last) - at(index - radius - 1)
                put(index, far(index - radius - 1, last))
            }
        }
    } else {
        for (index in 0 until edgeB) {
            acc += at(index + radius) - at(0)
            put(index, far(0, index + radius + 1))
        }
        for (index in edgeB until edgeA) {
            acc += at(last) - at(0)
            put(index, far(0, last))
        }
        if (last >= edgeA) {
            for (index in edgeA..last) {
                acc += at(last) - at(index - radius - 1)
                put(index, far(index - radius - 1, last))
            }
        }
    }
}
