package com.froggyeye.honestsignal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Brings back the indicators the user had switched on before a restart.
 *
 * A persistent status-bar indicator that silently disappears after every reboot
 * is worse than no indicator, because the user stops trusting it. Nothing is
 * started that the user had not already enabled.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        if (!HonestSignalService.wasEnabled(context)) return

        val serviceIntent = HonestSignalService.startIntent(context)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: IllegalStateException) {
            // ForegroundServiceStartNotAllowedException (API 31+) is an
            // IllegalStateException. BOOT_COMPLETED is normally exempt from the
            // background-start rules, but Play vitals recorded this exact
            // refusal on Android 16, and a crash in a boot receiver helps no
            // one. Ask the user to open the app instead; it re-syncs the
            // indicator on every foreground.
            onStartRefused(context, e)
        } catch (e: SecurityException) {
            onStartRefused(context, e)
        }

        // The floating bubble is restored by HonestSignalService once it is in the
        // foreground, not from here: Android 8 forbids a boot receiver starting
        // a plain background service, and OverlayService is not a foreground
        // service. If the user runs the bubble without the status-bar indicator
        // it returns the next time they open the app instead.
    }

    private fun onStartRefused(context: Context, e: Exception) {
        Log.w("BootReceiver", "Could not restore the indicator after boot", e)
        HonestSignalService.postRestoreNotification(context)
    }
}
