/// The Solver — a deterministic, exact-logic executor (System 2's rail).
///
/// An LLM, especially a small on-device one, does not *compute* — it predicts a
/// plausible next token. Ask it "847 × 963", "have I fasted 16 hours?" or "if
/// she was born in 2019, is she 5 in 2026?" and it pattern-matches toward an
/// answer that merely *looks* right. The Solver fixes exactly that class of
/// question by splitting the work:
///
///   • the model's job becomes *translation* — turn the question into a formal
///     term (constrained by [Solver.buildSolverGrammar] so the output is always
///     syntactically valid);
///   • the Solver's job is *evaluation* — compute that term exactly, in pure
///     Dart, with real arithmetic and logic, and hand back a guaranteed-correct
///     result plus a readable derivation of how it got there.
///
/// The model proposes; the Solver verifies. Model = language; Solver = truth.
///
/// ## Scope (deliberately small)
///
/// Exact rational arithmetic, dates/durations, comparisons, boolean logic, set
/// membership and ordering checks. This is a focused evaluator, **not** a
/// general theorem prover or SAT solver. It grows only where it earns it.
///
/// ## Laws it honours
///
/// Pure Dart, no dependencies, no native code, no floating-point in the
/// arithmetic core (every number is an exact [Rational] backed by [BigInt]), no
/// hidden state, and fully deterministic — the only clock it can read is the one
/// the caller injects via [SolverContext], so `(now)` is reproducible in tests.
///
/// ## The term language (S-expressions)
///
/// ```text
/// (+ 2 3)                                   => 5
/// (/ 7 2)                                   => 3.5            (exact)
/// (= (- 2026 2019) 5)                       => false          (she'd be 7)
/// (hours-between (datetime "2026-10-05T20:00")
///                (datetime "2026-10-06T12:00"))  => 16
/// (sorted-asc (list 1 2 3))                 => true
/// (if (> (sum (list 3 4 5)) 10) "high" "low") => "high"
/// ```
library;

// ─────────────────────────────────────────────────────────────────────────
// Exact rational number (BigInt numerator / denominator, always normalized).
// ─────────────────────────────────────────────────────────────────────────

/// An exact rational number. Normalized on construction (denominator > 0,
/// reduced by gcd), so equal values are always structurally equal. All Solver
/// arithmetic flows through this — there is no floating point in the hot path,
/// so results never drift.
class Rational {
  final BigInt _n;
  final BigInt _d;

  const Rational._(this._n, this._d);

  /// Normalizing constructor. Throws [ArgumentError] on a zero denominator
  /// (callers guard division explicitly, so this should never surface).
  factory Rational(BigInt n, BigInt d) {
    if (d == BigInt.zero) throw ArgumentError('zero denominator');
    var nn = n;
    var dd = d;
    if (dd.isNegative) {
      nn = -nn;
      dd = -dd;
    }
    if (nn == BigInt.zero) return Rational._(BigInt.zero, BigInt.one);
    final g = nn.abs().gcd(dd);
    return Rational._(nn ~/ g, dd ~/ g);
  }

  factory Rational.fromBigInt(BigInt v) => Rational._(v, BigInt.one);
  factory Rational.fromInt(int v) => Rational._(BigInt.from(v), BigInt.one);

  static final Rational zero = Rational._(BigInt.zero, BigInt.one);
  static final Rational one = Rational._(BigInt.one, BigInt.one);

  BigInt get numerator => _n;
  BigInt get denominator => _d;
  bool get isZero => _n == BigInt.zero;
  bool get isInteger => _d == BigInt.one;

  Rational operator +(Rational o) => Rational(_n * o._d + o._n * _d, _d * o._d);
  Rational operator -(Rational o) => Rational(_n * o._d - o._n * _d, _d * o._d);
  Rational operator *(Rational o) => Rational(_n * o._n, _d * o._d);
  Rational operator /(Rational o) => Rational(_n * o._d, _d * o._n);

