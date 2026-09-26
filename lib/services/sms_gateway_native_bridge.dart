import 'package:flutter/services.dart';

/// Thin Dart wrapper over the native 'neuralsafe/sms_gateway'
/// MethodChannel. Sends a single SMS via Android's SmsManager — no
/// permission checking here (that's SmsDispatchService's job, via
/// permission_handler); this bridge only sends.
class SmsGatewayNativeBridge {
  static const _channel = MethodChannel('neuralsafe/sms_gateway');

  /// Returns true if the native send call succeeded. Throws only on a
  /// genuine platform channel failure (e.g. missing handler); an
  /// SmsManager-level failure is reported as a normal `false` return
  /// via the native side rather than an exception, so callers can
  /// distinguish "the API rejected sending" from "the channel itself
  /// is broken."
  Future<bool> sendSms(String phoneNumber, String message) async {
    final result = await _channel.invokeMethod<bool>('sendSms', {
      'phoneNumber': phoneNumber,
      'message': message,
    });
    return result ?? false;
  }
}
