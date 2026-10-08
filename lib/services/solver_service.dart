import 'package:get/get.dart';

import '../core/cognition/solver.dart';
import 'log_service.dart';

/// The compact directive injected into the system prompt when the Solver is
/// offered for a turn. It teaches the model the inline propose-a-term syntax:
/// the model writes `[[solve (expr)]]`, and after the reply is generated the
/// app evaluates that term exactly and substitutes the real result. The model
/// proposes; the Solver owns the number.
const String solverDirective =
    'Exact calculator available: for any arithmetic, date/time, or logical '
    'check that must be exactly right, write it inline as [[solve (expr)]] and '
    'the app fills in the exact result (never guess the number yourself). Ops: '
    '+ - * / abs min max sum avg count = != < <= > >= and or not if between in '
    'sorted-asc date datetime now days-between hours-between minutes-between '
    'add-days year month day. '
    'Example: "that is [[solve (hours-between (datetime \\"2026-10-05T20:00\\") '
    '(now))]] hours". Use it only for things that genuinely compute; write '
    'normally otherwise.';

/// Matches a `[[solve (expr)]]` tag and captures the inner term. Non-greedy so
/// several tags on one line are handled independently; `dotAll` so a term may
/// wrap across lines.
final RegExp _solveTagRe = RegExp(r'\[\[\s*solve\s+(.+?)\]\]', dotAll: true);

/// Front-end seam for the Solver (System 2's deterministic rail).
///
/// Wraps the pure [Solver] with telemetry (so the status strip and a future
/// inspector can show what was computed) and the inline substitution that wires
/// it into the chat path. Stateless with respect to correctness — every result
/// comes straight from the pure evaluator.
class SolverService extends GetxService {
  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  /// The most recent evaluation (for the status strip / inspector).
  final lastResult = Rxn<SolverResult>();

  /// A small rolling window of recent evaluations (oldest first).
  final recent = <SolverResult>[].obs;
  static const int _recentCap = 20;

  /// How many terms the last [applyInline] substituted.
  final lastSubstitutions = 0.obs;

  /// Evaluate a single Solver term, recording telemetry. Never throws — a
  /// failure comes back inside the [SolverResult].
  SolverResult evaluate(String term, {DateTime? now}) {
    final r = Solver.evaluate(
      term,
      context: now != null ? SolverContext(now: now) : null,
    );
    lastResult.value = r;
    recent.add(r);
    if (recent.length > _recentCap) {
      recent.removeRange(0, recent.length - _recentCap);
    }
    _log?.info(
      'solve ${r.ok ? 'ok' : 'fail'}: $term => ${r.rendered}',
      source: 'Solver',
    );
    return r;
  }

  /// True when at least one `[[solve …]]` tag is present — a cheap pre-check so
  /// the hot path only does work when the model actually proposed a term.
  bool hasTag(String reply) => _solveTagRe.hasMatch(reply);

  /// Replace every `[[solve (expr)]]` in [reply] with its exact result
  /// (or a clear `[unverified: …]` marker when the term cannot be evaluated),
  /// and return the rewritten reply. [lastSubstitutions] is updated to the
  /// number of tags handled.
  String applyInline(String reply, {DateTime? now}) {
    var count = 0;
    final out = reply.replaceAllMapped(_solveTagRe, (m) {
      final term = m.group(1)!.trim();
      final r = evaluate(term, now: now);
      count++;
      return r.ok ? r.value!.render() : '[unverified: ${r.error}]';
    });
    lastSubstitutions.value = count;
    return out;
  }
}