  Rational negate() => Rational._(-_n, _d);
  Rational abs() => Rational._(_n.abs(), _d);

  int compareTo(Rational o) => (_n * o._d).compareTo(o._n * _d);
  double toDouble() => _n.toDouble() / _d.toDouble();

  /// The exact integer value, or an error if this is not a whole number.
  int toIntExact() {
    if (!isInteger) throw StateError('not an integer: ${render()}');
    return _n.toInt();
  }

  @override
  bool operator ==(Object other) =>
      other is Rational && _n == other._n && _d == other._d;

  @override
  int get hashCode => Object.hash(_n, _d);

  /// Renders exactly: a whole number as an integer, a terminating fraction as a
  /// finite decimal (e.g. `3.5`, `0.01`), and a repeating fraction as `n/d`
  /// with a rounded decimal hint (e.g. `1/3 (≈ 0.333333)`).
  String render() {
    if (_d == BigInt.one) return _n.toString();

    // Does the denominator divide a power of ten? (only factors 2 and 5)
    var dd = _d;
    var twos = 0;
    var fives = 0;
    final five = BigInt.from(5);
    while (dd % BigInt.two == BigInt.zero) {
      dd = dd ~/ BigInt.two;
      twos++;
    }
    while (dd % five == BigInt.zero) {
      dd = dd ~/ five;
      fives++;
    }

    if (dd != BigInt.one) {
      // Non-terminating: keep the exact fraction, add a readable approximation.
      return '$_n/$_d (≈ ${toDouble().toStringAsFixed(6)})';
    }

    final k = twos > fives ? twos : fives;
    final scale = BigInt.from(10).pow(k);
    final scaled = _n * (scale ~/ _d); // scale is divisible by _d here
    final neg = scaled < BigInt.zero;
    final digits = scaled.abs().toString().padLeft(k + 1, '0');
    final intPart = digits.substring(0, digits.length - k);
    var frac = digits.substring(digits.length - k);
    frac = frac.replaceAll(RegExp(r'0+$'), '');
    final body = frac.isEmpty ? intPart : '$intPart.$frac';
    return neg ? '-$body' : body;
  }

  @override
  String toString() => render();
}

// ─────────────────────────────────────────────────────────────────────────
// Values (the runtime results the evaluator produces).
// ─────────────────────────────────────────────────────────────────────────

/// A value the Solver can compute or hold.
abstract class SolverValue {
  const SolverValue();

  /// A human-readable rendering for results, traces and telemetry.
  String render();
}

class NumberValue extends SolverValue {
  final Rational value;
  const NumberValue(this.value);
  @override
  String render() => value.render();
}

class BoolValue extends SolverValue {
  final bool value;
  const BoolValue(this.value);
  @override
  String render() => value ? 'true' : 'false';
}

class StringValue extends SolverValue {
  final String value;
  const StringValue(this.value);
  @override
  String render() => '"$value"';
}

/// A date/time, always in UTC so arithmetic is deterministic regardless of the
/// device's timezone.
class DateValue extends SolverValue {
  final DateTime value; // UTC
  const DateValue(this.value);

  @override
  String render() {
    final d = value;
    String p2(int x) => x.toString().padLeft(2, '0');
    final date =
        '${d.year.toString().padLeft(4, '0')}-${p2(d.month)}-${p2(d.day)}';
    if (d.hour == 0 && d.minute == 0 && d.second == 0) return date;
    final secs = d.second != 0 ? ':${p2(d.second)}' : '';
    return '${date}T${p2(d.hour)}:${p2(d.minute)}$secs';
  }
}

class ListValue extends SolverValue {
  final List<SolverValue> items;
  const ListValue(this.items);
  @override
  String render() => '[${items.map((e) => e.render()).join(', ')}]';
}

// ─────────────────────────────────────────────────────────────────────────
// AST (parsed, before evaluation). Each node re-renders to canonical source
// via toString(), which is what the derivation trace shows.
// ─────────────────────────────────────────────────────────────────────────

