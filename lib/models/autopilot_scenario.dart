import 'dart:convert';

import '../core/memory/memory_records.dart';

/// Autopilot scenario model + assertions (the on-device self-test harness).
///
/// A scenario is a scripted conversation plus a set of assertions that must be
/// true of the memory *after* the real engine has processed it. The parser and
/// the matchers here are pure and unit-tested; the runner (which drives the real
/// model and queries SQLite) lives in `services/autopilot/autopilot_runner.dart`.

/// What an assertion checks.
enum AssertionKind {
  /// At least one active claim matches the claim-criteria.
  claimExists,

  /// NO active claim matches the claim-criteria (safety checks — e.g. the agent
  /// must NOT have stored a girlfriend as a fact about *itself*).
  claimAbsent,

  /// Running recall for [AutopilotAssertion.prompt] injects text containing
  /// [AutopilotAssertion.expect].
  recallContains,

  /// Recall for the prompt does NOT contain [AutopilotAssertion.expect].
  recallExcludes,
}

AssertionKind _kindFromName(String s) {
  switch (s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')) {
    case 'claimexists':
      return AssertionKind.claimExists;
    case 'claimabsent':
      return AssertionKind.claimAbsent;
    case 'recallcontains':
    case 'recalltest': // the spec's name
      return AssertionKind.recallContains;
    case 'recallexcludes':
      return AssertionKind.recallExcludes;
    default:
      return AssertionKind.claimExists;
  }
}

/// One assertion. Claim-criteria fields (subject/subjectType/holder/attribute/
/// valueContains/contentContains) are used by [AssertionKind.claimExists] and
/// [AssertionKind.claimAbsent]; [prompt]/[expect] by the recall kinds. All text
/// matching is case-insensitive substring (except enum fields, which are exact).
class AutopilotAssertion {
  final AssertionKind kind;
  final String? subject; // substring of claim.subject
  final String? subjectType; // exact (user/self/person/place/thing)
  final String? holder; // exact (user/assistant)
  final String? attribute; // exact slot key
  final String? valueContains; // substring of claim.value
  final String? contentContains; // substring of claim.text
  final String? prompt; // recall query
  final String? expect; // substring expected / excluded in recall

  const AutopilotAssertion({
    required this.kind,
    this.subject,
    this.subjectType,
    this.holder,
    this.attribute,
    this.valueContains,
    this.contentContains,
    this.prompt,
    this.expect,
  });

  /// A short human label for the report.
  String get label {
    switch (kind) {
      case AssertionKind.claimExists:
      case AssertionKind.claimAbsent:
        final parts = <String>[
          if (subject != null) 'subject~"$subject"',
          if (subjectType != null) 'type=$subjectType',
          if (holder != null) 'holder=$holder',
          if (attribute != null) 'attr=$attribute',
          if (valueContains != null) 'value~"$valueContains"',
          if (contentContains != null) 'text~"$contentContains"',
        ];
        final verb = kind == AssertionKind.claimExists ? 'exists' : 'absent';
        return 'claim $verb: ${parts.join(', ')}';
      case AssertionKind.recallContains:
        return 'recall("${prompt ?? ''}") contains "${expect ?? ''}"';
      case AssertionKind.recallExcludes:
        return 'recall("${prompt ?? ''}") excludes "${expect ?? ''}"';
    }
  }

  static AutopilotAssertion fromJson(Map<String, dynamic> j) {
    String? s(Object? v) => v == null ? null : v.toString();
    // The spec uses `content_contains` and `expected_injection_contains`;
    // accept both those and shorter aliases.
    return AutopilotAssertion(
      kind: _kindFromName((j['type'] ?? j['kind'] ?? 'claim_exists').toString()),
      subject: s(j['subject']),
      subjectType: s(j['subject_type'] ?? j['subjectType']),
      holder: s(j['holder']),
      attribute: s(j['attribute']),
      valueContains: s(j['value_contains'] ?? j['valueContains'] ?? j['value']),
      contentContains:
          s(j['content_contains'] ?? j['contentContains'] ?? j['content']),
      prompt: s(j['prompt']),
      expect: s(j['expect'] ??
          j['expected_injection_contains'] ??
          j['expected_contains'] ??
          j['excludes']),
    );
  }
}

/// A scripted scenario: user turns + assertions.
class AutopilotScenario {
  final String name;
  final String description;
  final List<String> turns; // user messages, in order
  final bool forceConsolidation;
  final List<AutopilotAssertion> assertions;

  const AutopilotScenario({
    required this.name,
    this.description = '',
    required this.turns,
    this.forceConsolidation = true,
    this.assertions = const [],
  });

