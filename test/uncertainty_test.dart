import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/cognition/uncertainty.dart';

void main() {
  group('computeUScore', () {
    test('all-zero inputs → 0', () {
      expect(
          computeUScore(const UScoreInputs(), const UScoreWeights()), 0.0);
    });

    test('all-one inputs → 1 (weight-normalized)', () {
      final u = computeUScore(
        const UScoreInputs(
            prediction: 1, contradiction: 1, novelty: 1, ambiguity: 1, risk: 1),
        const UScoreWeights(),
      );
      expect(u, closeTo(1.0, 1e-9));
    });

    test('is the weight-normalized blend of the components', () {
      // Default weights: 0.25/0.20/0.15/0.15/0.25, sum = 1.00.
      // Only prediction = 1 → 0.25 / 1.00.
      final u = computeUScore(
        const UScoreInputs(prediction: 1.0),
        const UScoreWeights(),
      );
      expect(u, closeTo(0.25 / 1.0, 1e-9));
    });

    test('normalization makes weights that do not sum to 1 still valid', () {
      // Weights sum to 2.0 here; a single maxed component returns its share.
      final u = computeUScore(
        const UScoreInputs(novelty: 1.0),
        const UScoreWeights(
            prediction: 0.5,
            contradiction: 0.5,
            novelty: 0.5,
            ambiguity: 0.25,
            risk: 0.25),
      );
      expect(u, closeTo(0.5 / 2.0, 1e-9));
    });

    test('zero total weight degrades to 0 (always System 1)', () {
      final u = computeUScore(
        const UScoreInputs(prediction: 1, novelty: 1),
        const UScoreWeights(
            prediction: 0,
            contradiction: 0,
            novelty: 0,
            ambiguity: 0,
            risk: 0),
      );
      expect(u, 0.0);
    });

    test('component inputs are clamped before blending', () {
      final u = computeUScore(
        const UScoreInputs(prediction: 5.0), // out of range
        const UScoreWeights(),
      );
      expect(u, closeTo(0.25 / 1.0, 1e-9)); // treated as 1.0, not 5.0
    });
  });

  group('gateMode', () {
    test('System 2 at or above the threshold, System 1 below', () {
      expect(gateMode(0.64, 0.65), UMode.system1);
      expect(gateMode(0.65, 0.65), UMode.system2);
      expect(gateMode(0.90, 0.65), UMode.system2);
    });

    test('clamps its inputs', () {
      expect(gateMode(2.0, 0.65), UMode.system2);
      expect(gateMode(-1.0, 0.65), UMode.system1);
    });
  });

  group('scoreUncertainty', () {
    test('a calm, well-covered turn stays System 1', () {
      final s = scoreUncertainty(
        const UScoreInputs(
            prediction: 0.1, contradiction: 0.0, novelty: 0.1, ambiguity: 0.1),
        const UScoreWeights(),
        0.65,
      );
      expect(s.mode, UMode.system1);
      expect(s.value, lessThan(0.65));
    });

    test('an unfamiliar, surprising turn gates to System 2', () {
      final s = scoreUncertainty(
        const UScoreInputs(
            prediction: 0.9, novelty: 0.9, ambiguity: 0.8, risk: 0.7),
        const UScoreWeights(),
        0.65,
      );
      expect(s.mode, UMode.system2);
      expect(s.value, greaterThanOrEqualTo(0.65));
    });

    test('breakdown is a compact, readable line', () {
      final s = scoreUncertainty(
        const UScoreInputs(prediction: 0.6, novelty: 0.3),
        const UScoreWeights(),
        0.65,
      );
      expect(s.breakdown, contains('U='));
      expect(s.breakdown, contains('System'));
      expect(s.breakdown, contains('pred'));
    });
  });
}
