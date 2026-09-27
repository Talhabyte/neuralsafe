import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';

class TextAnalysisResult {
  final double score; // 0-100
  final String predictedClass;
  final List<double> probabilities;

  TextAnalysisResult({
    required this.score,
    required this.predictedClass,
    required this.probabilities,
  });

  @override
  String toString() =>
      'TextAnalysisResult(score: $score, class: $predictedClass, probs: $probabilities)';
}

// Starter keyword lists (English + Urdu). Pragmatic placeholder set —
// expand later with domain-specific terms if time allows.
const List<String> kHighRiskWords = [
  'kill',
  'murder',
  'gun',
  'knife',
  'weapon',
  'die',
  'dead',
  'stab',
  'strangle',
  'suicide',
  'rape',
  'مار',
  'قتل',
  'خودکشی',
  'بندوق',
  'چھری',
];

const List<String> kModerateRiskWords = [
  'hit',
  'hurt',
  'scream',
  'afraid',
  'scared',
  'threat',
  'threaten',
  'help',
  'danger',
  'abuse',
  'beat',
  'hostage',
  'trapped',
  'ڈر',
  'خوف',
  'مدد',
  'دھمکی',
];

double _maxWordScore(String text) {
  final lower = text.toLowerCase();
  final words = lower.split(RegExp(r'\s+'));
  double maxScore = 0;
  for (final w in words) {
    final cleaned = w.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    if (cleaned.isEmpty) continue;
    if (kHighRiskWords.any((h) => cleaned.contains(h.toLowerCase()))) {
      if (95 > maxScore) maxScore = 95;
    } else if (kModerateRiskWords
        .any((m) => cleaned.contains(m.toLowerCase()))) {
      if (70 > maxScore) maxScore = 70;
    }
  }
  return maxScore;
}

/// Pure, unit-testable scoring function per FYP Chapter 4.5.2 pseudocode.
TextAnalysisResult computeTextScore(
    String originalText, List<double> classProbs) {
  assert(classProbs.length == 4);
  final pNormal = classProbs[0];
  final pDistress = classProbs[1];
  final pViolence = classProbs[2];
  final pHelp = classProbs[3];

  const classNames = ['Normal', 'Distress', 'Violence', 'Help'];
  var maxIdx = 0;
  var maxP = classProbs[0];
  for (var i = 1; i < classProbs.length; i++) {
    if (classProbs[i] > maxP) {
      maxP = classProbs[i];
      maxIdx = i;
    }
  }
  final predictedClass = classNames[maxIdx];

  final maxWordScore = _maxWordScore(originalText);

  double textScore;
  if (maxWordScore > 80) {
    textScore = 95;
  } else {
    double baseScore;
    switch (predictedClass) {
      case 'Violence':
        baseScore = 80 + pViolence * 20;
        break;
      case 'Distress':
        baseScore = 50 + pDistress * 30;
        break;
      case 'Help':
        baseScore = 40 + pHelp * 40;
        break;
      default:
        baseScore = pNormal * 20;
    }

    if (pViolence > 0.8 || pDistress > 0.75 || pHelp > 0.75) {
      textScore = baseScore;
    } else {
      final maxRiskProb =
          [pViolence, pDistress, pHelp].reduce((a, b) => a > b ? a : b);
      textScore = baseScore * (maxRiskProb / 0.8);
    }
  }

  final finalScore = [maxWordScore, textScore].reduce((a, b) => a > b ? a : b);
  final capped = finalScore > 100 ? 100.0 : finalScore;

  return TextAnalysisResult(
    score: capped,
    predictedClass: predictedClass,
    probabilities: classProbs,
  );
}

class TextAnalysisService {
  TextAnalysisService._();
  static final TextAnalysisService instance = TextAnalysisService._();

  SentencePieceTokenizer? _tokenizer;
  Interpreter? _interpreter;
  bool _initialized = false;

  static const int _maxLen = 128;
  static const int _padId = 1;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    final bytes = await rootBundle.load('assets/ml/sentencepiece.bpe.model');
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/sentencepiece.bpe.model');
    await file.writeAsBytes(bytes.buffer.asUint8List());

    _tokenizer = SentencePieceTokenizer.fromModelFileSync(file.path);
    _interpreter =
        await Interpreter.fromAsset('assets/ml/neuralsafe_text_model.tflite');
    _initialized = true;
  }

  int _toXlmrId(int rawId) {
    if (rawId == 0) return 3; // <unk>
    if (rawId == 1) return 0; // <s>
    if (rawId == 2) return 2; // </s>
    return rawId + 1;
  }

  Future<TextAnalysisResult> analyze(String text) async {
    if (!_initialized) {
      await init();
    }

    final rawIds = _tokenizer!.encode(text).ids;
    final contentIds = rawIds.map(_toXlmrId).toList();
    var fullIds = [0, ...contentIds, 2];

    if (fullIds.length > _maxLen) {
      fullIds = fullIds.sublist(0, _maxLen - 1) + [2];
    }

    final attentionMask = List<int>.filled(_maxLen, 0);
    final inputIds = List<int>.filled(_maxLen, _padId);
    for (var i = 0; i < fullIds.length; i++) {
      inputIds[i] = fullIds[i];
      attentionMask[i] = 1;
    }

    final output = List.filled(1 * 4, 0.0).reshape([1, 4]);
    _interpreter!.runForMultipleInputs(
      [
        [attentionMask],
        [inputIds],
      ],
      {0: output},
    );

    final probs = (output[0] as List).map((e) => e as double).toList();
    return computeTextScore(text, probs);
  }
}
