package com.froggyeye.honestsignal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Keeps the status-bar indicator alive.
 *
 * The service hosts a *background Flutter engine* running the app's own
 * measurement engine rather than reimplementing the scoring model in Kotlin.
 * Duplicating the formula in two languages would guarantee they eventually
 * disagree, and the score is the entire product.
 *
 * Timing stays on this side: an Android handler in a foreground service is far
 * more predictable than a Dart timer in a process the system may freeze, so
 * Kotlin decides *when* to measure and Dart decides *what the answer is*.
 */
class HonestSignalService : Service() {

    companion object {
        /**
         * Bumped to `_v2` when the importance changed. A channel's importance is
         * fixed at creation and **cannot be raised** by a later update — the user
         * owns it from then on — so an install that already created the v1
         * channel would keep IMPORTANCE_LOW, and keep having no status-bar icon,
         * forever. A new ID is the only way to move an existing install.
         */
        private const val CHANNEL_ID = "honest_signal_indicator_v2"

        /** Deleted on channel setup so the dead v1 entry does not linger in Settings. */
        private const val LEGACY_CHANNEL_ID = "honest_signal_indicator"
        private const val NOTIFICATION_ID = 4201
        private const val PREFS = "honest_signal_service"

        private const val KEY_ENABLED = "enabled"
        private const val KEY_THEME = "theme"
        private const val KEY_INTERVAL = "interval"
        private const val KEY_BUDGET = "budget"
        private const val KEY_CELLULAR = "cellular"

        const val ACTION_START = "com.froggyeye.honestsignal.START"
        const val ACTION_STOP = "com.froggyeye.honestsignal.STOP"
        const val ACTION_CONFIG = "com.froggyeye.honestsignal.CONFIG"
        const val ACTION_PUBLISH = "com.froggyeye.honestsignal.PUBLISH"
        const val ACTION_UI_ACTIVE = "com.froggyeye.honestsignal.UI_ACTIVE"

        const val EXTRA_THEME = "theme"
        const val EXTRA_INTERVAL = "intervalSeconds"
        const val EXTRA_BUDGET = "budgetLimitBytes"
        const val EXTRA_CELLULAR = "measureOnCellular"
        const val EXTRA_BARS = "bars"
        const val EXTRA_VERDICT = "verdict"
        const val EXTRA_DETAIL = "detail"
        const val EXTRA_ACTIVE = "active"
        const val EXTRA_UI_INTERVAL = "uiIntervalSeconds"

        /**
         * Floor for the UI-active lease. The lease must outlast the gap between
         * two foreground publishes or it expires mid-cycle and the service runs
         * the duplicate probe set the lease exists to prevent — reachable on
         * Pro, whose foreground interval also tops out at 60 s. Three intervals
         * of slack means two publishes have to be lost, not one.
         */
        private const val UI_ACTIVE_LEASE_MS = 60_000L
        private const val UI_ACTIVE_LEASE_INTERVALS = 3
        private const val CYCLE_WATCHDOG_MS = 30_000L

        @Volatile
        var isRunning: Boolean = false
            private set

        /** True when the user last left the indicator switched on. */
        fun wasEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, false)

