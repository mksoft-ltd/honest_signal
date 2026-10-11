package com.froggyeye.honestsignal

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** Intent extra naming the in-app route to open, read by Dart via `takeLaunchRoute`. */
        const val EXTRA_ROUTE = "route"
        const val ROUTE_HISTORY = "/history"

        /**
         * This activity is exported (it is the launcher entry), so any app can
         * start it with any extras. Only routes the app itself sends are
         * passed through to Dart; anything else is dropped rather than letting
         * a third party navigate the UI, to the paywall or elsewhere.
         */
        private val ALLOWED_ROUTES = setOf(ROUTE_HISTORY)
    }

    private var indicator: IndicatorPlugin? = null

    /** Held until Dart asks for it once, then cleared. */
    private var launchRoute: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before super: super.onCreate attaches the engine, and Dart may ask for
        // the route as soon as it is running. A recreated activity (rotation,
        // process death) gets a saved state and must not replay the route.
        if (savedInstanceState == null) captureRoute(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        // singleTop: a notification tapped while the app is already on top
        // arrives here rather than as a new activity.
        super.onNewIntent(intent)
        setIntent(intent)
        captureRoute(intent)
    }

    private fun captureRoute(intent: Intent?) {
        if (intent == null) return
        // Reopened from Recents: the system replays the original intent, extras
        // and all, which would re-open the history screen from a days-old alert.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val route = intent.getStringExtra(EXTRA_ROUTE) ?: return
        intent.removeExtra(EXTRA_ROUTE)
        if (route in ALLOWED_ROUTES) launchRoute = route
    }

    private fun takeLaunchRoute(): String? = launchRoute.also { launchRoute = null }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val plugin = IndicatorPlugin(this, ::takeLaunchRoute)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IndicatorPlugin.CHANNEL)
            .setMethodCallHandler(plugin)
        indicator = plugin

        // The same budget counter the background isolate uses, so the two
        // never disagree about how much data has been spent today.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BudgetChannel.NAME)
            .setMethodCallHandler(BudgetChannel.handler(applicationContext))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // Answer the pending Dart future first; if it was not ours, hand the
        // result on to the Flutter plugins that registered for it.
        if (indicator?.onPermissionResult(requestCode, grantResults) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun onDestroy() {
        indicator?.detach()
        indicator = null
        super.onDestroy()
    }
}
