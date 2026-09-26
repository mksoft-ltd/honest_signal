package com.froggyeye.honestsignal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundHistoryQueueTest {
    private val now = 2_000_000_000_000L

    private fun row(id: Int, timestamp: Long = now): Map<String, Any?> =
        mapOf("id" to id, "ts" to timestamp)

    @Test
    fun `append and drop preserve FIFO order`() {
        val rows = BackgroundHistoryQueue.append(listOf(row(1)), row(2), now)
        assertEquals(listOf(1, 2), rows.map { it["id"] })
        assertEquals(listOf(2), BackgroundHistoryQueue.drop(rows, listOf(now), now).map { it["id"] })
    }

    @Test
    fun `drop only removes peeked timestamps after expiry and append`() {
        val expired = now - BackgroundHistoryQueue.RETENTION_MS
        val peeked = listOf(row(1, expired), row(2, now - 1))
        val current = peeked + row(3, now + 1)

        val remaining = BackgroundHistoryQueue.drop(
            current,
            peeked.map { (it["ts"] as Number).toLong() },
            now + 1,
        )

        assertEquals(listOf(3), remaining.map { it["id"] })
    }

    @Test
    fun `malformed serialization and corrupt rows are discarded`() {
        assertTrue(BackgroundHistoryQueue.decode("not-json").isEmpty())
        val rows = BackgroundHistoryQueue.retained(
            listOf(row(1), mapOf("id" to 2), mapOf("id" to 3, "ts" to "bad")),
            now,
        )
        assertEquals(listOf(1), rows.map { it["id"] })
    }

    @Test
    fun `expiry boundary is inclusive and older rows are pruned`() {
        val cutoff = now - BackgroundHistoryQueue.RETENTION_MS
        val rows = BackgroundHistoryQueue.retained(
            listOf(row(1, cutoff - 1), row(2, cutoff)),
            now,
        )
        assertEquals(listOf(2), rows.map { it["id"] })
    }

    @Test
    fun `cap keeps the newest rows in FIFO order`() {
        val rows = BackgroundHistoryQueue.retained(
            (0..5).map { row(it) },
            now,
            cap = 3,
        )
        assertEquals(listOf(3, 4, 5), rows.map { it["id"] })
    }

    @Test
    fun `append uses the pinned default capacity`() {
        assertEquals(6_000, BackgroundHistoryQueue.MAX_PENDING_ROWS)
        val rows = (0 until BackgroundHistoryQueue.MAX_PENDING_ROWS).map { row(it) }
        val appended = BackgroundHistoryQueue.append(
            rows,
            row(BackgroundHistoryQueue.MAX_PENDING_ROWS),
            now,
        )
        assertEquals(BackgroundHistoryQueue.MAX_PENDING_ROWS, appended.size)
        assertEquals(1, appended.first()["id"])
        assertEquals(BackgroundHistoryQueue.MAX_PENDING_ROWS, appended.last()["id"])
    }

    @Test
    fun `failed commit is observable by the channel`() {
        var attempted = false
        val committed = BackgroundHistoryQueue.persist(listOf(row(1))) {
            attempted = true
            false
        }
        assertTrue(attempted)
        assertFalse(committed)
    }

    @Test
    fun `JSON round trip preserves queue order`() {
        val decoded = BackgroundHistoryQueue.decode(
            BackgroundHistoryQueue.encode(listOf(row(1), row(2))),
        )
        assertEquals(listOf(1, 2), decoded.map { (it["id"] as Number).toInt() })
    }
}
