package com.froggyeye.honestsignal

import android.graphics.Color

/**
 * The score colour ramp, shared by every Android surface that is allowed to
 * have a colour at all.
 *
 * Mirrors `AppColors.dark.forBars` in Dart — the dark set specifically. Change
 * the two together.
 *
 * Three callers, and they do not share a ground. `SignalBubbleView` draws on its
 * own dark plate whatever theme the phone is in. The notification uses these as
 * `setColor`, and below Android 16 as the colorized card, both of which live in
 * the system shade and therefore follow the phone's theme — the dark ramp's
 * mid-tones would not pass contrast on a light surface unaided, which is why
 * `AppColors.light` exists in Dart. It is still the right set here because
 * Android contrast-corrects a notification's accent colour against the surface
 * it lands on and chooses its own text colour over a colorized background; the
 * app hands over an intent, not a final pixel. If that ever stops being true,
 * the fix is a light ramp for the notification, not a nudge to these values.
 *
 * The status-bar small icon is deliberately not a caller: Android treats a small
 * icon as an alpha mask and picks the colour itself, so a red icon is not
 * something an app can ask for.
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
