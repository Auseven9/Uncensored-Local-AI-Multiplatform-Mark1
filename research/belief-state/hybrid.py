#!/usr/bin/env python3
"""
ALESIS HYBRID — tiered memory: Belief (fuzzy gist) + ExactStore (hard facts) + router + wake/sleep.
Implements #4 (model-as-router) and #2 (wake/sleep consolidation).

Thesis to test: tiering fixes Belief's TWO worst arena failures —
  (a) exact literals (Belief ~0%)  -> the ExactStore handles them,
  (b) the fabrication cliff past ~150 facts -> consolidation keeps Belief pruned + ExactStore backs it,
while KEEPING Belief's real wins (updates, whole-picture synthesis).

RUN:
  Colab: !pip -q install transformers accelerate torch sentence-transformers  ; paste ; run_hybrid(real=True)
  Local logic check:  python3 hybrid.py --selftest
"""
import sys, re, math, random
import numpy as np

D=8192; FLOOR=0.045; RAG_K=15; CAP=150     # CAP = Belief's safe capacity (kept under the cliff by consolidation)
ABST=("unsure","don't know","not sure","no information","not in memory","can't find","n/a")

class Embedder:
    def __init__(self, real, rng):
        self.real=real; self.rng=rng
        if real:
            from sentence_transformers import SentenceTransformer
            self.m=SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
            self.P=rng.standard_normal((self.m.get_sentence_embedding_dimension(),D))/np.sqrt(384)
    def vec(self,t):
        if self.real: return np.atleast_2d(self.m.encode(list(t),normalize_embeddings=True))
        o=[]
        for x in t:
            r=np.random.default_rng(abs(hash(("e",x)))%(2**32)); v=r.standard_normal(64); o.append(v/(np.linalg.norm(v)+1e-9))
        return np.array(o)
    def hyper(self,t):
        if self.real: return np.sign(self.vec(t)@self.P)
        o=[]
        for x in t:
            r=np.random.default_rng(abs(hash(("h",x)))%(2**32)); o.append(r.choice([-1.,1.],size=D))
        return np.array(o)

class Reader:
    def __init__(self, real):
        self.real=real
        if real:
            import torch; from transformers import AutoModelForCausalLM, AutoTokenizer
            self.torch=torch; self.tok=AutoTokenizer.from_pretrained("Qwen/Qwen2.5-1.5B-Instruct")
            self.m=AutoModelForCausalLM.from_pretrained("Qwen/Qwen2.5-1.5B-Instruct",torch_dtype="auto",device_map="auto").eval()
    P=("You answer ONLY from the MEMORY below. Answer in <=6 words. "
       "If the memory lacks the answer, reply exactly: unsure\n\nMEMORY:\n{c}\n\nQ: {q}\nA:")
    def ask(self,c,q,support=None,gold=None,distractors=()):
        if self.real:
            msg=[{"role":"user","content":self.P.format(c=c,q=q)}]
            txt=self.tok.apply_chat_template(msg,tokenize=False,add_generation_prompt=True)
            ids=self.tok(txt,return_tensors="pt").to(self.m.device)
            with self.torch.no_grad():
                o=self.m.generate(**ids,max_new_tokens=24,do_sample=False,pad_token_id=self.tok.eos_token_id)
            return self.tok.decode(o[0,ids["input_ids"].shape[1]:],skip_special_tokens=True).strip()
        cl=(c or "").lower(); need=support if support is not None else ([gold] if gold else [])
        if need and all(str(s).lower() in cl for s in need): return str(gold)
        for d in distractors:
            if str(d).lower() in cl: return str(d)
        return "unsure"

class Belief:
    def __init__(self,emb,floor=FLOOR):
        self.emb=emb; self.floor=floor; self.acc=np.zeros(D); self.last={}; self._r={}
    def role(self,k):
        if k not in self._r:
            r=np.random.default_rng(abs(hash(("r",k)))%(2**32)); self._r[k]=r.choice([-1.,1.],size=D)
        return self._r[k]
    def write(self,k,vv,sal=1.0):
        r=self.role(k); old=self.last.get(k)
        if old is not None: self.acc-=old[0]*r*old[1]
        self.acc+=sal*r*vv; self.last[k]=(sal,vv)
    def read(self,k,cb,labels):
        if k not in self.last: return None
        est=np.sign(self.acc)*self.role(k); s=(cb@est)/D; j=int(np.argmax(s))
        return labels[j] if s[j]>=self.floor else None

