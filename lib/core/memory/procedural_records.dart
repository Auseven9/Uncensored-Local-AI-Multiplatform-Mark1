/// Procedural memory — the fourth memory tier (the "how").
///
/// Working / episodic / semantic memory (all live) answer *what is happening*,
/// *what happened*, and *what is true*. Procedural memory answers *how to do
/// things*: the agent's skills, workflows, tool definitions, reusable snippets
/// and standing heuristics. It is the store the multi-step agent loop reads from
/// to decide which action to take, and the store it writes back to when it
/// learns a procedure that works.
///
/// Like a claim, a procedure carries adaptive-memory metadata (salience that
/// rises with use, a confidence/trust level) so the set self-curates toward the
/// procedures that actually earn their keep — invention drives, use decides.
///
/// This file is a pure data model (no I/O). The store (SQLite v7) persists it;
/// later agentic phases consume it.
library;

/// What kind of "how" this is.
enum ProcedureKind {
  /// A learned multi-step capability ("summarise my day").
  skill,

  /// A fixed ordered recipe of steps.
  workflow,

  /// A single callable tool / function the agent can invoke via the Command Bus.
  tool,

  /// A reusable fragment (a prompt, a query, a code snippet).
  snippet,

  /// A standing rule of thumb ("when the user is terse, keep replies short").
  heuristic,
}

ProcedureKind procedureKindFromName(String? s) {
  switch ((s ?? '').toLowerCase().trim()) {
    case 'workflow':
      return ProcedureKind.workflow;
    case 'tool':
      return ProcedureKind.tool;
    case 'snippet':
      return ProcedureKind.snippet;
    case 'heuristic':
      return ProcedureKind.heuristic;
    case 'skill':
    default:
      return ProcedureKind.skill;
  }
}

/// Whether the agent may currently use this procedure.
enum ProcedureStatus { active, disabled }

ProcedureStatus procedureStatusFromName(String? s) =>
    (s ?? '').toLowerCase().trim() == 'disabled'
        ? ProcedureStatus.disabled
        : ProcedureStatus.active;

/// One stored procedure.
class ProcedureRecord {
  final int? id;
  final DateTime createdUtc;

  /// A short stable identifier the agent refers to it by ("get_time").
  final String name;
  final ProcedureKind kind;

  /// WHEN to reach for it — a natural-language cue or trigger pattern.
  final String trigger;

  /// HOW — the definition: steps, a snippet, or a tool's contract.
  final String body;

  /// JSON schema of the procedure's arguments, or '' when it takes none.
  final String paramsJson;

  final ProcedureStatus status;

  /// Retrieval strength — reinforced each time the procedure is used, decays
  /// while unused (same two-strength model as claims, Phase 3).
  final double salience;

  /// How much the agent trusts this procedure to do what it says.
  final double confidence;

  final int usageCount;
  final DateTime? lastUsedUtc;

  const ProcedureRecord({
    this.id,
    required this.createdUtc,
    required this.name,
    this.kind = ProcedureKind.skill,
    this.trigger = '',
    this.body = '',
    this.paramsJson = '',
    this.status = ProcedureStatus.active,
    this.salience = 0.5,
    this.confidence = 0.5,
    this.usageCount = 0,
    this.lastUsedUtc,
  });

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'created_utc': createdUtc.toUtc().toIso8601String(),
        'name': name,
        'kind': kind.name,
        'trigger': trigger,
        'body': body,
        'params_json': paramsJson,
        'status': status.name,
        'salience': salience,
        'confidence': confidence,
        'usage_count': usageCount,
        'last_used_utc': lastUsedUtc?.toUtc().toIso8601String(),
      };

  factory ProcedureRecord.fromRow(Map<String, Object?> row) {
    DateTime parse(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final last = row['last_used_utc'];
    return ProcedureRecord(
      id: (row['id'] as num?)?.toInt(),
      createdUtc: parse(row['created_utc']),
      name: row['name']?.toString() ?? '',
      kind: procedureKindFromName(row['kind']?.toString()),
      trigger: row['trigger']?.toString() ?? '',
      body: row['body']?.toString() ?? '',
      paramsJson: row['params_json']?.toString() ?? '',
      status: procedureStatusFromName(row['status']?.toString()),
      salience: (row['salience'] as num?)?.toDouble() ?? 0.5,
      confidence: (row['confidence'] as num?)?.toDouble() ?? 0.5,
      usageCount: (row['usage_count'] as num?)?.toInt() ?? 0,
      lastUsedUtc:
          (last == null || last.toString().isEmpty) ? null : parse(last),
    );
  }

  ProcedureRecord copyWith({
    int? id,
    DateTime? createdUtc,
    String? name,
    ProcedureKind? kind,
    String? trigger,
    String? body,
    String? paramsJson,
    ProcedureStatus? status,
    double? salience,
    double? confidence,
    int? usageCount,
    DateTime? lastUsedUtc,
  }) =>
      ProcedureRecord(
        id: id ?? this.id,
        createdUtc: createdUtc ?? this.createdUtc,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        trigger: trigger ?? this.trigger,
        body: body ?? this.body,
        paramsJson: paramsJson ?? this.paramsJson,
        status: status ?? this.status,
        salience: salience ?? this.salience,
        confidence: confidence ?? this.confidence,
        usageCount: usageCount ?? this.usageCount,
        lastUsedUtc: lastUsedUtc ?? this.lastUsedUtc,
      );
}
