import 'dart:convert';

/// What an [EpisodicEntry] captures. The episodic tier is a raw, chronological
/// log of everything the agent did — the "short-term memory" that the gate
/// later summarises and curates into the semantic tier.
enum EpisodicKind { turn, toolCall, toolResult, reflection, error }

/// Category of a durable [SemanticFact] in long-term memory.
enum SemanticCategory { fact, preference, rule, summary }

EpisodicKind episodicKindFromName(String name) => EpisodicKind.values.firstWhere(
      (e) => e.name == name,
      orElse: () => EpisodicKind.turn,
    );

SemanticCategory semanticCategoryFromName(String name) =>
    SemanticCategory.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SemanticCategory.fact,
    );

/// Lifecycle state of a claim (a [SemanticFact] viewed as an epistemic node).
enum ClaimStatus { active, superseded, ambiguous }

ClaimStatus claimStatusFromName(String name) => ClaimStatus.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ClaimStatus.active,
    );

/// The kind of relation a [RelationEdge] asserts between two claims.
enum RelationType { supports, contradicts, causes, partOf, related }

RelationType relationTypeFromName(String name) =>
    RelationType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => RelationType.related,
    );

/// One millisecond-timestamped row of the episodic ledger.
class EpisodicEntry {
  final int? id;
  final String sessionId;
  final DateTime timestampUtc;
  final int sequence;
  final EpisodicKind kind;
  final String role;
  final String content;
  final Map<String, dynamic>? metadata;
  final bool consolidated;

  EpisodicEntry({
    this.id,
    required this.sessionId,
    required this.timestampUtc,
    required this.sequence,
    required this.kind,
    required this.role,
    required this.content,
    this.metadata,
    this.consolidated = false,
  });

  Map<String, Object?> toRow() => {
        'session_id': sessionId,
        'timestamp_utc': timestampUtc.toUtc().toIso8601String(),
        'timestamp_millis': timestampUtc.toUtc().millisecondsSinceEpoch,
        'sequence': sequence,
        'kind': kind.name,
        'role': role,
        'content': content,
        'metadata_json': metadata == null ? null : json.encode(metadata),
        'consolidated': consolidated ? 1 : 0,
      };

  static EpisodicEntry fromRow(Map<String, Object?> row) {
    final metaRaw = row['metadata_json'] as String?;
    return EpisodicEntry(
      id: row['id'] as int?,
      sessionId: row['session_id'] as String,
      timestampUtc:
          DateTime.parse(row['timestamp_utc'] as String).toUtc(),
      sequence: (row['sequence'] as num).toInt(),
      kind: episodicKindFromName(row['kind'] as String),
      role: row['role'] as String,
      content: row['content'] as String,
      metadata: metaRaw == null
          ? null
          : (json.decode(metaRaw) as Map).cast<String, dynamic>(),
      consolidated: (row['consolidated'] as num?)?.toInt() == 1,
    );
  }
}

/// One durable fact/preference/rule in long-term (semantic) memory.
class SemanticFact {
  final int? id;
  final DateTime createdUtc;
  final SemanticCategory category;
  final String text;
  final String? sourceSessionId;
  final double confidence;
  final String dedupeHash;

  /// Optional embedding vector. Null until the embedding helper model is wired
  /// in (Phase 2b). Retrieval falls back to keyword/graph recall when absent.
  final List<double>? embedding;

  // ── Epistemic-graph fields (Phase 2): a fact is a claim node. ──
  /// Current activation/importance of this claim (0..1). Spreading-activation
  /// recall reads it as a prior and can reinforce it over time.
  final double salience;

  /// Lifecycle state: active, superseded by a newer claim, or ambiguous
  /// (in an unresolved contradiction).
  final ClaimStatus status;

  /// If this claim supersedes an older one, that claim's id.
  final int? supersedes;

  SemanticFact({
    this.id,
    required this.createdUtc,
    required this.category,
    required this.text,
    this.sourceSessionId,
    this.confidence = 0.5,
    String? dedupeHash,
    this.embedding,
    this.salience = 0.5,
    this.status = ClaimStatus.active,
    this.supersedes,
  }) : dedupeHash = dedupeHash ?? stableContentHash(text);