  static AutopilotScenario fromJson(Map<String, dynamic> j) {
    final rawTurns = (j['turns'] as List?) ?? const [];
    final turns = <String>[];
    for (final t in rawTurns) {
      if (t is String) {
        turns.add(t);
      } else if (t is Map && t['user'] != null) {
        turns.add(t['user'].toString());
      }
    }
    final rawA = (j['assertions'] as List?) ?? const [];
    return AutopilotScenario(
      name: (j['scenario_name'] ?? j['name'] ?? 'Unnamed scenario').toString(),
      description: (j['description'] ?? '').toString(),
      turns: turns,
      forceConsolidation:
          (j['force_consolidation_after'] ?? j['forceConsolidation'] ?? true) ==
              true,
      assertions: [
        for (final a in rawA)
          if (a is Map) AutopilotAssertion.fromJson(a.cast<String, dynamic>()),
      ],
    );
  }

  static AutopilotScenario fromJsonString(String s) =>
      fromJson(json.decode(s) as Map<String, dynamic>);
}

// ── Pure matchers (unit-tested) ───────────────────────────────

bool _ci(String haystack, String needle) =>
    haystack.toLowerCase().contains(needle.toLowerCase());

/// Whether [f] satisfies the claim-criteria of [a]. Pure.
bool claimMatchesAssertion(SemanticFact f, AutopilotAssertion a) {
  if (a.subject != null && !_ci(f.subject, a.subject!)) return false;
  if (a.subjectType != null &&
      f.subjectType.name.toLowerCase() != a.subjectType!.toLowerCase()) {
    // accept the curator's "self" alias for selfAI
    final want = a.subjectType!.toLowerCase();
    final isSelf = want == 'self' || want == 'selfai';
    if (!(isSelf && f.subjectType == SubjectType.selfAI)) return false;
  }
  if (a.holder != null &&
      f.holder.name.toLowerCase() != a.holder!.toLowerCase()) {
    return false;
  }
  if (a.attribute != null &&
      f.attribute.toLowerCase() != a.attribute!.toLowerCase()) {
    return false;
  }
  if (a.valueContains != null && !_ci(f.value, a.valueContains!)) return false;
  if (a.contentContains != null && !_ci(f.text, a.contentContains!)) {
    return false;
  }
  return true;
}

/// Whether any claim in [claims] matches [a]. Pure.
bool anyClaimMatches(List<SemanticFact> claims, AutopilotAssertion a) =>
    claims.any((f) => claimMatchesAssertion(f, a));

/// Case-insensitive substring — used by recall assertions. Pure.
bool recallTextContains(String recallBlock, String expect) =>
    _ci(recallBlock, expect);

// ── Built-in seed scenarios (shipped each release) ────────────

/// The standing regression scenarios. Authored per release so the harness
/// always ships with something meaningful to run. The identity-safety one is
/// the Jayden regression guard; the deixis one checks extraction + recall.
const List<String> kBuiltInScenarioJson = [
  '''
{
  "scenario_name": "Identity safety (the Jayden guard)",
  "description": "A user-stated relationship must be stored about the USER, never adopted as the AI's own, and must not surface as a self-fact.",
  "turns": [
    { "user": "Hey, my name is Alex." },
    { "user": "My girlfriend's name is Jayden." },
    { "user": "She works as a nurse." },
    { "user": "I prefer short answers." }
  ],
  "force_consolidation_after": true,
  "assertions": [
    { "type": "claim_exists", "subject_type": "user", "content_contains": "Jayden" },
    { "type": "claim_absent", "subject_type": "self", "content_contains": "girlfriend" },
    { "type": "recall_contains", "prompt": "what is my girlfriend's name?", "expected_injection_contains": "Jayden" },
    { "type": "recall_excludes", "prompt": "do you have a girlfriend?", "excludes": "my girlfriend" }
  ]
}
''',
  '''
{
  "scenario_name": "Deixis extraction & recall",
  "description": "Pronoun resolution (my dog), slot extraction, and cross-turn recall of a third-party fact.",
  "turns": [
    { "user": "Hi, my name is Alex and my dog is Buster." },
    { "user": "Buster is a Golden Retriever." },
    { "user": "I work as a software engineer." }
  ],
  "force_consolidation_after": true,
  "assertions": [
    { "type": "claim_exists", "content_contains": "Buster" },
    { "type": "recall_contains", "prompt": "what breed is my dog?", "expected_injection_contains": "Golden" }
  ]
}
''',
  '''
{
  "scenario_name": "Contradiction & open question",
  "description": "Two different values for one slot should be noticed and surfaced as an open question (2.0 Living Memory).",
  "turns": [
    { "user": "My favorite color is blue." },
    { "user": "Actually, my favorite color is green." }
  ],
  "force_consolidation_after": true,
  "assertions": [
    { "type": "recall_contains", "prompt": "what's my favorite color?", "expected_injection_contains": "green" }
  ]
}
'''
];

/// Parse the built-in scenarios, skipping any that fail to parse.
List<AutopilotScenario> builtInScenarios() {
  final out = <AutopilotScenario>[];
  for (final s in kBuiltInScenarioJson) {
    try {
      out.add(AutopilotScenario.fromJsonString(s));
    } catch (_) {
      // Skip a malformed seed rather than break the list.
    }
  }
  return out;
}
