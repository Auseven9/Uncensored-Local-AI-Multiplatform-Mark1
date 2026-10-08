// belief_state.dart
// ALESIS fast working-memory "belief-state organ" — PROPOSED / UNPROVEN.
// Gated on the rung-1 coupling experiment. DO NOT wire into production until
// rung-1 shows it beats a plain scratchpad AND RAG.
//
// Constraints (from the team / Cairn's code review):
//  - Lives in its OWN store as a single BLOB. NEVER chained into the Archive.
//  - A disposable, lossy, reconstructive cache — never the system of record.
//  - Decodes below a confidence floor return `unsure` — never a fabricated value
//    (respects the no-fake-data law).
//  - Pure Dart, O(D) elementwise math, microseconds/turn — does NOT touch the
//    llama engine. Value embeddings are produced UPSTREAM (reused from
//    consolidation), never live-embedded here (avoids the embedder co-residency crash).
//
// NOTE (web/io split): the role RNG uses 64-bit bitwise ops — correct on native
// (device). For the _web impl, swap _next/_seed for a 32-bit-safe generator.

import 'dart:typed_data';

class BeliefDecode {
  final String? value;      // null => unsure (below floor)
  final double confidence;  // cosine to nearest candidate
  const BeliefDecode(this.value, this.confidence);
  bool get isUnsure => value == null;
}

class BeliefState {
  final int d;            // hypervector dimension (e.g. 10000)
  final double alpha;     // decay / forgetting knob (0 < alpha <= 1)
  final double floor;     // confidence floor; below => unsure
  final Float32List _acc; // real accumulator (the live belief); queryable = sign(_acc)

  BeliefState({this.d = 10000, this.alpha = 0.95, this.floor = 0.08})
      : _acc = Float32List(d);

  /// Sign-quantize an upstream embedding to a ±1 hypervector (tiled/truncated to d).
  Float32List quantize(List<double> embedding) {
    final v = Float32List(d);
    final m = embedding.length;
    for (var i = 0; i < d; i++) {
      v[i] = embedding[i % m] >= 0 ? 1.0 : -1.0;
    }
    return v;
  }

  /// Write one (key -> value) binding into the belief, with decay.
  /// [valueVector] = quantize(valueEmbedding), produced upstream.
  void write(String key, Float32List valueVector) {
    final r = _role(key);
    for (var i = 0; i < d; i++) {
      _acc[i] = alpha * _acc[i] + r[i] * valueVector[i]; // bind + bundle + decay
    }
  }

  /// Reconstructive recall (unbind -> cleanup). [candidates] is the cleanup memory
  /// supplied by the RECALL layer (e.g. recent values from the episodic store) —
  /// the organ does NOT own an unbounded codebook. Returns `unsure` below [floor].
  BeliefDecode read(String key, Map<String, Float32List> candidates) {
    final r = _role(key);
    final est = Float32List(d);
    for (var i = 0; i < d; i++) {
      est[i] = (_acc[i] >= 0 ? 1.0 : -1.0) * r[i]; // unbind from sign(acc)
    }
    String? best;
    var bestCos = floor;
    candidates.forEach((label, cand) {
      var dot = 0.0;
      for (var i = 0; i < d; i++) dot += est[i] * cand[i];
      final cos = dot / d;
      if (cos > bestCos) { bestCos = cos; best = label; }
    });
    return BeliefDecode(best, best == null ? 0.0 : bestCos);
  }

  /// Persist as the float-accumulator BLOB (~4*d bytes; keeps decay across reloads).
  Uint8List toBytes() => _acc.buffer.asUint8List(0, d * 4);
  static BeliefState fromBytes(Uint8List bytes,
      {int d = 10000, double alpha = 0.95, double floor = 0.08}) {
    final bs = BeliefState(d: d, alpha: alpha, floor: floor);
    bs._acc.setAll(0, Float32List.view(Uint8List.fromList(bytes).buffer, 0, d));
    return bs;
  }

  /// Tiny-cache variant: 1 bit/dim sign BLOB (~d/8 bytes). Loses fine decay weight.
  Uint8List toSignBits() {
    final out = Uint8List((d + 7) >> 3);
    for (var i = 0; i < d; i++) {
      if (_acc[i] >= 0) out[i >> 3] |= (1 << (i & 7));
    }
    return out;
  }

  // --- deterministic splitmix64 role vectors (reproducible, never stored) ---
  Float32List _role(String key) {
    final v = Float32List(d);
    var s = _seed(key);
    for (var i = 0; i < d; i++) {
      s = _next(s);
      v[i] = (s & 1) == 0 ? 1.0 : -1.0;
    }
    return v;
  }
  int _seed(String key) {
    var h = 0xcbf29ce484222325;
    for (final c in key.codeUnits) {
      h ^= c; h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h;
  }
  int _next(int x) {
    x = (x + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF;
    var z = x;
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF;
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF;
    return (z ^ (z >> 31)) & 0xFFFFFFFFFFFFFFFF;
  }
}

// --- Example wiring (pseudocode, matches Cairn's seams) ---
// final belief = BeliefState.fromBytes(store.readBeliefBlob() ?? empty);
// // WRITE in chat_controller.sendMessage finally-block (where Solver.applyInline is):
// for (final fact in turnFacts) belief.write(fact.key, belief.quantize(fact.valueEmbedding));
// store.writeBeliefBlob(belief.toBytes());
// // READ at the recall seam (where remembering() builds the injected block):
// final d = belief.read('device', recentCandidatesFromEpisodicStore);
// final line = d.isUnsure ? 'device: (unsure)' : 'device: ${d.value}';
