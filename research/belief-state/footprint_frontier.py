#!/usr/bin/env python3
"""
Footprint frontier — belief's REAL reason to exist on-device: constant-ish RAM at scale.

The value test killed the "gist beats recall+graph on answer quality" thesis. This tests the
thesis belief was actually BORN for: on a phone, the exact Archive lives on disk regardless,
so belief doesn't compete with it — it competes with the RAM-RESIDENT HOT INDEX (the N
embeddings you must keep live to do fast similarity recall), which grows LINEARLY in N.
Belief is a fixed-width hypervector that superimposes everything.

We measure the VSA capacity law empirically (how many facts fit per dimension at >=90%
exact recall@1), then compute the footprint each representation needs at device scale.

  hot index  : N facts x 384-dim float32 embeddings resident = 1536 bytes/fact (linear)
  belief      : D bits packed; capacity ~ c*D facts  =>  D = N/c  =>  1/(8c) bytes/fact

Mechanism matches belief_state.dart: sign-quantized +-1 codes, bind=multiply, bundle=sum,
recall=unbind+cleanup (argmax over the value codebook). Two regimes bound the answer:
  ortho  = random +-1 value codes (best-case capacity ceiling)
  real   = anisotropic low-rank+noise codes (real-embedding floor; what we actually measured)

python3 footprint_frontier.py
Signed-off-by: Claude1
"""
import numpy as np

EMB_DIM_INDEX = 384           # MiniLM dim the hot index would store, float32
TARGET = 0.90                 # fidelity bar: exact recall@1

def make_values(V, D, rng, regime):
    if regime == "ortho":
        return rng.choice([-1.0, 1.0], size=(V, D))
    k = 4                                                   # low-rank latent -> anisotropy
    W = rng.standard_normal((64, k)); Z = rng.standard_normal((V, k))
    emb = Z @ W.T + 0.05 * rng.standard_normal((V, 64))
    emb /= np.linalg.norm(emb, axis=1, keepdims=True) + 1e-9
    P = rng.standard_normal((64, D)) / np.sqrt(64)
    return np.sign(emb @ P)

def recall_at1(N, D, regime, rng, nq=60):
    """Store N distinct key->value facts in one D-dim belief vector; measure exact recall@1."""
    values = make_values(N, D, rng, regime)                # N distinct value codes (= codebook)
    roles = rng.choice([-1.0, 1.0], size=(N, D))           # N random key roles
    mem = (roles * values).sum(0)                          # bundle all facts
    idx = rng.choice(N, size=min(nq, N), replace=False)
    hits = 0
    for i in idx:
        est = roles[i] * mem                               # unbind key i
        if int(np.argmax(values @ est)) == i: hits += 1    # cleanup vs codebook
    return hits / len(idx)

def capacity(D, regime, rng):
    """Largest N with recall@1 >= TARGET (grid search over N ~ fractions of D)."""
    best = 0
    for frac in (0.004, 0.008, 0.012, 0.016, 0.02, 0.025, 0.03, 0.04, 0.05, 0.07):
        N = max(2, int(D * frac))
        if recall_at1(N, D, regime, np.random.default_rng(rng.integers(1 << 30))) >= TARGET:
            best = N
        else:
            break
    return best

def human(b):
    for u in ("B", "KB", "MB", "GB"):
        if b < 1024 or u == "GB": return f"{b:.1f}{u}"
        b /= 1024

def main():
    print("=" * 74)
    print("FOOTPRINT FRONTIER — belief (fixed-width) vs hot embedding index (linear)")
    print("=" * 74)
    rng = np.random.default_rng(0)

    print(f"\n[1] measured VSA capacity law (exact recall@1 >= {TARGET:.0%})\n")
    print(f"    {'D':>6} | {'ortho N':>9} {'c=N/D':>8} | {'real N':>8} {'c=N/D':>8}")
    print("    " + "-" * 44)
    cs = {"ortho": [], "real": []}
    for D in (256, 512, 1024, 2048, 4096, 8192):
        co = capacity(D, "ortho", rng); cr = capacity(D, "real", rng)
        cs["ortho"].append(co / D); cs["real"].append(cr / D)
        print(f"    {D:>6} | {co:>9} {co/D:>8.4f} | {cr:>8} {cr/D:>8.4f}")
    c_ortho = float(np.median(cs["ortho"])); c_real = float(np.median(cs["real"]))
    print(f"\n    capacity constant c (facts/dim):  ortho ~{c_ortho:.4f}   real ~{c_real:.4f}")
    print(f"    => belief bytes/fact (1 bit/dim):  ortho ~{1/(8*c_ortho):.1f}   real ~{1/(8*c_real):.1f}")
    print(f"       hot index bytes/fact (fp32):    {EMB_DIM_INDEX*4} (int8-quantized: {EMB_DIM_INDEX})")

    print(f"\n[2] footprint at device scale (belief D scaled to hold N at >={TARGET:.0%} recall)\n")
    print(f"    {'N facts':>9} | {'hot index fp32':>15} | {'belief (ortho)':>15} | {'belief (real)':>14} | {'win vs fp32':>12}")
    print("    " + "-" * 76)
    for N in (1_000, 10_000, 100_000, 1_000_000):
        idx_b = N * EMB_DIM_INDEX * 4
        bo = (N / c_ortho) / 8                              # bits -> bytes, 1 bit/dim packed
        br = (N / c_real) / 8
        print(f"    {N:>9,} | {human(idx_b):>15} | {human(bo):>15} | {human(br):>14} | {idx_b/br:>10.0f}x")

    print("\nread:")
    print(" - belief footprint DOES grow with N (D must scale to hold capacity) — it is NOT O(1).")
    print(" - but at ~1 bit/dim it is ~2-3 orders smaller PER FACT than a float32 hot index, so the")
    print("   RAM-resident recall index is MBs where the exact store is on disk and belief is tiny.")
    print(" - anisotropy (real) costs capacity vs ortho; that gap is what whitening would recover")
    print("   (naive ZCA did not — see Ark v11; a regularized whitening is the open lever).")
    print(" - fidelity here is exact recall@1>=90%; WITH the gate, sub-90% belief still works as a")
    print("   cheap candidate generator (Archive corrects misses), so the real budget can be smaller.")
    print(" - honest scope: this is footprint vs a RAM hot index, NOT belief replacing the Archive.")

if __name__ == "__main__":
    main()
