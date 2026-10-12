#!/usr/bin/env python3
"""
BELIEF GATE — make the fabricating organ fail-safe by grounding it on the Archive.

THE THESIS (Build ③, safety half).
  STATE_OF_BELIEF measured the hard truth: the VSA belief organ is a GIST organ, not a
  memory. Past capacity (~D/41, i.e. ~150-200 facts at D=8192) it FABRICATES 27-40% of
  recalls and — the dangerous part — it does NOT fail safe: it returns a confident wrong
  answer with no signal that it made one up.

  CORTEX's architecture says exactly how to use an organ like that: a cheap, powerful,
  UNTRUSTWORTHY proposer is safe the moment a sound, cheap verifier sits in front of it.
  Belief IS that proposer. The Archive — "the half that cannot lie" (the exact hash-chain
  store) — is the oracle. The grounding gate is the verifier.

  So the marriage is not additive, it is CORRECTIVE:
    • Belief proposes a recall / a gist (fast, associative, System-1).
    • The gate grounds every claim against the Archive.
        - matches Archive            -> PASS (verified recall)
        - contradicts Archive        -> FAIL  -> fabrication CAUGHT, corrected to Archive truth
        - absent from Archive        -> ABSTAIN ("not in memory") — never asserted
  The claim this file PROVES or KILLS, measured: with the gate, Belief's confident-wrong
  rate collapses to ~0 (false-pass == 0) even as its RAW fabrication climbs past 30-40%,
  and synthesis survives as grounded-and-labelled rather than discarded.

RELATION TO gist_vs_recall.py:
  that file measures Belief's VALUE  (does the gist beat recall+graph on synthesis?).
  THIS file measures Belief's SAFETY (can its fabrication be made unable to leak?).
  Safety is what unblocks wiring Belief near the remembering() seam regardless of the
  value verdict — a fabricating organ you cannot trust should not touch lib/ until it is
  provably fail-safe. Conventions (D=8192, +/-1 roles, bind=product, bundle=sum, cleanup
  argmax(codebook@est), FLOOR, correct/fabricate/abstain) match vsa_realistic.py and
  gist_vs_recall.py so the result is comparable to the existing arena.

RUN:
  python3 belief_gate.py --test      # soundness: the gate NEVER false-passes a fabrication
  python3 belief_gate.py --measure   # the two-track measurement (recall safety + synthesis honesty)
  python3 belief_gate.py --demo      # readable walk-through on the japan/kitchen/race corpus

Signed-off-by: Claude1   (research prototype; research/ only — does not touch lib/ or the Archive)
"""
import sys
import numpy as np

D = 8192          # hypervector width (matches gist_vs_recall.py; capacity ~ D/41 ~ 200 facts)
FLOOR = 0.045     # cleanup confidence floor (matches gist_vs_recall.py)

# ════════════════════════════ verdict primitives (mirror CORTEX bank) ═══════
PASS, FAIL, ABSTAIN = "PASS", "FAIL", "ABSTAIN"
class Check:
    __slots__ = ("status", "exact", "name", "detail")
    def __init__(self, status, exact, name, detail=None):
        self.status, self.exact, self.name, self.detail = status, exact, name, detail

# ════════════════════════════ the value codebook (REALISTIC, correlated) ════
def make_codebook(n, seed=0, regime="emb", whiten=False, emb_dim=64, rank=4, noise=0.05):
    """n concept hypervectors in {-1,+1}^D. 'emb' = correlated like real embeddings
    (anisotropic -> crosstalk -> the measured fabrication); 'ortho' = easy random codes.
    Defaults (rank=4, noise=0.05) give mean|cos|~0.30 — real-embedding-shaped — and
    reproduce the measured 27-40% fabrication past ~150-200 facts. whiten=True applies the
    ZCA fix from vsa_realistic.py (decorrelate, keep semantics)."""
    rng = np.random.default_rng(seed)
    if regime == "ortho":
        emb = rng.standard_normal((n, emb_dim))
    else:                                              # low-rank latent + noise = anisotropy
        W = rng.standard_normal((emb_dim, rank)); Z = rng.standard_normal((n, rank))
        emb = Z @ W.T + noise * rng.standard_normal((n, emb_dim))
    emb = emb / (np.linalg.norm(emb, axis=1, keepdims=True) + 1e-9)
    if whiten:
        C = np.cov(emb.T); ev, V = np.linalg.eigh(C)
        emb = emb @ (V @ np.diag(1.0 / np.sqrt(np.clip(ev, 1e-6, None))) @ V.T)
        emb = emb / (np.linalg.norm(emb, axis=1, keepdims=True) + 1e-9)
    P = rng.standard_normal((emb_dim, D)) / np.sqrt(emb_dim)   # random projection to hyperdim
    return np.sign(emb @ P)                                    # {-1,+1}^(n x D)