abstract class SolverExpr {
  const SolverExpr();
}

class NumberLiteral extends SolverExpr {
  final Rational value;
  const NumberLiteral(this.value);
  @override
  String toString() => value.render();
}

class BoolLiteral extends SolverExpr {
  final bool value;
  const BoolLiteral(this.value);
  @override
  String toString() => value ? 'true' : 'false';
}

class StringLiteral extends SolverExpr {
  final String value;
  const StringLiteral(this.value);
  @override
  String toString() => '"$value"';
}

class CallExpr extends SolverExpr {
  final String op;
  final List<SolverExpr> args;
  const CallExpr(this.op, this.args);
  @override
  String toString() => '($op${args.map((a) => ' $a').join()})';
}

// ─────────────────────────────────────────────────────────────────────────
// Errors, context and result.
// ─────────────────────────────────────────────────────────────────────────

/// A typed failure raised internally during parse or evaluation. Never escapes
/// [Solver.evaluate] — it is caught and turned into a [SolverResult.failure].
class SolverError implements Exception {
  final String message;
  const SolverError(this.message);
  @override
  String toString() => 'SolverError: $message';
}

/// The deterministic environment an evaluation runs in. The only clock the
/// Solver may read is [now]; injecting it keeps `(now)` reproducible.
class SolverContext {
  final DateTime now; // UTC

  SolverContext({DateTime? now}) : now = (now ?? DateTime.now().toUtc());
}

/// The outcome of an evaluation: either a value (with a derivation trace) or a
/// human-readable error. Never throws to the caller.
class SolverResult {
  final bool ok;
  final SolverValue? value;
  final String? error;

  /// Inner-to-outer list of `"(expr) = value"` steps — the actual computation,
  /// not a story about it. Usable in the owner-facing inspector.
  final List<String> derivation;

  const SolverResult._(this.ok, this.value, this.error, this.derivation);

  factory SolverResult.success(SolverValue value, List<String> derivation) =>
      SolverResult._(true, value, null, List.unmodifiable(derivation));

  factory SolverResult.failure(String error,
          [List<String> derivation = const []]) =>
      SolverResult._(false, null, error, List.unmodifiable(derivation));

  /// The value rendered, or `error: <message>` when it failed.
  String get rendered => ok ? value!.render() : 'error: $error';

  @override
  String toString() =>
      ok ? 'SolverResult(${value!.render()})' : 'SolverResult(error: $error)';
}

// ─────────────────────────────────────────────────────────────────────────
// Date/duration helpers (top-level privates shared by the evaluator).
// ─────────────────────────────────────────────────────────────────────────

final BigInt _microPerDay = BigInt.from(86400000000);
final BigInt _microPerHour = BigInt.from(3600000000);
final BigInt _microPerMinute = BigInt.from(60000000);

final RegExp _dateTimeRe = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2}))?)?$');

DateTime? _parseDateTime(String s) {
  final m = _dateTimeRe.firstMatch(s.trim());
  if (m == null) return null;
  int g(int i, [int def = 0]) {
    final v = m.group(i);
    return v == null ? def : int.parse(v);
  }

  return DateTime.utc(g(1), g(2, 1), g(3, 1), g(4), g(5), g(6));
}

// ─────────────────────────────────────────────────────────────────────────
// The Solver facade: parse, evaluate, and build the constraining grammar.
// ─────────────────────────────────────────────────────────────────────────

class Solver {
  const Solver._();

  /// Every function the term language understands. Kept in lockstep with the
  /// evaluator's switch and used to constrain the GBNF grammar's `op` rule.
  static const Set<String> knownOps = {
    // arithmetic
    '+', '-', '*', '/', 'abs', 'neg', 'min', 'max', 'pow', 'sum', 'avg', 'count',
    // comparison
    '=', '!=', '<', '<=', '>', '>=',
    // boolean / control
    'and', 'or', 'not', 'if',
    // sets / ordering
    'list', 'in', 'between', 'all-distinct', 'sorted-asc', 'sorted-desc',
    // dates / durations
    'date', 'datetime', 'now', 'days-between', 'hours-between',
    'minutes-between', 'add-days', 'add-hours', 'year', 'month', 'day',
  };

