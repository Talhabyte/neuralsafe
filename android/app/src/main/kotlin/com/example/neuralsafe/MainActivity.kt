package com.example.neuralsafe

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    // Phase 3 Step 1: screen lock/unlock event stream.
    // See ScreenStateReceiver.kt for what each broadcast means.
    private val screenStateChannelName = "neuralsafe/screen_state"
    private var screenStateReceiver: ScreenStateReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, screenStateChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {

                // Called when Dart starts listening (ScreenActivityService.events.listen(...)).
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return

                    val receiver = ScreenStateReceiver(events)
                    screenStateReceiver = receiver

                    // SCREEN_ON/SCREEN_OFF/USER_PRESENT are implicit broadcasts —
                    // since Android 8 (API 26) these can't be declared in the
                    // manifest, so we register dynamically here instead.
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_SCREEN_ON)
                        addAction(Intent.ACTION_SCREEN_OFF)
                        addAction(Intent.ACTION_USER_PRESENT)
                    }

                    // Android 13 (API 33)+ requires an explicit exported/not-exported
                    // flag on context-registered receivers, even for system broadcasts.
                    // These are protected system broadcasts, so RECEIVER_NOT_EXPORTED
                    // is correct — no other app can send them anyway.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        @Suppress("UnspecifiedRegisterReceiverFlag")
                        registerReceiver(receiver, filter)
                    }
                }

                // Called when Dart stops listening.
                override fun onCancel(arguments: Any?) {
                    screenStateReceiver?.let { unregisterReceiver(it) }
                    screenStateReceiver = null
                }
            })
    }
}