def mean_abs_cos(cb, m=3000, seed=9):
    """mean |cosine| between distinct codes — the anisotropy knob (cf. vsa_realistic.py)."""
    rng = np.random.default_rng(seed); i = rng.integers(0, len(cb), m); j = rng.integers(0, len(cb), m); ok = i != j
    return float(np.abs((cb[i[ok]] * cb[j[ok]]).sum(1) / cb.shape[1]).mean())

# ════════════════════════════ Belief: the VSA gist organ (the proposer) ═════
class Belief:
    """Authentic VSA store. remember bundles bind(role,value) into one superposition; recall
    unbinds and cleans up against the codebook. Past capacity the superposition saturates and
    cleanup returns the WRONG concept — confidently. This is the organ that cannot fail safe."""
    def __init__(self, codebook, seed=1):
        self.cb = codebook; self.D = codebook.shape[1]; self.rng = np.random.default_rng(seed)
        self.mem = np.zeros(self.D)                 # key-bound superposition (for recall)
        self.roles = {}                             # key -> role hypervector
    def _role(self, key):
        if key not in self.roles: self.roles[key] = self.rng.choice([-1.0, 1.0], size=self.D)
        return self.roles[key]
    def remember(self, key, vidx, topic=None):      # topic is recorded by the Archive, not Belief
        self.mem += self._role(key) * self.cb[vidx]
    def recall(self, key):
        """-> (value_index, confidence, margin). Fabricates past capacity, with no safe signal."""
        est = self._role(key) * self.mem            # unbind (role^2 = 1) -> value + crosstalk
        s = (self.cb @ est) / self.D
        order = np.argsort(s)[::-1]
        return int(order[0]), float(s[order[0]]), float(s[order[0]] - s[order[1]])
    def gist_over(self, neighborhood, k=6):
        """Whole-picture gist of a RETRIEVED neighborhood — the app's real mechanism
        (gist_vs_recall.py gist_label): bundle the neighborhood, clean up vs the codebook.
        Fabricates when a leaked/correlated concept out-scores a true member."""
        nb = list(neighborhood)
        if not nb: return []
        bundle = np.sign(self.cb[nb].sum(0))
        s = (self.cb @ bundle) / self.D
        return [(int(i), float(s[i])) for i in np.argsort(s)[::-1][:k] if s[i] >= FLOOR]

# ════════════════════════════ Archive: the exact store (the oracle) ═════════
class Archive:
    """The half that cannot lie — exact key->value, plus topic membership. In the app this is
    the hash-chain archive_table; here a dict. The gate consults it to ground every Belief claim."""
    def __init__(self):
        self.kv = {}; self.topics = {}
    def remember(self, key, vidx, topic=None):
        self.kv[key] = vidx
        if topic is not None: self.topics.setdefault(topic, set()).add(vidx)
    def get(self, key): return self.kv.get(key)
    def members(self, topic): return self.topics.get(topic, set())

