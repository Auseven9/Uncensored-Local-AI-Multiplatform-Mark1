import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/memory/memory_dynamics.dart';

void main() {
  group('permanenceFloor', () {
    test('beta=0 means nothing is permanent (floor 0)', () {
      expect(permanenceFloor(1.0, 0.0), 0.0);
      expect(permanenceFloor(0.5, 0.0), 0.0);
    });

    test('default beta=1 keeps ~10% of confidence', () {
      expect(permanenceFloor(1.0, 1.0), closeTo(0.10, 1e-9));
      expect(permanenceFloor(0.5, 1.0), closeTo(0.05, 1e-9));
    });

    test('scales with beta and confidence, clamped to 1', () {
      expect(permanenceFloor(1.0, 5.0), closeTo(0.5, 1e-9));
      // beta high enough that a fully-confident claim never decays at all.
      expect(permanenceFloor(1.0, 10.0), closeTo(1.0, 1e-9));
      // Clamp: no overshoot past 1.0 even past the documented knob max.
      expect(permanenceFloor(1.0, 20.0), 1.0);
    });

    test('confidence is clamped before scaling', () {
      expect(permanenceFloor(2.0, 1.0), closeTo(0.10, 1e-9));
      expect(permanenceFloor(-1.0, 1.0), 0.0);
    });
  });

  group('decayedSalience', () {
    test('relaxes toward the floor by e^-1 after exactly tau cycles', () {
      // s=1, floor=0, tau=100, elapsed=100 → 1 * e^-1 ≈ 0.3679.
      final s = decayedSalience(1.0, cyclesElapsed: 100, tau: 100, floor: 0.0);
      expect(s, closeTo(math.exp(-1), 1e-9));
    });

    test('never drops below the floor', () {
      final s = decayedSalience(0.9,
          cyclesElapsed: 100000, tau: 10, floor: 0.3);
      expect(s, closeTo(0.3, 1e-6));
      expect(s, greaterThanOrEqualTo(0.3));
    });

    test('a claim already at/under the floor is unchanged', () {
      expect(decayedSalience(0.2, cyclesElapsed: 50, tau: 100, floor: 0.3),
          0.2);
      expect(decayedSalience(0.3, cyclesElapsed: 50, tau: 100, floor: 0.3),
          0.3);
    });

    test('no-op for non-positive elapsed or tau', () {
      expect(decayedSalience(0.7, cyclesElapsed: 0, tau: 100, floor: 0.0), 0.7);
      expect(decayedSalience(0.7, cyclesElapsed: 50, tau: 0, floor: 0.0), 0.7);
      expect(
          decayedSalience(0.7, cyclesElapsed: -5, tau: 100, floor: 0.0), 0.7);
    });

    test('monotonically decreasing in elapsed, bounded below by floor', () {
      var prev = 1.0;
      for (final e in [10, 50, 100, 500, 5000]) {
        final s = decayedSalience(1.0,
            cyclesElapsed: e.toDouble(), tau: 100, floor: 0.1);
        expect(s, lessThanOrEqualTo(prev));
        expect(s, greaterThanOrEqualTo(0.1 - 1e-9));
        prev = s;
      }
    });
  });

  group('reinforcedSalience', () {
    test('alpha=0 is a no-op (recall does not strengthen)', () {
      expect(reinforcedSalience(0.5, 0.0), 0.5);
    });

    test('default alpha=2 closes ~8% of the gap to 1.0', () {
      // 0.5 + (2*0.04)*(1-0.5) = 0.5 + 0.08*0.5 = 0.54
      expect(reinforcedSalience(0.5, 2.0), closeTo(0.54, 1e-9));
    });

    test('diminishing returns: saturates just under 1.0, never overshoots', () {
      var s = 0.5;
      for (var i = 0; i < 500; i++) {
        s = reinforcedSalience(s, 2.0);
      }
      expect(s, lessThanOrEqualTo(1.0));
      expect(s, greaterThan(0.99));
    });

    test('each application is strictly increasing below 1.0', () {
      final a = reinforcedSalience(0.3, 2.0);
      final b = reinforcedSalience(a, 2.0);
      expect(a, greaterThan(0.3));
      expect(b, greaterThan(a));
    });

    test('input is clamped', () {
      expect(reinforcedSalience(-0.5, 2.0), greaterThanOrEqualTo(0.0));
      expect(reinforcedSalience(1.5, 2.0), 1.0);
    });
  });

  group('reinforcedConfidence', () {
    test('alpha=0 is a no-op', () {
      expect(reinforcedConfidence(0.5, 0.0), 0.5);
    });

    test('accrues much more slowly than salience (quarter the rate)', () {
      final dConf = reinforcedConfidence(0.5, 2.0) - 0.5;
      final dSal = reinforcedSalience(0.5, 2.0) - 0.5;
      expect(dConf, greaterThan(0.0));
      expect(dConf, closeTo(dSal / 4.0, 1e-9));
    });

    test('sustained recall turns a mid claim into a core one', () {
      var c = 0.5;
      for (var i = 0; i < 100; i++) {
        c = reinforcedConfidence(c, 2.0);
      }
      expect(c, greaterThan(0.85));
      expect(c, lessThanOrEqualTo(1.0));
    });
  });

  group('integration: reinforce raises the floor it decays toward', () {
    test('a recalled claim resists forgetting more than an ignored one', () {
      // Two claims start identical.
      var usedSal = 0.6, usedConf = 0.5;
      var ignoredSal = 0.6;
      const ignoredConf = 0.5;

      // The "used" claim is recalled 20 times (reinforced), the other never.
      for (var i = 0; i < 20; i++) {
        usedSal = reinforcedSalience(usedSal, 2.0);
        usedConf = reinforcedConfidence(usedConf, 2.0);
      }

      // Then a long idle stretch decays both.
      final usedFloor = permanenceFloor(usedConf, 1.0);
      final ignoredFloor = permanenceFloor(ignoredConf, 1.0);
      usedSal = decayedSalience(usedSal,
          cyclesElapsed: 100000, tau: 100, floor: usedFloor);
      ignoredSal = decayedSalience(ignoredSal,
          cyclesElapsed: 100000, tau: 100, floor: ignoredFloor);

      // The used claim settled to a higher residual strength — it is "stickier".
      expect(usedFloor, greaterThan(ignoredFloor));
      expect(usedSal, greaterThan(ignoredSal));
    });
  });
}
