package com.froggyeye.honestsignal

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.SizeF
import android.widget.RemoteViews
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * The home-screen widget: the latest score, its verdict and when it was
 * measured. A free feature, and read-only — it never measures; tapping it
 * opens the app, which does.
 *
 * Rendered from [LastReading] on four occasions: a new reading worth drawing
 * ([LastReading.save]), the one-shot stale alarm scheduled below, the system's
 * 30-minute `updatePeriodMillis`, and a resize. The wording deliberately
 * avoids relative ages; see [ReadingText.widgetStatus] for why.
 */
class SignalWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "SignalWidget"

        /**
         * Re-renders once the newest reading crosses [ReadingText.STALE_AFTER_MS],
         * so a widget left showing a fresh-looking score after measuring stops
         * dims and says "Not live" instead of waiting up to 30 minutes for the
         * periodic update.
         */
        private const val ACTION_STALE_REFRESH = "com.froggyeye.honestsignal.WIDGET_STALE_REFRESH"

        /** A few seconds past the threshold so the render is unambiguously stale. */
        private const val STALE_ALARM_SLACK_MS = 5_000L

        /** Below this width (dp) the verdict text cannot fit beside the bars. */
        private const val WIDE_MIN_WIDTH_DP = 100

        private const val REQUEST_OPEN_APP = 10
        private const val REQUEST_STALE_ALARM = 11

        /** Renders every instance of the widget from the stored reading. */
        fun refreshAll(context: Context) {
            runCatching {
                val manager = AppWidgetManager.getInstance(context) ?: return
                val ids = manager.getAppWidgetIds(ComponentName(context, SignalWidgetProvider::class.java))
                render(context, manager, ids)
            }.onFailure { Log.w(TAG, "Widget refresh failed", it) }
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val now = System.currentTimeMillis()
            val reading = LastReading.load(context)
            for (id in ids) {
                manager.updateAppWidget(id, viewsFor(context, manager, id, reading, now))
            }
            LastReading.markRendered(context, reading, now)
            if (ids.isNotEmpty()) scheduleStaleRefresh(context, reading, now)
        }

        private fun viewsFor(
            context: Context,
            manager: AppWidgetManager,
            id: Int,
            reading: Reading?,
            now: Long,
        ): RemoteViews {
            val wide = build(context, reading, now, wide = true)
            val small = build(context, reading, now, wide = false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Responsive layouts: the launcher picks per size itself, and
                // keeps picking correctly through a resize without a round trip
                // to the app.
                return RemoteViews(
                    mapOf(
                        SizeF(40f, 40f) to small,
                        SizeF(WIDE_MIN_WIDTH_DP.toFloat(), 40f) to wide,
                    )
                )
            }
            // Pre-12 there is only one RemoteViews per instance, so choose from
            // the size the launcher last reported (re-reported on resize via
            // onAppWidgetOptionsChanged). No report yet means the default 2x1.
            val minWidth = manager.getAppWidgetOptions(id)
                ?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
            return if (minWidth in 1 until WIDE_MIN_WIDTH_DP) small else wide
        }

        private fun build(context: Context, reading: Reading?, now: Long, wide: Boolean): RemoteViews {
            val views = RemoteViews(
                context.packageName,
                if (wide) R.layout.widget_signal else R.layout.widget_signal_small,
            )
            val timeFormat = android.text.format.DateFormat.getTimeFormat(context)
            val dateFormat = dateFormat()
            val stale = reading == null || ReadingText.isStale(reading, now)
            val bars = reading?.bars ?: 0

            // The non-plate glyph: the plate exists to survive an arbitrary
            // wallpaper behind a status-bar mask, and the widget brings its own
            // background.
            views.setImageViewResource(
                R.id.widget_bars,
                IndicatorIcons.resourceFor(reading?.theme, bars, false),
            )
            tintBars(context, views, bars)
            // Dimmed rather than hidden when stale: the last known score is
            // still useful, as long as it does not look current.
            views.setInt(R.id.widget_bars, "setImageAlpha", if (stale) 110 else 255)

            if (wide) {
                views.setTextViewText(R.id.widget_verdict, reading?.verdict ?: "Honest Signal")
                views.setTextViewText(
                    R.id.widget_status,
                    ReadingText.widgetStatus(reading, now, timeFormat, dateFormat),
                )
            } else {
                views.setTextViewText(
                    R.id.widget_status,
                    ReadingText.widgetShortStatus(reading, now, timeFormat, dateFormat),
                )
            }
            views.setContentDescription(
                R.id.widget_root,
                ReadingText.widgetContentDescription(reading, now, timeFormat, dateFormat),
            )
            views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
            return views
        }

        /**
         * The score colour, in the ramp that matches the widget's own
         * background. From Android 12 RemoteViews can carry both and let the
         * launcher choose at inflation, so a theme switch recolours the bars
         * without the app running. Before that the choice is made now, and a
         * theme switch is picked up on the next render — at most a minute away
         * while measuring, 30 otherwise.
         */
        private fun tintBars(context: Context, views: RemoteViews, bars: Int) {
            val light = SignalColours.forBarsOnLight(bars)
            val dark = SignalColours.forBars(bars)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                views.setColorInt(R.id.widget_bars, "setColorFilter", light, dark)
            } else {
                val night = (context.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
                views.setInt(R.id.widget_bars, "setColorFilter", if (night) dark else light)
            }
        }

        private fun dateFormat(): DateFormat {
            val locale = Locale.getDefault()
            return SimpleDateFormat(
                android.text.format.DateFormat.getBestDateTimePattern(locale, "d MMM"),
                locale,
            )
        }

        private fun openAppIntent(context: Context): PendingIntent =
            PendingIntent.getActivity(
                context,
                REQUEST_OPEN_APP,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        /**
         * An inexact, non-wakeup alarm: there is no point waking the phone to
         * redraw a widget nobody can see, and RTC fires at the next wake —
         * which is when someone might look. Replaces any earlier one, since
         * the PendingIntent is identical; needs no exact-alarm permission.
         */
        private fun scheduleStaleRefresh(context: Context, reading: Reading?, now: Long) {
            if (reading == null || ReadingText.isStale(reading, now)) return
            runCatching {
                val alarms = context.getSystemService(AlarmManager::class.java) ?: return
                val pending = PendingIntent.getBroadcast(
                    context,
                    REQUEST_STALE_ALARM,
                    Intent(context, SignalWidgetProvider::class.java).setAction(ACTION_STALE_REFRESH),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                alarms.set(
                    AlarmManager.RTC,
                    reading.timestampMs + ReadingText.STALE_AFTER_MS + STALE_ALARM_SLACK_MS,
                    pending,
                )
            }.onFailure { Log.w(TAG, "Could not schedule the stale refresh", it) }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_STALE_REFRESH) {
            refreshAll(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        // Re-renders every instance, not just appWidgetIds: one stored reading
        // feeds them all, and drawing them together keeps them in step.
        refreshAll(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        refreshAll(context)
    }
}
