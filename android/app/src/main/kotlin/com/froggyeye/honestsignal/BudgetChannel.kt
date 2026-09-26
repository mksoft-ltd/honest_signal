package com.froggyeye.honestsignal

import android.content.Context
import io.flutter.plugin.common.MethodChannel

/**
 * The day's probe-byte counter.
 *
 * It lives here rather than in Hive because two Dart isolates need it — the UI
 * engine while the app is open, and the background engine hosted by
 * [HonestSignalService] the rest of the time — and Hive is not safe across
 * isolates. SharedPreferences is, so both isolates talk to this one store.
 */
object BudgetStore {
    private const val PREFS = "honest_signal_budget"
    private const val KEY_DAY = "day"
    private const val KEY_USED = "used"

    @Synchronized
    fun read(context: Context, day: String): Pair<String, Long> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val storedDay = prefs.getString(KEY_DAY, null)
        // A new calendar day resets the counter. Dart owns the notion of "which
        // day it is" so that the local-midnight rollover matches what the user
        // sees in the app.
        if (storedDay != day) return day to 0L
        return day to prefs.getLong(KEY_USED, 0L)
    }

    @Synchronized
    fun spend(context: Context, day: String, bytes: Long): Pair<String, Long> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = read(context, day).second
        val next = current + bytes.coerceAtLeast(0L)
        prefs.edit().putString(KEY_DAY, day).putLong(KEY_USED, next).apply()
        return day to next
    }
}

/** Wires [BudgetStore] onto a Flutter engine's binary messenger. */
object BudgetChannel {
    const val NAME = "com.froggyeye.honestsignal/budget"
    private const val HISTORY_PREFS = "honest_signal_background_history"
    private const val HISTORY_ROWS = "rows"

    private fun readStoredRows(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(HISTORY_PREFS, Context.MODE_PRIVATE)
        return BackgroundHistoryQueue.decode(prefs.getString(HISTORY_ROWS, "[]"))
    }

    private fun writeStoredRows(context: Context, rows: List<Map<String, Any?>>) {
        val preferences = context.getSharedPreferences(HISTORY_PREFS, Context.MODE_PRIVATE)
        val committed = BackgroundHistoryQueue.persist(rows) { serialized ->
            preferences.edit().putString(HISTORY_ROWS, serialized).commit()
        }
        check(committed) { "Could not commit background history" }
    }

    @Synchronized
    private fun appendHistory(context: Context, row: Map<*, *>) {
        val rows = BackgroundHistoryQueue.append(
            readStoredRows(context),
            row.entries.associate { it.key.toString() to it.value },
            System.currentTimeMillis(),
        )
        // commit() makes the queue durable before Dart reports the cycle done.
        writeStoredRows(context, rows)
    }

    @Synchronized
    private fun readHistory(context: Context): List<Map<String, Any?>> {
        val rows = BackgroundHistoryQueue.retained(
            readStoredRows(context),
            System.currentTimeMillis(),
        )
        // Peek also persists pruning so corrupt/expired rows do not reappear.
        writeStoredRows(context, rows)
        return rows
    }

    @Synchronized
    private fun dropHistory(context: Context, timestamps: List<Long>) {
        writeStoredRows(
            context,
            BackgroundHistoryQueue.drop(
                readStoredRows(context),
                timestamps,
                System.currentTimeMillis(),
            ),
        )
    }

    fun handler(context: Context): MethodChannel.MethodCallHandler =
        MethodChannel.MethodCallHandler { call, result ->
            if (call.method == "historyAppend") {
                @Suppress("UNCHECKED_CAST")
                val row = call.arguments as? Map<String, Any?>
                if (row == null) result.error("bad_args", "sample is required", null)
                else {
                    runCatching { appendHistory(context, row) }.fold(
                        onSuccess = { result.success(null) },
                        onFailure = {
                            result.error("history_write_failed", it.localizedMessage, null)
                        },
                    )
                }
                return@MethodCallHandler
            }
            if (call.method == "historyPeek") {
                runCatching { readHistory(context) }.fold(
                    onSuccess = { result.success(it) },
                    onFailure = {
                        result.error("history_write_failed", it.localizedMessage, null)
                    },
                )
                return@MethodCallHandler
            }
            if (call.method == "historyDrop") {
                runCatching {
                    val timestamps = (call.argument<List<Number>>("timestamps") ?: emptyList())
                        .map { it.toLong() }
                    dropHistory(context, timestamps)
                }.fold(
                    onSuccess = { result.success(null) },
                    onFailure = {
                        result.error("history_write_failed", it.localizedMessage, null)
                    },
                )
                return@MethodCallHandler
            }
            val day = call.argument<String>("day")
            if (day == null) {
                result.error("bad_args", "day is required", null)
                return@MethodCallHandler
            }
            val outcome = when (call.method) {
                "budgetRead" -> BudgetStore.read(context, day)
                "budgetSpend" -> BudgetStore.spend(
                    context,
                    day,
                    (call.argument<Number>("bytes") ?: 0).toLong()
                )
                else -> {
                    result.notImplemented()
                    return@MethodCallHandler
                }
            }
            result.success(mapOf("day" to outcome.first, "used" to outcome.second))
        }
}
