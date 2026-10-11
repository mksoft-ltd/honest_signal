package com.froggyeye.honestsignal

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Posts the "connection dropped" / "connection is back" notifications.
 *
 * *Whether* to alert — the bars threshold, how long it must hold, debouncing
 * a flapping link — is decided in the background Dart isolate, next to the
 * scoring model, which then calls `postAlert` on the background channel. This
 * side only owns the Android mechanics, and never throws back across the
 * channel: a missed alert is a lesser failure than a broken measurement loop.
 */
object ConnectionAlerts {
    private const val TAG = "ConnectionAlerts"

    /**
     * Its own channel, separate from the silent indicator channel, so the user
     * can silence alerts, or make them louder, without touching the
     * status-bar icon — and because an alert is the one notification here that
     * *should* make a sound by default.
     */
    const val CHANNEL_ID = "connection_alerts"

    /**
     * One fixed ID: a "recovered" replaces the "drop" it answers rather than
     * stacking under it, so the shade never shows a resolved outage as live.
     */
    private const val NOTIFICATION_ID = 4203
    private const val REQUEST_OPEN_HISTORY = 3

    const val KIND_DROP = "drop"
    const val KIND_RECOVERED = "recovered"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        // IMPORTANCE_DEFAULT: makes a sound and shows an icon, does not peek.
        // The user owns the importance from here on (see CHANNEL_ID in
        // HonestSignalService), which is the point of a separate channel.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Connection alerts",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Tells you when the connection drops out and when it comes back"
        }
        manager.createNotificationChannel(channel)
    }

    /**
     * Never throws. Unknown [kind] values are posted as a drop-style alert
     * with the given text, since Dart wrote the words and they are still the
     * best description available.
     */
    fun post(
        context: Context,
        kind: String?,
        title: String?,
        body: String?,
        theme: String,
        highContrast: Boolean,
    ) {
        runCatching {
            // areNotificationsEnabled is false both when the Android 13+
            // POST_NOTIFICATIONS grant is missing and when the user switched
            // the app's notifications off on any version; either way, skip.
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
            // Redundant with the line above on 13+, but explicit so the grant
            // check sits next to notify() where lint (and a reader) expects it.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) return
            ensureChannel(context)

            val recovered = kind == KIND_RECOVERED
            val bars = if (recovered) 5 else 0
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                // The user's own glyph, empty for a drop and full for a
                // recovery, so the status bar says which at a glance.
                .setSmallIcon(IndicatorIcons.resourceFor(theme, bars, highContrast))
                .setColor(SignalColours.forBars(bars))
                .setContentTitle(title ?: if (recovered) "Connection is back" else "Connection dropped")
                .setContentText(body.orEmpty())
                .setStyle(NotificationCompat.BigTextStyle().bigText(body.orEmpty()))
                .setContentIntent(openHistory(context))
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                // Pre-O only; the channel's importance governs from API 26.
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setShowWhen(true)
                .build()
            try {
                NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
            } catch (e: SecurityException) {
                // Revoked between the check and the post.
                Log.w(TAG, "Notification permission withdrawn", e)
            }
        }.onFailure { Log.w(TAG, "Could not post the connection alert", it) }
    }

    /** Opens the app on the history screen, where the drop is visible in context. */
    private fun openHistory(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            REQUEST_OPEN_HISTORY,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(MainActivity.EXTRA_ROUTE, MainActivity.ROUTE_HISTORY)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
