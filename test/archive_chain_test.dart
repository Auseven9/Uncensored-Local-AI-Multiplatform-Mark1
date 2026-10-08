import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/memory/archive_chain.dart';

/// Build an intact chain of [n] entries with deterministic content.
List<ArchiveEntry> _chain(int n) {
  final out = <ArchiveEntry>[];
  var prev = kArchiveGenesisHash;
  for (var i = 0; i < n; i++) {
    final e = nextEntry(
      seq: i,
      prevHash: prev,
      timestampUtc: '2026-10-08T00:0${i}:00',
      role: i.isEven ? 'user' : 'assistant',
      content: 'turn number $i',
    );
    out.add(e);
    prev = e.hash;
  }
  return out;
}

void main() {
  group('computeArchiveHash', () {
    test('is deterministic', () {
      final a = computeArchiveHash(
          prevHash: 'p', timestampUtc: 't', role: 'user', content: 'hi');
      final b = computeArchiveHash(
          prevHash: 'p', timestampUtc: 't', role: 'user', content: 'hi');
      expect(a, b);
      expect(a.length, 64); // sha256 hex
    });

    test('changes when any field changes', () {
      final base = computeArchiveHash(
          prevHash: 'p', timestampUtc: 't', role: 'user', content: 'hi');
      expect(
          computeArchiveHash(
              prevHash: 'p2', timestampUtc: 't', role: 'user', content: 'hi'),
          isNot(base));
      expect(
          computeArchiveHash(
              prevHash: 'p', timestampUtc: 't', role: 'user', content: 'hi!'),
          isNot(base));
      expect(
          computeArchiveHash(
              prevHash: 'p',
              timestampUtc: 't',
              role: 'assistant',
              content: 'hi'),
          isNot(base));
    });

    test('field boundaries are unambiguous (no delimiter forgery)', () {
      // Moving a character across the role/content boundary must NOT collide.
      final a = computeArchiveHash(
          prevHash: '', timestampUtc: '', role: 'ab', content: 'c');
      final b = computeArchiveHash(
          prevHash: '', timestampUtc: '', role: 'a', content: 'bc');
      expect(a, isNot(b));
    });
  });

  group('verifyChain — intact', () {
    test('empty chain is vacuously intact', () {
      final v = verifyChain([]);
      expect(v.ok, true);
      expect(v.verified, 0);
      expect(v.fault, ChainFault.none);
    });

    test('a well-formed chain verifies', () {
      final v = verifyChain(_chain(5));
      expect(v.ok, true);
      expect(v.verified, 5);
      expect(v.brokenAt, isNull);
    });
  });

  group('verifyChain — tamper detection (fail-closed)', () {
    test('in-place edit of an entry is caught', () {
      final c = _chain(5);
      // Edit the content of entry 2 without recomputing its hash.
      c[2] = ArchiveEntry(
        seq: c[2].seq,
        timestampUtc: c[2].timestampUtc,
        role: c[2].role,
        content: 'EDITED',
        prevHash: c[2].prevHash,
        hash: c[2].hash, // stale
      );
      final v = verifyChain(c);
      expect(v.ok, false);
      expect(v.fault, ChainFault.tamperedEntry);
      expect(v.brokenAt, 2);
    });

    test('deleting a middle entry breaks the link', () {
      final c = _chain(5)..removeAt(2);
      // Re-number so seq stays contiguous (simulating a naive deletion that
      // tries to hide itself) — the prevHash link must still break.
      final renum = <ArchiveEntry>[];
      for (var i = 0; i < c.length; i++) {
        renum.add(ArchiveEntry(
          seq: i,
          timestampUtc: c[i].timestampUtc,
          role: c[i].role,
          content: c[i].content,
          prevHash: c[i].prevHash,
          hash: c[i].hash,
        ));
      }
      final v = verifyChain(renum);
      expect(v.ok, false);
      expect(v.fault, ChainFault.brokenLink);
      expect(v.brokenAt, 2); // the entry that used to follow the deleted one
    });

    test('a sequence gap is caught', () {
      final c = _chain(3);
      c[1] = ArchiveEntry(
        seq: 99, // gap
        timestampUtc: c[1].timestampUtc,
        role: c[1].role,
        content: c[1].content,
        prevHash: c[1].prevHash,
        hash: c[1].hash,
      );
      final v = verifyChain(c);
      expect(v.ok, false);
      expect(v.fault, ChainFault.sequenceGap);
    });

    test('a bad genesis is caught', () {
      final c = _chain(3);
      c[0] = ArchiveEntry(
        seq: 0,
        timestampUtc: c[0].timestampUtc,
        role: c[0].role,
        content: c[0].content,
        prevHash: 'not-the-genesis',
        hash: c[0].hash,
      );
      final v = verifyChain(c);
      expect(v.ok, false);
      expect(v.fault, ChainFault.badGenesis);
      expect(v.brokenAt, 0);
    });
  });

  group('nextEntry', () {
    test('produces a self-consistent link off the current tip', () {
      final first = nextEntry(
        seq: 0,
        prevHash: kArchiveGenesisHash,
        timestampUtc: '2026-10-08T00:00:00',
        role: 'user',
        content: 'hello',
      );
      expect(first.prevHash, kArchiveGenesisHash);
      expect(
          first.hash,
          computeArchiveHash(
              prevHash: kArchiveGenesisHash,
              timestampUtc: '2026-10-08T00:00:00',
              role: 'user',
              content: 'hello'));
      final second = nextEntry(
        seq: 1,
        prevHash: first.hash,
        timestampUtc: '2026-10-08T00:01:00',
        role: 'assistant',
        content: 'hi there',
      );
      expect(verifyChain([first, second]).ok, true);
    });
  });
}
