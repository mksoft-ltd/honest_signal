package com.froggyeye.honestsignal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * The Kotlin end of the high-contrast wire.
 *
 * `flutter test` compiles none of this directory, and the Dart suite can only
 * check that the 36 drawables exist and are named — so deleting the
 * `if (highContrast)` branch from [IndicatorIcons.resourceFor], which would
 * silently give every user the old mask, left the whole Dart suite green. This
 * is a plain JVM test with no Robolectric: it needs the generated `R` constants
 * and nothing else from Android.
 *
 * Run with:
 *
 *     cd android && ./gradlew :app:testDebugUnitTest
 */
class IndicatorIconsTest {

    private val themes = listOf("bars", "dots", "wave")
    private val levels = 0..5

    @Test
    fun `the plate variant is a different drawable at every theme and level`() {
        for (theme in themes) {
            for (level in levels) {
                assertNotEquals(
                    "$theme level $level resolves to the same drawable with " +
                        "high contrast on and off — the plate is not being selected",
                    IndicatorIcons.resourceFor(theme, level, false),
                    IndicatorIcons.resourceFor(theme, level, true),
                )
            }
        }
    }

    @Test
    fun `every theme, level and variant is a distinct drawable`() {
        // 3 themes x 6 levels x 2 variants, no id used twice: catches a
        // copy-paste in the arrays that would freeze the icon at one level, or
        // a theme quietly aliasing another.
        val ids = mutableListOf<Int>()
        for (theme in themes) {
            for (level in levels) {
                ids += IndicatorIcons.resourceFor(theme, level, true)
                ids += IndicatorIcons.resourceFor(theme, level, false)
            }
        }

        assertEquals(36, ids.size)
        assertEquals("two entries resolve to the same drawable", 36, ids.toSet().size)
        // A unit test gets real ids from the generated R jar; all-zero would
        // make the assertions above vacuous rather than failing, so say so.
        assertEquals("resource ids came back as 0 — R was not generated", 0, ids.count { it == 0 })
    }

    @Test
    fun `an unknown theme falls back to bars rather than throwing`() {
        // The theme name crosses a platform channel as a bare string; a build
        // that renames a BarTheme must not crash the service.
        assertEquals(
            IndicatorIcons.resourceFor("bars", 3, true),
            IndicatorIcons.resourceFor("spirals", 3, true),
        )
    }

    @Test
    fun `a score outside 0 to 5 is clamped, not an array index crash`() {
        assertEquals(
            IndicatorIcons.resourceFor("bars", 0, true),
            IndicatorIcons.resourceFor("bars", -1, true),
        )
        assertEquals(
            IndicatorIcons.resourceFor("bars", 5, true),
            IndicatorIcons.resourceFor("bars", 99, true),
        )
    }
}
