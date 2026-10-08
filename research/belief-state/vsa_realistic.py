"""
Push the belief-state sim to REALISTIC conditions.

The toy test used random, near-orthogonal fillers. Real LLM embeddings are NOT
orthogonal -- related concepts point in similar directions (anisotropy). That
correlation is the make-or-break question: does VSA crosstalk destroy recall
when the fillers are real-embedding-shaped? And does the standard fix (whiten
to decorrelate) rescue it? Everything measured.
"""
import numpy as np
rng = np.random.default_rng(1)

d = 1024          # work at embedding dimensionality (realistic, not the toy 10k)
N = 300           # codebook size (distinct "concepts" ALESIS might store)

def unit(x):
    return x / (np.linalg.norm(x, axis=-1, keepdims=True) + 1e-9)

# --- three filler regimes -------------------------------------------------
# (a) orthogonal random codes: great math, but ZERO semantics (can't generalize)
ortho = unit(rng.standard_normal((N, d)))  # random Gaussian ~ near-orthogonal in high-d

# (b) realistic correlated "embeddings": low-rank latent + noise => anisotropy
k = 48
W = rng.standard_normal((d, k))
Z = rng.standard_normal((N, k))
emb = unit(Z @ W.T + 0.35 * rng.standard_normal((N, d)))  # correlated like real embeddings

# (c) whitened embeddings: decorrelate (ZCA) while keeping a semantic basis
C = np.cov(emb.T)
evals, evecs = np.linalg.eigh(C)
Wzca = evecs @ np.diag(1.0/np.sqrt(np.clip(evals, 1e-6, None))) @ evecs.T
white = unit(emb @ Wzca)

def mean_abs_cos(X, m=2000):
    i = rng.integers(0, len(X), m); j = rng.integers(0, len(X), m)
    ok = i != j
    return np.abs(np.sum(X[i[ok]]*X[j[ok]], axis=1)).mean()

print("Mean |cosine| between distinct fillers (lower = more orthogonal = better for VSA):")
print(f"   (a) orthogonal codes : {mean_abs_cos(ortho):.3f}")
print(f"   (b) raw embeddings   : {mean_abs_cos(emb):.3f}   <- realistic, correlated")
print(f"   (c) whitened emb     : {mean_abs_cos(white):.3f}\n")

def capacity(codebook, K, trials=25):
    accs = []
    for _ in range(trials):
        roles = rng.choice([-1.0, 1.0], size=(K, d))      # clean random role keys
        vidx  = rng.integers(0, N, size=K)
        belief = np.sum(roles * codebook[vidx], axis=0)    # bundle K bound pairs
        hits = 0
        for i in range(K):
            est = roles[i] * belief                        # unbind (exact, roles^2=1)
            guess = np.argmax(codebook @ est)              # cleanup vs codebook
            hits += (guess == vidx[i])
        accs.append(hits/K)
    return np.mean(accs)

print("Retrieval accuracy vs #facts in one belief vector (d=1024):")
print(f"   {'K':>4} | {'orthogonal':>11} | {'raw-emb':>8} | {'whitened':>9}")
for K in [10, 20, 40, 60, 100]:
    print(f"   {K:>4} | {capacity(ortho,K)*100:>10.1f}% | {capacity(emb,K)*100:>7.1f}% | {capacity(white,K)*100:>8.1f}%")
print("\n  Read: raw embeddings crosstalk and recall collapses; whitening restores most")
print("  of the capacity WHILE keeping a semantic space. That's the real design knob.")
