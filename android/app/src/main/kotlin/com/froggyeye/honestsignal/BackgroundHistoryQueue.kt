package com.froggyeye.honestsignal

import org.json.JSONArray
import org.json.JSONObject

/** Pure transformations for the native cross-engine history hand-off queue. */
object BackgroundHistoryQueue {
    const val MAX_PENDING_ROWS = 3_000
    const val RETENTION_MS = 25L * 60L * 60L * 1_000L

    fun decode(serialized: String?): List<Map<String, Any?>> = runCatching {
        val json = JSONArray(serialized ?: "[]")
        buildList {
            for (index in 0 until json.length()) {
                val item = json.optJSONObject(index) ?: continue
                add(buildMap {
                    for (key in item.keys()) {
                        put(key, if (item.isNull(key)) null else item.get(key))
                    }
                })
            }
        }
    }.getOrElse { emptyList() }

    fun encode(rows: List<Map<String, Any?>>): String = JSONArray().apply {
        rows.forEach { put(JSONObject(it)) }
    }.toString()

    fun persist(
        rows: List<Map<String, Any?>>,
        commit: (String) -> Boolean,
    ): Boolean = commit(encode(rows))

    fun retained(
        rows: List<Map<String, Any?>>,
        nowMs: Long,
        cap: Int = MAX_PENDING_ROWS,
    ): List<Map<String, Any?>> {
        val cutoff = nowMs - RETENTION_MS
        return rows
            .filter { (it["ts"] as? Number)?.toLong()?.let { ts -> ts >= cutoff } == true }
            .takeLast(cap.coerceAtLeast(0))
    }

    fun append(
        rows: List<Map<String, Any?>>,
        row: Map<String, Any?>,
        nowMs: Long,
    ): List<Map<String, Any?>> = retained(rows + row, nowMs)

    fun drop(
        rows: List<Map<String, Any?>>,
        timestamps: List<Long>,
        nowMs: Long,
    ): List<Map<String, Any?>> {
        val remaining = timestamps.groupingBy { it }.eachCount().toMutableMap()
        val kept = rows.filter { row ->
            val timestamp = (row["ts"] as? Number)?.toLong()
                ?: return@filter true
            val count = remaining[timestamp] ?: 0
            if (count == 0) true
            else {
                remaining[timestamp] = count - 1
                false
            }
        }
        return retained(kept, nowMs)
    }
}
