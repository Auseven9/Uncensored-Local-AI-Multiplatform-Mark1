import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/models/autopilot_scenario.dart';
import 'package:portable_ai_flutter/core/memory/memory_records.dart';

SemanticFact _claim(
  String text, {
  String subject = 'the user',
  SubjectType subjectType = SubjectType.user,
  ClaimHolder holder = ClaimHolder.user,
  String attribute = '',
  String value = '',
}) =>
    SemanticFact(
      createdUtc: DateTime.utc(2026),
      category: SemanticCategory.fact,
      text: text,
      subject: subject,
      subjectType: subjectType,
      holder: holder,
      attribute: attribute,
      value: value,
    );

void main() {
  group('AutopilotScenario.fromJson', () {
    test('parses turns (both {user:...} and bare strings) + assertions', () {
      final s = AutopilotScenario.fromJsonString('''
      {
        "scenario_name": "T",
        "turns": [ { "user": "hi" }, "second" ],
        "force_consolidation_after": true,
        "assertions": [
          { "type": "claim_exists", "subject": "Alex", "content_contains": "dog" },
          { "type": "recall_test", "prompt": "breed?", "expected_injection_contains": "Golden" }
        ]
      }
      ''');
      expect(s.name, 'T');
      expect(s.turns, ['hi', 'second']);
      expect(s.forceConsolidation, isTrue);
      expect(s.assertions, hasLength(2));
      expect(s.assertions[0].kind, AssertionKind.claimExists);
      expect(s.assertions[0].contentContains, 'dog');
      // "recall_test" (the spec's name) maps to recallContains.
      expect(s.assertions[1].kind, AssertionKind.recallContains);
      expect(s.assertions[1].expect, 'Golden');
    });
  });

  group('claimMatchesAssertion', () {
    test('matches on content substring, case-insensitive', () {
      final f = _claim('The user has a dog named Buster');
      expect(
          claimMatchesAssertion(
              f, const AutopilotAssertion(kind: AssertionKind.claimExists, contentContains: 'buster')),
          isTrue);
      expect(
          claimMatchesAssertion(
              f, const AutopilotAssertion(kind: AssertionKind.claimExists, contentContains: 'cat')),
          isFalse);
    });

    test('subjectType "self" alias matches selfAI claims', () {
      final f = _claim('I seem to ask a lot of questions',
          subject: 'myself',
          subjectType: SubjectType.selfAI,
          holder: ClaimHolder.assistant);
      expect(
          claimMatchesAssertion(
              f, const AutopilotAssertion(kind: AssertionKind.claimExists, subjectType: 'self')),
          isTrue);
    });

    test('a user-subject claim does NOT match a self-subject assertion', () {
      // The identity-safety guard: a user fact must not count as a self fact.
      final f = _claim('The user has a girlfriend named Jayden',
          subjectType: SubjectType.user);
      expect(
          claimMatchesAssertion(
              f,
              const AutopilotAssertion(
                  kind: AssertionKind.claimAbsent,
                  subjectType: 'self',
                  contentContains: 'girlfriend')),
          isFalse);
    });

    test('matches slot + value', () {
      final f = _claim('partner is Jayden',
          attribute: 'partner_name', value: 'Jayden');
      expect(
          claimMatchesAssertion(
              f,
              const AutopilotAssertion(
                  kind: AssertionKind.claimExists,
                  attribute: 'partner_name',
                  valueContains: 'jayden')),
          isTrue);
    });
  });

  group('anyClaimMatches / recallTextContains', () {
    test('anyClaimMatches scans the set', () {
      final claims = [
        _claim('likes tea'),
        _claim('The user has a dog named Buster'),
      ];
      expect(
          anyClaimMatches(claims,
              const AutopilotAssertion(kind: AssertionKind.claimExists, contentContains: 'Buster')),
          isTrue);
    });

    test('recallTextContains is case-insensitive', () {
      expect(recallTextContains('About you: - has a Golden Retriever', 'golden'),
          isTrue);
      expect(recallTextContains('About you: - likes tea', 'golden'), isFalse);
    });
  });

  group('builtInScenarios', () {
    test('ship and parse, including the Jayden guard', () {
      final list = builtInScenarios();
      expect(list, isNotEmpty);
      expect(list.any((s) => s.name.toLowerCase().contains('jayden')), isTrue);
      final jayden =
          list.firstWhere((s) => s.name.toLowerCase().contains('jayden'));
      // It carries the self-absence safety assertion.
      expect(
          jayden.assertions.any((a) => a.kind == AssertionKind.claimAbsent),
          isTrue);
    });
  });
}
