import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/services/solver_service.dart';

void main() {
  group('SolverService.evaluate', () {
    test('records telemetry and computes exactly', () {
      final s = SolverService();
      final r = s.evaluate('(+ 2 3)');
      expect(r.ok, true);
      expect(r.value!.render(), '5');
      expect(s.lastResult.value, isNotNull);
      expect(s.recent.length, 1);
    });

    test('injected clock makes (now) deterministic', () {
      final s = SolverService();
      final r = s.evaluate('(year (now))', now: DateTime.utc(2026, 1, 1));
      expect(r.ok, true);
      expect(r.value!.render(), '2026');
    });
  });

  group('SolverService.applyInline', () {
    test('substitutes an inline solve tag with the exact result', () {
      final s = SolverService();
      final out = s.applyInline(
          'You have fasted [[solve (hours-between (datetime "2026-10-05T20:00") '
          '(datetime "2026-10-06T12:00"))]] hours.');
      expect(out, 'You have fasted 16 hours.');
      expect(s.lastSubstitutions.value, 1);
    });

    test('handles several tags in one reply', () {
      final s = SolverService();
      final out = s.applyInline('[[solve (+ 1 1)]] and [[solve (* 2 3)]]');
      expect(out, '2 and 6');
      expect(s.lastSubstitutions.value, 2);
    });

    test('a bad term becomes a clear marker, never a crash', () {
      final s = SolverService();
      final out = s.applyInline('result: [[solve (/ 1 0)]]');
      expect(out, contains('unverified'));
      expect(s.lastSubstitutions.value, 1);
    });

    test('no tag → reply unchanged, zero substitutions', () {
      final s = SolverService();
      const text = 'Just a normal reply with no computation.';
      expect(s.applyInline(text), text);
      expect(s.lastSubstitutions.value, 0);
    });

    test('hasTag detects presence cheaply', () {
      final s = SolverService();
      expect(s.hasTag('x [[solve (+ 1 1)]] y'), true);
      expect(s.hasTag('no tags here'), false);
    });
  });
}
