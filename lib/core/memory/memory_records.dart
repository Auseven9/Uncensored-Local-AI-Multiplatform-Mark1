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

/// What a claim is *about* — its subject. The crucial distinction is
/// [selfAI] vs [user]: it's what stops the agent from adopting the user's life
/// as its own ("you have a girlfriend named Jayden" → the *user* does, not the
/// AI). [person]/[place]/[thing] are third parties the user mentioned (Jayden,
/// a city, a car); [unknown] is the honest fallback when it can't be resolved.
enum SubjectType { selfAI, user, person, place, thing, unknown }

SubjectType subjectTypeFromName(String name) => SubjectType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SubjectType.user,
    );

/// Whose *view* a claim represents. The same subject can be held from two
/// perspectives — e.g. about the AI: what the [user] asserts about it ("you're
/// blunt") vs. what the AI itself has come to think ([assistant], "I seem to
/// explain better than I summarize"). Lets the agent hold a user-view and a
/// formulated self-view without the two colliding.
enum ClaimHolder { user, assistant }

ClaimHolder claimHolderFromName(String name) => ClaimHolder.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ClaimHolder.user,
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

  // ── Identity / attribution (Phase 5) ──────────────────────────
  /// Who/what this claim is about, as a short canonical label ("the user",
  /// "Jayden", "myself"). Display/dedupe aid; [subjectType] carries the role.
  final String subject;

  /// The subject's role — the self-vs-other distinction that keeps the agent
  /// from adopting the user's facts as its own. Defaults to [SubjectType.user]
  /// because the overwhelming majority of stored facts are about the user, and
  /// that default also reframes legacy rows safely.
  final SubjectType subjectType;

  /// Whose view this claim is: the user's assertion, or the AI's own formulated
  /// view. Defaults to [ClaimHolder.user] (the user told us).
  final ClaimHolder holder;

  /// A short *slot key* for what aspect of [subject] this claim pins down —
  /// e.g. "partner_name", "job", "birthday" (Phase 5b / 2.0). Empty when the
  /// claim isn't a single-slot fact. Two active claims sharing (subject,
  /// attribute) but asserting different [value]s are a contradiction the agent
  /// can detect, surface, and resolve.
  final String attribute;

  /// The bare value this claim asserts for its (subject, attribute) slot —
  /// e.g. "Jayden", "nurse", "Denver" (2.0). Lets contradiction detection
  /// compare *values* rather than whole-sentence phrasings (so "partner is
  /// Jayden" and "partner's name is Jayden" aren't a false conflict). Empty
  /// when [attribute] is empty; falls back to [text] when the curator omits it.
  final String value;

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
    this.subject = '',
    this.subjectType = SubjectType.user,
    this.holder = ClaimHolder.user,
    this.attribute = '',
    this.value = '',
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
        'subject': subject,
        'subject_type': subjectType.name,
        'holder': holder.name,
        'attribute': attribute,
        'value': value,
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
      subject: (row['subject'] as String?) ?? '',
      subjectType: subjectTypeFromName((row['subject_type'] as String?) ?? 'user'),
      holder: claimHolderFromName((row['holder'] as String?) ?? 'user'),
      attribute: (row['attribute'] as String?) ?? '',
      value: (row['value'] as String?) ?? '',
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
    String? subject,
    SubjectType? subjectType,
    ClaimHolder? holder,
    String? attribute,
    String? value,
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
      subject: subject ?? this.subject,
      subjectType: subjectType ?? this.subjectType,
      holder: holder ?? this.holder,
      attribute: attribute ?? this.attribute,
      value: value ?? this.value,
    );
  }
}

/// Lifecycle of an [OpenQuestion].
enum OpenQuestionStatus { open, resolved }

OpenQuestionStatus openQuestionStatusFromName(String name) =>
    OpenQuestionStatus.values.firstWhere((e) => e.name == name,
        orElse: () => OpenQuestionStatus.open);

/// An unresolved contradiction the agent has noticed in its own memory (2.0):
/// two or more active claims that pin the same (subject, attribute) slot to
/// different values. Surfaced to the user as a clarifying question, and
/// resolved by a correction (which supersedes the losing claim).
class OpenQuestion {
  final int? id;
  final String subject;
  final String attribute;

  /// The conflicting claim ids this question is about.
  final List<int> claimIds;

  /// A ready-to-inject, human-readable question ("Is the user's partner named
  /// Jayden or Jordan?").
  final String question;

  final OpenQuestionStatus status;
  final DateTime createdUtc;
  final DateTime? resolvedUtc;

  OpenQuestion({
    this.id,
    required this.subject,
    required this.attribute,
    required this.claimIds,
    required this.question,
    this.status = OpenQuestionStatus.open,
    DateTime? createdUtc,
    this.resolvedUtc,
  }) : createdUtc = createdUtc ?? DateTime.now().toUtc();

  Map<String, Object?> toRow() => {
        'subject': subject,
        'attribute': attribute,
        'claim_ids_json': json.encode(claimIds),
        'question': question,
        'status': status.name,
        'created_utc': createdUtc.toUtc().toIso8601String(),
        'resolved_utc': resolvedUtc?.toUtc().toIso8601String(),
      };

  static OpenQuestion fromRow(Map<String, Object?> row) {
    final idsRaw = row['claim_ids_json'] as String?;
    final resolved = row['resolved_utc'] as String?;
    return OpenQuestion(
      id: row['id'] as int?,
      subject: (row['subject'] as String?) ?? '',
      attribute: (row['attribute'] as String?) ?? '',
      claimIds: idsRaw == null
          ? const []
          : (json.decode(idsRaw) as List).map((e) => (e as num).toInt()).toList(),
      question: (row['question'] as String?) ?? '',
      status: openQuestionStatusFromName((row['status'] as String?) ?? 'open'),
      createdUtc: DateTime.parse(row['created_utc'] as String).toUtc(),
      resolvedUtc: resolved == null ? null : DateTime.parse(resolved).toUtc(),
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