  /// Evaluate a term and return a result. Tolerates markdown fences and
  /// surrounding prose (the first balanced S-expression is extracted). Never
  /// throws — every failure is captured in [SolverResult.error].
  static SolverResult evaluate(String term, {SolverContext? context}) {
    final ctx = context ?? SolverContext();
    final SolverExpr expr;
    try {
      final src = extractSExpr(term);
      if (src == null || src.isEmpty) {
        return SolverResult.failure('no expression found');
      }
      expr = _parse(src);
    } on SolverError catch (e) {
      return SolverResult.failure(e.message);
    }

    final ev = _Eval(ctx);
    try {
      final v = ev.eval(expr);
      return SolverResult.success(v, ev.trace);
    } on SolverError catch (e) {
      return SolverResult.failure(e.message, ev.trace);
    }
  }

  /// A GBNF grammar that constrains model output to a syntactically valid Solver
  /// term, with the function name forced to the known set (so the sampler
  /// cannot invent an operator the evaluator does not implement). Arity and
  /// argument types are validated at evaluation time, exactly as the tool
  /// grammar validates arguments after parsing.
  static String buildSolverGrammar() {
    final ops = knownOps.toList()
      ..sort((a, b) {
        // Longest first so e.g. "<=" is tried before "<" and
        // "days-between" before "day".
        final byLen = b.length.compareTo(a.length);
        return byLen != 0 ? byLen : a.compareTo(b);
      });
    final opRule = ops.map((o) => '"$o"').join(' | ');
    return '''
root    ::= ws expr ws
expr    ::= call | number | boolean | string
call    ::= "(" ws op ws arglist ")"
arglist ::= ( expr ws )*
op      ::= $opRule
boolean ::= "true" | "false"
number  ::= "-"? ( "0" | [1-9] [0-9]* ) ( "." [0-9]+ )?
string  ::= "\\"" ( [^"\\\\] | "\\\\" ["\\\\/bfnrt] )* "\\""
ws      ::= [ \\t\\n\\r]*
''';
  }

