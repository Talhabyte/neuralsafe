import 'dart:async';

import 'package:flutter/material.dart';

import '../models/anomaly_result_log_entry.dart';
import '../services/emergency_contact_repository.dart';
import '../services/onboarding_repository.dart';
import '../services/risk_decision_engine.dart';
import '../services/text_analysis_service.dart';
import '../services/user_profile_repository.dart';
import '../services/voice_analysis_service.dart';
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

  // --- Text module manual test hook (temporary, until real SMS
  // interception / MessageInterceptor is built) ---
  final _behaviorController =
      StreamController<AnomalyResultLogEntry>.broadcast();
  late final RiskDecisionEngine _riskEngine =
      RiskDecisionEngine(anomalyStream: _behaviorController.stream)..start();
  final _textController = TextEditingController();
  TextAnalysisResult? _lastTextResult;
  bool _isAnalyzing = false;

  // --- Voice module manual test hook (temporary, until real always-on
  // background mic monitoring is wired in per Chapter 6.4) ---
  StreamSubscription<VoiceAnalysisResult>? _voiceSubscription;
  VoiceAnalysisResult? _lastVoiceResult;
  bool _isVoiceRunning = false;
  bool _isStartingVoice = false;

  Future<void> _openSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SetupScreen()),
    );
    // Refresh after returning, in case setup was just completed/edited.
    setState(() {});
  }

  Future<void> _analyzeText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isAnalyzing = true);
    try {
      final result = await TextAnalysisService.instance.analyze(text);
      _riskEngine.submitTextScore(result.score);
      setState(() {
        _lastTextResult = result;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Analysis failed: $e')));
      }
    }
  }

  Future<void> _toggleVoice() async {
    if (_isVoiceRunning) {
      await VoiceAnalysisService.instance.stop();
      await _voiceSubscription?.cancel();
      _voiceSubscription = null;
      setState(() => _isVoiceRunning = false);
      return;
    }

    setState(() => _isStartingVoice = true);
    final started = await VoiceAnalysisService.instance.start();
    setState(() => _isStartingVoice = false);

    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Microphone permission denied.'),
        ));
      }
      return;
    }

    _voiceSubscription = VoiceAnalysisService.instance.scores.listen((result) {
      _riskEngine.submitVoiceScore(result.score);
      setState(() => _lastVoiceResult = result);
    });

    setState(() => _isVoiceRunning = true);
  }

  @override
  void dispose() {
    _textController.dispose();
    _voiceSubscription?.cancel();
    if (_isVoiceRunning) {
      VoiceAnalysisService.instance.stop();
    }
    _riskEngine.stop();
    _riskEngine.dispose();
    _behaviorController.close();
    super.dispose();
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

    return SingleChildScrollView(
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
          const Divider(height: 48),
          const Text('Text Module Test (temporary)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _textController,
            decoration: const InputDecoration(
              labelText: 'Message text',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isAnalyzing ? null : _analyzeText,
            child: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze Text'),
          ),
          if (_lastTextResult != null) ...[
            const SizedBox(height: 16),
            Text('Predicted class: ${_lastTextResult!.predictedClass}'),
            Text('TextScore: ${_lastTextResult!.score.toStringAsFixed(2)}'),
            Text('Probabilities: ${_lastTextResult!.probabilities}'),
            const SizedBox(height: 8),
            Text(
              'Fused Danger Score: '
              '${_riskEngine.latest?.fusionResult.finalScore.toStringAsFixed(2) ?? '-'}',
            ),
            Text('Risk Tier: ${_riskEngine.latest?.riskTier ?? '-'}'),
          ],
          const Divider(height: 48),
          const Text('Voice Module Test (temporary)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_isVoiceRunning
              ? 'Listening... (updates every 500ms)'
              : 'Mic is off.'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isStartingVoice ? null : _toggleVoice,
            child: Text(_isStartingVoice
                ? 'Starting...'
                : (_isVoiceRunning ? 'Stop Listening' : 'Start Listening')),
          ),
          if (_lastVoiceResult != null) ...[
            const SizedBox(height: 16),
            Text('Classification: ${_lastVoiceResult!.classification}'),
            Text('VoiceScore: ${_lastVoiceResult!.score.toStringAsFixed(2)}'),
            Text('Probabilities: ${_lastVoiceResult!.probabilities}'),
            const SizedBox(height: 8),
            Text(
              'Fused Danger Score: '
              '${_riskEngine.latest?.fusionResult.finalScore.toStringAsFixed(2) ?? '-'}',
            ),
            Text('Risk Tier: ${_riskEngine.latest?.riskTier ?? '-'}'),
          ],
        ],
      ),
    );
  }
}
