import 'package:flutter_test/flutter_test.dart';
import 'package:neuralsafe/services/voice_analysis_service.dart';

void main() {
  group('computeVoiceScore', () {
    test('a single loud/scream-like window is held at Normal (gated)', () {
      final state = VoiceScoringState();
      final r1 = computeVoiceScore([0.05, 0.1, 0.85], state);
      // First window: escalation to HighDanger is not yet confirmed, so
      // the classification and score stay at the Normal-tier formula.
      expect(r1.classification, 'Normal');
      expect(r1.score, closeTo(0.85 * 15 * 0.3, 1e-9));
    });

    test(
        'sustained scream (2+ consecutive windows) escalates and drives '
        'score up quickly', () {
      final state = VoiceScoringState();
      VoiceAnalysisResult? last;
      for (var i = 0; i < 8; i++) {
        last = computeVoiceScore([0.05, 0.1, 0.85], state);
      }
      // By the 2nd consecutive window the HighDanger tier is confirmed,
      // and after several more sustained windows the smoothed score
      // should be climbing well past the elevated threshold.
      expect(last!.classification, 'HighDanger');
      expect(last.score, greaterThan(80));
    });

    test('clear Normal (quiet) settles near zero', () {
      final state = VoiceScoringState();
      VoiceAnalysisResult? last;
      for (var i = 0; i < 10; i++) {
        last = computeVoiceScore([0.9, 0.08, 0.02], state);
      }
      expect(last!.classification, 'Normal');
      expect(last.score, lessThan(5));
    });

    test('a single loud window followed by quiet ones never escalates', () {
      // Regression test for the flickering issue: one spike surrounded by
      // normal windows should never flip the classification or spike the
      // score, since escalation requires 2 consecutive agreeing windows.
      final state = VoiceScoringState();
      computeVoiceScore([0.9, 0.08, 0.02], state); // quiet
      final spike = computeVoiceScore([0.05, 0.1, 0.85], state); // one spike
      final after = computeVoiceScore([0.9, 0.08, 0.02], state); // quiet again

      expect(spike.classification, 'Normal');
      expect(after.classification, 'Normal');
      expect(after.score, lessThan(10));
    });

    test('duration boost applies after 6+ consecutive elevated windows', () {
      final state = VoiceScoringState();
      VoiceAnalysisResult? last;
      for (var i = 0; i < 20; i++) {
        last = computeVoiceScore([0.0, 1.0, 0.0], state);
        if (state.consecutiveElevatedCount >= 6) break;
      }
      expect(state.consecutiveElevatedCount, greaterThanOrEqualTo(6));
      expect(last!.score, greaterThan(40));
    });

    test('score never exceeds 100', () {
      final state = VoiceScoringState();
      VoiceAnalysisResult? last;
      for (var i = 0; i < 20; i++) {
        last = computeVoiceScore([0.0, 0.0, 1.0], state);
      }
      expect(last!.score, lessThanOrEqualTo(100.0));
    });
  });
}
