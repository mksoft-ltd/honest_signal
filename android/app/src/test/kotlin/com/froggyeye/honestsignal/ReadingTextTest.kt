package com.froggyeye.honestsignal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * The wording the home-screen widget and Quick Settings tile put next to a
 * score. The rule under test throughout: a reading that is no longer current
 * must never be presented as if it were.
 *
 *     cd android && ./gradlew :app:testDebugUnitTest
 */
class ReadingTextTest {

    // 2026-10-11 14:32:00 UTC
    private val now = 1_791_729_120_000L
    private val utc = TimeZone.getTimeZone("UTC")
    private val time = SimpleDateFormat("HH:mm", Locale.UK).apply { timeZone = utc }
    private val date = SimpleDateFormat("d MMM", Locale.UK).apply { timeZone = utc }

    private fun reading(ageMs: Long, bars: Int = 4, verdict: String = "Good", theme: String = "bars") =
        Reading(bars, verdict, "42 ms", now - ageMs, theme)

    @Test
    fun `age reads in the largest whole unit`() {
        assertEquals("just now", ReadingText.age(now - 59_000, now))
        assertEquals("1 min ago", ReadingText.age(now - 60_000, now))
        assertEquals("12 min ago", ReadingText.age(now - 12 * 60_000, now))
        assertEquals("3 h ago", ReadingText.age(now - 3 * 3_600_000 - 59 * 60_000, now))
        assertEquals("2 d ago", ReadingText.age(now - 2 * 86_400_000L, now))
    }

    @Test
    fun `a timestamp in the future reads as just now, not a negative age`() {
        assertEquals("just now", ReadingText.age(now + 300_000, now))
    }

    @Test
    fun `tile subtitle carries score, verdict and age`() {
        assertEquals("4/5 · Good · 2 min ago", ReadingText.tileSubtitle(reading(2 * 60_000), now))
        assertEquals("Open to measure", ReadingText.tileSubtitle(null, now))
    }

    @Test
    fun `stale boundary is two minutes, inclusive`() {
        assertFalse(ReadingText.isStale(reading(ReadingText.STALE_AFTER_MS - 1), now))
        assertTrue(ReadingText.isStale(reading(ReadingText.STALE_AFTER_MS), now))
    }

    @Test
    fun `a fresh widget states the score and the absolute time`() {
        assertEquals("4/5 · measured 14:31", ReadingText.widgetStatus(reading(60_000), now, time, date))
    }

    @Test
    fun `a stale widget says Not live and drops the score from the status line`() {
        assertEquals(
            "Not live · last measured 14:20",
            ReadingText.widgetStatus(reading(12 * 60_000), now, time, date),
        )
    }

    @Test
    fun `a reading from another day shows the date instead of a misleading time`() {
        // 14:32 yesterday would read as "a few minutes ago" at a glance.
        assertEquals(
            "Not live · last measured 10 Oct",
            ReadingText.widgetStatus(reading(86_400_000L), now, time, date),
        )
        assertEquals("10 Oct", ReadingText.widgetShortStatus(reading(86_400_000L), now, time, date))
    }

    @Test
    fun `no reading prompts the user to measure`() {
        assertEquals("Open to measure", ReadingText.widgetStatus(null, now, time, date))
        assertEquals("Open", ReadingText.widgetShortStatus(null, now, time, date))
    }

    @Test
    fun `content description says Not live when stale`() {
        assertEquals(
            "Honest Signal. Not live. Good, 4 of 5. Measured 14:20.",
            ReadingText.widgetContentDescription(reading(12 * 60_000), now, time, date),
        )
    }

    @Test
    fun `stored values with no timestamp or verdict are no reading at all`() {
        assertNull(Reading.fromStored(4, "Good", "", null, "bars"))
        assertNull(Reading.fromStored(4, "Good", "", 0L, "bars"))
        assertNull(Reading.fromStored(null, "Good", "", now, "bars"))
        assertNull(Reading.fromStored(4, " ", "", now, "bars"))
    }

    @Test
    fun `stored values are clamped and defaulted`() {
        val r = Reading.fromStored(9, "Great", null, now, null)!!
        assertEquals(5, r.bars)
        assertEquals("", r.detail)
        assertEquals("bars", r.theme)
    }

    @Test
    fun `refresh throttle renders changes at once and repeats at most once a minute`() {
        val shown = reading(10_000)
        val renderedAt = now - 10_000
        // Nothing drawn yet.
        assertTrue(ReadingText.shouldRefresh(null, 0L, shown, now))
        // Same score, verdict and theme, 10 s later: skip.
        assertFalse(ReadingText.shouldRefresh(shown, renderedAt, reading(0), now))
        // Any visible change: draw now.
        assertTrue(ReadingText.shouldRefresh(shown, renderedAt, reading(0, bars = 3), now))
        assertTrue(ReadingText.shouldRefresh(shown, renderedAt, reading(0, verdict = "Fair"), now))
        assertTrue(ReadingText.shouldRefresh(shown, renderedAt, reading(0, theme = "dots"), now))
        // Unchanged but a minute since the last draw: draw, so the time moves on.
        assertTrue(
            ReadingText.shouldRefresh(shown, now - ReadingText.MIN_REFRESH_GAP_MS, reading(0), now),
        )
        // A clock that went backwards must not freeze the widget.
        assertTrue(ReadingText.shouldRefresh(shown, now + 5_000, reading(0), now))
    }

    @Test
    fun `the first reading after a stale gap clears Not live immediately`() {
        // The stale alarm redrew 1 s ago, so the gap rule alone would wait.
        val stale = reading(5 * 60_000)
        assertTrue(ReadingText.shouldRefresh(stale, now - 1_000, reading(0), now))
    }

    @Test
    fun `alert config is clamped to the ranges the settings offer`() {
        assertEquals(AlertConfig(true, 0, 1), AlertConfig.of(true, -3, 0))
        assertEquals(AlertConfig(true, 2, 30), AlertConfig.of(true, 7, 999))
        assertEquals(AlertConfig(false, 1, 2), AlertConfig.DEFAULT)
    }
}
