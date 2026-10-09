import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/cognition/solver.dart';

/// Evaluate and assert success, returning the rendered value.
String _ok(String term, {SolverContext? ctx}) {
  final r = Solver.evaluate(term, context: ctx);
  expect(r.ok, true, reason: 'expected success for `$term`, got: ${r.error}');
  return r.value!.render();
}

SolverResult _fail(String term) {
  final r = Solver.evaluate(term);
  expect(r.ok, false, reason: 'expected failure for `$term`');
  return r;
}

void main() {
  group('exact arithmetic', () {
    test('basic + - * /', () {
      expect(_ok('(+ 2 3)'), '5');
      expect(_ok('(* 6 7)'), '42');
      expect(_ok('(- 10 3 2)'), '5');
      expect(_ok('(- 5)'), '-5'); // unary negate
      expect(_ok('(+ )'), '0'); // empty + is additive identity
      expect(_ok('(* )'), '1'); // empty * is multiplicative identity
    });

    test('division is exact, not floating point', () {
      expect(_ok('(/ 7 2)'), '3.5');
      expect(_ok('(/ 1 4)'), '0.25');
      // A repeating fraction stays exact (kept as n/d with a decimal hint).
      expect(_ok('(/ 1 3)'), contains('1/3'));
      expect(_ok('(/ 10 5)'), '2');
    });

    test('division by zero fails cleanly', () {
      expect(_fail('(/ 5 0)').error, contains('division by zero'));
    });

    test('big integers stay exact (no overflow, no rounding)', () {
      expect(_ok('(* 99999999999 99999999999)'), '9999999999800000000001');
    });

    test('abs / neg / pow', () {
      expect(_ok('(abs (- 0 7))'), '7');
      expect(_ok('(neg 4)'), '-4');
      expect(_ok('(pow 2 10)'), '1024');
      expect(_ok('(pow 10 -2)'), '0.01'); // exact negative power
      expect(_fail('(pow 2 0.5)').error, contains('integer exponent'));
    });

    test('min / max / sum / avg / count over list or args', () {
      expect(_ok('(sum (list 1 2 3 4))'), '10');
      expect(_ok('(sum 1 2 3)'), '6');
      expect(_ok('(avg (list 2 4))'), '3');
      expect(_ok('(max 3 9 2)'), '9');
      expect(_ok('(min (list 5 1 9))'), '1');
      expect(_ok('(count (list 1 2 3))'), '3');
    });
  });

  group('comparison and logic', () {
    test('equality and ordering', () {
      expect(_ok('(= 2 2)'), 'true');
      expect(_ok('(!= 2 3)'), 'true');
      expect(_ok('(< 2 3)'), 'true');
      expect(_ok('(>= 3 3)'), 'true');
      expect(_ok('(> 2 3)'), 'false');
    });

    test('the age-contradiction case (born 2019, claimed 5 in 2026)', () {
      // 2026 - 2019 = 7, not 5 → the Dreamer should NOT silently merge this.
      expect(_ok('(= (- 2026 2019) 5)'), 'false');
      expect(_ok('(- 2026 2019)'), '7');
    });

    test('boolean operators short-circuit correctly', () {
      expect(_ok('(and true (> 5 3))'), 'true');
      expect(_ok('(and true false)'), 'false');
      expect(_ok('(or false false)'), 'false');
      expect(_ok('(or false true)'), 'true');
      expect(_ok('(not false)'), 'true');
    });

    test('if picks the taken branch', () {
      expect(_ok('(if (< 1 2) 10 20)'), '10');
      expect(_ok('(if (> 1 2) 10 20)'), '20');
      expect(_ok('(if (> (sum (list 3 4 5)) 10) 1 0)'), '1');
    });
  });

  group('sets and ordering', () {
    test('membership', () {
      expect(_ok('(in 3 (list 1 2 3))'), 'true');
      expect(_ok('(in 9 (list 1 2 3))'), 'false');
    });

    test('between (inclusive)', () {
      expect(_ok('(between 5 1 10)'), 'true');
      expect(_ok('(between 0 1 10)'), 'false');
    });

    test('all-distinct', () {
      expect(_ok('(all-distinct (list 1 2 3))'), 'true');
      expect(_ok('(all-distinct (list 1 2 2))'), 'false');
    });

    test('sorted-asc / sorted-desc (transitive ordering check)', () {
      expect(_ok('(sorted-asc (list 1 2 3))'), 'true');
      expect(_ok('(sorted-asc (list 3 2 1))'), 'false');
      expect(_ok('(sorted-desc (list 3 2 1))'), 'true');
    });
  });

  group('dates and durations', () {
    test('days / hours / minutes between are exact', () {
      expect(
          _ok('(days-between (date "2026-01-01") (date "2026-01-11"))'), '10');
      // The fasting example: 8pm Oct 5 → noon Oct 6 is exactly 16 hours.
      expect(
          _ok('(hours-between (datetime "2026-10-05T20:00") '
              '(datetime "2026-10-06T12:00"))'),
          '16');
      expect(
          _ok('(minutes-between (datetime "2026-10-06T10:00") '
              '(datetime "2026-10-06T10:30"))'),
          '30');
    });

    test('component extraction and date math', () {
      expect(_ok('(year (date "2026-12-25"))'), '2026');
      expect(_ok('(month (date "2026-12-25"))'), '12');
      expect(_ok('(day (date "2026-12-25"))'), '25');
      expect(_ok('(add-days (date "2026-01-01") 10)'), '2026-01-11');
      expect(_ok('(add-hours (datetime "2026-01-01T00:00") 5)'),
          '2026-01-01T05:00');
    });

    test('(now) reads the injected clock — deterministic', () {
      final ctx = SolverContext(now: DateTime.utc(2026, 10, 6, 12, 0, 0));
      expect(_ok('(year (now))', ctx: ctx), '2026');
      expect(
          _ok('(hours-between (datetime "2026-10-06T08:00") (now))', ctx: ctx),
          '4');
    });

    test('unparseable date fails cleanly', () {
      expect(_fail('(date "not-a-date")').error, contains('cannot parse'));
    });
  });

  group('parse tolerance', () {
    test('strips markdown code fences', () {
      expect(_ok('```\n(+ 1 2)\n```'), '3');
      expect(_ok('```lisp\n(* 3 3)\n```'), '9');
    });

    test('extracts the first balanced expression from surrounding prose', () {
      expect(_ok('the answer is (+ 1 2)!'), '3');
    });
  });

  group('error handling (never throws to the caller)', () {
    test('unknown function', () {
      expect(_fail('(bogus 1 2)').error, contains('unknown function'));
    });

    test('wrong arity', () {
      expect(_fail('(not true false)').error, contains('argument'));
    });

    test('type mismatch', () {
      expect(_fail('(+ 1 true)').error, contains('number'));
    });

    test('empty / garbage input', () {
      expect(Solver.evaluate('').ok, false);
      expect(Solver.evaluate('just some words').ok, false);
    });
  });

  group('derivation trace', () {
    test('records inner-to-outer computation steps', () {
      final r = Solver.evaluate('(+ 1 (* 2 3))');
      expect(r.ok, true);
      expect(r.value!.render(), '7');
      expect(r.derivation.length, greaterThanOrEqualTo(2));
      expect(r.derivation.first, contains('(* 2 3) = 6'));
      expect(r.derivation.last, contains('= 7'));
    });
  });

  group('grammar', () {
    test('known ops include the core operators', () {
      expect(Solver.knownOps.contains('+'), true);
      expect(Solver.knownOps.contains('hours-between'), true);
    });

    test('grammar constrains op names and orders longest-first', () {
      final g = Solver.buildSolverGrammar();
      expect(g, contains('root'));
      expect(g, contains('days-between'));
      // "days-between" must be offered before the shorter "day" so the
      // sampler/parser does not match the prefix first.
      expect(g.indexOf('"days-between"'), lessThan(g.indexOf('"day"')));
    });
  });
}
