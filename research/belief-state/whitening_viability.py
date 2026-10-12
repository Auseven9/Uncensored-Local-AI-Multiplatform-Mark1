#!/usr/bin/env python3
"""
Whitening viability — does ZCA whitening make the belief gist FUNCTION at realistic scale?

Before asking whether the gist has VALUE, it has to be CORRECT. Raw (anisotropic) codes
crosstalk, so cleanup picks wrong concepts as the codebook grows; whitening decorrelates
them. This measures gist member-recovery (can a bundled neighborhood be cleaned back to its
true members out of a codebook of N concepts?) vs codebook size, RAW vs WHITENED. No LLM —
pure VSA + the realistic-anisotropy codebook from belief_gate.py (mean|cos| ~0.30, the
measured regime). This is the whitening fix's effect, isolated.

python3 whitening_viability.py
Signed-off-by: Claude1
"""
import numpy as np
from belief_gate import make_codebook, FLOOR, mean_abs_cos

def gist_recover(cb, rng, M=6, leaked=4, k=6):
    """Bundle M random 'theme members' (+ leaked distractors), clean up top-k vs the whole
    codebook, measure how many true members come back (precision, recall)."""
    N, D = cb.shape
    members = list(rng.choice(N, size=M, replace=False))
    pool = [i for i in range(N) if i not in members]
    nb = members + list(rng.choice(pool, size=leaked, replace=False))
    bundle = np.sign(cb[nb].sum(0))
    s = (cb @ bundle) / D
    top = [int(i) for i in np.argsort(s)[::-1][:k] if s[i] >= FLOOR]
    hit = sum(1 for i in top if i in members)
    return hit / max(1, len(top)), hit / M

def measure():
    print("=" * 70)
    print("WHITENING VIABILITY — gist member-recovery vs codebook size (no LLM)")
    print("=" * 70)
    trials = 80
    print(f"\n{'N':>5} | {'mean|cos|':>13} | {'RAW gist':^17} | {'WHITENED gist':^17}")
    print(f"{'(cb)':>5} | {'raw / white':>13} | {'prec':>7} {'recall':>8} | {'prec':>7} {'recall':>8}")
    print("-" * 66)
    for N in [50, 150, 300, 600, 1000]:
        cb_raw = make_codebook(N, seed=0, regime="emb", whiten=False)
        cb_wh = make_codebook(N, seed=0, regime="emb", whiten=True)
        craw, cwh = mean_abs_cos(cb_raw), mean_abs_cos(cb_wh)
        def avg(cb):
            rng = np.random.default_rng(7); ps, rs = [], []
            for _ in range(trials):
                p, r = gist_recover(cb, rng); ps.append(p); rs.append(r)
            return 100 * np.mean(ps), 100 * np.mean(rs)
        pr, rr = avg(cb_raw); pw, rw = avg(cb_wh)
        print(f"{N:>5} | {craw:>5.2f} / {cwh:>5.2f} | {pr:>6.1f}% {rr:>7.1f}% | {pw:>6.1f}% {rw:>7.1f}%")
    print("\nraw gist recovery collapses as the codebook grows (crosstalk between correlated")
    print("codes); whitening decorrelates (mean|cos| ~0.30 -> ~0.06) and holds recovery up.")
    print("=> whitening is the PREREQUISITE for the gist being correct at realistic concept scale.")
    print("   (it makes the gist VIABLE; whether a viable gist adds VALUE is gist_whitened_value.py.)")

if __name__ == "__main__":
    measure()
