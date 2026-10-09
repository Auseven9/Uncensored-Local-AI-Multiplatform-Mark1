import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/cognition/belief.dart';

void main() {
  group('fuseSlotBeliefs — Dempster–Shafer (Phase 4b)', () {
    test('no evidence → insufficient', () {
      final o = fuseSlotBeliefs(const []);
      expect(o.top, isNull);
      expect(o.ignorance, 1.0);
      expect(decideSlot(o), BeliefVerdict.insufficient);
    });

    test('single claim → that value, leftover mass stays as ignorance', () {
      final o = fuseSlotBeliefs(const [SlotEvidence('Jayden', 0.8)]);
      expect(o.top, 'Jayden');
      expect(o.topBelief, closeTo(0.8, 1e-9));
      expect(o.ignorance, closeTo(0.2, 1e-9));
      expect(o.conflict, closeTo(0.0, 1e-9));
      expect(decideSlot(o), BeliefVerdict.resolve);
    });

    test('two claims agreeing REINFORCE the value', () {
      final o = fuseSlotBeliefs(
          const [SlotEvidence('blue', 0.6), SlotEvidence('blue', 0.6)]);
      expect(o.top, 'blue');
      // 0.6 ⊕ 0.6 (agree) = 0.84 — stronger than either alone.
      expect(o.topBelief, closeTo(0.84, 1e-6));
      expect(o.conflict, closeTo(0.0, 1e-9));
      expect(decideSlot(o), BeliefVerdict.resolve);
    });

    test('two equally-confident conflicting claims → high conflict → ask', () {
      final o = fuseSlotBeliefs(
          const [SlotEvidence('blue', 0.8), SlotEvidence('green', 0.8)]);
      expect(o.conflict, closeTo(0.64, 1e-6));
      expect(o.belief['blue'], closeTo(o.belief['green']!, 1e-6)); // tied
      expect(decideSlot(o), BeliefVerdict.ask);
    });

    test('asymmetric confidence → the stronger value wins (resolve)', () {
      final o = fuseSlotBeliefs(
          const [SlotEvidence('Jayden', 0.9), SlotEvidence('Jordan', 0.3)]);
      expect(o.top, 'Jayden');
      expect(o.topBelief, closeTo(0.863, 1e-3));
      expect(o.conflict, closeTo(0.27, 1e-6));
      expect(o.margin, greaterThan(0.2));
      expect(decideSlot(o), BeliefVerdict.resolve);
    });

    test('case-insensitive value matching (same candidate reinforces)', () {
      final o = fuseSlotBeliefs(
          const [SlotEvidence('Green', 0.6), SlotEvidence('green ', 0.6)]);
      expect(o.belief.length, 1); // one candidate, not two
      expect(o.topBelief, closeTo(0.84, 1e-6));
    });

    test('decideSlot thresholds gate a weak winner to ask', () {
      // A lone low-confidence claim: a value exists but belief is below the bar.
      final o = fuseSlotBeliefs(const [SlotEvidence('maybe', 0.3)]);
      expect(o.top, 'maybe');
      expect(decideSlot(o, minTopBelief: 0.5), BeliefVerdict.ask);
    });
  });
}