# ════════════════════════════ the gate: ground Belief on the Archive ════════
class BeliefGate:
    """Belief proposes; the Archive grounds. A fabrication can never leave as a confident answer:
    it is corrected to Archive truth (FAIL caught) or declared not-in-memory (ABSTAIN)."""
    def __init__(self, belief, archive): self.b, self.a = belief, archive
    def recall(self, key):
        vidx, conf, margin = self.b.recall(key)
        truth = self.a.get(key)
        if truth is None:
            return None, Check(ABSTAIN, False, "archive-grounding", "not in memory"), "abstain"
        if vidx == truth:
            return truth, Check(PASS, True, "archive-grounding", f"belief agrees (conf {conf:.2f})"), "belief"
        return truth, Check(FAIL, True, "archive-grounding",
                            f"belief said {vidx}, archive says {truth} — fabrication corrected"), "corrected"
    def synthesize(self, topic, neighborhood, k=6):
        """Groundedness filter: every gist claim from the retrieved neighborhood must trace to an
        Archive topic member. Ungrounded claims are STRIPPED (fabrication); survivors are labelled."""
        members = self.a.members(topic)
        grounded, stripped = [], []
        for vidx, score in self.b.gist_over(neighborhood, k=k):
            (grounded if vidx in members else stripped).append(vidx)
        return grounded, stripped

# ════════════════════════════ the measurement ═══════════════════════════════
def measure(regime="emb", seed=0):
    print("=" * 76)
    print(f"BELIEF GATE — measured (D={D}, codebook regime='{regime}')")
    print("=" * 76)
    rng = np.random.default_rng(seed); N = 600; cb = make_codebook(N, seed=seed, regime=regime)
    print(f"codebook anisotropy: mean|cos| = {mean_abs_cos(cb):.3f}  (real-embedding-shaped; "
          f"higher = more crosstalk = more fabrication)")

    # ---- Track 1: RECALL SAFETY — does the gate stop fabrication from leaking? ----
    print("\n[1] RECALL SAFETY  —  store K facts, recall them back\n")
    print(f"    {'K':>4} | {'belief raw':^21} | {'belief + GATE':^31}")
    print(f"    {'':>4} | {'correct':>9} {'FABRICATE':>10} | {'correct':>9} {'leak(false-pass)':>16} {'':>2}")
    print("    " + "-" * 60)
    for K in [25, 50, 100, 150, 200, 300, 450, 600]:
        b = Belief(cb, seed=seed + 1); a = Archive()
        vals = rng.choice(N, size=K, replace=False)
        for i, v in enumerate(vals):
            b.remember(f"k{i}", int(v)); a.remember(f"k{i}", int(v))
        raw_ok = raw_fab = g_ok = g_leak = 0
        for i, v in enumerate(vals):
            rv, _, _ = b.recall(f"k{i}")
            raw_ok += (rv == v); raw_fab += (rv != v)
            gv, chk, _ = BeliefGate(b, a).recall(f"k{i}")
            g_ok += (gv == v)
            g_leak += (chk.status == PASS and gv != v)   # a fabrication wrongly blessed as correct
        print(f"    {K:>4} | {100*raw_ok/K:>8.1f}% {100*raw_fab/K:>9.1f}% | "
              f"{100*g_ok/K:>8.1f}% {100*g_leak/K:>15.1f}%")
    print("\n    raw belief fabricates more as it saturates; the gate corrects every one to")
    print("    Archive truth. false-pass stays 0: a fabrication provably cannot leak as truth.")

    # ---- Track 2: SYNTHESIS HONESTY — does the gate keep the gist truthful? ----
    print("\n[2] SYNTHESIS HONESTY  —  gist of a retrieved neighborhood (6 true members +")
    print("    leaked distractors). WHITENED regime: gist cleanup is only viable here — in the raw")
    print("    regime above, cleanup collapses (even a clean neighborhood misreads), so synthesis")
    print("    REQUIRES the whitening fix. The gate stays safe in BOTH; here it also does real work.\n")
    print(f"    {'leaked':>6} | {'belief raw gist':^21} | {'belief + GATE':^21}")
    print(f"    {'into nb':>7} | {'precision':>9} {'recall':>9} | {'precision':>9} {'recall':>9}")
    print("    " + "-" * 52)
    M = 6; members = list(range(M))
    cbw = make_codebook(N, seed=seed, regime=regime, whiten=True)   # whitened = viable gist regime
    a2 = Archive(); b2 = Belief(cbw, seed=seed + 2)
    for v in members: a2.remember(f"t{v}", v, topic="T"); b2.remember(f"t{v}", v)
    for leaked in [0, 2, 5, 10, 20]:
        nb = members + [int(rng.integers(M, N)) for _ in range(leaked)]   # recall-leaked distractors
        raw = [v for v, _ in b2.gist_over(nb, k=M)]
        raw_true = sum(1 for v in raw if v in members)
        raw_prec = raw_true / (len(raw) or 1); raw_rec = raw_true / M
        grounded, stripped = BeliefGate(b2, a2).synthesize("T", nb, k=M)
        g_rec = len(grounded) / M                      # grounded ⊆ members by construction → precision 1.0
        print(f"    {leaked:>6}  | {100*raw_prec:>8.1f}% {100*raw_rec:>8.1f}% | "
              f"{100.0:>8.1f}% {100*g_rec:>8.1f}%")
    print("\n    the gate strips every ungrounded (leaked/fabricated) gist claim -> precision 1.0.")
    print("    honest cost: it cannot recover a true member the gist failed to surface (recall")
    print("    unchanged). the gate makes the gist HONEST, not OMNISCIENT — whether the gist is")
    print("    VALUABLE (good recall vs recall+graph) is gist_vs_recall.py's question, not this one's.")

    # ---- the capacity knob, for context (does not change the safety guarantee) ----
    print("\n[3] the whitening fix reduces how MUCH there is to catch (safety holds regardless)\n")
    for reg, wh in [("emb", False), ("emb", True)]:
        cb2 = make_codebook(N, seed=seed, regime=reg, whiten=wh)
        b = Belief(cb2, seed=seed + 3); vals = rng.choice(N, size=200, replace=False)
        for i, v in enumerate(vals): b.remember(f"k{i}", int(v))
        fab = sum(1 for i, v in enumerate(vals) if b.recall(f"k{i}")[0] != v)
        tag = "raw embeddings" + ("  + ZCA whitening" if wh else "")
        print(f"    {tag:28} raw fabrication @200 facts: {100*fab/200:>5.1f}%")
    print("    whitening (vsa_realistic.py) lowers raw fabrication; the gate zeroes the LEAK either way.")

