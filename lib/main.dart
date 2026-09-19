import 'package:flutter/material.dart';
import 'screens/calculator_screen.dart';
import 'services/secure_vault_service.dart';
import 'services/behavioral_monitoring_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SecureVaultService.instance.init();
  debugPrint('[NeuralSafe] Secure vault initialized: '
      '${SecureVaultService.instance.isInitialized}');

  BehavioralMonitoringService.instance.start();

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
