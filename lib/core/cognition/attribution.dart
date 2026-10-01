/// Identity-safe memory rendering (Phase 5).
///
/// The bug this exists to kill: a user's statement ("my girlfriend is Jayden")
/// gets stored as a bare second-person sentence ("you have a girlfriend named
/// Jayden") and then injected under a single "Your memory" header — so the "you"
/// re-binds to the *reader*, which is the AI, and the agent concludes it has a
/// girlfriend. The sentence never carried who it was about.
///
/// The fix is structural: every claim knows its [SubjectType] (self vs user vs
/// third party) and its [ClaimHolder] (the user's view vs the AI's own), and the
/// memory block is rendered into clearly-labeled buckets where the subject can
/// never silently re-bind:
///   • facts about the user go under a header that *pins* "you" to the user,
///   • facts about the AI appear only under explicit "about myself" headings,
///   • the two self-perspectives (what the user says about the AI vs what the
///     AI has come to think of itself) are kept apart.
///
/// Pure and deterministic — no I/O — so the safety property (a user-fact is
/// never placed under an "about myself" heading) is unit-testable in isolation.
library;

import '../memory/memory_records.dart';

/// One line of recalled memory, tagged with just enough to place it safely.
class MemoryLine {
  final String text;
  final SubjectType subjectType;
  final ClaimHolder holder;
  const MemoryLine(
    this.text, {
    this.subjectType = SubjectType.user,
    this.holder = ClaimHolder.user,
  });
}

/// Section headers — single source of truth so the renderer and its tests agree.
const String kUserHeaderPrefix = 'About you';
const String kAiFromUserHeader = 'What you have told me about myself:';
const String kAiSelfViewHeader = 'What I have come to think about myself:';
const String kThirdPartyHeader = 'People and things you have mentioned:';
const String kOtherHeader = 'Other remembered details:';
const String kOpenQuestionsHeader =
    'Things I have conflicting notes on — ask to clarify rather than guess:';

/// Render [lines] into an identity-safe memory block.
///
/// [awareness] adds the capability framing ("this is your memory, treat it as
/// true") — gated so the blank-identity mode can omit it; the structural bucket
/// separation (which carries the safety) applies either way. [userLabel] is how
/// the user is named to the model; it's embedded in the user header's
/// parenthetical so "you" is pinned even without the framing sentence.
String renderMemoryBlock(
  List<MemoryLine> lines, {
  required bool awareness,
  String userLabel = 'the person you are talking with',
  List<String> openQuestions = const [],
}) {
  final aboutUser = <String>[];
  final aiFromUser = <String>[]; // subject=AI, holder=user
  final aiSelfView = <String>[]; // subject=AI, holder=assistant
  final thirdParty = <String>[];
  final other = <String>[];

  for (final l in lines) {
    final t = l.text.trim();
    if (t.isEmpty) continue;
    switch (l.subjectType) {
      case SubjectType.selfAI:
        if (l.holder == ClaimHolder.assistant) {
          aiSelfView.add(t);
        } else {
          aiFromUser.add(t);
        }
        break;
      case SubjectType.user:
        aboutUser.add(t);
        break;
      case SubjectType.person:
      case SubjectType.place:
      case SubjectType.thing:
        thirdParty.add(t);
        break;
      case SubjectType.unknown:
        other.add(t);
        break;
    }
  }

  final questions = [
    for (final q in openQuestions)
      if (q.trim().isNotEmpty) q.trim()
  ];

  if (aboutUser.isEmpty &&
      aiFromUser.isEmpty &&
      aiSelfView.isEmpty &&
      thirdParty.isEmpty &&
      other.isEmpty &&
      questions.isEmpty) {
    return '';
  }

  final buf = StringBuffer();
  if (awareness) {
    buf
      ..writeln(
          'Your long-term memory from past conversations. Treat it as true; if '
          'something is not here, say you do not recall it rather than guess. In '
          'these notes "you" means $userLabel — never yourself; anything about '
          'yourself appears only under an "about myself" heading below.')
      ..writeln();
  } else {
    buf
      ..writeln('Relevant memory ("you" = $userLabel, not yourself):')
      ..writeln();
  }

  void section(String header, List<String> items) {
    if (items.isEmpty) return;
    buf.writeln(header);
    for (final it in items) {
      buf.writeln('- $it');
    }
    buf.writeln();
  }

  section('$kUserHeaderPrefix ($userLabel):', aboutUser);
  section(kThirdPartyHeader, thirdParty);
  section(kAiFromUserHeader, aiFromUser);
  section(kAiSelfViewHeader, aiSelfView);
  section(kOtherHeader, other);
  // Noticed contradictions the agent should raise rather than guess past (2.0).
  section(kOpenQuestionsHeader, questions);

  return buf.toString().trim();
}

// ── Deterministic third-person enforcement (v2.0.2) ───────────

/// Rewrite the user's first-person deixis in a claim the USER asserted into the
/// third person, so a stored claim can never read as the AI's own
/// ("my girlfriend" → "the user's girlfriend").
///
/// Phase 5a gave every claim a `subjectType`/`holder`, but relied on the
/// curator model to WRITE third-person `text`. A small local model does not do
/// that reliably: it sometimes leaves the user's "my"/"me" in a `holder=user`
/// claim, which re-introduces — at the claim-text tier — the exact second-person
/// leak 5a set out to kill. The identity-safety invariant must not depend on a
/// 4B following instructions, so callers enforce it here for user-asserted
/// claims. NEVER apply this to the assistant's own self-view (`holder=assistant`),
/// where "I"/"my" correctly means the AI.
///
/// Only grammatically-safe possessive/object pronouns are rewritten; a leading
/// subject "I" (+ verb) is left to the curator prompt, since rewriting it would
/// need verb agreement this pure pass can't do. Capitalization of a
/// sentence-initial match is preserved.
String thirdPersonizeUserText(String s) {
  if (s.isEmpty) return s;
  // Longest forms first so "myself" isn't partially touched by "my".
  const pairs = <List<String>>[
    ['myself', 'the user'],
    ['mine', "the user's"],
    ['my', "the user's"],
    ['me', 'the user'],
  ];
  var out = s;
  for (final p in pairs) {
    final re = RegExp('\\b${p[0]}\\b', caseSensitive: false);
    out = out.replaceAllMapped(re, (m) {
      final matched = m[0]!;
      final startsUpper = matched[0] == matched[0].toUpperCase() &&
          matched[0] != matched[0].toLowerCase();
      return startsUpper ? _capitalizeFirst(p[1]) : p[1];
    });
  }
  return out;
}

String _capitalizeFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