# ---------------------------------------------------------------- the HYBRID
class Hybrid:
    """Belief = fuzzy gist (fixed size).  ExactStore = exact hard facts (grows, never lies).
    write-order kept for consolidation.  consolidate() = the wake/sleep sweep."""
    def __init__(self, emb):
        self.emb=emb; self.belief=Belief(emb); self.store={}; self.order=[]; self.sal={}
    def write(self,k,v,vv,salience=1.0):
        self.belief.write(k,vv,salience); self.store[k]=v          # BOTH tiers
        if k not in self.sal: self.order.append(k)
        self.sal[k]=salience
    def consolidate(self, cap=CAP):
        """SLEEP: keep only the top-`cap` facts (by salience, then recency) live in Belief,
        so Belief never crosses its fabrication cliff. ExactStore keeps everything."""
        if len(self.order)<=cap: return 0
        ranked=sorted(self.order, key=lambda k:(self.sal.get(k,1.0), self.order.index(k)), reverse=True)
        keep=set(ranked[:cap]); dropped=len(self.order)-cap
        b=Belief(self.emb); vv=self.emb.hyper([self.store[k] for k in self.order if k in keep])
        for i,k in enumerate([k for k in self.order if k in keep]): b.write(k,vv[i],self.sal.get(k,1.0))
        self.belief=b
        return dropped                                              # count pruned out of the hot vector
    # ROUTER (#4): blend fuzzy gist + exact record; exact wins when present.
    def context(self, probe_keys, cb, labels):
        gist=[]
        for k in probe_keys:
            g=self.belief.read(k,cb,labels); gist.append(f"{k}: {g if g is not None else 'unsure'}")
        exact=[f"{k}: {self.store[k]}" for k in probe_keys if k in self.store]   # the hard-fact fetch
        return "Gist (fuzzy):\n"+"\n".join(gist)+"\nExact record:\n"+"\n".join(exact)

def _norm(s): return re.sub(r"[^a-z0-9 ]","",(s or "").lower()).strip()
def is_ab(a): a=_norm(a); return any(k in a for k in (_norm(x) for x in ABST))
def classify(ans,gold,qtype,distractors=(),syn=()):
    if qtype=="unanswerable": return "correct" if is_ab(ans) else "fabricate"
    if is_ab(ans): return "abstain"
    if qtype=="exact": return "correct" if (ans or "").strip()==str(gold) else "fabricate"
    a=_norm(ans); g=[_norm(gold)]+[_norm(x) for x in syn]
    hit=any(x and x in a for x in g); comp=any(_norm(d) in a for d in distractors if _norm(d) not in g)
    return "correct" if (hit and not comp) else "fabricate"

def codebook(emb,vals,rng,decoys=400):
    labels=list(vals)+[f"dc_{i}_{rng.integers(10**6)}" for i in range(decoys)]
    return emb.hyper(labels), labels

# ---------------------------------------------------------------- comparison: HYBRID vs the pieces alone
def build_belief_only(emb,facts,sal=None):
    b=Belief(emb); sal=sal or {}; vv=emb.hyper([v for _,v in facts])
    for i,(k,v) in enumerate(facts): b.write(k,vv[i],sal.get(k,1.0))
    return b
def ctx_rag(facts,q,emb,k=RAG_K):
    items=[f"{a}: {b}" for a,b in facts]; order=np.argsort(-(emb.vec(items)@emb.vec([q])[0]))[:k]
    return "\n".join(items[i] for i in order)

def score_methods(facts, probes, emb, reader, rng, sal=None, consolidate_cap=None):
    cb,labels=codebook(emb,[v for _,v in facts],rng)
    belief=build_belief_only(emb,facts,sal)
    hy=Hybrid(emb); vv=emb.hyper([v for _,v in facts])
    for i,(k,v) in enumerate(facts): hy.write(k,v,vv[i],(sal or {}).get(k,1.0))
    dropped=hy.consolidate(consolidate_cap) if consolidate_cap else 0
    cbh,labh=codebook(emb,[hy.store[k] for k in hy.store],rng)
    out={m:dict(correct=0,abstain=0,fabricate=0) for m in ("HYBRID","belief_only","kv_only","rag")}
    for p in probes:
        key=p["key"]; pk=p.get("agg_keys",[key])
        ctxs={
          "HYBRID": hy.context(pk,cbh,labh),
          "belief_only": "\n".join(f"{k}: {belief.read(k,cb,labels) or 'unsure'}" for k in pk),
          "kv_only": "\n".join(f"{k}: {hy.store.get(k,'(none)')}" for k in pk),
          "rag": ctx_rag(facts,p["q"],emb),
        }
        for m,c in ctxs.items():
            a=reader.ask(c,p["q"],support=p.get("support"),gold=p["gold"],distractors=p.get("distractors",()))
            out[m][classify(a,p["gold"],p["qtype"],p.get("distractors",()),p.get("syn",[]))]+=1
    return out, dropped

