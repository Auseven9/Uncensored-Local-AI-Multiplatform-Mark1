"""
Vector's objection 2, measured: how fast does VSA capacity collapse when you
ask for STRUCTURE (nested records) instead of a flat bag of facts?
Also settles Cairn's size nit: what each representation actually costs.
"""
import numpy as np
rng = np.random.default_rng(7)
D = 10000
def hv(n): return rng.choice([-1.0, 1.0], size=(n, D))   # bipolar

# ---- FLAT: K atoms, ONE unbind to recall ----
def flat_acc(K, N=200, trials=15):
    acc = []
    for _ in range(trials):
        keys, cb = hv(K), hv(N)
        idx = rng.integers(0, N, K)
        belief = np.sign((keys * cb[idx]).sum(0))
        hits = sum(np.argmax(cb @ (belief * keys[i])) == idx[i] for i in range(K))
        acc.append(hits / K)
    return np.mean(acc)

# ---- NESTED: K records, each a 3-field bundle; recall needs TWO unbinds ----
# belief = Σ ID_i (x) Record_i ,  Record_i = Σ_f FIELD_f (x) value   (compounds noise)
def nested_acc(K, N=200, trials=15):
    fields = hv(3)                       # NAME, ROLE, LOC role keys
    acc = []
    for _ in range(trials):
        cb = hv(N)
        ids = hv(K)
        vidx = rng.integers(0, N, (K, 3))
        belief = np.zeros(D)
        for i in range(K):
            rec = np.sign((fields * cb[vidx[i]]).sum(0))   # one record vector (3 atoms)
            belief += ids[i] * rec
        belief = np.sign(belief)
        hits = tot = 0
        for i in range(K):
            rec_est = belief * ids[i]                       # unbind 1: get noisy record
            for f in range(3):
                val_est = rec_est * fields[f]               # unbind 2: get noisy value
                hits += np.argmax(cb @ val_est) == vidx[i, f]
                tot += 1
        acc.append(hits / tot)
    return np.mean(acc)

print("Capacity vs STRUCTURE (D=10000). Flat = 1 unbind; Nested records = 2 unbinds:\n")
print(f"   {'records/facts K':>16} | {'FLAT (1 unbind)':>16} | {'NESTED (2 unbind)':>18}")
for K in [10, 20, 40, 60, 100]:
    print(f"   {K:>16} | {flat_acc(K)*100:>15.1f}% | {nested_acc(K)*100:>17.1f}%")
print("\n  -> Vector was right: one level of nesting (relations/records) collapses")
print("     capacity hard. A flat bag is cheap; structure compounds noise per level.\n")

# ---- Cairn's size nit: what each representation costs for ONE vector ----
print("Representation size for ONE belief vector (D=10000):")
print(f"   binary (1 bit/dim, XOR bind) : {D/8/1024:6.2f} KB   <- the '1.25KB' claim")
print(f"   bipolar int8 (MAP)           : {D/1024:6.2f} KB")
print(f"   real float32 (FHRR/HRR)      : {4*D/1024:6.2f} KB   <- if fillers are real embeddings")
print("   -> Cairn is right: 1.25KB is the BINARY scheme. Real-valued fillers = ~40KB.")
print("      Decision: use binary/bipolar VSA with embeddings quantized to signs,")
print("      OR accept ~40KB FHRR. 40KB is still nothing on a phone -- but name it.")
