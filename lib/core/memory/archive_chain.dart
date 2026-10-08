/// The Archive chain — the pure, tamper-evident integrity core.
///
/// The Archive is ALESIS's immutable ground truth: an append-only ledger of
/// what was actually said, where each entry carries the SHA-256 hash of the
/// entry before it. Because every hash folds in the previous hash *and* the
/// entry's own content, the chain is **tamper-evident**:
///
///   • edit an entry in place  → its own hash no longer matches its content;
///   • delete a middle entry    → the next entry's `prevHash` no longer matches
///                                the (now missing) prior hash;
///   • reorder entries          → same break, at the first moved link.
///
/// It is tamper-*evident*, not tamper-*proof*: someone who recomputes every
/// downstream hash could forge an append, and truncating the tail or wiping the
/// store leaves a shorter-but-valid chain. Catching those is the job of the
/// out-of-store backup + the Integrity panel, not the chain alone. What the
/// chain guarantees is that an in-place edit or a middle deletion in the stored
/// ledger cannot pass unnoticed — which is exactly what must hold before the
/// Dreamer is ever allowed to consolidate over this history.
///
/// This file is pure and deterministic: hashing and verification only, no
/// database, no I/O. The store layer (the `archive` table + migration) and the
/// single chat-path writer build on these functions; keeping them separate lets
/// the integrity logic be proven in isolation.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The `prevHash` of the very first entry (seq 0) — a fixed all-zero sentinel so
/// the first link is well-defined and the genesis is itself verifiable.
const String kArchiveGenesisHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// One immutable, chained record of a single turn in the Archive.
class ArchiveEntry {
  /// 0-based position in the chain (contiguous; seq 0 is the genesis link).
  final int seq;

  /// ISO-8601 UTC timestamp of when the turn was recorded.
  final String timestampUtc;

  /// Who produced the content (e.g. 'user', 'assistant').
  final String role;

  /// The verbatim turn content — the thing being made tamper-evident.
  final String content;

  /// The hash of the previous entry (the genesis sentinel for seq 0).
  final String prevHash;

  /// This entry's own hash: [computeArchiveHash] over its fields.
  final String hash;

  const ArchiveEntry({
    required this.seq,
    required this.timestampUtc,
    required this.role,
    required this.content,
    required this.prevHash,
    required this.hash,
  });

  @override
  String toString() =>
      'ArchiveEntry(seq=$seq, role=$role, hash=${hash.substring(0, 8)}…)';
}

/// The canonical hash of one link: SHA-256 over a JSON-encoded tuple of
/// (prevHash, timestampUtc, role, content). JSON encoding escapes the fields so
/// no delimiter ambiguity can let one field's bytes masquerade as another's —
/// the encoding is unambiguous and reproducible across platforms.
String computeArchiveHash({
  required String prevHash,
  required String timestampUtc,
  required String role,
  required String content,
}) {
  final payload = jsonEncode([prevHash, timestampUtc, role, content]);
  return sha256.convert(utf8.encode(payload)).toString();
}

/// Build the next entry to append, given the current tip hash. The returned
/// entry's [ArchiveEntry.hash] is computed here, so the store layer only has to
/// persist it — it never computes its own hash and so cannot drift from this
/// definition.
ArchiveEntry nextEntry({
  required int seq,
  required String prevHash,
  required String timestampUtc,
  required String role,
  required String content,
}) {
  final hash = computeArchiveHash(
    prevHash: prevHash,
    timestampUtc: timestampUtc,
    role: role,
    content: content,
  );
  return ArchiveEntry(
    seq: seq,
    timestampUtc: timestampUtc,
    role: role,
    content: content,
    prevHash: prevHash,
    hash: hash,
  );
}

/// Why kind of break [verifyChain] found, for precise owner-facing reporting.
enum ChainFault { none, sequenceGap, brokenLink, tamperedEntry, badGenesis }

/// The outcome of verifying a chain.
class ChainVerification {
  /// True only when every link checks out (an empty chain is vacuously intact).
  final bool ok;

  /// How many links were verified before the result (all of them when [ok]).
  final int verified;

  /// The `seq` of the first bad entry, or null when [ok].
  final int? brokenAt;

  final ChainFault fault;

  /// Human-readable summary for logs and the Integrity panel.
  final String reason;

  const ChainVerification({
    required this.ok,
    required this.verified,
    required this.fault,
    required this.reason,
    this.brokenAt,
  });
}

/// Verify that [entries] (in ascending seq order) form an intact chain.
///
/// Fail-closed: it stops and reports the FIRST break it finds, naming the kind
/// of tampering, so the daemon can refuse to dream over a corrupted history and
/// the Integrity panel can show the owner exactly where it broke. An empty
/// chain is intact.
ChainVerification verifyChain(List<ArchiveEntry> entries) {
  var prev = kArchiveGenesisHash;
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];

    if (e.seq != i) {
      return ChainVerification(
        ok: false,
        verified: i,
        brokenAt: e.seq,
        fault: ChainFault.sequenceGap,
        reason: 'sequence gap at index $i (found seq ${e.seq}) — '
            'an entry is missing or out of order',
      );
    }

    if (e.prevHash != prev) {
      return ChainVerification(
        ok: false,
        verified: i,
        brokenAt: e.seq,
        fault: i == 0 ? ChainFault.badGenesis : ChainFault.brokenLink,
        reason: i == 0
            ? 'bad genesis: first entry prevHash is not the genesis sentinel'
            : 'broken link at seq ${e.seq}: prevHash does not match the prior '
                'entry — a middle entry was deleted or reordered',
      );
    }

    final expected = computeArchiveHash(
      prevHash: e.prevHash,
      timestampUtc: e.timestampUtc,
      role: e.role,
      content: e.content,
    );
    if (e.hash != expected) {
      return ChainVerification(
        ok: false,
        verified: i,
        brokenAt: e.seq,
        fault: ChainFault.tamperedEntry,
        reason: 'tampered entry at seq ${e.seq}: stored hash does not match its '
            'content — this entry was edited in place',
      );
    }

    prev = e.hash;
  }

  return ChainVerification(
    ok: true,
    verified: entries.length,
    fault: ChainFault.none,
    reason: entries.isEmpty
        ? 'empty chain (intact)'
        : 'intact (${entries.length} links)',
  );
}
