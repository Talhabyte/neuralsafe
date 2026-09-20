package com.example.neuralsafe

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings

/**
 * Wraps UsageStatsManager for Step 3.6's app-usage/context signal.
 * Collects ONLY: package name, foreground/background event type, and
 * timestamp for each observed transition. Never reads notification
 * content, screen content, accessibility text, or any other app data.
 */
class AppUsageChannel(private val context: Context) {

    fun hasUsageAccess(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * PACKAGE_USAGE_STATS has no runtime permission dialog — the user
     * must grant it manually via this settings screen.
     */
    fun openUsageAccessSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    /**
     * Returns raw MOVE_TO_FOREGROUND / MOVE_TO_BACKGROUND events in
     * [since, until), each as a Map with only packageName, eventType
     * ("foreground"/"background"), and timestamp (millis). Any other
     * UsageEvents type is skipped entirely — never surfaced to Dart.
     */
    fun queryEvents(since: Long, until: Long): List<Map<String, Any>> {
        val usageStatsManager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usageStatsManager.queryEvents(since, until)
        val result = mutableListOf<Map<String, Any>>()
        val event = UsageEvents.Event()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val eventType = when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> "foreground"
                UsageEvents.Event.MOVE_TO_BACKGROUND -> "background"
                else -> null
            } ?: continue

            result.add(
                mapOf(
                    "packageName" to event.packageName,
                    "eventType" to eventType,
                    "timestamp" to event.timeStamp
                )
            )
        }

        return result
    }
}