def pct(d): t=sum(d.values()) or 1; return f"{100*d['correct']/t:3.0f}c {100*d['fabricate']/t:3.0f}f {100*d['abstain']/t:3.0f}a"

def run_hybrid(real=False, seed=0):
    rng=np.random.default_rng(seed); emb=Embedder(real,rng); reader=Reader(real); R=random.Random(seed)
    print(f"\n===== ALESIS HYBRID  (real={real}) =====  (c=correct f=fabricate a=abstain)")

    # TEST A: exact literals (Belief-alone ~0; hybrid should route to ExactStore and win)
    code="".join(R.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(6))
    phone="".join(R.choice("0123456789") for _ in range(10))
    facts=[("conf_code",code),("phone",phone)]+[(f"n_{i}",f"v{R.randint(0,9999)}") for i in range(20)]
    probes=[dict(q="What is my confirmation code?",gold=code,qtype="exact",support=[code],key="conf_code"),
            dict(q="What is my phone number?",gold=phone,qtype="exact",support=[phone],key="phone")]
    res,_=score_methods(facts,probes,emb,reader,rng)
    print("\nA) EXACT LITERALS   (Belief alone fails; hybrid routes to the exact store)")
    for m in res: print(f"   {m:12} {pct(res[m])}")

    # TEST B: capacity 600 facts WITH wake/sleep consolidation (hybrid should NOT fabricate)
    big=[(f"k_{i}",f"val{R.randint(0,10**6)}") for i in range(600)]
    tgt=R.sample(range(600),20); probes=[dict(q=f"What is k_{i}?",gold=big[i][1],qtype="closed",
        support=[big[i][1]],key=f"k_{i}") for i in tgt]
    res,dropped=score_methods(big,probes,emb,reader,rng,consolidate_cap=CAP)
    print(f"\nB) CAPACITY @600 + wake/sleep (Belief alone fabricated ~30-40%; {dropped} pruned from hot vector)")
    for m in res: print(f"   {m:12} {pct(res[m])}")

    # TEST C: updates (keep Belief's win — current value after changes)
    upd=[("doctor","Dr. Allen"),("doctor","Dr. Bauer"),("doctor","Dr. Diaz")]
    facts=[(f"n_{i}",f"v{R.randint(0,999)}") for i in range(5)]+upd+[(f"m_{i}",f"v{R.randint(0,999)}") for i in range(5)]
    probes=[dict(q="Who is my doctor now?",gold="Diaz",qtype="closed",support=["Diaz"],
                 distractors=["Allen","Bauer"],syn=["dr. diaz"],key="doctor")]
    res,_=score_methods(facts,probes,emb,reader,rng)
    print("\nC) UPDATES   (hybrid should keep Belief's win vs RAG's stale answer)")
    for m in res: print(f"   {m:12} {pct(res[m])}")

    # TEST D: synthesis (keep Belief's win — whole-picture where RAG is blind)
    key=[("p_a","booked a flight to Tokyo in April"),("p_b","bought a Japan Rail Pass"),
         ("p_c","reading about ryokan etiquette")]
    facts=key+[(f"n_{i}",f"note{R.randint(0,999)}") for i in range(57)]
    probes=[dict(q="Taken together, what am I trying to do?",gold="japan",qtype="closed",
                 support=["Tokyo","Japan Rail","ryokan"],syn=["tokyo","trip to japan"],key="p_a",
                 agg_keys=["p_a","p_b","p_c"])]
    res,_=score_methods(facts,probes,emb,reader,rng)
    print("\nD) SYNTHESIS   (hybrid should keep Belief's whole-picture win; RAG blind)")
    for m in res: print(f"   {m:12} {pct(res[m])}")

    print("\nWIN CONDITION: HYBRID >= best single tier on A,B,C,D at once — exact facts (A),")
    print("no fabrication at scale (B), current-truth (C), whole-picture (D). One memory, all four.")

if __name__=="__main__":
    run_hybrid(real=("--selftest" not in sys.argv))
