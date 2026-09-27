import 'package:flutter/material.dart';
import 'screens/calculator_screen.dart';
import 'services/secure_vault_service.dart';
import 'services/behavioral_monitoring_service.dart';
import 'services/text_analysis_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SecureVaultService.instance.init();
  debugPrint('[NeuralSafe] Secure vault initialized: '
      '${SecureVaultService.instance.isInitialized}');
  BehavioralMonitoringService.instance.start();
  await TextAnalysisService.instance.init();
  debugPrint('[NeuralSafe] Text analysis service initialized: '
      '${TextAnalysisService.instance.isInitialized}');
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
