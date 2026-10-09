import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/cognition/reconciliation.dart';
import 'package:portable_ai_flutter/core/memory/memory_records.dart';

SemanticFact _claim(
  String text, {
  int? id,
  String subject = 'the user',
  String attribute = '',
  String value = '',
  ClaimStatus status = ClaimStatus.active,
}) =>
    SemanticFact(
      id: id,
      createdUtc: DateTime.utc(2026),
      category: SemanticCategory.fact,
      text: text,
      subject: subject,
      attribute: attribute,
      value: value,
      status: status,
    );

void main() {
  group('findSlotCollisions', () {
    test('THE case: two different values on one slot is a collision', () {
      final collisions = findSlotCollisions([
        _claim('The user\'s partner is named Jayden',
            id: 1, attribute: 'partner_name', value: 'Jayden'),
        _claim('The user\'s partner is named Jordan',
            id: 2, attribute: 'partner_name', value: 'Jordan'),
      ]);
      expect(collisions, hasLength(1));
      expect(collisions.first.attribute, 'partner_name');
    });

    test('same VALUE in different phrasings is NOT a collision', () {
      final collisions = findSlotCollisions([
        _claim('partner is Jayden',
            id: 1, attribute: 'partner_name', value: 'Jayden'),
        _claim("the user's partner's name is Jayden",
            id: 2, attribute: 'partner_name', value: 'Jayden'),
      ]);
      expect(collisions, isEmpty); // the whole point of the value field
    });

    test('falls back to text when value is absent (still case-insensitive)', () {
      final collisions = findSlotCollisions([
        _claim('partner named Jayden', id: 1, attribute: 'partner_name'),
        _claim('Partner Named Jayden', id: 2, attribute: 'partner_name'),
      ]);
      expect(collisions, isEmpty);
    });

    test('different attributes do not collide', () {
      final collisions = findSlotCollisions([
        _claim('nurse', id: 1, attribute: 'job', value: 'nurse'),
        _claim('Denver', id: 2, attribute: 'city', value: 'Denver'),
      ]);
      expect(collisions, isEmpty);
    });

    test('claims without an attribute are skipped', () {
      final collisions = findSlotCollisions([
        _claim('likes long walks', id: 1),
        _claim('hates long walks', id: 2),
      ]);
      expect(collisions, isEmpty);
    });

    test('superseded claims are excluded', () {
      final collisions = findSlotCollisions([
        _claim('Jordan',
            id: 1,
            attribute: 'partner_name',
            value: 'Jordan',
            status: ClaimStatus.superseded),
        _claim('Jayden', id: 2, attribute: 'partner_name', value: 'Jayden'),
      ]);
      expect(collisions, isEmpty);
    });

    test('same attribute on different subjects does not collide', () {
      final collisions = findSlotCollisions([
        _claim('nurse', id: 1, subject: 'Jayden', attribute: 'job', value: 'nurse'),
        _claim('teacher',
            id: 2, subject: 'the user', attribute: 'job', value: 'teacher'),
      ]);
      expect(collisions, isEmpty);
    });
  });

  group('hasCorrectionCue (narrow by design)', () {
    test('detects clear corrections', () {
      expect(hasCorrectionCue("no, her name is Jaylen"), isTrue);
      expect(hasCorrectionCue("actually it's Jordan"), isTrue);
      expect(hasCorrectionCue("I meant my sister"), isTrue);
      expect(hasCorrectionCue("that's wrong"), isTrue);
      expect(hasCorrectionCue("scratch that"), isTrue);
    });

    test('does NOT fire on ordinary speech (the false-positive guard)', () {
      expect(hasCorrectionCue("I changed jobs last year"), isFalse);
      expect(hasCorrectionCue("I'd rather use SQLite"), isFalse);
      expect(hasCorrectionCue("that's not important"), isFalse);
      expect(hasCorrectionCue("my partner is named Jayden"), isFalse);
    });
  });

  group('correctionTargets (ties a correction to the slot)', () {
    test('a cued turn that names the new value targets it', () {
      expect(correctionTargets("no, her name is Jaylen", "Jaylen"), isTrue);
    });

    test('an UNRELATED correction elsewhere in the batch does not target', () {
      // The #1 bug: a batch-global cue must not supersede an unrelated slot.
      expect(
          correctionTargets("no, let's not talk about that", "Jordan"), isFalse);
    });

    test('no cue means no targeting even if the value is mentioned', () {
      expect(correctionTargets("my partner is Jayden", "Jayden"), isFalse);
    });
  });

  group('chooseReconcileAction', () {
    test('a correction supersedes; otherwise ask', () {
      expect(chooseReconcileAction(correction: true),
          ReconcileAction.supersedeOld);
      expect(chooseReconcileAction(correction: false), ReconcileAction.askUser);
    });
  });

  group('buildQuestion', () {
    test('names the slot and the conflicting values and asks which is right', () {
      final c = SlotCollision('the user', 'partner_name', [
        _claim('partner is Jayden', attribute: 'partner_name', value: 'Jayden'),
        _claim('partner is Jordan', attribute: 'partner_name', value: 'Jordan'),
      ]);
      final q = buildQuestion(c);
      expect(q, contains('the user'));
      expect(q, contains('partner_name'));
      expect(q, contains('Jayden'));
      expect(q, contains('Jordan'));
      expect(q.toLowerCase(), contains('which is right'));
    });
  });
}
