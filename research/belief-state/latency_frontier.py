#!/usr/bin/env python3
"""
latency_frontier.py — is belief's footprint win LOAD-BEARING on the recall hot path?

Setting up the latency test forced an honest re-examination of the v12 footprint number,
and it does not survive it:

  v12 compared belief's BUNDLE (one D-bit vector) to the hot index. But a bundle is useless
  without the VALUE CODEBOOK you clean up against — the N per-fact codes. For EXACT recall of
  arbitrary facts those codes ARE the content (≈ the embeddings themselves). Count them and
  belief's footprint is ~N^2/c (quadratic), far LARGER than the linear index — not 480x
  smaller. The bundle alone being tiny is irrelevant: you can't decode it without the codebook.

So this file measures two honest things:
  [1] true resident footprint for exact recall (bundle + codebook) vs the index  -> v12 fixed
  [2] measured hot-path latency: belief as a fixed small cache vs a RAM / disk index

Caveat: x86 + Python/numpy. Absolute ms are NOT a Snapdragon/Dart number; read the SHAPE
(how cost scales with N) and the footprint accounting, not the milliseconds.

python3 latency_frontier.py
Signed-off-by: Claude1
"""
import numpy as np, time, os, tempfile
from statistics import median

C_REAL = 0.025                 # measured facts/dim at large D (v12 real regime, recall@1>=90%)
IDX_BYTES_PER_FACT = 384 * 4   # float32 MiniLM embedding kept hot for similarity recall

def med_ms(fn, trials=15):
    ts = []
    for _ in range(trials):
        t = time.perf_counter(); fn(); ts.append(time.perf_counter() - t)
    return median(ts) * 1e3

def human(b):
    for u in ("B", "KB", "MB", "GB", "TB"):
        if b < 1024 or u == "TB": return f"{b:,.1f}{u}"
        b /= 1024

def part1_footprint():
    print("=" * 84)
    print("[1] TRUE resident footprint for EXACT recall of N facts  (correction to Ark v12)")
    print("=" * 84)
    print("\n    the bundle is useless without the value codebook you clean up against.")
    print("    roles are free (regenerated from the key); the codebook is not.\n")
    print(f"    {'N':>10} | {'index(fp32)':>12} | {'bundle only':>12} | {'+codebook=needed':>17} | {'belief/index':>12}")
    print("    " + "-" * 76)
    for N in (1_000, 10_000, 100_000, 1_000_000):
        D = N / C_REAL
        bundle = D / 8
        codebook = N * D / 8           # N unique D-bit value codes, resident for cleanup
        total = bundle + codebook
        idx = N * IDX_BYTES_PER_FACT
        print(f"    {N:>10,} | {human(idx):>12} | {human(bundle):>12} | {human(total):>17} | {total/idx:>10.0f}x")
    print("\n    => with the codebook counted, belief exact-recall footprint is ~N^2/c — QUADRATIC,")
    print("       orders of magnitude LARGER than the linear index. v12's 480x counted the bundle")
    print("       alone and is WRONG for exact recall. VSA bundling is lossy and not a bit-compressor;")
    print("       you cannot beat the information floor for storing N independent facts.")

def part2_latency():
    print("\n" + "=" * 84)
    print("[2] MEASURED hot-path latency  (x86/Python/numpy — read SHAPE, not device-ms)")
    print("=" * 84)
    rng = np.random.default_rng(0)
    D, W = 8192, 200                                   # belief as a FIXED small L1 cache (~capacity facts)
    roles = rng.choice([-1., 1.], size=(W, D)); vals = rng.choice([-1., 1.], size=(W, D))
    mem = (roles * vals).sum(0)
    def belief_q(): est = roles[7] * mem; return int(np.argmax(vals @ est))
    bl = med_ms(belief_q)
    belief_ram = (1 + W) * D / 8                        # bundle + resident codebook
    cache200 = W * IDX_BYTES_PER_FACT                   # alternative: just cache W embeddings
    print(f"\n    belief fixed L1 cache: D={D}, {W} facts, {human(belief_ram)} RAM  ->  {bl:.3f} ms/query")
    print(f"    (vs just caching {W} embeddings directly: {human(cache200)} — SAME ORDER, no footprint win)\n")
    print(f"    {'N facts':>10} | {'RAM index brute':>16} | {'disk mmap brute (warm)':>23}")
    print("    " + "-" * 56)
    tmp = tempfile.mkdtemp()
    for N in (1_000, 10_000, 100_000):
        emb = rng.standard_normal((N, 384)).astype('float32'); emb /= np.linalg.norm(emb, axis=1, keepdims=True) + 1e-9
        q = emb[11].copy()
        rr = med_ms(lambda: int(np.argmax(emb @ q)))
        path = os.path.join(tmp, f"idx{N}.f32"); emb.tofile(path)
        mm = np.memmap(path, dtype='float32', mode='r', shape=(N, 384)); _ = mm[0, 0]  # warm the cache
        dd = med_ms(lambda: int(np.argmax(mm @ q)))
        print(f"    {N:>10,} | {rr:>13.3f} ms | {dd:>20.3f} ms")
        del mm; os.remove(path)
    os.rmdir(tmp)
    print(f"\n    belief L1 is fast (~{bl:.3f} ms) but covers only ~{W} recent facts; arbitrary recall")
    print("    still hits the index. brute index is O(N); a real ANN index (HNSW/IVF, not measured)")
    print("    is ~log(N) and would stay sub-ms well past 1M — so the DISK index is not the")
    print("    bottleneck belief was supposed to rescue. warm mmap ≈ RAM speed (page cache), i.e.")
    print("    a 'disk' index still consumes RAM when hot — which is the budget belief claimed to save.")

def verdict():
    print("\n" + "=" * 84)
    print("VERDICT (honest, and it corrects v12):")
    print("=" * 84)
    print(" - EXACT recall: belief has NO footprint win once the codebook is counted (quadratic),")
    print("   and NO latency win vs a proper ANN index. As a fixed L1 cache it costs ~the same RAM")
    print("   as just caching that many embeddings. The 480x was an artifact of ignoring the codebook.")
    print(" - belief's REAL potential edges are NOT storage or recall: fixed-shape all-elementwise")
    print("   math (SIMD/NPU-friendly, no gather/sort), holographic query without an index, and")
    print("   graceful degradation. Those are COMPUTE-ARCHITECTURE properties — device-specific,")
    print("   and NOT measurable on x86/Python here. That is the only honest door still open.")

if __name__ == "__main__":
    part1_footprint(); part2_latency(); verdict()
