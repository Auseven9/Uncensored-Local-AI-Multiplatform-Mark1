import 'dart:math' as math;
import 'dart:typed_data';

/// Pure vector-search utilities for embedding-based recall (Phase 2b).
///
/// Brute-force cosine similarity is used deliberately: at this app's scale
/// (hundreds to low-thousands of claims) an exact linear scan in Dart is
/// simpler, dependency-free, and fast enough (a few milliseconds), and it
/// avoids shipping an ANN index onto the device. If the claim count ever
/// outgrows that, [nearestByCosine] is the single seam to swap for an
/// approximate index — callers depend only on it.
///
/// Everything here is pure (no I/O, no plugins) so it runs and unit-tests
/// identically on device, desktop, and web.

/// Dot product of two equal-length vectors. Returns 0 for a length mismatch
/// rather than throwing, so a stale or differently-sized embedding can never
/// crash recall — it simply contributes nothing.
double dotProduct(List<double> a, List<double> b) {
  if (a.length != b.length) return 0.0;
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// L2 norm (magnitude) of a vector.
double l2Norm(List<double> v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  return math.sqrt(sum);
}

/// Cosine similarity in [-1, 1]. Returns 0 when either vector is all-zero or
/// the lengths differ (an undefined comparison contributes nothing instead of
/// producing NaN).
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0.0;
  final na = l2Norm(a);
  final nb = l2Norm(b);
  if (na == 0.0 || nb == 0.0) return 0.0;
  return (dotProduct(a, b) / (na * nb)).clamp(-1.0, 1.0).toDouble();
}

/// The [k] corpus entries most similar to [query] by cosine, strongest first,
/// keeping only those at or above [threshold]. Deterministic: ties break by id
/// ascending so results are stable across runs.
List<({int id, double score})> nearestByCosine({
  required List<double> query,
  required Map<int, List<double>> corpus,
  int k = 10,
  double threshold = 0.0,
}) {
  final scored = <({int id, double score})>[];
  for (final entry in corpus.entries) {
    final s = cosineSimilarity(query, entry.value);
    if (s >= threshold) scored.add((id: entry.key, score: s));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.id.compareTo(b.id);
  });
  return scored.take(k <= 0 ? 0 : k).toList();
}

/// Pack a vector into little-endian Float32 bytes for compact BLOB storage.
/// Float32 halves the storage of Float64 and is well within an embedding's
/// meaningful precision.
Uint8List encodeVectorF32(List<double> v) {
  final f32 = Float32List(v.length);
  for (var i = 0; i < v.length; i++) {
    f32[i] = v[i];
  }
  return f32.buffer.asUint8List();
}

/// Read a Float32 BLOB (as written by [encodeVectorF32]) back into doubles.
/// Copies first so the result is safe regardless of the source buffer's
/// alignment or offset.
List<double> decodeVectorF32(Uint8List bytes) {
  final copy = Uint8List.fromList(bytes);
  final f32 = copy.buffer.asFloat32List(0, copy.length ~/ 4);
  return List<double>.from(f32);
}
