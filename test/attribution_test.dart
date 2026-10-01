import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/cognition/attribution.dart';
import 'package:portable_ai_flutter/core/memory/memory_records.dart';

void main() {
  group('thirdPersonizeUserText — deterministic 3rd-person enforcement', () {
    test('rewrites first-person possessive (the "my girlfriend" leak)', () {
      expect(thirdPersonizeUserText('My girlfriend is Jayden'),
          "The user's girlfriend is Jayden");
      expect(thirdPersonizeUserText('her name is my favorite'),
          "her name is the user's favorite");
    });

    test('keeps a name while removing the leak', () {
      // The identity-safety point: "Jayden" survives, "my girlfriend" does not.
      final out = thirdPersonizeUserText("My girlfriend's name is Jayden");
      expect(out.contains('Jayden'), isTrue);
      expect(out.toLowerCase().contains('my girlfriend'), isFalse);
    });

    test('handles me / mine / myself', () {
      expect(thirdPersonizeUserText('give it to me'), 'give it to the user');
      expect(thirdPersonizeUserText('that book is mine'),
          "that book is the user's");
      expect(thirdPersonizeUserText('I hurt myself'), 'I hurt the user');
    });

    test('leaves already-third-person text untouched', () {
      expect(thirdPersonizeUserText('The user has a dog named Buster'),
          'The user has a dog named Buster');
    });

    test('does not touch subject "I" (+verb) — left to the curator prompt', () {
      expect(
          thirdPersonizeUserText('I work as a nurse'), 'I work as a nurse');
    });

    test('does not mangle substrings (time, user)', () {
      expect(thirdPersonizeUserText('the time is mine'), "the time is the user's");
    });
  });

  group('renderMemoryBlock — identity safety', () {
    test('empty input renders nothing', () {
      expect(renderMemoryBlock(const [], awareness: true), '');
      expect(
          renderMemoryBlock(
              const [MemoryLine('   ', subjectType: SubjectType.user)],
              awareness: true),
          '');
    });

    test('THE bug: a legacy second-person user fact never lands under an '
        '"about myself" heading', () {
      // This is exactly the Jayden case: a user-subject fact phrased in second
      // person. It must render under the user bucket, never the self bucket.
      final block = renderMemoryBlock(
        const [
          MemoryLine('you have a girlfriend named Jayden',
              subjectType: SubjectType.user, holder: ClaimHolder.user),
        ],
        awareness: true,
      );
      expect(block, contains('you have a girlfriend named Jayden'));
      expect(block, contains(kUserHeaderPrefix)); // under "About you (...)"
      expect(block, isNot(contains(kAiFromUserHeader)));
      expect(block, isNot(contains(kAiSelfViewHeader)));
      expect(block.toLowerCase(), contains('about myself'),
          reason: 'the binding instruction mentions the about-myself heading');
    });

    test('the user header pins "you" to the user with the label', () {
      final block = renderMemoryBlock(
        const [MemoryLine('likes tea', subjectType: SubjectType.user)],
        awareness: true,
        userLabel: 'Alex',
      );
      expect(block, contains('About you (Alex):'));
      expect(block, contains('"you" means Alex'));
    });

    test('the two self-perspectives are kept in separate buckets', () {
      final block = renderMemoryBlock(
        const [
          MemoryLine('you are blunt',
              subjectType: SubjectType.selfAI, holder: ClaimHolder.user),
          MemoryLine('I seem to explain better than I summarize',
              subjectType: SubjectType.selfAI, holder: ClaimHolder.assistant),
        ],
        awareness: true,
      );
      expect(block, contains(kAiFromUserHeader));
      expect(block, contains(kAiSelfViewHeader));
      // The user-view line precedes the self-view line (stable section order).
      expect(block.indexOf('you are blunt'),
          lessThan(block.indexOf('I seem to explain')));
    });

    test('third parties land in the people/things bucket, not about-you', () {
      final block = renderMemoryBlock(
        const [
          MemoryLine('Jayden is a nurse', subjectType: SubjectType.person),
        ],
        awareness: true,
      );
      expect(block, contains(kThirdPartyHeader));
      expect(block, contains('Jayden is a nurse'));
    });

    test('unknown-subject lines fall into the neutral "other" bucket', () {
      final block = renderMemoryBlock(
        const [MemoryLine('the meeting was moved', subjectType: SubjectType.unknown)],
        awareness: true,
      );
      expect(block, contains(kOtherHeader));
    });

    test('awareness off drops the capability framing but keeps the "you" '
        'binding and the buckets', () {
      final block = renderMemoryBlock(
        const [MemoryLine('you have a dog', subjectType: SubjectType.user)],
        awareness: false,
        userLabel: 'Alex',
      );
      expect(block, isNot(contains('Treat it as true')));
      expect(block, contains('"you" = Alex'));
      expect(block, contains('About you (Alex):'));
    });

    test('a mixed set routes every subject to its own bucket', () {
      final block = renderMemoryBlock(
        const [
          MemoryLine('you have a girlfriend named Jayden',
              subjectType: SubjectType.user),
          MemoryLine('Jayden is a nurse', subjectType: SubjectType.person),
          MemoryLine('you find me helpful',
              subjectType: SubjectType.selfAI, holder: ClaimHolder.user),
          MemoryLine('I notice I ask a lot of questions',
              subjectType: SubjectType.selfAI, holder: ClaimHolder.assistant),
        ],
        awareness: true,
      );
      expect(block, contains('About you ('));
      expect(block, contains(kThirdPartyHeader));
      expect(block, contains(kAiFromUserHeader));
      expect(block, contains(kAiSelfViewHeader));
    });
  });
}
