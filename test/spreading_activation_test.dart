import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/memory/memory_records.dart';
import 'package:portable_ai_flutter/core/memory/spreading_activation.dart';

RelationEdge _edge(int from, int to, {double weight = 1.0}) =>
    RelationEdge(fromFact: from, toFact: to, weight: weight);

void main() {
  group('spreadActivation', () {
    test('a seed with no edges keeps only itself', () {
      final r = spreadActivation(seeds: {1: 1.0}, edges: []);
      expect(r.scores.keys.toSet(), {1});
      expect(r.scores[1], 1.0);
    });

    test('activation flows one hop with alpha decay', () {
      final r = spreadActivation(
        seeds: {1: 1.0},
        edges: [_edge(1, 2)],
        alpha: 0.85,
        threshold: 0.15,
        maxHops: 2,
      );
      expect(r.scores[1], 1.0);
      expect(r.scores[2], closeTo(0.85, 1e-9));
    });

    test('edges are bidirectional for recall', () {
      // Seed the TARGET of the directed edge; recall should still reach source.
      final r = spreadActivation(seeds: {2: 1.0}, edges: [_edge(1, 2)]);
      expect(r.scores.containsKey(1), isTrue);
      expect(r.scores[1], closeTo(0.85, 1e-9));
    });

    test('decays over two hops and stops at maxHops', () {
      // 1-2-3-4 chain; from seed 1 with hop cap 2, reaches 2 and 3 but not 4.
      final r = spreadActivation(
        seeds: {1: 1.0},
        edges: [_edge(1, 2), _edge(2, 3), _edge(3, 4)],
        alpha: 0.85,
        threshold: 0.05,
        maxHops: 2,
      );
      expect(r.scores[2], closeTo(0.85, 1e-9));
      expect(r.scores[3], closeTo(0.7225, 1e-9)); // 0.85^2
      expect(r.scores.containsKey(4), isFalse); // beyond maxHops
    });

    test('threshold prunes weak activation', () {
      final r = spreadActivation(
        seeds: {1: 1.0},
        edges: [_edge(1, 2, weight: 0.1)],
        alpha: 0.85,
        threshold: 0.15,
      );
      // 1.0 * 0.85 * 0.1 = 0.085 < 0.15 → neighbour 2 dropped.
      expect(r.scores.containsKey(2), isFalse);
      expect(r.scores[1], 1.0);
    });

    test('ranked() orders by descending activation', () {
      final r = spreadActivation(
        seeds: {1: 1.0},
        edges: [_edge(1, 2, weight: 1.0), _edge(1, 3, weight: 0.5)],
        alpha: 0.85,
        threshold: 0.1,
      );
      // 1:1.0, 2:0.85, 3:0.425
      expect(r.ranked(), [1, 2, 3]);
    });
  });
}
