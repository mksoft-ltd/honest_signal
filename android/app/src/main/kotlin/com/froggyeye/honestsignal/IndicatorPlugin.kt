package com.froggyeye.honestsignal

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android half of the indicator bridge that the app's UI isolate talks to.
 *
 * Kept as a plain handler owned by [MainActivity] rather than a full Flutter
 * plugin: it is app-specific, needs an Activity for the runtime permission
 * request, and has no life outside this app.
 */
class IndicatorPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.froggyeye.honestsignal/indicator"
        private const val NOTIFICATION_PERMISSION_REQUEST = 9101
    }

    /** Held while the system permission dialog is up, answered in [onPermissionResult]. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isIndicatorRunning" -> result.success(HonestSignalService.isRunning)

            "startIndicator" -> {
                startService(configIntent(call, HonestSignalService.ACTION_START))
                result.success(null)
            }

            "updateConfig" -> {
                // Only meaningful while the service is up; starting it here
                // would switch the indicator on as a side effect of the user
                // changing an unrelated setting.
                if (HonestSignalService.isRunning) {
                    send(configIntent(call, HonestSignalService.ACTION_CONFIG))
                }
                result.success(null)
            }

            "stopIndicator" -> {
                if (HonestSignalService.isRunning) {
                    send(
                        Intent(activity, HonestSignalService::class.java)
                            .setAction(HonestSignalService.ACTION_STOP)
                    )
                }
                result.success(null)
            }

            "publishSample" -> {
                // The service owns the notification and overlay lifetimes. A
                // sample can only be delivered to one that is already running;
                // the uiActive flag below is a renewable lease, so a lost
                // delivery self-heals on the next foreground measurement.
                if (HonestSignalService.isRunning) send(
                    Intent(activity, HonestSignalService::class.java).apply {
                        action = HonestSignalService.ACTION_PUBLISH
                        putExtra(HonestSignalService.EXTRA_BARS, call.argument<Int>("bars") ?: 0)
                        putExtra(HonestSignalService.EXTRA_VERDICT, call.argument<String>("verdict"))
                        putExtra(HonestSignalService.EXTRA_DETAIL, call.argument<String>("detail"))
                        putExtra(HonestSignalService.EXTRA_THEME, call.argument<String>("theme"))
                        putExtra(HonestSignalService.EXTRA_ACTIVE, call.argument<Boolean>("uiActive") ?: true)
                        putExtra(
                            HonestSignalService.EXTRA_UI_INTERVAL,
                            call.argument<Int>("uiIntervalSeconds") ?: 0,
                        )
                    }
                )
                result.success(null)
            }

            "setUiActive" -> {
                if (HonestSignalService.isRunning) {
                    send(
                        Intent(activity, HonestSignalService::class.java).apply {
                            action = HonestSignalService.ACTION_UI_ACTIVE
                            putExtra(
                                HonestSignalService.EXTRA_ACTIVE,
                                call.argument<Boolean>("active") ?: false,
                            )
                        }
                    )
                }
                result.success(null)
            }

            "notificationPermissionStatus" ->
                result.success(NotificationManagerCompat.from(activity).areNotificationsEnabled())

            "requestNotificationPermission" -> requestNotificationPermission(result)

            "canDrawOverlays" -> result.success(OverlayService.canDraw(activity))

            "openOverlaySettings" -> {
                // Android offers no in-app grant for SYSTEM_ALERT_WINDOW; this
                // deep link to the system screen is the only route.
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${activity.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }

            "startOverlay" -> {
                if (OverlayService.canDraw(activity)) {
                    send(
                        Intent(activity, OverlayService::class.java)
                            .setAction(OverlayService.ACTION_START)
                    )
                }
                result.success(OverlayService.canDraw(activity))
            }

            "stopOverlay" -> {
                if (OverlayService.isRunning) {
                    send(
                        Intent(activity, OverlayService::class.java)
                            .setAction(OverlayService.ACTION_STOP)
                    )
                }
                result.success(null)
            }

            "isOverlayRunning" -> result.success(OverlayService.isRunning)

            else -> result.notImplemented()
        }
    }

    private fun configIntent(call: MethodCall, action: String): Intent =
        Intent(activity, HonestSignalService::class.java).apply {
            this.action = action
            putExtra(HonestSignalService.EXTRA_THEME, call.argument<String>("theme"))
            putExtra(
                HonestSignalService.EXTRA_INTERVAL,
                call.argument<Int>("intervalSeconds") ?: 300,
            )
            putExtra(
                HonestSignalService.EXTRA_BUDGET,
                (call.argument<Number>("budgetLimitBytes") ?: 0).toLong(),
            )
            putExtra(
                HonestSignalService.EXTRA_CELLULAR,
                call.argument<Boolean>("measureOnCellular") ?: true,
            )
            putExtra(HonestSignalService.EXTRA_ACTIVE, call.argument<Boolean>("uiActive") ?: false)
        }

    /**
     * Starts the foreground service. Only ever called while the app is on
     * screen — Android forbids a background start, and this is the one call
     * that creates the service rather than messaging an existing one.
     */
    private fun startService(intent: Intent) {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }
        }
    }

    /**
     * Messages an already-running service.
     *
     * Wrapped because the lifecycle callback that reports the app going to the
     * background races the system's own view of foreground state; losing the
     * message can delay one update while an uncaught IllegalStateException
     * would crash the app on the way out. Foreground publishes renew a service
     * lease, so the service resumes its own cycle if a lifecycle message drops.
     */
    private fun send(intent: Intent) {
        runCatching { activity.startService(intent) }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // Before Android 13 notifications need no runtime grant, but the
            // user may still have switched them off in system settings.
            result.success(NotificationManagerCompat.from(activity).areNotificationsEnabled())
            return
        }

        val granted = activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }

        // A second concurrent request would leak the first result and hang the
        // Dart future that is awaiting it.
        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    /** Called by [MainActivity] from `onRequestPermissionsResult`. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return false
        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        result.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        )
        return true
    }

    fun detach() {
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
    }
}
