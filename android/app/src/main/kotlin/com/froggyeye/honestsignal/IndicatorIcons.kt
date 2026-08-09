package com.froggyeye.honestsignal

/**
 * Maps a theme name and a 0..5 score to the drawable that the status-bar
 * notification uses as its small icon.
 *
 * Pre-rendered vector drawables rather than a bitmap built at runtime: the
 * system renders resource small icons through its own monochrome tinting path
 * on every Android version and OEM skin, which a runtime bitmap is not
 * guaranteed to survive. Eighteen tiny XML files buy that certainty.
 *
 * Theme names match `BarTheme` in Dart; the geometry matches
 * `lib/shared/widgets/signal_bars.dart`.
 */
object IndicatorIcons {

    private val BARS = intArrayOf(
        R.drawable.ic_signal_bars_0,
        R.drawable.ic_signal_bars_1,
        R.drawable.ic_signal_bars_2,
        R.drawable.ic_signal_bars_3,
        R.drawable.ic_signal_bars_4,
        R.drawable.ic_signal_bars_5,
    )

    private val DOTS = intArrayOf(
        R.drawable.ic_signal_dots_0,
        R.drawable.ic_signal_dots_1,
        R.drawable.ic_signal_dots_2,
        R.drawable.ic_signal_dots_3,
        R.drawable.ic_signal_dots_4,
        R.drawable.ic_signal_dots_5,
    )

    private val WAVE = intArrayOf(
        R.drawable.ic_signal_wave_0,
        R.drawable.ic_signal_wave_1,
        R.drawable.ic_signal_wave_2,
        R.drawable.ic_signal_wave_3,
        R.drawable.ic_signal_wave_4,
        R.drawable.ic_signal_wave_5,
    )

    fun resourceFor(theme: String?, bars: Int): Int {
        val level = bars.coerceIn(0, 5)
        return when (theme) {
            "dots" -> DOTS[level]
            "wave" -> WAVE[level]
            else -> BARS[level]
        }
    }
}
