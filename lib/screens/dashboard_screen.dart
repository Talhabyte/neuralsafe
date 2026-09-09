import 'package:flutter/material.dart';

import '../services/emergency_contact_repository.dart';
import '../services/onboarding_repository.dart';
import '../services/user_profile_repository.dart';
import 'setup_screen.dart';

/// Reached only via the calculator's secret code. Shows either a
/// "get started" prompt (setup incomplete) or a read-only summary of
/// the saved profile/contact (setup complete), with an edit option.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _onboardingRepo = OnboardingRepository();
  final _profileRepo = UserProfileRepository();
  final _contactRepo = EmergencyContactRepository();

  Future<void> _openSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SetupScreen()),
    );
    // Refresh after returning, in case setup was just completed/edited.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = _onboardingRepo.load();

    return Scaffold(
      appBar: AppBar(title: const Text('Safety Dashboard')),
      body: onboarding.isComplete ? _buildSummary() : _buildGetStarted(),
    );
  }

  Widget _buildGetStarted() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Setup has not been completed yet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _openSetup,
              child: const Text('Start Setup'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final profile = _profileRepo.load();
    final contact = _contactRepo.loadPrimary();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Name: ${profile?.name ?? '-'}'),
          Text('Preferred language: '
              '${profile?.preferredLanguage == 'ur' ? 'Urdu' : 'English'}'),
          const SizedBox(height: 24),
          const Text('Primary Emergency Contact',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Name: ${contact?.name ?? '-'}'),
          Text('Phone: ${contact?.phoneNumber ?? '-'}'),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _openSetup,
            child: const Text('Edit Setup'),
          ),
        ],
      ),
    );
  }
}