        fun startIntent(context: Context): Intent {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return Intent(context, HonestSignalService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_THEME, prefs.getString(KEY_THEME, "bars"))
                putExtra(EXTRA_INTERVAL, prefs.getInt(KEY_INTERVAL, 300))
                putExtra(EXTRA_BUDGET, prefs.getLong(KEY_BUDGET, 25L * 1024 * 1024))
                putExtra(EXTRA_CELLULAR, prefs.getBoolean(KEY_CELLULAR, true))
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var backgroundChannel: MethodChannel? = null

    private var theme: String = "bars"
    private var intervalSeconds: Int = 300
    private var budgetLimitBytes: Long = 25L * 1024 * 1024
    private var measureOnCellular: Boolean = true

    private var uiActiveUntilMs = 0L
    private var engineReady = false
    private var cycleInFlight = false
    private var cycleGeneration = 0L
    private var cycleWatchdog: Runnable? = null

    private var bars = 0
    private var verdict = "Measuring…"
    private var detail = "Starting up"

    private val tick = object : Runnable {
        override fun run() {
            runCycle()
            handler.postDelayed(this, intervalSeconds * 1000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                persistEnabled(false)
                stop()
                return START_NOT_STICKY
            }

            ACTION_PUBLISH -> {
                // A reading measured by the UI isolate. While the app is open it
                // is already probing, so the service shows its result instead of
                // running a second, redundant set of probes.
                bars = intent.getIntExtra(EXTRA_BARS, bars)
                verdict = intent.getStringExtra(EXTRA_VERDICT) ?: verdict
                detail = intent.getStringExtra(EXTRA_DETAIL) ?: detail
                theme = intent.getStringExtra(EXTRA_THEME) ?: theme
                renewUiLease(
                    intent.getBooleanExtra(EXTRA_ACTIVE, true),
                    intent.getIntExtra(EXTRA_UI_INTERVAL, 0),
                )
                if (isRunning) updateNotification()
                OverlayService.publish(bars, theme)
            }

            ACTION_UI_ACTIVE -> {
                val active = intent.getBooleanExtra(EXTRA_ACTIVE, false)
                renewUiLease(active)
                // Leaving the app is the handoff point. Start the background
                // side immediately rather than leaving a fresh score stale
                // until the next sparse service tick.
                if (!active) runCycle()
            }

            ACTION_CONFIG -> {
                applyConfig(intent)
                if (isRunning) restartLoop()
            }

            else -> {
                applyConfig(intent)
                renewUiLease(intent?.getBooleanExtra(EXTRA_ACTIVE, false) ?: false)
                persistEnabled(true)
                startForegroundIndicator()
                ensureEngine()
                restartLoop()
                restoreOverlayIfEnabled()
            }
        }
        // START_STICKY: if the system reclaims the process, the indicator the
        // user explicitly switched on should come back rather than silently
        // vanish. onStartCommand handles a null intent via applyConfig's
        // persisted fallbacks.
        return START_STICKY
    }

    private fun applyConfig(intent: Intent?) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        theme = intent?.getStringExtra(EXTRA_THEME) ?: prefs.getString(KEY_THEME, theme) ?: theme
        intervalSeconds = intent?.getIntExtra(EXTRA_INTERVAL, 0)
            ?.takeIf { it > 0 } ?: prefs.getInt(KEY_INTERVAL, intervalSeconds)
        budgetLimitBytes = intent?.getLongExtra(EXTRA_BUDGET, 0L)
            ?.takeIf { it > 0 } ?: prefs.getLong(KEY_BUDGET, budgetLimitBytes)
        measureOnCellular = intent?.takeIf { it.hasExtra(EXTRA_CELLULAR) }
            ?.getBooleanExtra(EXTRA_CELLULAR, true)
            ?: prefs.getBoolean(KEY_CELLULAR, measureOnCellular)

        // Never let a bad value turn the indicator into a battery drain.
        intervalSeconds = intervalSeconds.coerceIn(30, 3600)

        prefs.edit()
            .putString(KEY_THEME, theme)
            .putInt(KEY_INTERVAL, intervalSeconds)
            .putLong(KEY_BUDGET, budgetLimitBytes)
            .putBoolean(KEY_CELLULAR, measureOnCellular)
            .apply()
    }

    private fun persistEnabled(enabled: Boolean) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    private fun startForegroundIndicator() {
        // The 2-argument form deliberately: it takes the foreground service type
        // from the manifest, which keeps the specialUse declaration in exactly
        // one place and works unchanged from API 24 to 35+.
        startForeground(NOTIFICATION_ID, buildNotification())
        isRunning = true
    }

    // After a reboot the boot receiver may only start *this* service, since a
    // receiver cannot start a plain background one. Once running in the
    // foreground it can, so the bubble comes back here.
    private fun restoreOverlayIfEnabled() {
        if (!OverlayService.wasEnabled(this)) return
        // The grant can be withdrawn in system settings at any time, including
        // while the device was off.
        if (!OverlayService.canDraw(this)) return
        startService(
            Intent(this, OverlayService::class.java)
                .setAction(OverlayService.ACTION_START)
        )
    }