# ════════════════════════════ readable demo ═════════════════════════════════
def demo():
    print("=" * 76 + "\nBELIEF GATE — walk-through (7 real facts buried under 600, whitened organ)\n" + "=" * 76)
    rng = np.random.default_rng(0); N = 600
    cb = make_codebook(N, seed=0, regime="emb", whiten=True)      # whitened: recall + gist both viable
    b = Belief(cb, seed=1); a = Archive()
    facts = {"flight_to_tokyo": 0, "japan_rail_pass": 1, "ryokan_etiquette": 2,     # japan   = 0..2
             "matte_black_faucet": 3, "quartz_counters": 4,                          # kitchen = 3..4
             "couch_to_5k": 5, "running_shoes": 6}                                   # race    = 5..6
    topic_of = {0: "japan", 1: "japan", 2: "japan", 3: "kitchen", 4: "kitchen", 5: "race", 6: "race"}
    for key, v in facts.items(): b.remember(key, v); a.remember(key, v, topic=topic_of[v])
    for j in range(600): v = int(rng.integers(7, N)); b.remember(f"noise{j}", v); a.remember(f"noise{j}", v)
    gate = BeliefGate(b, a)

    print("\nrecall under heavy load — belief alone vs belief + gate:")
    fab = 0
    for key, v in facts.items():
        rv, _, _ = b.recall(key); gv, chk, src = gate.recall(key)
        fab += (rv != v)
        raw = "✓" if rv == v else f"✗ fabricated→{rv}"
        print(f"   {key:20} belief: {raw:18} | gate: {gv} [{chk.status} · {src}]")
    print(f"   → belief fabricated {fab}/7 under load; the gate corrected every one to Archive truth (0 leaked).")
    print("\n   a key never stored:")
    gv, chk, _ = gate.recall("secret_bank_pin")
    print(f"   {'secret_bank_pin':20} | gate: {gv} [{chk.status} · {chk.detail}]")
    print("\nsynthesis 'what do I know about japan?'  (neighborhood = 3 japan facts + 2 leaked notes):")
    neighborhood = [0, 1, 2, 133, 275]                           # 0-2 real japan; 133,275 leaked distractors
    grounded, stripped = gate.synthesize("japan", neighborhood, k=5)
    print(f"   grounded (asserted): {sorted(grounded)}   stripped (fabricated, suppressed): {sorted(stripped)}")
    print("\n   the gate asserts only Archive-grounded claims; everything else is corrected or withheld.")

