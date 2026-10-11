package com.froggyeye.honestsignal

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

/**
 * The Quick Settings tile: the latest score at a pull of the shade. A free
 * feature and, like the widget, read-only — tapping opens the app rather than
 * toggling the indicator, because starting a foreground service from a tile
 * tap is a background start on several Android versions and would fail in
 * exactly the moment the user is looking at it.
 *
 * Standard (non-active) listening mode: the system binds the tile whenever the
 * shade opens, which is when its text is rebuilt, so the relative age in the
 * subtitle is accurate at the moment it is read. [LastReading.requestTileUpdate]
 * covers the active/inactive flip while the shade is already down.
 *
 * TileService is API 24, which is also the app's minSdk (Flutter's default),
 * so the class needs no version guard; the subtitle (29) and the PendingIntent
 * collapse (34) do.
 */
class SignalTileService : TileService() {

    companion object {
        private const val TAG = "SignalTile"
        private const val REQUEST_OPEN_APP = 20
    }

    override fun onStartListening() {
        super.onStartListening()
        render()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        render()
    }

    override fun onClick() {
        super.onClick()
        // On a locked phone, ask for the unlock first rather than opening the
        // app behind the keyguard where the user cannot see it.
        if (isLocked) unlockAndRun { openApp() } else openApp()
    }

    private fun render() {
        val tile = qsTile ?: return
        runCatching {
            val reading = LastReading.load(this)
            val now = System.currentTimeMillis()
            val subtitle = ReadingText.tileSubtitle(reading, now)

            tile.label = getString(R.string.tile_label)
            // Non-plate glyph: the system tints tile icons itself, so the plate's
            // contrast backing would just show as a filled square.
            tile.icon = Icon.createWithResource(
                this,
                IndicatorIcons.resourceFor(reading?.theme, reading?.bars ?: 0, false),
            )
            // ACTIVE tracks the indicator service rather than the score: the
            // tile's highlighted state is the system's "this is on" signal, and
            // the only thing here that is on or off is background measuring.
            tile.state = if (HonestSignalService.isRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = subtitle
            }
            // Below Android 10 there is no subtitle, so the label alone would
            // say nothing; the description at least reaches TalkBack.
            tile.contentDescription = "Honest Signal, $subtitle"
            tile.updateTile()
        }.onFailure { Log.w(TAG, "Tile render failed", it) }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14 made the Intent overload throw
                // UnsupportedOperationException for apps targeting 34+.
                startActivityAndCollapse(
                    PendingIntent.getActivity(
                        this,
                        REQUEST_OPEN_APP,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        }.onFailure { Log.w(TAG, "Could not open the app from the tile", it) }
    }
}
