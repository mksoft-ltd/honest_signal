package com.froggyeye.honestsignal

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.View

/**
 * The floating bubble's contents: the same mark as the in-app meter and the
 * status-bar icon, drawn small and semi-transparent.
 *
 * Drawn on a canvas rather than inflated from a layout so the geometry can be
 * kept in step with `signal_bars.dart` by eye, in one place.
 */
@SuppressLint("ViewConstructor")
class SignalBubbleView(context: Context) : View(context) {

    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(150, 12, 14, 16)
    }
    private val shapePaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private var bars: Int = 0
    private var theme: String = "bars"

    fun setScore(bars: Int, theme: String) {
        this.bars = bars.coerceIn(0, 5)
        this.theme = theme
        invalidate()
    }

    /**
     * Matches `AppColors.dark.forBars` in Dart — the dark set specifically,
     * because the bubble always draws on its own dark plate whatever theme the
     * phone is in. Change the two together.
     */
    private fun colourFor(level: Int): Int = when (level) {
        0 -> Color.rgb(0xE0, 0x48, 0x3C)
        1 -> Color.rgb(0xE8, 0x86, 0x3B)
        2, 3 -> Color.rgb(0xD8, 0xB2, 0x2E)
        4 -> Color.rgb(0x4F, 0xA8, 0x3D)
        else -> Color.rgb(0x1F, 0xA9, 0x7A)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val w = width.toFloat()
        val h = height.toFloat()
        val radius = w * 0.28f
        canvas.drawRoundRect(RectF(0f, 0f, w, h), radius, radius, backgroundPaint)

        val inset = w * 0.22f
        val left = inset
        val right = w - inset
        val bottom = h - inset
        val top = inset
        val active = colourFor(bars)
        val inactive = Color.argb(70, 255, 255, 255)

        when (theme) {
            "dots" -> drawDots(canvas, left, right, top, bottom, active, inactive)
            "wave" -> drawWave(canvas, left, right, top, bottom, active, inactive)
            else -> drawBars(canvas, left, right, top, bottom, active, inactive)
        }
    }

    private fun drawBars(
        canvas: Canvas,
        left: Float,
        right: Float,
        top: Float,
        bottom: Float,
        active: Int,
        inactive: Int,
    ) {
        val count = 5
        val span = right - left
        val gap = span * 0.055f
        val barWidth = (span - gap * (count - 1)) / count
        val fullHeight = bottom - top

        for (i in 0 until count) {
            val factor = 0.32f + (i / (count - 1f)) * 0.68f
            val barHeight = fullHeight * factor
            val x = left + i * (barWidth + gap)
            shapePaint.color = if (i < bars) active else inactive
            canvas.drawRoundRect(
                RectF(x, bottom - barHeight, x + barWidth, bottom),
                barWidth * 0.3f,
                barWidth * 0.3f,
                shapePaint,
            )
        }
    }

    private fun drawDots(
        canvas: Canvas,
        left: Float,
        right: Float,
        top: Float,
        bottom: Float,
        active: Int,
        inactive: Int,
    ) {
        val count = 5
        val span = right - left
        val gap = span * 0.06f
        val slot = (span - gap * (count - 1)) / count
        val centreY = (top + bottom) / 2f

        for (i in 0 until count) {
            val radius = slot * (0.28f + (i / (count - 1f)) * 0.22f)
            shapePaint.color = if (i < bars) active else inactive
            canvas.drawCircle(left + i * (slot + gap) + slot / 2f, centreY, radius, shapePaint)
        }
    }

    private fun drawWave(
        canvas: Canvas,
        left: Float,
        right: Float,
        top: Float,
        bottom: Float,
        active: Int,
        inactive: Int,
    ) {
        val count = 5
        val centreX = (left + right) / 2f
        val maxRadius = bottom - top
        val stroke = maxRadius * 0.12f

        shapePaint.style = Paint.Style.FILL
        shapePaint.color = if (bars >= 1) active else inactive
        canvas.drawCircle(centreX, bottom, stroke * 0.7f, shapePaint)

        shapePaint.style = Paint.Style.STROKE
        shapePaint.strokeWidth = stroke
        shapePaint.strokeCap = Paint.Cap.ROUND
        for (i in 1 until count) {
            val radius = maxRadius * (i / (count - 1f)) * 0.9f
            shapePaint.color = if (i < bars) active else inactive
            canvas.drawArc(
                RectF(centreX - radius, bottom - radius, centreX + radius, bottom + radius),
                220f,
                100f,
                false,
                shapePaint,
            )
        }
        shapePaint.style = Paint.Style.FILL
    }
}