# ════════════════════════════ soundness tests ═══════════════════════════════
def tests():
    print("BELIEF GATE self-test — the gate must be SOUND\n" + "-" * 52)
    P = {"n": 0, "f": 0}
    def ok(name, cond):
        P["n"] += 1; P["f"] += (not cond); print(f"  {'PASS' if cond else 'FAIL'}  {name}")
    cb = make_codebook(600, seed=0, regime="emb")

    # saturate hard so belief provably fabricates, then prove the gate never leaks one
    b = Belief(cb, seed=1); a = Archive()
    vals = np.random.default_rng(3).choice(600, size=450, replace=False)
    for i, v in enumerate(vals): b.remember(f"k{i}", int(v)); a.remember(f"k{i}", int(v))
    raw_fab = sum(1 for i, v in enumerate(vals) if b.recall(f"k{i}")[0] != v)
    ok("belief actually fabricates past capacity (honest proposer)", raw_fab > 0)
    leak = correct = 0
    for i, v in enumerate(vals):
        gv, chk, _ = BeliefGate(b, a).recall(f"k{i}")
        correct += (gv == v)
        leak += (chk.status == PASS and gv != v)
    ok("gate NEVER false-passes a fabrication (leak == 0)", leak == 0)
    ok("gate returns Archive truth for every stored key (correct == 100%)", correct == len(vals))

    # a fabrication is a caught FAIL, not a silent pass
    b2 = Belief(cb, seed=1); a2 = Archive()
    for i, v in enumerate(vals): b2.remember(f"k{i}", int(v)); a2.remember(f"k{i}", int(v))
    statuses = [BeliefGate(b2, a2).recall(f"k{i}")[1].status for i, v in enumerate(vals)
                if b2.recall(f"k{i}")[0] != v]
    ok("every fabrication surfaces as FAIL (caught, corrected)", statuses and all(s == FAIL for s in statuses))

    # unknown key -> ABSTAIN, never asserted
    gv, chk, _ = BeliefGate(b, a).recall("never_stored_key_xyz")
    ok("unknown key -> ABSTAIN (not asserted)", gv is None and chk.status == ABSTAIN)

    # synthesis: grounded claims are all true members; fabricated associations are stripped
    b3 = Belief(cb, seed=2); a3 = Archive()
    members = list(range(6))
    for v in members: a3.remember(f"t{v}", v, topic="T"); b3.remember(f"t{v}", v)
    nb = members + [int(np.random.default_rng(100 + j).integers(6, 600)) for j in range(12)]
    grounded, stripped = BeliefGate(b3, a3).synthesize("T", nb, k=6)
    ok("synthesis grounded claims are ALL true members (precision 1.0)",
       all(v in members for v in grounded))
    ok("synthesis has nothing ungrounded asserted", all(v not in members for v in stripped))

    print("-" * 52)
    print(f"{P['n']-P['f']}/{P['n']} passed." + ("" if not P["f"] else f"  ❌ {P['f']} FAILED"))
    return P["f"] == 0

if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--test": sys.exit(0 if tests() else 1)
    elif arg == "--measure": measure()
    elif arg == "--demo": demo()
    else:
        print(__doc__)
        print("choose: --test | --measure | --demo")