  /// Extracts the first balanced, parenthesis-delimited S-expression from [raw]
  /// (stripping code fences). If there is no `(`, the trimmed text is returned
  /// as a bare atom. Returns `null` when nothing usable is present.
  static String? extractSExpr(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '');
      final last = text.lastIndexOf('```');
      if (last != -1) text = text.substring(0, last);
      text = text.trim();
    }

    final start = text.indexOf('(');
    if (start == -1) return text.isEmpty ? null : text;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null; // unbalanced
  }

  // ── Parsing ───────────────────────────────────────────────────

  static SolverExpr _parse(String src) {
    final tokens = _tokenize(src);
    if (tokens.isEmpty) throw const SolverError('empty expression');
    final p = _Cursor(tokens);
    final expr = _parseExpr(p);
    return expr;
  }

  static List<String> _tokenize(String s) {
    final out = <String>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        i++;
        continue;
      }
      if (c == '(' || c == ')') {
        out.add(c);
        i++;
        continue;
      }
      if (c == '"') {
        final sb = StringBuffer('"');
        i++;
        while (i < s.length) {
          final d = s[i];
          if (d == r'\' && i + 1 < s.length) {
            sb.write(d);
            sb.write(s[i + 1]);
            i += 2;
            continue;
          }
          sb.write(d);
          i++;
          if (d == '"') break;
        }
        out.add(sb.toString());
        continue;
      }
      final sb = StringBuffer();
      while (i < s.length) {
        final d = s[i];
        if (d == ' ' ||
            d == '\t' ||
            d == '\n' ||
            d == '\r' ||
            d == '(' ||
            d == ')') {
          break;
        }
        sb.write(d);
        i++;
      }
      out.add(sb.toString());
    }
    return out;
  }

  static SolverExpr _parseExpr(_Cursor p) {
    final tok = p.peek();
    if (tok == null) throw const SolverError('unexpected end of input');

    if (tok == '(') {
      p.next(); // consume '('
      final head = p.peek();
      if (head == null || head == '(' || head == ')') {
        throw const SolverError('expected a function name after "("');
      }
      final op = p.next();
      if (op.startsWith('"') || _tryNumber(op) != null) {
        throw SolverError('"$op" is not a valid function name');
      }
      final args = <SolverExpr>[];
      while (true) {
        final t2 = p.peek();
        if (t2 == null) throw const SolverError('unbalanced "(" — missing ")"');
        if (t2 == ')') {
          p.next();
          break;
        }
        args.add(_parseExpr(p));
      }
      return CallExpr(op, args);
    }

    if (tok == ')') throw const SolverError('unexpected ")"');

    p.next();
    return _atom(tok);
  }

  static SolverExpr _atom(String tok) {
    if (tok.startsWith('"')) {
      var inner = tok.substring(1);
      if (inner.endsWith('"') && inner.isNotEmpty) {
        inner = inner.substring(0, inner.length - 1);
      }
      return StringLiteral(_unescape(inner));
    }
    if (tok == 'true') return const BoolLiteral(true);
    if (tok == 'false') return const BoolLiteral(false);
    final parsed = _tryNumber(tok);
    if (parsed != null) return NumberLiteral(parsed);
    throw SolverError('unexpected symbol "$tok"');
  }

  static final RegExp _numberRe =
      RegExp(r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$');

  static Rational? _tryNumber(String s) {
    if (!_numberRe.hasMatch(s)) return null;
    final neg = s.startsWith('-');
    final body = neg ? s.substring(1) : s;
    final dot = body.indexOf('.');
    if (dot == -1) {
      final n = BigInt.parse(body);
      return Rational.fromBigInt(neg ? -n : n);
    }
    final intP = body.substring(0, dot);
    final fracP = body.substring(dot + 1);
    final digits = BigInt.parse(intP + fracP);
    final den = BigInt.from(10).pow(fracP.length);
    return Rational(neg ? -digits : digits, den);
  }

  static String _unescape(String s) {
    final sb = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == r'\' && i + 1 < s.length) {
        final n = s[i + 1];
        i += 2;
        switch (n) {
          case 'n':
            sb.write('\n');
            break;
          case 't':
            sb.write('\t');
            break;
          case 'r':
            sb.write('\r');
            break;
          case '"':
            sb.write('"');
            break;
          case r'\':
            sb.write(r'\');
            break;
          case '/':
            sb.write('/');
            break;
          default:
            sb.write(n);
        }
      } else {
        sb.write(c);
        i++;
      }
    }
    return sb.toString();
  }
}

/// A tiny token cursor for the recursive-descent parser.
class _Cursor {
  final List<String> _t;
  int _i = 0;
  _Cursor(this._t);
  String? peek() => _i < _t.length ? _t[_i] : null;
  String next() => _t[_i++];
}

// ─────────────────────────────────────────────────────────────────────────
// The evaluator. Post-order: children evaluate (and record their trace line)
// before the parent, so the derivation reads inner-to-outer.
// ─────────────────────────────────────────────────────────────────────────

class _Eval {
  final SolverContext ctx;
  final List<String> trace = [];
  _Eval(this.ctx);

  SolverValue eval(SolverExpr e) {
    if (e is NumberLiteral) return NumberValue(e.value);
    if (e is BoolLiteral) return BoolValue(e.value);
    if (e is StringLiteral) return StringValue(e.value);
    if (e is CallExpr) {
      final v = _call(e);
      trace.add('$e = ${v.render()}');
      return v;
    }
    throw const SolverError('cannot evaluate expression');
  }

