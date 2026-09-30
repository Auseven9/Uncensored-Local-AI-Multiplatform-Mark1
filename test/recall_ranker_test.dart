import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/memory/recall_ranker.dart';

RecallCandidate _c({
  RecallSource source = RecallSource.semantic,
  required String text,
  double relevance = 0.5,
  double salience = 0.5,
  DateTime? at,
}) =>
    RecallCandidate(
      source: source,
      text: text,
      relevance: relevance,
      salience: salience,
      timestamp: at ?? DateTime.now(),
      dedupeKey: normalizeForDedupe(text),
    );

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);

  test('dedupes same content across tiers, keeping strongest relevance', () {
    final r = fuseAndRank([
      _c(text: 'The user is Dylon', relevance: 0.4, at: now),
      _c(
          text: 'the user is  Dylon', // normalises to the same key
          relevance: 0.9,
          source: RecallSource.episodic,
          at: now),
    ], now: now);
    expect(r.length, 1);
    expect(r.first.relevance, 0.9);
  });

  test('recency boosts a newer candidate when relevance and salience tie', () {
    final fresh = _c(text: 'fresh', at: now.subtract(const Duration(hours: 1)));
    final stale =
        _c(text: 'stale', at: now.subtract(const Duration(hours: 200)));
    final r = fuseAndRank([stale, fresh], now: now, recencyHalfLifeHours: 72);
    expect(r.first.text, 'fresh');
  });

  test('salience breaks ties toward the more important claim', () {
    final r = fuseAndRank([
      _c(text: 'low', salience: 0.1, at: now),
      _c(text: 'high', salience: 0.9, at: now),
    ], now: now);
    expect(r.first.text, 'high');
  });

  test('character budget caps how many are injected', () {
    final items = List.generate(
        20,
        (i) => _c(
            text: 'memory item number $i padded out a bit',
            relevance: 1.0 - i * 0.01,
            at: now));
    final r = fuseAndRank(items, now: now, charBudget: 120);
    expect(r.length, lessThan(20));
    expect(r, isNotEmpty);
  });

  test('results are sorted by descending score', () {
    final r = fuseAndRank([
      _c(text: 'a', relevance: 0.2, at: now),
      _c(text: 'b', relevance: 0.9, at: now),
      _c(text: 'c', relevance: 0.5, at: now),
    ], now: now);
    for (var i = 1; i < r.length; i++) {
      expect(r[i - 1].score >= r[i].score, isTrue);
    }
    expect(r.first.text, 'b');
  });
}
