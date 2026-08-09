package com.froggyeye.honestsignal

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.app.Service
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * The optional floating indicator: a small, draggable, semi-transparent bubble
 * drawn over other apps.
 *
 * Deliberately constrained. It is roughly the size of a status-bar icon, it
 * accepts touches only on itself, it never covers system UI, and it exists only
 * after the user has both bought Pro and granted "display over other apps" in
 * system settings. Long-pressing it turns it off without opening the app.
 */
class OverlayService : Service() {

    companion object {
        private const val PREFS = "honest_signal_overlay"
        private const val KEY_X = "x"
        private const val KEY_Y = "y"
        private const val KEY_ENABLED = "enabled"

        const val ACTION_START = "com.froggyeye.honestsignal.OVERLAY_START"
        const val ACTION_STOP = "com.froggyeye.honestsignal.OVERLAY_STOP"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        private var instance: OverlayService? = null

        /** Pushes a new score to the bubble if it is on screen. */
        fun publish(bars: Int, theme: String) {
            instance?.update(bars, theme)
        }

        fun canDraw(context: Context): Boolean = Settings.canDrawOverlays(context)

        fun wasEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, false)
    }

    private var windowManager: WindowManager? = null
    private var bubble: SignalBubbleView? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    private var lastBars = 0
    private var lastTheme = "bars"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            persistEnabled(false)
            removeBubble()
            stopSelf()
            return START_NOT_STICKY
        }

        // The grant can be revoked in system settings while the service is
        // alive; adding a window without it throws, so re-check every time.
        if (!canDraw(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        persistEnabled(true)
        showBubble()
        return START_STICKY
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showBubble() {
        if (bubble != null) return

        val manager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        windowManager = manager

        val size = (resources.displayMetrics.density * 44).roundToInt()
        val view = SignalBubbleView(this).apply { setScore(lastBars, lastTheme) }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val params = WindowManager.LayoutParams(
            size,
            size,
            type,
            // NOT_FOCUSABLE keeps the keyboard and the app underneath working
            // normally; without it the bubble would steal input from whatever
            // the user is actually doing.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = prefs.getInt(KEY_X, 24)
            y = prefs.getInt(KEY_Y, 240)
        }

        view.setOnTouchListener(DragListener(params, manager, view))

        manager.addView(view, params)
        bubble = view
        layoutParams = params
        instance = this
        isRunning = true
    }

    private inner class DragListener(
        private val params: WindowManager.LayoutParams,
        private val manager: WindowManager,
        private val view: View,
    ) : View.OnTouchListener {
        private var startX = 0
        private var startY = 0
        private var touchX = 0f
        private var touchY = 0f
        private var downAt = 0L
        private var dragged = false

        override fun onTouch(v: View?, event: MotionEvent): Boolean {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    downAt = System.currentTimeMillis()
                    dragged = false
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - touchX).roundToInt()
                    val dy = (event.rawY - touchY).roundToInt()
                    if (abs(dx) > 8 || abs(dy) > 8) dragged = true
                    params.x = startX + dx
                    params.y = startY + dy
                    manager.updateViewLayout(view, params)
                    return true
                }

                MotionEvent.ACTION_UP -> {
                    savePosition(params.x, params.y)
                    val heldMs = System.currentTimeMillis() - downAt
                    if (!dragged) {
                        // Long-press is the escape hatch: turn the bubble off
                        // without hunting through settings.
                        if (heldMs > 600) stopOverlayFromBubble() else openApp()
                    }
                    return true
                }
            }
            return false
        }
    }

    private fun openApp() {
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
        )
    }

    private fun stopOverlayFromBubble() {
        persistEnabled(false)
        removeBubble()
        stopSelf()
    }

    private fun savePosition(x: Int, y: Int) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putInt(KEY_X, x).putInt(KEY_Y, y).apply()
    }

    private fun persistEnabled(enabled: Boolean) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    private fun update(bars: Int, theme: String) {
        lastBars = bars
        lastTheme = theme
        bubble?.setScore(bars, theme)
    }

    private fun removeBubble() {
        bubble?.let { view ->
            runCatching { windowManager?.removeView(view) }
        }
        bubble = null
        layoutParams = null
        instance = null
        isRunning = false
    }

    override fun onDestroy() {
        removeBubble()
        super.onDestroy()
    }
}
