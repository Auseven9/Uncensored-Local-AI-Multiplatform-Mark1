import 'dart:math' as math;

import 'memory_records.dart' show SubjectType, ClaimHolder;

/// Which memory tier a recall candidate came from.
enum RecallSource { working, episodic, semantic }

/// One candidate memory to (maybe) inject, from any tier, before scoring.
class RecallCandidate {
  final RecallSource source;
  final String text;

  /// Raw match strength, 0..1 (graph activation for semantic, keyword overlap
  /// for episodic, 1.0 for the live working set).
  final double relevance;

  /// Importance prior, 0..1 (claim salience; a flat default for raw turns).
  final double salience;

  /// When the underlying memory was created — drives the recency term.
  final DateTime timestamp;

  /// Normalised text, used to dedupe the same content across tiers.
  final String dedupeKey;

  /// True when this (semantic) claim was a direct meaning match — its id was in
  /// the embedding nearest-neighbour seed set for the cue. Lets the UI show
  /// whether embeddings actually contributed, vs keyword/graph seeding.
  final bool viaEmbedding;

  /// The backing semantic claim's id, when this candidate came from the
  /// semantic tier. Null for episodic/working candidates. Lets the recall path
  /// reinforce exactly the claims it actually injected (Phase 3).
  final int? factId;

  /// Who/what this candidate is about, and whose view it is (Phase 5) — drives
  /// identity-safe rendering so a user-fact can't re-bind to the AI. Semantic
  /// candidates carry the claim's values; raw episodic snippets stay [unknown].
  final SubjectType subjectType;
  final ClaimHolder holder;

  /// Final blended score, filled in by [fuseAndRank].
  double score = 0.0;

  RecallCandidate({
    required this.source,
    required this.text,
    required this.relevance,
    required this.salience,
    required this.timestamp,
    required this.dedupeKey,
    this.viaEmbedding = false,
    this.factId,
    this.subjectType = SubjectType.user,
    this.holder = ClaimHolder.user,
  });
}

/// The outcome of one recall pass, surfaced to the UI as "recalled-memory
/// chips" so the memory is visible before the (slow) model speaks.
class RecallResult {
  /// The items actually injected into context, already ranked and budget-capped.
  final List<RecallCandidate> injected;

  /// Whether an embedding model contributed meaning-based seeds this turn.
  final bool embeddingsActive;

  /// How many claims currently have an embedding in the meaning index. 0 while
  /// [embeddingsActive] is true means nothing has been indexed yet (so meaning
  /// recall can't match anything, no matter the cue).
  final int embeddingIndexed;

  /// The best cosine similarity the cue scored against any indexed claim this
  /// turn, threshold aside. Null when embeddings were off or the index empty.
  /// Exactly 0.0 with a non-empty index signals a dimension mismatch; a low
  /// positive value means the seed threshold is simply higher than reality.
  final double? embeddingTop;

  /// The cue that drove this recall (short, for display/debug).
  final String cue;

  const RecallResult({
    required this.injected,
    required this.embeddingsActive,
    this.embeddingIndexed = 0,
    this.embeddingTop,
    this.cue = '',
  });

  /// How many of the injected candidates were meaning (embedding) matches.
  int get meaningMatches => injected.where((c) => c.viaEmbedding).length;

  bool get isEmpty => injected.isEmpty;
}

/// Normalise text into a dedupe key (lowercase, collapse whitespace).
String normalizeForDedupe(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Fuse recall candidates from every tier into a single ranked, budget-capped
/// list — the core of the associative recall engine.
///
/// Steps: dedupe by [RecallCandidate.dedupeKey] (keep the strongest match),
/// score each by a blend of `relevance`, `salience` and an exponential
/// `recency` term, sort descending, then greedily admit candidates until the
/// character [charBudget] is spent (so injection never blows the tiny context
/// window). Pure and deterministic — no I/O.
List<RecallCandidate> fuseAndRank(
  List<RecallCandidate> candidates, {
  required DateTime now,
  double wRelevance = 0.6,
  double wSalience = 0.25,
  double wRecency = 0.15,
  double recencyHalfLifeHours = 72.0,
  int charBudget = 600,
}) {
  // Dedupe: keep the candidate with the strongest raw relevance per key.
  final byKey = <String, RecallCandidate>{};
  for (final c in candidates) {
    if (c.text.trim().isEmpty) continue;
    final existing = byKey[c.dedupeKey];
    if (existing == null || c.relevance > existing.relevance) {
      byKey[c.dedupeKey] = c;
    }
  }

  final items = byKey.values.toList();
  final halfLife = recencyHalfLifeHours <= 0 ? 1.0 : recencyHalfLifeHours;
  for (final c in items) {
    final ageHours =
        math.max(0.0, now.difference(c.timestamp).inMinutes / 60.0);
    final recency = math.exp(-ageHours / halfLife);
    c.score = wRelevance * c.relevance.clamp(0.0, 1.0) +
        wSalience * c.salience.clamp(0.0, 1.0) +
        wRecency * recency;
  }

  items.sort((a, b) => b.score.compareTo(a.score));

  // Greedy budget cap by character count ("- " prefix + newline ≈ 3 chars).
  final out = <RecallCandidate>[];
  var used = 0;
  for (final c in items) {
    final cost = c.text.length + 3;
    if (out.isNotEmpty && used + cost > charBudget) break;
    out.add(c);
    used += cost;
  }
  return out;
}
