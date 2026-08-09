package com.froggyeye.honestsignal

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var indicator: IndicatorPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val plugin = IndicatorPlugin(this)
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
