/// Active memory reconciliation (2.0 "Living Memory").
///
/// This is what turns a passive store into a mind that curates itself: it looks
/// at the claims the agent holds and notices when two of them pin the SAME
/// (subject, attribute) slot to DIFFERENT values — e.g. "the user's partner is
/// Jayden" and "the user's partner is Jordan". That's a contradiction the agent
/// should not silently keep; it should either accept it as a *correction* (when
/// the user just fixed an earlier statement) or *ask* which is right.
///
/// Everything here is pure and deterministic — contradiction detection belongs
/// in code, not in a stochastic 4B model that may or may not notice. The model
/// supplies the structure (subject/attribute on each claim); this decides.
library;

import '../memory/memory_records.dart';

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// The value a claim asserts for its slot — the bare [SemanticFact.value] when
/// the curator supplied it, else the full text. Comparing *values* (not whole
/// sentences) is what keeps paraphrases of the same fact from registering as a
/// contradiction ("partner is Jayden" vs "partner's name is Jayden").
String _valueOf(SemanticFact f) =>
    f.value.trim().isNotEmpty ? f.value.trim() : f.text.trim();

/// Content tokens (lowercased words >2 chars) — used to check whether a
/// correction turn actually refers to a given value.
Set<String> _contentTokens(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.length > 2)
    .toSet();

/// A group of active claims that pin one (subject, attribute) slot to different
/// values — a contradiction to surface.
class SlotCollision {
  final String subject;
  final String attribute;

  /// The conflicting claims (≥2, with ≥2 distinct values).
  final List<SemanticFact> claims;

  const SlotCollision(this.subject, this.attribute, this.claims);
}

/// Find all slot collisions among [claims]. A slot is a non-empty
/// (subject, attribute) pair; a collision is ≥2 *active* claims on one slot
/// whose normalized texts differ. Claims without both keys aren't slot facts
/// and are skipped. Pure.
List<SlotCollision> findSlotCollisions(List<SemanticFact> claims) {
  final bySlot = <String, List<SemanticFact>>{};
  for (final c in claims) {
    if (c.status != ClaimStatus.active) continue;
    final subj = _norm(c.subject);
    final attr = _norm(c.attribute);
    if (subj.isEmpty || attr.isEmpty) continue;
    (bySlot['$subj\u0000$attr'] ??= <SemanticFact>[]).add(c);
  }

  final out = <SlotCollision>[];
  bySlot.forEach((_, group) {
    // Distinct by VALUE, not whole-sentence text, so paraphrases of the same
    // value don't count as a conflict.
    final distinctValues = <String>{for (final c in group) _norm(_valueOf(c))};
    if (distinctValues.length >= 2) {
      out.add(SlotCollision(group.first.subject, group.first.attribute, group));
    }
  });
  return out;
}

/// Correction cues in a user utterance — phrases that clearly signal "I'm
/// fixing an earlier statement". Deliberately narrow: bare words like "wrong",
/// "changed", "rather", "instead" or "not" appear constantly in normal speech
/// ("I changed jobs", "I'd rather…") and must NOT be treated as corrections, or
/// a genuine ambiguity gets silently overwritten instead of asked about.
final RegExp _correctionCue = RegExp(
  r"(^|[\s.,!?])(actually|no,|no it'?s|not quite|i meant|i mean|"
  r"correction|scratch that|my mistake|my bad|that'?s wrong|that is wrong|"
  r"it'?s actually|should be|change that to|changed it to|i misspoke|typo)"
  r"([\s.,!?]|$)",
  caseSensitive: false,
);

/// Whether [text] carries a correction cue.
bool hasCorrectionCue(String text) => _correctionCue.hasMatch(text);

/// Whether [turnText] is a correction aimed specifically at [newValueOrText] —
/// it carries a correction cue AND mentions the new value. This ties a
/// correction to the slot it actually touches, so an unrelated "no, not that"
/// elsewhere in the batch can't trigger a wrong supersede on a correct fact.
bool correctionTargets(String turnText, String newValueOrText) {
  if (!hasCorrectionCue(turnText)) return false;
  final target = _contentTokens(newValueOrText);
  if (target.isEmpty) return false;
  final inTurn = _contentTokens(turnText);
  return target.any(inTurn.contains);
}

/// How to reconcile a newly-asserted value that collides with an existing one
/// on the same slot.
enum ReconcileAction { supersedeOld, askUser }

/// Decide. A correction supersedes the old value; otherwise the humble default
/// is to ASK the user rather than silently overwrite (some slots legitimately
/// hold multiple values, and a wrong overwrite loses truth).
ReconcileAction chooseReconcileAction({required bool correction}) =>
    correction ? ReconcileAction.supersedeOld : ReconcileAction.askUser;

/// Build the ready-to-inject clarifying question for a collision.
String buildQuestion(SlotCollision c) {
  final subj = c.subject.trim().isEmpty ? 'something' : c.subject.trim();
  final attr = c.attribute.trim();
  final values = c.claims
      .map(_valueOf)
      .map((v) => v.trim())
      .where((t) => t.isNotEmpty)
      .toSet() // de-dupe identical values
      .toList();
  final joined = values.join('  —or—  ');
  final slot = attr.isEmpty ? subj : '$subj ($attr)';
  return 'I have conflicting notes about $slot: $joined. Which is right?';
}