    private fun restartLoop() {
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    /**
     * [uiIntervalSeconds] is the foreground cadence the UI is publishing at; 0
     * when the caller does not know it (a bare lifecycle message), in which
     * case the flat floor applies.
     */
    private fun renewUiLease(active: Boolean, uiIntervalSeconds: Int = 0) {
        uiActiveUntilMs = if (active) {
            val fromInterval = uiIntervalSeconds.coerceAtLeast(0) *
                UI_ACTIVE_LEASE_INTERVALS * 1000L
            System.currentTimeMillis() + maxOf(UI_ACTIVE_LEASE_MS, fromInterval)
        } else {
            0L
        }
    }

    private fun isUiActive(): Boolean = System.currentTimeMillis() < uiActiveUntilMs

    private fun runCycle() {
        // The UI isolate is already probing and publishing; a second set of
        // probes would double the data cost for an identical answer.
        if (isUiActive() || !engineReady || cycleInFlight) return
        val channel = backgroundChannel ?: return

        cycleInFlight = true
        val generation = ++cycleGeneration
        cycleWatchdog?.let(handler::removeCallbacks)
        cycleWatchdog = Runnable {
            if (generation == cycleGeneration) cycleInFlight = false
        }.also { handler.postDelayed(it, CYCLE_WATCHDOG_MS) }
        channel.invokeMethod(
            "runCycle",
            mapOf(
                "measureOnCellular" to measureOnCellular,
                "budgetLimitBytes" to budgetLimitBytes,
            ),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (!finishCycle(generation)) return
                    val map = result as? Map<*, *> ?: return
                    bars = (map["bars"] as? Number)?.toInt() ?: bars
                    verdict = map["verdict"] as? String ?: verdict
                    detail = map["detail"] as? String ?: detail
                    updateNotification()
                    OverlayService.publish(bars, theme)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    finishCycle(generation)
                }

                override fun notImplemented() {
                    finishCycle(generation)
                }
            },
        )
    }

    /** Ignores a late callback from a cycle the watchdog already released. */
    private fun finishCycle(generation: Long): Boolean {
        if (generation != cycleGeneration) return false
        cycleWatchdog?.let(handler::removeCallbacks)
        cycleWatchdog = null
        cycleInFlight = false
        return true
    }

    private fun ensureEngine() {
        if (engine != null) return

        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val created = FlutterEngine(applicationContext)
        // Named entrypoint rather than a stored callback handle: the name is
        // checked at compile time on the Dart side and survives a reinstall,
        // where a handle from a previous install would be meaningless.
        created.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "honestSignalBackgroundMain",
            )
        )

        MethodChannel(created.dartExecutor.binaryMessenger, BudgetChannel.NAME)
            .setMethodCallHandler(BudgetChannel.handler(applicationContext))

        val channel = MethodChannel(
            created.dartExecutor.binaryMessenger,
            "com.froggyeye.honestsignal/background",
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method == "backgroundReady") {
                // Waiting for Dart to say it is up avoids firing runCycle into
                // an engine whose plugins have not registered yet.
                engineReady = true
                runCycle()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        engine = created
        backgroundChannel = channel
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        // IMPORTANCE_DEFAULT, deliberately, despite this notification being
        // silent. From Android 11 the status bar hides the icon of anything
        // below IMPORTANCE_DEFAULT — those land in the shade's "Silent" section
        // only. This channel previously used IMPORTANCE_LOW on the belief that
        // it was "visible in the status bar but never intrusive"; that was true
        // before Android 11 and is false now, and it cost the app its headline
        // Android feature.
        //
        // DEFAULT is the lowest importance that still gets an icon. It does not
        // peek — heads-up needs IMPORTANCE_HIGH — and the sound and vibration it
        // would otherwise carry are removed on the channel below and again on
        // the builder, so the result is an icon and nothing else.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Signal indicator",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Shows your measured connection quality in the status bar."
            setShowBadge(false)
            enableVibration(false)
            vibrationPattern = null
            enableLights(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
        // Order matters only in that both must happen; the v1 channel is dead
        // and leaving it would show the user a stale duplicate in Settings.
        manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
    }

    private fun buildNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, HonestSignalService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(IndicatorIcons.resourceFor(theme, bars))
            .setContentTitle(verdict)
            .setContentText(detail)
            .setContentIntent(openIntent)
            .addAction(0, "Turn off", stopIntent)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            // Belt and braces with the channel's own silencing: the channel
            // decides whether an icon appears, this decides whether anything is
            // heard. Without it, raising the channel to DEFAULT would make every
            // score change chime.
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            // Pre-O only — from API 26 the channel's importance governs, and
            // PRIORITY_LOW is still right on 24/25, where a low-priority
            // notification does show a status-bar icon.
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun stop() {
        handler.removeCallbacks(tick)
        cycleWatchdog?.let(handler::removeCallbacks)
        cycleWatchdog = null
        engine?.destroy()
        engine = null
        backgroundChannel = null
        engineReady = false
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        cycleWatchdog?.let(handler::removeCallbacks)
        cycleWatchdog = null
        engine?.destroy()
        engine = null
        backgroundChannel = null
        engineReady = false
        isRunning = false
        super.onDestroy()
    }
}
