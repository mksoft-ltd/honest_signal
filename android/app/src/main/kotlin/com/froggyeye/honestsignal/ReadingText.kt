package com.froggyeye.honestsignal

import java.text.DateFormat
import java.util.Calendar
import java.util.Date

/**
 * The last score the app measured, as the widget and the Quick Settings tile
 * show it. Persisted by [LastReading]; this type and everything in
 * [ReadingText] are plain JVM so the wording can be unit-tested without
 * Robolectric.
 */
data class Reading(
    val bars: Int,
    val verdict: String,
    val detail: String,
    val timestampMs: Long,
    val theme: String,
) {
    companion object {
        /**
         * Rebuilds a reading from whatever was stored, or null when nothing
         * usable was. A missing or non-positive timestamp means "never
         * measured": showing a score with no age attached would present an
         * unknown-vintage number as current, which is the one thing these
         * surfaces must not do.
         */
        fun fromStored(
            bars: Int?,
            verdict: String?,
            detail: String?,
            timestampMs: Long?,
            theme: String?,
        ): Reading? {
            if (bars == null || timestampMs == null || timestampMs <= 0L) return null
            if (verdict.isNullOrBlank()) return null
            return Reading(
                bars = bars.coerceIn(0, 5),
                verdict = verdict,
                detail = detail.orEmpty(),
                timestampMs = timestampMs,
                theme = theme ?: "bars",
            )
        }
    }
}

/** Every user-visible string the widget and tile derive from a [Reading]. */
object ReadingText {

    /**
     * How old a reading can be before it stops being presented as current.
     *
     * Two minutes because the slowest *default* cadence anywhere in the app is
     * well inside it — the foreground and background loops both default to
     * seconds — so a reading older than this means measuring has stopped, not
     * that the next one is merely due.
     */
    const val STALE_AFTER_MS = 2 * 60 * 1000L

    const val NO_READING = "Open to measure"

    fun isStale(reading: Reading, nowMs: Long): Boolean =
        nowMs - reading.timestampMs >= STALE_AFTER_MS

    fun score(bars: Int): String = "${bars.coerceIn(0, 5)}/5"

    /**
     * Relative age for a surface that is re-rendered at the moment it is
     * looked at — the tile, whose text is rebuilt every time the shade opens.
     * A clock that went backwards reads as "just now" rather than a negative
     * age.
     */
    fun age(timestampMs: Long, nowMs: Long): String {
        val elapsed = (nowMs - timestampMs).coerceAtLeast(0L)
        val minutes = elapsed / 60_000L
        return when {
            minutes < 1 -> "just now"
            minutes < 60 -> "$minutes min ago"
            minutes < 24 * 60 -> "${minutes / 60} h ago"
            else -> "${minutes / (24 * 60)} d ago"
        }
    }

    /** e.g. "4/5 · Good · 2 min ago", or [NO_READING]. */
    fun tileSubtitle(reading: Reading?, nowMs: Long): String {
        if (reading == null) return NO_READING
        return "${score(reading.bars)} · ${reading.verdict} · ${age(reading.timestampMs, nowMs)}"
    }

    /**
     * The widget's second line.
     *
     * A home-screen widget is *not* re-rendered when it is looked at — only
     * when the app pushes a new reading, when the stale alarm fires, or on the
     * system's 30-minute period, any of which Doze can push back. A relative
     * "2 min ago" would therefore keep saying "2 min ago" for as long as it
     * took the next render to happen, which is exactly the stale-number-shown-
     * as-live failure this app exists to avoid. So the widget states the
     * absolute time it was measured, which stays true however long it sits on
     * screen, and says "Not live" outright once the reading had already aged
     * out at render time.
     *
     * [timeFormat] carries the time zone and the user's 12/24-hour preference;
     * [dateFormat] is used instead once the reading is from another day.
     */
    fun widgetStatus(
        reading: Reading?,
        nowMs: Long,
        timeFormat: DateFormat,
        dateFormat: DateFormat,
    ): String {
        if (reading == null) return NO_READING
        val at = measuredAt(reading.timestampMs, nowMs, timeFormat, dateFormat)
        return if (isStale(reading, nowMs)) {
            "Not live · last measured $at"
        } else {
            "${score(reading.bars)} · measured $at"
        }
    }

    /** The compact 1x1 line: just the time, or a prompt to measure. */
    fun widgetShortStatus(
        reading: Reading?,
        nowMs: Long,
        timeFormat: DateFormat,
        dateFormat: DateFormat,
    ): String {
        if (reading == null) return "Open"
        return measuredAt(reading.timestampMs, nowMs, timeFormat, dateFormat)
    }

    /** Spoken by TalkBack for the whole widget. */
    fun widgetContentDescription(reading: Reading?, nowMs: Long, timeFormat: DateFormat, dateFormat: DateFormat): String {
        if (reading == null) return "Honest Signal. No reading yet. Open to measure."
        val at = measuredAt(reading.timestampMs, nowMs, timeFormat, dateFormat)
        val live = if (isStale(reading, nowMs)) "Not live. " else ""
        return "Honest Signal. $live${reading.verdict}, ${reading.bars.coerceIn(0, 5)} of 5. Measured $at."
    }

    private fun measuredAt(
        timestampMs: Long,
        nowMs: Long,
        timeFormat: DateFormat,
        dateFormat: DateFormat,
    ): String {
        val then = Calendar.getInstance(timeFormat.timeZone).apply { timeInMillis = timestampMs }
        val now = Calendar.getInstance(timeFormat.timeZone).apply { timeInMillis = nowMs }
        val sameDay = then.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
            then.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR)
        return if (sameDay) timeFormat.format(Date(timestampMs)) else dateFormat.format(Date(timestampMs))
    }

    /**
     * Whether a new reading is worth re-rendering every widget for.
     *
     * Readings arrive as often as every two seconds, from both the UI isolate
     * and the service. Pushing RemoteViews to the launcher and re-binding the
     * tile at that rate costs battery for no visible change, since the widget
     * shows minute-resolution time. A changed score, verdict or theme renders
     * at once; an unchanged one at most once a minute; and the first reading
     * after a gap long enough for the widget to have gone stale renders at
     * once, so "Not live" clears the moment measuring resumes.
     *
     * [previous] is the reading the widgets were last rendered *with*, not
     * the last one saved — throttled readings are stored but not drawn.
     */
    fun shouldRefresh(previous: Reading?, lastRenderMs: Long, next: Reading, nowMs: Long): Boolean {
        if (previous == null) return true
        if (previous.bars != next.bars) return true
        if (previous.verdict != next.verdict) return true
        if (previous.theme != next.theme) return true
        if (isStale(previous, nowMs)) return true
        val sinceRender = nowMs - lastRenderMs
        return sinceRender < 0 || sinceRender >= MIN_REFRESH_GAP_MS
    }

    const val MIN_REFRESH_GAP_MS = 60_000L
}

/**
 * Drop/recovery alert thresholds, clamped to the ranges the settings UI
 * offers. The values cross a platform channel and are restored from
 * SharedPreferences after a reboot, so neither source is trusted to be in
 * range.
 */
data class AlertConfig(val enabled: Boolean, val bars: Int, val minutes: Int) {
    companion object {
        const val DEFAULT_BARS = 1
        const val DEFAULT_MINUTES = 2
        val DEFAULT = AlertConfig(false, DEFAULT_BARS, DEFAULT_MINUTES)

        fun of(enabled: Boolean, bars: Int, minutes: Int): AlertConfig =
            AlertConfig(enabled, bars.coerceIn(0, 2), minutes.coerceIn(1, 30))
    }
}
