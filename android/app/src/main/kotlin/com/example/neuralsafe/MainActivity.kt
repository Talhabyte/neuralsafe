package com.example.neuralsafe

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val screenStateChannelName = "neuralsafe/screen_state"
    private var screenStateReceiver: ScreenStateReceiver? = null

    private val appUsageChannelName = "neuralsafe/app_usage"

    // Phase 6: emergency SMS dispatch.
    private val smsGatewayChannelName = "neuralsafe/sms_gateway"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, screenStateChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return
                    val receiver = ScreenStateReceiver(events)
                    screenStateReceiver = receiver
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_SCREEN_ON)
                        addAction(Intent.ACTION_SCREEN_OFF)
                        addAction(Intent.ACTION_USER_PRESENT)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        @Suppress("UnspecifiedRegisterReceiverFlag")
                        registerReceiver(receiver, filter)
                    }
                }
                override fun onCancel(arguments: Any?) {
                    screenStateReceiver?.let { unregisterReceiver(it) }
                    screenStateReceiver = null
                }
            })

        val appUsageChannel = AppUsageChannel(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUsageChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageAccess" -> result.success(appUsageChannel.hasUsageAccess())
                    "openUsageAccessSettings" -> {
                        appUsageChannel.openUsageAccessSettings()
                        result.success(null)
                    }
                    "queryEvents" -> {
                        val since = call.argument<Number>("since")?.toLong()
                        val until = call.argument<Number>("until")?.toLong()
                        if (since == null || until == null) {
                            result.error("INVALID_ARGS", "since/until required", null)
                        } else {
                            result.success(appUsageChannel.queryEvents(since, until))
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        val smsGatewayChannel = SmsGatewayChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsGatewayChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val phoneNumber = call.argument<String>("phoneNumber")
                        val message = call.argument<String>("message")
                        if (phoneNumber == null || message == null) {
                            result.error("INVALID_ARGS", "phoneNumber/message required", null)
                        } else {
                            result.success(smsGatewayChannel.sendSms(phoneNumber, message))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}