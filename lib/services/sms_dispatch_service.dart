import 'package:permission_handler/permission_handler.dart';

import 'sms_gateway_native_bridge.dart';

enum SmsSendStatus { success, permissionDenied, failed }

class SmsSendResult {
  final SmsSendStatus status;
  const SmsSendResult(this.status);
  bool get isSuccess => status == SmsSendStatus.success;
}

/// Sends a single SMS, handling the SEND_SMS runtime permission check/
/// request via permission_handler (already a project dependency).
/// SEND_SMS is a normal dangerous permission with a standard runtime
/// dialog — unlike PACKAGE_USAGE_STATS, no special-access settings
/// screen is needed.
///
/// Every dependency is injectable so this is fully unit testable
/// without touching the real permission system or sending a real SMS.
class SmsDispatchService {
  SmsDispatchService({
    Future<PermissionStatus> Function()? checkPermission,
    Future<PermissionStatus> Function()? requestPermission,
    Future<bool> Function(String phoneNumber, String message)? sendSms,
  })  : _checkPermission = checkPermission ?? (() => Permission.sms.status),
        _requestPermission =
            requestPermission ?? (() => Permission.sms.request()),
        _sendSms = sendSms ?? SmsGatewayNativeBridge().sendSms;

  final Future<PermissionStatus> Function() _checkPermission;
  final Future<PermissionStatus> Function() _requestPermission;
  final Future<bool> Function(String phoneNumber, String message) _sendSms;

  Future<SmsSendResult> send(String phoneNumber, String message) async {
    var status = await _checkPermission();
    if (!status.isGranted) {
      status = await _requestPermission();
    }
    if (!status.isGranted) {
      return const SmsSendResult(SmsSendStatus.permissionDenied);
    }

    try {
      final succeeded = await _sendSms(phoneNumber, message);
      return SmsSendResult(
        succeeded ? SmsSendStatus.success : SmsSendStatus.failed,
      );
    } catch (_) {
      return const SmsSendResult(SmsSendStatus.failed);
    }
  }
}
