import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/memory/vector_search.dart';

void main() {
  group('cosineSimilarity', () {
    test('identical vectors are 1.0', () {
      expect(cosineSimilarity([1, 2, 3], [1, 2, 3]), closeTo(1.0, 1e-9));
    });

    test('orthogonal vectors are 0.0', () {
      expect(cosineSimilarity([1, 0], [0, 1]), closeTo(0.0, 1e-9));
    });

    test('opposite vectors are -1.0', () {
      expect(cosineSimilarity([1, 2], [-1, -2]), closeTo(-1.0, 1e-9));
    });

    test('scale-invariant (magnitude does not matter)', () {
      expect(cosineSimilarity([2, 0], [9, 0]), closeTo(1.0, 1e-9));
    });

    test('zero vector yields 0, not NaN', () {
      expect(cosineSimilarity([0, 0, 0], [1, 2, 3]), 0.0);
    });

    test('length mismatch yields 0 rather than throwing', () {
      expect(cosineSimilarity([1, 2, 3], [1, 2]), 0.0);
    });
  });

  group('nearestByCosine', () {
    final corpus = {
      1: <double>[1, 0, 0],
      2: <double>[0.9, 0.1, 0],
      3: <double>[0, 1, 0],
      4: <double>[0, 0, 1],
    };

    test('ranks by similarity, strongest first', () {
      final r = nearestByCosine(query: [1, 0, 0], corpus: corpus, k: 2);
      expect(r.map((e) => e.id).toList(), [1, 2]);
      expect(r.first.score, closeTo(1.0, 1e-9));
    });

    test('respects k', () {
      final r = nearestByCosine(query: [1, 0, 0], corpus: corpus, k: 1);
      expect(r.length, 1);
      expect(r.first.id, 1);
    });

    test('threshold prunes weak matches', () {
      final r =
          nearestByCosine(query: [1, 0, 0], corpus: corpus, k: 10, threshold: 0.5);
      // Only ids 1 and 2 point roughly along x; 3 and 4 are orthogonal (0.0).
      expect(r.map((e) => e.id).toSet(), {1, 2});
    });

    test('empty corpus yields empty result', () {
      final r = nearestByCosine(query: [1, 0], corpus: const {});
      expect(r, isEmpty);
    });

    test('ties break by id ascending (deterministic)', () {
      final tied = {
        5: <double>[1, 0],
        2: <double>[1, 0],
        9: <double>[1, 0],
      };
      final r = nearestByCosine(query: [1, 0], corpus: tied, k: 3);
      expect(r.map((e) => e.id).toList(), [2, 5, 9]);
    });
  });

  group('encode/decode round-trip', () {
    test('preserves values within Float32 precision', () {
      final v = [0.0, 1.0, -1.0, 0.5, 3.14159, -2.71828];
      final bytes = encodeVectorF32(v);
      expect(bytes, isA<Uint8List>());
      expect(bytes.length, v.length * 4);
      final back = decodeVectorF32(bytes);
      expect(back.length, v.length);
      for (var i = 0; i < v.length; i++) {
        expect(back[i], closeTo(v[i], 1e-5));
      }
    });

    test('empty vector round-trips to empty', () {
      final bytes = encodeVectorF32(const []);
      expect(bytes, isEmpty);
      expect(decodeVectorF32(bytes), isEmpty);
    });
  });
}