  Map<String, Object?> toRow() => {
        'created_utc': createdUtc.toUtc().toIso8601String(),
        'category': category.name,
        'text': text,
        'source_session_id': sourceSessionId,
        'confidence': confidence,
        'dedupe_hash': dedupeHash,
        'embedding_json': embedding == null ? null : json.encode(embedding),
        'salience': salience,
        'status': status.name,
        'supersedes': supersedes,
      };

  static SemanticFact fromRow(Map<String, Object?> row) {
    final embRaw = row['embedding_json'] as String?;
    return SemanticFact(
      id: row['id'] as int?,
      createdUtc: DateTime.parse(row['created_utc'] as String).toUtc(),
      category: semanticCategoryFromName(row['category'] as String),
      text: row['text'] as String,
      sourceSessionId: row['source_session_id'] as String?,
      confidence: (row['confidence'] as num?)?.toDouble() ?? 0.5,
      dedupeHash: row['dedupe_hash'] as String,
      embedding: embRaw == null
          ? null
          : (json.decode(embRaw) as List)
              .map((e) => (e as num).toDouble())
              .toList(),
      salience: (row['salience'] as num?)?.toDouble() ?? 0.5,
      status: claimStatusFromName((row['status'] as String?) ?? 'active'),
      supersedes: (row['supersedes'] as num?)?.toInt(),
    );
  }

  /// A copy with selected fields replaced (used when the in-memory store needs
  /// to assign an id or mutate claim fields without losing the others).
  SemanticFact copyWith({
    int? id,
    SemanticCategory? category,
    String? text,
    double? confidence,
    double? salience,
    ClaimStatus? status,
    int? supersedes,
    List<double>? embedding,
  }) {
    final newText = text ?? this.text;
    return SemanticFact(
      id: id ?? this.id,
      createdUtc: createdUtc,
      category: category ?? this.category,
      text: newText,
      sourceSessionId: sourceSessionId,
      confidence: confidence ?? this.confidence,
      dedupeHash: text == null ? dedupeHash : stableContentHash(newText),
      embedding: embedding ?? this.embedding,
      salience: salience ?? this.salience,
      status: status ?? this.status,
      supersedes: supersedes ?? this.supersedes,
    );
  }
}

/// One directed edge in the epistemic graph: [fromFact] --(type)--> [toFact].
/// Spreading-activation recall walks these edges to pull in related claims.
class RelationEdge {
  final int? id;
  final int fromFact;
  final int toFact;
  final RelationType type;
  final double weight;
  final DateTime createdUtc;

  RelationEdge({
    this.id,
    required this.fromFact,
    required this.toFact,
    this.type = RelationType.related,
    this.weight = 1.0,
    DateTime? createdUtc,
  }) : createdUtc = createdUtc ?? DateTime.now().toUtc();

  Map<String, Object?> toRow() => {
        'from_fact': fromFact,
        'to_fact': toFact,
        'type': type.name,
        'weight': weight,
        'created_utc': createdUtc.toUtc().toIso8601String(),
      };

  static RelationEdge fromRow(Map<String, Object?> row) => RelationEdge(
        id: row['id'] as int?,
        fromFact: (row['from_fact'] as num).toInt(),
        toFact: (row['to_fact'] as num).toInt(),
        type: relationTypeFromName(row['type'] as String),
        weight: (row['weight'] as num?)?.toDouble() ?? 1.0,
        createdUtc: DateTime.parse(row['created_utc'] as String).toUtc(),
      );
}

/// Deterministic content hash used to deduplicate semantic facts (the primary
/// guard against "database poisoning" by repeated near-identical writes).
///
/// Normalises case and whitespace, then folds two 32-bit FNV-1a hashes with
/// different offsets into a 16-hex-char string. The 32-bit width keeps the
/// arithmetic exact on the web (JS number) runtime as well as native; the hash
/// only needs to be stable *within a device's* local database.
String stableContentHash(String text) {
  final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final a = _fnv1a32(normalized, 0x811c9dc5);
  final b = _fnv1a32(normalized, 0x01000193);
  return a.toRadixString(16).padLeft(8, '0') +
      b.toRadixString(16).padLeft(8, '0');
}

int _fnv1a32(String s, int offset) {
  const prime = 0x01000193;
  var hash = offset & 0xFFFFFFFF;
  for (final unit in s.codeUnits) {
    hash = (hash ^ unit) & 0xFFFFFFFF;
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  return hash & 0xFFFFFFFF;
}
