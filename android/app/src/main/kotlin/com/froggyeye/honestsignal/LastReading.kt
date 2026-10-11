package com.froggyeye.honestsignal

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.service.quicksettings.TileService
import android.util.Log

/**
 * The most recent score, wherever it was measured, for the surfaces that show
 * it outside the app: the home-screen widget ([SignalWidgetProvider]) and the
 * Quick Settings tile ([SignalTileService]).
 *
 * Two writers feed it — the UI isolate through `updateWidgets` on the
 * indicator channel, on every foreground reading whether or not the indicator
 * service is running, and [HonestSignalService] for every background cycle
 * and published sample. Both are on the main thread of the one app process,
 * so SharedPreferences is a sufficient store; [save] is still synchronised so
 * the throttle bookkeeping cannot interleave.
 */
object LastReading {
    private const val TAG = "LastReading"
    private const val PREFS = "honest_signal_last_reading"

    private const val KEY_BARS = "bars"
    private const val KEY_VERDICT = "verdict"
    private const val KEY_DETAIL = "detail"
    private const val KEY_TIMESTAMP = "timestampMs"
    private const val KEY_THEME = "theme"

    // The reading the widgets were last drawn with, kept apart from the latest
    // so a throttled save cannot make the throttle compare a reading with
    // itself.
    private const val RENDERED_PREFIX = "rendered_"
    private const val KEY_LAST_RENDER = "lastRenderMs"

    fun load(context: Context): Reading? = read(prefs(context), "")

    /**
     * Stores [reading] and, unless it would change nothing visible (see
     * [ReadingText.shouldRefresh]), re-renders every widget and asks the tile
     * to rebind. Never throws: these surfaces are a convenience, and neither
     * caller — the measurement loop or a platform-channel reply — should fail
     * because a launcher misbehaved.
     */
    @Synchronized
    fun save(context: Context, reading: Reading) {
        runCatching {
            val prefs = prefs(context)
            write(prefs.edit(), "", reading).apply()
            val now = System.currentTimeMillis()
            val rendered = read(prefs, RENDERED_PREFIX)
            val lastRender = prefs.getLong(KEY_LAST_RENDER, 0L)
            if (ReadingText.shouldRefresh(rendered, lastRender, reading, now)) {
                refreshSurfaces(context)
            }
        }.onFailure { Log.w(TAG, "Could not save the last reading", it) }
    }

    /** Re-renders from what is stored; the widget's own update paths use this too. */
    fun refreshSurfaces(context: Context) {
        SignalWidgetProvider.refreshAll(context)
        requestTileUpdate(context)
    }

    /** Called by [SignalWidgetProvider] after each full render. */
    @Synchronized
    fun markRendered(context: Context, reading: Reading?, nowMs: Long) {
        val editor = prefs(context).edit().putLong(KEY_LAST_RENDER, nowMs)
        if (reading != null) write(editor, RENDERED_PREFIX, reading)
        editor.apply()
    }

    /**
     * Asks the system to bind the tile so it can redraw. Tiles are otherwise
     * only refreshed when the shade opens, which covers the text but not the
     * active/inactive state flipping while the shade is already down.
     *
     * Wrapped because some OEM builds throw when the tile has never been
     * added, and an unbound tile is not worth a crash in the service.
     */
    fun requestTileUpdate(context: Context) {
        runCatching {
            TileService.requestListeningState(
                context,
                ComponentName(context, SignalTileService::class.java),
            )
        }.onFailure { Log.w(TAG, "Tile update request refused", it) }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun read(prefs: SharedPreferences, prefix: String): Reading? =
        Reading.fromStored(
            bars = prefs.takeIf { it.contains(prefix + KEY_BARS) }?.getInt(prefix + KEY_BARS, 0),
            verdict = prefs.getString(prefix + KEY_VERDICT, null),
            detail = prefs.getString(prefix + KEY_DETAIL, null),
            timestampMs = prefs.takeIf { it.contains(prefix + KEY_TIMESTAMP) }
                ?.getLong(prefix + KEY_TIMESTAMP, 0L),
            theme = prefs.getString(prefix + KEY_THEME, null),
        )

    private fun write(editor: SharedPreferences.Editor, prefix: String, reading: Reading) =
        editor
            .putInt(prefix + KEY_BARS, reading.bars.coerceIn(0, 5))
            .putString(prefix + KEY_VERDICT, reading.verdict)
            .putString(prefix + KEY_DETAIL, reading.detail)
            .putLong(prefix + KEY_TIMESTAMP, reading.timestampMs)
            .putString(prefix + KEY_THEME, reading.theme)
}