  // ── typed accessors ──
  Rational _num(SolverValue v, String op) {
    if (v is NumberValue) return v.value;
    throw SolverError('$op expects a number, got ${v.render()}');
  }

  bool _bool(SolverValue v, String op) {
    if (v is BoolValue) return v.value;
    throw SolverError('$op expects a boolean, got ${v.render()}');
  }

  DateTime _date(SolverValue v, String op) {
    if (v is DateValue) return v.value;
    throw SolverError('$op expects a date, got ${v.render()}');
  }

  void _arity(CallExpr e, int n) {
    if (e.args.length != n) {
      throw SolverError(
          '${e.op} expects $n argument(s), got ${e.args.length}');
    }
  }

  void _arityMin(CallExpr e, int n) {
    if (e.args.length < n) {
      throw SolverError('${e.op} expects at least $n argument(s)');
    }
  }

  /// Values from either a single list argument or the argument list itself —
  /// so `(sum (list 1 2 3))` and `(sum 1 2 3)` both work.
  List<SolverValue> _gatherValues(CallExpr e) {
    if (e.args.length == 1) {
      final v = eval(e.args[0]);
      if (v is ListValue) return v.items;
      return [v];
    }
    return [for (final a in e.args) eval(a)];
  }

  List<Rational> _gatherNums(CallExpr e) =>
      _gatherValues(e).map((v) => _num(v, e.op)).toList();

  bool _eq(SolverValue a, SolverValue b) {
    if (a is NumberValue && b is NumberValue) return a.value == b.value;
    if (a is DateValue && b is DateValue) {
      return a.value.isAtSameMomentAs(b.value);
    }
    if (a is BoolValue && b is BoolValue) return a.value == b.value;
    if (a is StringValue && b is StringValue) return a.value == b.value;
    if (a is ListValue && b is ListValue) {
      if (a.items.length != b.items.length) return false;
      for (var i = 0; i < a.items.length; i++) {
        if (!_eq(a.items[i], b.items[i])) return false;
      }
      return true;
    }
    return false;
  }

  int _cmp(SolverValue a, SolverValue b, String op) {
    if (a is NumberValue && b is NumberValue) {
      return a.value.compareTo(b.value);
    }
    if (a is DateValue && b is DateValue) {
      return a.value.compareTo(b.value);
    }
    throw SolverError('$op needs two numbers or two dates');
  }

