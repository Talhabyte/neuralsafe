package com.example.neuralsafe

import android.telephony.SmsManager

/**
 * Wraps Android's SmsManager for Step 6's emergency alert dispatch.
 * Sends exactly one text message to one recipient. Does not check or
 * request permissions itself — the Dart side (SmsDispatchService, via
 * permission_handler) is responsible for ensuring SEND_SMS is granted
 * before calling this.
 */
class SmsGatewayChannel {

    fun sendSms(phoneNumber: String, message: String): Boolean {
        return try {
            val smsManager = SmsManager.getDefault()
            // Long messages are split automatically so they don't
            // silently truncate.
            val parts = smsManager.divideMessage(message)
            smsManager.sendMultipartTextMessage(
                phoneNumber, null, parts, null, null
            )
            true
        } catch (e: Exception) {
            false
        }
    }
}