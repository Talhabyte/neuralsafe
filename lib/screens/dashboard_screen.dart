import 'package:flutter/material.dart';

/// Placeholder for the real safety dashboard. Phase 2 will add:
/// emergency contact setup, onboarding status, event log viewer,
/// and a manual "I'm safe" dismiss control for MEDIUM RISK alerts.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Dashboard')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Dashboard placeholder.\n\n'
            'Next: emergency contacts, onboarding progress, '
            'and the live Danger Score readout will go here.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