  SolverValue _call(CallExpr e) {
    final op = e.op;
    switch (op) {
      // ── arithmetic ──
      case '+':
        {
          var acc = Rational.zero;
          for (final a in e.args) {
            acc = acc + _num(eval(a), op);
          }
          return NumberValue(acc);
        }
      case '*':
        {
          var acc = Rational.one;
          for (final a in e.args) {
            acc = acc * _num(eval(a), op);
          }
          return NumberValue(acc);
        }
      case '-':
        {
          _arityMin(e, 1);
          final first = _num(eval(e.args[0]), op);
          if (e.args.length == 1) return NumberValue(first.negate());
          var acc = first;
          for (var k = 1; k < e.args.length; k++) {
            acc = acc - _num(eval(e.args[k]), op);
          }
          return NumberValue(acc);
        }
      case '/':
        {
          _arityMin(e, 1);
          if (e.args.length == 1) {
            final d = _num(eval(e.args[0]), op);
            if (d.isZero) throw const SolverError('division by zero');
            return NumberValue(Rational.one / d);
          }
          var acc = _num(eval(e.args[0]), op);
          for (var k = 1; k < e.args.length; k++) {
            final d = _num(eval(e.args[k]), op);
            if (d.isZero) throw const SolverError('division by zero');
            acc = acc / d;
          }
          return NumberValue(acc);
        }
      case 'abs':
        _arity(e, 1);
        return NumberValue(_num(eval(e.args[0]), op).abs());
      case 'neg':
        _arity(e, 1);
        return NumberValue(_num(eval(e.args[0]), op).negate());
      case 'min':
        {
          final ns = _gatherNums(e);
          if (ns.isEmpty) throw const SolverError('min needs at least one number');
          var m = ns.first;
          for (final r in ns) {
            if (r.compareTo(m) < 0) m = r;
          }
          return NumberValue(m);
        }
      case 'max':
        {
          final ns = _gatherNums(e);
          if (ns.isEmpty) throw const SolverError('max needs at least one number');
          var m = ns.first;
          for (final r in ns) {
            if (r.compareTo(m) > 0) m = r;
          }
          return NumberValue(m);
        }
      case 'sum':
        {
          var acc = Rational.zero;
          for (final r in _gatherNums(e)) {
            acc = acc + r;
          }
          return NumberValue(acc);
        }
      case 'avg':
        {
          final ns = _gatherNums(e);
          if (ns.isEmpty) throw const SolverError('avg needs at least one number');
          var acc = Rational.zero;
          for (final r in ns) {
            acc = acc + r;
          }
          return NumberValue(acc / Rational.fromInt(ns.length));
        }
      case 'count':
        {
          if (e.args.length == 1) {
            final v = eval(e.args[0]);
            if (v is ListValue) {
              return NumberValue(Rational.fromInt(v.items.length));
            }
            return NumberValue(Rational.one);
          }
          return NumberValue(Rational.fromInt(e.args.length));
        }
      case 'pow':
        {
          _arity(e, 2);
          final base = _num(eval(e.args[0]), op);
          final ex = _num(eval(e.args[1]), op);
          if (!ex.isInteger) {
            throw const SolverError('pow needs an integer exponent');
          }
          final k = ex.toIntExact();
          if (k >= 0) {
            return NumberValue(
                Rational(base.numerator.pow(k), base.denominator.pow(k)));
          }
          if (base.isZero) {
            throw const SolverError('division by zero (0 to a negative power)');
          }
          final j = -k;
          return NumberValue(
              Rational(base.denominator.pow(j), base.numerator.pow(j)));
        }

      // ── comparison ──
      case '=':
        _arity(e, 2);
        return BoolValue(_eq(eval(e.args[0]), eval(e.args[1])));
      case '!=':
        _arity(e, 2);
        return BoolValue(!_eq(eval(e.args[0]), eval(e.args[1])));
      case '<':
        _arity(e, 2);
        return BoolValue(_cmp(eval(e.args[0]), eval(e.args[1]), op) < 0);
      case '<=':
        _arity(e, 2);
        return BoolValue(_cmp(eval(e.args[0]), eval(e.args[1]), op) <= 0);
      case '>':
        _arity(e, 2);
        return BoolValue(_cmp(eval(e.args[0]), eval(e.args[1]), op) > 0);
      case '>=':
        _arity(e, 2);
        return BoolValue(_cmp(eval(e.args[0]), eval(e.args[1]), op) >= 0);

      // ── boolean / control (short-circuit) ──
      case 'and':
        for (final a in e.args) {
          if (!_bool(eval(a), op)) return const BoolValue(false);
        }
        return const BoolValue(true);
      case 'or':
        for (final a in e.args) {
          if (_bool(eval(a), op)) return const BoolValue(true);
        }
        return const BoolValue(false);
      case 'not':
        _arity(e, 1);
        return BoolValue(!_bool(eval(e.args[0]), op));
      case 'if':
        {
          _arity(e, 3);
          final cond = _bool(eval(e.args[0]), op);
          return eval(cond ? e.args[1] : e.args[2]);
        }

      // ── sets / ordering ──
      case 'list':
        return ListValue([for (final a in e.args) eval(a)]);
      case 'in':
        {
          _arity(e, 2);
          final x = eval(e.args[0]);
          final coll = eval(e.args[1]);
          if (coll is! ListValue) {
            throw const SolverError('in expects a list as its second argument');
          }
          for (final item in coll.items) {
            if (_eq(x, item)) return const BoolValue(true);
          }
          return const BoolValue(false);
        }
      case 'between':
        {
          _arity(e, 3);
          final x = eval(e.args[0]);
          final lo = eval(e.args[1]);
          final hi = eval(e.args[2]);
          return BoolValue(_cmp(lo, x, op) <= 0 && _cmp(x, hi, op) <= 0);
        }
      case 'all-distinct':
        {
          final vs = _gatherValues(e);
          for (var i = 0; i < vs.length; i++) {
            for (var j = i + 1; j < vs.length; j++) {
              if (_eq(vs[i], vs[j])) return const BoolValue(false);
            }
          }
          return const BoolValue(true);
        }
      case 'sorted-asc':
        {
          final vs = _gatherValues(e);
          for (var i = 1; i < vs.length; i++) {
            if (_cmp(vs[i - 1], vs[i], op) > 0) return const BoolValue(false);
          }
          return const BoolValue(true);
        }
      case 'sorted-desc':
        {
          final vs = _gatherValues(e);
          for (var i = 1; i < vs.length; i++) {
            if (_cmp(vs[i - 1], vs[i], op) < 0) return const BoolValue(false);
          }
          return const BoolValue(true);
        }

      // ── dates / durations ──
      case 'date':
      case 'datetime':
        {
          _arity(e, 1);
          final v = eval(e.args[0]);
          if (v is! StringValue) {
            throw SolverError('$op expects a quoted date string');
          }
          final dt = _parseDateTime(v.value);
          if (dt == null) {
            throw SolverError('$op: cannot parse "${v.value}"');
          }
          return DateValue(dt);
        }
      case 'now':
        _arity(e, 0);
        return DateValue(ctx.now);
      case 'days-between':
        {
          _arity(e, 2);
          final a = _date(eval(e.args[0]), op);
          final b = _date(eval(e.args[1]), op);
          final micros = BigInt.from(b.difference(a).inMicroseconds);
          return NumberValue(Rational(micros, _microPerDay));
        }
      case 'hours-between':
        {
          _arity(e, 2);
          final a = _date(eval(e.args[0]), op);
          final b = _date(eval(e.args[1]), op);
          final micros = BigInt.from(b.difference(a).inMicroseconds);
          return NumberValue(Rational(micros, _microPerHour));
        }
      case 'minutes-between':
        {
          _arity(e, 2);
          final a = _date(eval(e.args[0]), op);
          final b = _date(eval(e.args[1]), op);
          final micros = BigInt.from(b.difference(a).inMicroseconds);
          return NumberValue(Rational(micros, _microPerMinute));
        }
      case 'add-days':
        {
          _arity(e, 2);
          final d = _date(eval(e.args[0]), op);
          final n = _num(eval(e.args[1]), op);
          if (!n.isInteger) {
            throw const SolverError('add-days needs a whole number of days');
          }
          return DateValue(d.add(Duration(days: n.toIntExact())));
        }
      case 'add-hours':
        {
          _arity(e, 2);
          final d = _date(eval(e.args[0]), op);
          final n = _num(eval(e.args[1]), op);
          if (!n.isInteger) {
            throw const SolverError('add-hours needs a whole number of hours');
          }
          return DateValue(d.add(Duration(hours: n.toIntExact())));
        }
      case 'year':
        _arity(e, 1);
        return NumberValue(Rational.fromInt(_date(eval(e.args[0]), op).year));
      case 'month':
        _arity(e, 1);
        return NumberValue(Rational.fromInt(_date(eval(e.args[0]), op).month));
      case 'day':
        _arity(e, 1);
        return NumberValue(Rational.fromInt(_date(eval(e.args[0]), op).day));

      default:
        throw SolverError('unknown function "$op"');
    }
  }
}
