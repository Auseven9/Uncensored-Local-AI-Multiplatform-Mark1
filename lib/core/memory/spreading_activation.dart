import 'memory_records.dart';

/// Result of a spreading-activation pass: claim id → final activation score.
class ActivationResult {
  final Map<int, double> scores;
  const ActivationResult(this.scores);

  /// Claim ids ordered by descending activation.
  List<int> ranked() {
    final ids = scores.keys.toList()
      ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return ids;
  }
}

/// Pure spreading-activation over an epistemic graph.
///
/// Starting from [seeds] (claim id → initial activation, typically 1.0 for a
/// keyword/embedding hit), activation flows outward along [edges]: each active
/// node passes `activation * alpha * edgeWeight` to its neighbours, for up to
/// [maxHops] hops. A node keeps the strongest activation it receives across
/// paths; anything staying below [threshold] is dropped.
///
/// Edges are walked bidirectionally for recall — an edge A→B lets a query that
/// hits A surface B and vice versa. Associative recall is symmetric even when
/// the asserted relation (supports/causes/…) has a direction.
ActivationResult spreadActivation({
  required Map<int, double> seeds,
  required List<RelationEdge> edges,
  double alpha = 0.85,
  double threshold = 0.15,
  int maxHops = 2,
}) {
  // Bidirectional adjacency: node -> [(neighbour, weight)].
  final adjacency = <int, List<MapEntry<int, double>>>{};
  void addAdj(int from, int to, double w) {
    (adjacency[from] ??= <MapEntry<int, double>>[]).add(MapEntry(to, w));
  }

  for (final e in edges) {
    final w = e.weight.clamp(0.0, 1.0).toDouble();
    if (w <= 0) continue;
    addAdj(e.fromFact, e.toFact, w);
    addAdj(e.toFact, e.fromFact, w);
  }

  final scores = <int, double>{};
  // Frontier: nodes whose (improved) activation should propagate next hop.
  var frontier = <int, double>{};
  seeds.forEach((id, act) {
    final a = act.clamp(0.0, 1.0).toDouble();
    if (a > (scores[id] ?? 0.0)) scores[id] = a;
    frontier[id] = a;
  });

  for (var hop = 0; hop < maxHops && frontier.isNotEmpty; hop++) {
    final next = <int, double>{};
    frontier.forEach((node, act) {
      final neighbours = adjacency[node];
      if (neighbours == null) return;
      for (final entry in neighbours) {
        final propagated = act * alpha * entry.value;
        if (propagated < threshold) continue;
        if (propagated > (scores[entry.key] ?? 0.0)) {
          scores[entry.key] = propagated;
          if (propagated > (next[entry.key] ?? 0.0)) {
            next[entry.key] = propagated;
          }
        }
      }
    });
    frontier = next;
  }

  scores.removeWhere((_, v) => v < threshold);
  return ActivationResult(scores);
}
