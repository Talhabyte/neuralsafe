import 'package:flutter/material.dart';
import 'screens/calculator_screen.dart';
import 'services/secure_vault_service.dart';
import 'services/behavioral_monitoring_service.dart';
import 'services/behavioral_event_repository.dart';
import 'models/behavioral_event.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SecureVaultService.instance.init();
  debugPrint('[NeuralSafe] Secure vault initialized: '
      '${SecureVaultService.instance.isInitialized}');

  BehavioralMonitoringService.instance.start();

  // --- TEMPORARY: Step 3.6 appUsageSession persistence diagnostic   ---
  // --- only. REMOVE THIS ENTIRE BLOCK (and the two imports above)   ---
  // --- once confirmed. Read-only — calls loadAll() only, never      ---
  // --- save()/clearAll(), so it cannot alter any persisted data.    ---
  final allEvents = BehavioralEventRepository().loadAll();
  final usageEvents = allEvents
      .where((e) => e.type == BehavioralEventType.appUsageSession)
      .toList();

  debugPrint('[NeuralSafe] Step 3.6 diagnostic: total persisted events = '
      '${allEvents.length}');
  debugPrint('[NeuralSafe] Step 3.6 diagnostic: appUsageSession count = '
      '${usageEvents.length}');

  debugPrint('[NeuralSafe] Step 3.6 diagnostic: all appUsageSession events '
      '(oldest to newest):');
  for (final event in usageEvents) {
    debugPrint('[NeuralSafe]   - packageName: ${event.packageName}, '
        'durationMs: ${event.durationMs}, timestamp: ${event.timestamp}');
  }
  // --- END TEMPORARY BLOCK ---

  runApp(const NeuralSafeApp());
}

class NeuralSafeApp extends StatelessWidget {
  const NeuralSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Deliberately plain — no NeuralSafe branding anywhere in the
      // visible app, per the stealth design constraint (Chapter 4.2.3).
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const CalculatorScreen(),
    );
  }
}
