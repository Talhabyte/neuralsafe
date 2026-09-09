package com.example.neuralsafe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.EventChannel

/**
 * Listens for the three screen-state system broadcasts NeuralSafe's
 * behavioral monitoring needs (Chapter 4.5.3 — screen unlock frequency):
 *
 *  - ACTION_SCREEN_ON     : display turned on (may just be a glance, not a full unlock)
 *  - ACTION_SCREEN_OFF    : display turned off / device locked
 *  - ACTION_USER_PRESENT  : device was actually unlocked past the lock screen
 *
 * Each event is forwarded to Dart as a small Map via the EventChannel's
 * EventSink, with a "type" string and a millisecond epoch "timestamp".
 * No aggregation or interpretation happens here — that's Dart-side work
 * for a later step, not this receiver's job.
 */
class ScreenStateReceiver(private val eventSink: EventChannel.EventSink) : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        val eventType = when (intent?.action) {
            Intent.ACTION_SCREEN_ON -> "screen_on"
            Intent.ACTION_SCREEN_OFF -> "screen_off"
            Intent.ACTION_USER_PRESENT -> "user_present"
            else -> return // ignore anything unexpected
        }

        val payload = mapOf(
            "type" to eventType,
            "timestamp" to System.currentTimeMillis()
        )

        eventSink.success(payload)
    }
}