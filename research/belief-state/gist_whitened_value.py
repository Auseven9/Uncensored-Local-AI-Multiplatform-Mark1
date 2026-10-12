#!/usr/bin/env python3
"""
Whitened gist VALUE re-run — fold the whitening fix into the gist-vs-recall value test.

gist_vs_recall.py showed a weak, confounded signal for the RAW gist on a tiny codebook.
This adds the whitening fix and a THIRD condition so we can separate "does the gist help"
from "does whitening make it help" — all three share the IDENTICAL recall+graph underneath:

  A = recall+graph
  B = recall+graph + gist (RAW, as in gist_vs_recall.py)
  C = recall+graph + gist (ZCA-WHITENED embeddings -> near-orthogonal hypervectors)

The codebook of decoy concepts is scaled up (`n_decoy_concepts`) so cleanup is stressed —
the regime where raw crosstalk makes the gist mislabel and whitening should rescue it.

RUN
  Conclusive (Colab/GPU):  !pip -q install transformers accelerate torch sentence-transformers
                           from gist_whitened_value import run_whitened ; run_whitened(real=True, n_decoy_concepts=300)
  Plumbing check (no LLM): python3 gist_whitened_value.py --selftest

Signed-off-by: Claude1
"""
import sys, random
import numpy as np
import gist_vs_recall as g                      # reuse the EXACT recall+graph, reader, classify, corpus

def fit_zca(embs, eps=1e-3):
    """ZCA whitening matrix W = C^(-1/2) from a corpus of embeddings (decorrelate, keep basis)."""
    C = np.cov(embs.T); ev, V = np.linalg.eigh(C)
    return V @ np.diag(1.0 / np.sqrt(np.clip(ev, eps, None))) @ V.T

class WhitenedGist:
    """Gist label with embeddings whitened BEFORE the random projection to hyperdim.
    Both the neighborhood bundle and the concept codebook use the same W, so cleanup is fair."""
    def __init__(self, emb, concept_texts):
        self.emb = emb; self.labels = concept_texts; self.P = emb.P
        cvec = emb.vec(concept_texts)
        self.W = fit_zca(cvec)
        self.cb = np.sign((cvec @ self.W) @ self.P)          # whitened concept codebook
    def label(self, hood, facts):
        byid = {f.id: f for f in facts}; texts = [byid[i].text for i in hood]
        if not texts: return None
        hv = np.sign((self.emb.vec(texts) @ self.W) @ self.P)
        belief = np.sign(hv.sum(0))
        s = (self.cb @ belief) / belief.shape[0]; j = int(np.argmax(s))
        return self.labels[j] if s[j] >= g.FLOOR else None

def build_scaled(R, emb, n_distractor_facts, n_decoy_concepts):
    """Same corpus shape as gist_vs_recall.build_corpus, but the cleanup concept codebook is
    grown to n_decoy_concepts decoys (stresses cleanup — where whitening should matter)."""
    facts = []; i = 0
    concepts = [t[1] for t in g.THEMES] + [f"unrelated topic {j}" for j in range(n_decoy_concepts)]
    for key, label, members, _ in g.THEMES:
        for m in members:
            ents = {w for w in g._n(m).split() if len(w) > 3}
            facts.append(g.Fact(i, m, ents, sal=R.uniform(.4, .9), age=R.uniform(1, 120))); i += 1
    for _ in range(n_distractor_facts):
        topic = R.randint(0, 999); m = f"random note about topic {topic} item {R.randint(0, 999)}"
        facts.append(g.Fact(i, m, {f"topic{topic}"}, sal=R.uniform(.1, .6), age=R.uniform(1, 200))); i += 1
    return facts, concepts

def run_whitened(real=False, seed=0, distractors=(0, 120, 400), n_decoy_concepts=300):
    rng = np.random.default_rng(seed); emb = g.Embedder(real, rng); reader = g.Reader(real); R = random.Random(seed)
    print(f"\n===== WHITENED GIST vs RECALL (real={real}, decoy_concepts={n_decoy_concepts}, seed={seed}) =====")
    print("c/f/a = % correct/fabricate/abstain")
    for nd in distractors:
        facts, concepts = build_scaled(R, emb, nd, n_decoy_concepts)
        G = g.RecallGraph(emb, facts)
        cb_raw = emb.hyper(concepts)                         # B: raw concept codebook
        wg = WhitenedGist(emb, concepts) if real else None   # C: whitened (needs emb.P => real only)
        agg = {m: dict(correct=0, fabricate=0, abstain=0) for m in ("A_recall", "B_gist_raw", "C_gist_white")}
        nq = 0
        for key, label, members, qs in g.THEMES:
            for q, gold, syn, dis in qs:
                nq += 1
                got, hood = G.recall(q); cA = g.ctx(got)
                glB = g.gist_label(emb, hood, facts, cb_raw, concepts)
                glC = wg.label(hood, facts) if wg else glB
                cB = cA + (f"\n\nOverall pattern: {glB}" if glB else "")
                cC = cA + (f"\n\nOverall pattern: {glC}" if glC else "")
                agg["A_recall"][g.classify(reader.ask(cA, q, gold=gold, distractors=dis), gold, dis, syn)] += 1
                agg["B_gist_raw"][g.classify(reader.ask(cB, q, gold=gold, distractors=dis), gold, dis, syn)] += 1
                agg["C_gist_white"][g.classify(reader.ask(cC, q, gold=gold, distractors=dis), gold, dis, syn)] += 1
        print(f"\n-- {nd} distractor facts, {n_decoy_concepts} decoy concepts ({nq} synthesis Qs) --")
        for m in agg:
            d = agg[m]; t = sum(d.values()) or 1
            print(f"   {m:14} {100*d['correct']/t:3.0f}c {100*d['fabricate']/t:3.0f}f {100*d['abstain']/t:3.0f}a")
    print("\nWIN for the whitening fix: C > B (whitening makes the gist label correct, so it helps")
    print("instead of perturbing); and C > A means the whitened gist beats recall+graph. If C == B")
    print("== A, the gist does not earn wiring even whitened — honest either way.")

if __name__ == "__main__":
    run_whitened(real=("--selftest" not in sys.argv))
