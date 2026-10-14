import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/research/research_agent.dart';

void main() {
  group('clampTurns (the 1–100 selector)', () {
    test('clamps below, within, above', () {
      expect(ResearchAgent.clampTurns(0), 1);
      expect(ResearchAgent.clampTurns(-5), 1);
      expect(ResearchAgent.clampTurns(1), 1);
      expect(ResearchAgent.clampTurns(50), 50);
      expect(ResearchAgent.clampTurns(100), 100);
      expect(ResearchAgent.clampTurns(101), 100);
      expect(ResearchAgent.clampTurns(99999), 100);
    });
  });

  group('parseQuery (tolerant of tiny-model noise)', () {
    test('strips a label and quotes', () {
      expect(ResearchAgent.parseQuery('Query: "quantum computing basics"'),
          'quantum computing basics');
    });
    test('takes the first line and strips numbering', () {
      expect(ResearchAgent.parseQuery('1. best coffee in rome\n2. gelato'),
          'best coffee in rome');
    });
    test('skips code fences', () {
      expect(ResearchAgent.parseQuery('```\nfoo bar\n```'), 'foo bar');
    });
    test('empty / whitespace yields empty', () {
      expect(ResearchAgent.parseQuery('   \n  '), '');
    });
  });

  group('query dedupe', () {
    test('normalizeQuery is case/space/punct-insensitive', () {
      expect(ResearchAgent.normalizeQuery('Quantum   Computing!'),
          'quantum computing');
    });
    test('isNovelQuery rejects empties and repeats', () {
      final seen = <String>{};
      expect(ResearchAgent.isNovelQuery('black holes', seen), true);
      seen.add(ResearchAgent.normalizeQuery('black holes'));
      expect(ResearchAgent.isNovelQuery('Black   Holes', seen), false);
      expect(ResearchAgent.isNovelQuery('', seen), false);
    });
  });

  group('parseSummary', () {
    test('extracts a TITLE line and body', () {
      final p = ResearchAgent.parseSummary(
          'TITLE: Superconductors\nThey conduct with no resistance.',
          query: 'superconductors');
      expect(p.title, 'Superconductors');
      expect(p.content, 'They conduct with no resistance.');
    });
    test('tolerates a markdown heading form', () {
      final p = ResearchAgent.parseSummary('# Title: Foo\nbody text',
          query: 'q');
      expect(p.title, 'Foo');
      expect(p.content, 'body text');
    });
    test('derives a title from the query when none is given', () {
      final p = ResearchAgent.parseSummary('Just prose, no title line.',
          query: 'coffee beans');
      expect(p.title, 'Coffee beans');
      expect(p.content, 'Just prose, no title line.');
    });
  });

  group('deriveTopicName', () {
    test('strips a leading imperative and trailing period', () {
      expect(ResearchAgent.deriveTopicName('Go find me information about '
          'black holes.'), 'Black holes');
    });
    test('passes a bare subject through, capitalized', () {
      expect(ResearchAgent.deriveTopicName('quantum entanglement'),
          'Quantum entanglement');
    });
    test('truncates a very long goal', () {
      final name = ResearchAgent.deriveTopicName('a' * 200);
      expect(name.length, lessThanOrEqualTo(60));
      expect(name, endsWith('…'));
    });
  });

  group('organize prompt', () {
    test('includes the goal and the finding titles', () {
      final prompt = ResearchAgent.organizeUserPrompt(
        goal: 'the history of tea',
        titles: ['Origins', 'Trade routes'],
        contents: ['Tea began in China.', 'It spread along the Silk Road.'],
      );
      expect(prompt, contains('the history of tea'));
      expect(prompt, contains('Origins'));
      expect(prompt, contains('Trade routes'));
    });
  });
}
