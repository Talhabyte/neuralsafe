import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:neuralsafe/services/sms_dispatch_service.dart';

void main() {
  group('SmsDispatchService.send', () {
    test('sends successfully when permission is already granted', () async {
      String? sentPhoneNumber;
      String? sentMessage;

      final service = SmsDispatchService(
        checkPermission: () async => PermissionStatus.granted,
        requestPermission: () async =>
            throw StateError('should not be called when already granted'),
        sendSms: (phoneNumber, message) async {
          sentPhoneNumber = phoneNumber;
          sentMessage = message;
          return true;
        },
      );

      final result = await service.send('+923001234567', 'test message');

      expect(result.status, SmsSendStatus.success);
      expect(result.isSuccess, true);
      expect(sentPhoneNumber, '+923001234567');
      expect(sentMessage, 'test message');
    });

    test(
        'requests permission when not initially granted, then sends if '
        'granted', () async {
      var requestCalled = false;

      final service = SmsDispatchService(
        checkPermission: () async => PermissionStatus.denied,
        requestPermission: () async {
          requestCalled = true;
          return PermissionStatus.granted;
        },
        sendSms: (phoneNumber, message) async => true,
      );

      final result = await service.send('+923001234567', 'test message');

      expect(requestCalled, true);
      expect(result.status, SmsSendStatus.success);
    });

    test('returns permissionDenied if still denied after requesting', () async {
      final service = SmsDispatchService(
        checkPermission: () async => PermissionStatus.denied,
        requestPermission: () async => PermissionStatus.denied,
        sendSms: (phoneNumber, message) async =>
            throw StateError('should not be called'),
      );

      final result = await service.send('+923001234567', 'test message');

      expect(result.status, SmsSendStatus.permissionDenied);
      expect(result.isSuccess, false);
    });

    test('returns failed if the native send call returns false', () async {
      final service = SmsDispatchService(
        checkPermission: () async => PermissionStatus.granted,
        requestPermission: () async => PermissionStatus.granted,
        sendSms: (phoneNumber, message) async => false,
      );

      final result = await service.send('+923001234567', 'test message');

      expect(result.status, SmsSendStatus.failed);
    });

    test('returns failed if the native send call throws', () async {
      final service = SmsDispatchService(
        checkPermission: () async => PermissionStatus.granted,
        requestPermission: () async => PermissionStatus.granted,
        sendSms: (phoneNumber, message) async =>
            throw Exception('platform channel error'),
      );

      final result = await service.send('+923001234567', 'test message');

      expect(result.status, SmsSendStatus.failed);
    });
  });
}
