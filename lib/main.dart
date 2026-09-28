import 'package:flutter/material.dart';
import 'screens/calculator_screen.dart';
import 'services/alert_cooldown_manager.dart';
import 'services/behavioral_anomaly_pipeline.dart';
import 'services/behavioral_monitoring_service.dart';
import 'services/emergency_alert_dispatcher.dart';
import 'services/emergency_response_orchestrator.dart';
import 'services/feature_vault_service.dart';
import 'services/location_service.dart';
import 'services/risk_decision_engine.dart';
import 'services/secure_vault_service.dart';
import 'services/sms_dispatch_service.dart';
import 'services/text_analysis_service.dart';
import 'services/voice_analysis_service.dart';

/// IMPORTANT: constructed with dryRun: true in main() below — real SMS
/// sending is disabled. Every other step of the alert pipeline
/// (cooldown check, contact load, location acquisition, message
/// construction) runs for real. Flip dryRun to false in main() only
/// deliberately, once you've verified the pipeline on a physical
/// device with a real test contact you control (see
/// EmergencyAlertDispatcher's own doc comment).
late final EmergencyResponseOrchestrator emergencyOrchestrator;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SecureVaultService.instance.init();
  debugPrint('[NeuralSafe] Secure vault initialized: '
      '${SecureVaultService.instance.isInitialized}');

  // Separate encrypted box from SecureVaultService's — holds
  // BehavioralBaseline and AnomalyResultLogEntry data (Phase 4).
  // BehavioralBaselineRepository/AnomalyResultRepository both throw a
  // StateError if this hasn't completed before they're used, so this
  // must happen before BehavioralAnomalyPipeline.instance.start() below.
  await FeatureVaultService.instance.init();
  debugPrint('[NeuralSafe] Feature vault initialized: '
      '${FeatureVaultService.instance.isInitialized}');

  // Behavioral: raw event collection, then the periodic pipeline that
  // turns collected events into a scored anomaly result.
  BehavioralMonitoringService.instance.start();
  BehavioralAnomalyPipeline.instance.start();

  await TextAnalysisService.instance.init();
  debugPrint('[NeuralSafe] Text analysis service initialized: '
      '${TextAnalysisService.instance.isInitialized}');
  await VoiceAnalysisService.instance.init();
  debugPrint('[NeuralSafe] Voice analysis service initialized: '
      '${VoiceAnalysisService.instance.isInitialized}');

  // The real, persistent fusion engine — fed continuously by the
  // Behavioral pipeline above. Text/Voice scores are submitted to it
  // from wherever those modules produce a result (currently the
  // dashboard's manual test hooks).
  final riskEngine = RiskDecisionEngine.instance;

  emergencyOrchestrator = EmergencyResponseOrchestrator(
    riskDecisions: riskEngine.decisions,
    dispatcher: EmergencyAlertDispatcher(
      locationService: LocationService(),
      smsDispatchService: SmsDispatchService(),
      cooldownManager: AlertCooldownManager(),
      dryRun: true, // see warning above
    ),
  )..start();
  debugPrint('[NeuralSafe] Emergency response orchestrator started '
      '(dryRun: true — no real SMS will be sent)');

  runApp(const NeuralSafeApp());
}

class NeuralSafeApp extends StatelessWidget {
  const NeuralSafeApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const CalculatorScreen(),
    );
  }
}
