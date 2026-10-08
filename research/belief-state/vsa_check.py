"""
Does VSA belief-state memory actually check out? A from-scratch validation.
MAP architecture: bipolar hypervectors, bind = elementwise product, bundle = sign of sum.
No libraries beyond numpy. Everything measured, nothing asserted.
"""
import numpy as np
rng = np.random.default_rng(0)

D = 10000  # hypervector dimension (one belief-state vector = D trits ~ 1.25 KB packed)

def rand_hv(n=1):
    return rng.choice(np.array([-1, 1], dtype=np.int8), size=(n, D))

# ---------- 1. Near-orthogonality: the "blessing of dimensionality" ----------
A = rand_hv(1000).astype(np.int32)   # widen: int8 dot of D=10000 would overflow
sims = (A @ A[0]) / D
offdiag = sims[1:]
print("1) Random hypervectors are near-orthogonal")
print(f"   cos(random, random): mean={offdiag.mean():+.4f}  std={offdiag.std():.4f}  (1/sqrt(D)={1/np.sqrt(D):.4f})")
print(f"   self-similarity: {sims[0]:.4f}\n")

# ---------- 2. Binding is invertible and loss-free (MAP) ----------
a, b = rand_hv(1).astype(np.int32), rand_hv(1).astype(np.int32)
bound = a * b                 # bind role a to filler b
recovered = bound * a         # unbind with a  (a*a = 1 elementwise)
print("2) Binding/unbinding is exact")
print(f"   cos(unbind(bind(a,b), a), b) = {(recovered @ b.T)[0,0]/D:.4f}\n")

# ---------- 3. Bundling capacity: how many facts fit in ONE vector? ----------
# Store K key->value pairs in a single belief vector, then try to read each back.
def capacity_trial(K, codebook_size=200, trials=30):
    accs = []
    for _ in range(trials):
        keys   = rand_hv(K)
        vocab  = rand_hv(codebook_size)          # cleanup memory of possible values
        vidx   = rng.integers(0, codebook_size, size=K)
        vals   = vocab[vidx]
        belief = np.sign(np.sum(keys * vals, axis=0))  # bundle all bound pairs -> 1 vector
        belief[belief == 0] = 1
        # read each key back
        hits = 0
        for i in range(K):
            est  = belief * keys[i]              # unbind
            guess = np.argmax(vocab @ est)       # cleanup: nearest codebook entry
            hits += (guess == vidx[i])
        accs.append(hits / K)
    return np.mean(accs)

print("3) Capacity of ONE belief vector (D=10000), retrieval accuracy vs #facts stored:")
for K in [10, 20, 40, 60, 80, 120, 160, 240]:
    print(f"   {K:3d} facts bundled -> {capacity_trial(K)*100:5.1f}% recalled")
print()

# ---------- 4. The forgetting curve: decayed streaming belief state ----------
# belief_t = normalize(alpha*belief_{t-1} + key_t (x) value_t).  Then read back by age.
def forgetting_curve(T=60, alpha=0.9, codebook_size=200, trials=40):
    by_age = np.zeros(T)
    for _ in range(trials):
        vocab = rand_hv(codebook_size)
        keys  = rand_hv(T)
        vidx  = rng.integers(0, codebook_size, size=T)
        belief = np.zeros(D)
        for t in range(T):
            belief = alpha*belief + (keys[t]*vocab[vidx[t]]).astype(float)
            belief /= (np.linalg.norm(belief)/np.sqrt(D))  # renormalize
        for t in range(T):
            est = belief * keys[t]
            guess = np.argmax(vocab @ est)
            by_age[T-1-t] += (guess == vidx[t])  # age 0 = most recent
    return by_age/trials

for alpha in [0.90, 0.97]:
    print(f"4) Forgetting curve (alpha={alpha}): recall accuracy by how many turns ago:")
    curve = forgetting_curve(alpha=alpha)
    for age in [0,1,2,3,5,8,12,20,30,45,59]:
        bar = "#"*int(curve[age]*30)
        print(f"   {age:2d} turns ago -> {curve[age]*100:5.1f}%  {bar}")
    print()
print("   (recent = sharp, old = faded. the memory horizon IS the alpha knob.)")
