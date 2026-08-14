package com.froggyeye.honestsignal

import android.graphics.Color

/**
 * The score colour ramp, shared by every Android surface that is allowed to
 * have a colour at all.
 *
 * Mirrors `AppColors.dark.forBars` in Dart — the dark set specifically, because
 * both users of this file draw on their own dark ground whatever theme the
 * phone is in. Change the two together.
 *
 * The status-bar small icon is deliberately not a user: Android treats a small
 * icon as an alpha mask and picks the colour itself, so a red icon is not
 * something an app can ask for. Colour reaches the user through the shade entry
 * and the floating bubble instead.
 */
object SignalColours {

    fun forBars(level: Int): Int = when (level.coerceIn(0, 5)) {
        0 -> Color.rgb(0xE0, 0x48, 0x3C)
        1 -> Color.rgb(0xE8, 0x86, 0x3B)
        2, 3 -> Color.rgb(0xD8, 0xB2, 0x2E)
        4 -> Color.rgb(0x4F, 0xA8, 0x3D)
        else -> Color.rgb(0x1F, 0xA9, 0x7A)
    }
}
