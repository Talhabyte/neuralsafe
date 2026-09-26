import '../models/dispatch_result.dart';
import '../models/location_result.dart';
import 'alert_cooldown_manager.dart';
import 'emergency_contact_repository.dart';
import 'location_service.dart';
import 'sms_dispatch_service.dart';

/// Orchestrates a full emergency alert dispatch: cooldown check, load
/// ALL stored emergency contacts, acquire location (best-effort — a
/// failure does not block dispatch), build the alert message, and send
/// to every contact. Deliberately standalone and UNWIRED — nothing
/// calls `dispatch()` automatically. A later, separately-approved step
/// decides when this should actually be triggered (e.g. from
/// `RiskDecisionEngine`'s highDanger tier).
///
/// [dryRun]: when true, every step runs for real (cooldown, contact
/// load, location acquisition, message construction) EXCEPT the
/// actual SMS send, which is simulated as always-successful without
/// calling the injected [smsDispatchService]. This exists specifically
/// so the full pipeline can be verified on a physical device without a
/// real SMS leaving — flip to false only deliberately, with a real
/// test contact you control.
class EmergencyAlertDispatcher {
  EmergencyAlertDispatcher({
    required LocationService locationService,
    required SmsDispatchService smsDispatchService,
    required AlertCooldownManager cooldownManager,
    List<dynamic> Function()? loadContacts,
    DateTime Function()? clock,
    this.dryRun = false,
  })  : _locationService = locationService,
        _smsDispatchService = smsDispatchService,
        _cooldownManager = cooldownManager,
        _loadContacts = loadContacts ?? EmergencyContactRepository().loadAll,
        _clock = clock ?? DateTime.now;

  final LocationService _locationService;
  final SmsDispatchService _smsDispatchService;
  final AlertCooldownManager _cooldownManager;

  /// Untyped as `List<dynamic> Function()` (rather than
  /// `List<EmergencyContact> Function()`) deliberately, so tests can
  /// inject lightweight fake contact objects without constructing full
  /// `EmergencyContact` instances. Each element is expected to expose
  /// `id` (`String`) and `phoneNumber` (`String`) — see the `dynamic`
  /// casts in `dispatch()` below.
  final List<dynamic> Function() _loadContacts;
  final DateTime Function() _clock;
  final bool dryRun;

  Future<DispatchResult> dispatch() async {
    final now = _clock();

    if (!_cooldownManager.canSendAlert()) {
      return DispatchResult(
        outcome: DispatchOutcome.suppressedByCooldown,
        location: null,
        perContactSuccess: const {},
        attemptedAt: now,
      );
    }

    final contacts = _loadContacts();
    if (contacts.isEmpty) {
      return DispatchResult(
        outcome: DispatchOutcome.noContactsConfigured,
        location: null,
        perContactSuccess: const {},
        attemptedAt: now,
      );
    }

    final location = await _locationService.acquireCurrentLocation();
    final message = _buildMessage(location);

    final perContactSuccess = <String, bool>{};
    for (final contact in contacts) {
      final String contactId = contact.id as String;
      final String phoneNumber = contact.phoneNumber as String;

      final bool succeeded;
      if (dryRun) {
        succeeded = true; // simulated — real sendSms is never called
      } else {
        final result = await _smsDispatchService.send(phoneNumber, message);
        succeeded = result.isSuccess;
      }
      perContactSuccess[contactId] = succeeded;
    }

    _cooldownManager.recordAlertSent();

    final allSucceeded = perContactSuccess.values.every((ok) => ok);

    return DispatchResult(
      outcome:
          allSucceeded ? DispatchOutcome.sent : DispatchOutcome.partialFailure,
      location: location,
      perContactSuccess: perContactSuccess,
      attemptedAt: now,
    );
  }

  String _buildMessage(LocationResult location) {
    final locationPart = location.mapsLink ?? 'Unavailable';
    return 'EMERGENCY ALERT: NeuralSafe user requires immediate assistance. '
        'Location: $locationPart (Automated alert sent by NeuralSafe)';
  }
}
