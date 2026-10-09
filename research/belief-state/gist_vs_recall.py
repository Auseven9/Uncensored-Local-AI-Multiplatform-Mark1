#!/usr/bin/env python3
"""
GIST vs RECALL — does the belief gist organ earn its wiring?

The honest question (Build ③): Cairn's recall engine is already good at connecting related
things (keyword+embedding seeds -> spreading activation over a relation graph -> fuse-rank).
So the bar for the VSA belief gist is HIGH. This measures whether adding the gist lifts
WHOLE-PICTURE synthesis ABOVE recall+graph alone — the one thing row-based recall can't do.

  A = recall+graph        (budget-limited discrete facts)
  B = recall+graph + gist (A, plus a whole-picture label distilled from the FULL neighborhood
                           — including cluster members that didn't fit A's budget)

Discriminating regime (same as the arena): clusters bigger than the recall budget, many
distractors. If B never beats A even there, belief does NOT earn wiring — and that's a real,
honest result worth having before touching lib/.

RUN:
  Colab: !pip -q install transformers accelerate torch sentence-transformers ; paste ; run(real=True)
  Local logic check (plumbing only, stubs have no semantics): python3 gist_vs_recall.py --selftest

NOTE: this SIMULATES the recall+graph mechanism faithfully in Python (not the exact Dart consts);
the A-vs-B comparison is valid because both conditions use the identical recall. The gist is the
neighborhood belief vector cleaned up against a concept codebook -> a whole-picture label.
"""
import sys, re, math, random
import numpy as np

D=8192; FLOOR=0.045; BUDGET_FACTS=6         # recall budget ~ how many facts fit the context slice
ABST=("unsure","don't know","not sure","no idea","can't tell","n/a","no information")

class Embedder:
    def __init__(self, real, rng):
        self.real=real
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
    P=("You answer ONLY from the MEMORY below, in <=6 words. If it isn't there, reply exactly: unsure\n"
       "\nMEMORY:\n{c}\n\nQ: {q}\nA:")
    def ask(self,c,q,support=None,gold=None,distractors=()):
        if self.real:
            msg=[{"role":"user","content":self.P.format(c=c,q=q)}]
            txt=self.tok.apply_chat_template(msg,tokenize=False,add_generation_prompt=True)
            ids=self.tok(txt,return_tensors="pt").to(self.m.device)
            with self.torch.no_grad():
                o=self.m.generate(**ids,max_new_tokens=24,do_sample=False,pad_token_id=self.tok.eos_token_id)
            return self.tok.decode(o[0,ids["input_ids"].shape[1]:],skip_special_tokens=True).strip()
        cl=(c or "").lower()
        if gold is not None and str(gold).lower() in cl: return str(gold)          # stub: plumbing only
        for d in distractors:
            if str(d).lower() in cl: return str(d)
        return "unsure"

def _n(s): return re.sub(r"[^a-z0-9 ]","",(s or "").lower()).strip()
def is_ab(a): a=_n(a); return any(k in a for k in (_n(x) for x in ABST))
def classify(ans,gold,distractors=(),syn=()):
    if is_ab(ans): return "abstain"
    a=_n(ans); g=[_n(gold)]+[_n(x) for x in syn]
    hit=any(x and x in a for x in g); comp=any(_n(d) in a for d in distractors if _n(d) not in g)
    return "correct" if (hit and not comp) else "fabricate"

# ---------------------------------------------------------------- recall + graph (simulated)
class Fact:
    __slots__=("id","text","ents","sal","age")
    def __init__(self,i,text,ents,sal,age): self.id=i; self.text=text; self.ents=ents; self.sal=sal; self.age=age

class RecallGraph:
    def __init__(self, emb, facts):
        self.emb=emb; self.facts=facts
        self.fv=emb.vec([f.text for f in facts])                       # embeddings for NN
        self.nbr={f.id:set() for f in facts}                           # edges = shared entity
        for a in facts:
            for b in facts:
                if a.id<b.id and (a.ents & b.ents): self.nbr[a.id].add(b.id); self.nbr[b.id].add(a.id)
    def recall(self, query, k=BUDGET_FACTS):
        q=_n(query).split(); qv=self.emb.vec([query])[0]
        seed={}
        for i,f in enumerate(self.facts):
            kw=len(set(q)&set(_n(f.text).split()))/ (len(q)+1e-9)       # keyword overlap
            sim=float(self.fv[i]@qv)                                    # embedding similarity
            seed[f.id]=max(kw, sim)
        top=sorted(seed, key=seed.get, reverse=True)[:k]               # seeds
        act=dict.fromkeys(top,1.0)                                     # spreading activation (1 hop)
        for fid in top:
            for nb in self.nbr[fid]: act[nb]=max(act.get(nb,0), 0.6*seed.get(nb,0.3))
        byid={f.id:f for f in self.facts}
        score={fid: 0.6*(seed.get(fid,0)+act.get(fid,0)) + 0.25*byid[fid].sal + 0.15*math.exp(-byid[fid].age/72)
               for fid in act}
        chosen=sorted(score, key=score.get, reverse=True)[:k]          # fuse-rank -> budget
        return [byid[fid] for fid in chosen], set(chosen)|set(top)

def gist_label(emb, neighborhood_ids, facts, concept_codebook, labels):
    """belief over the FULL neighborhood -> cleanup against concept codebook -> whole-picture label."""
    byid={f.id:f for f in facts}
    texts=[byid[i].text for i in neighborhood_ids]
    if not texts: return None
    hv=emb.hyper(texts); belief=np.sign(hv.sum(0))                     # bundle the neighborhood
    s=(concept_codebook@belief)/D; j=int(np.argmax(s))
    return labels[j] if s[j]>=FLOOR else None

def ctx(facts): return "\n".join(f"- {f.text}" for f in facts)

# ---------------------------------------------------------------- corpus (themed clusters + distractors)
THEMES=[
 ("japan",   "planning a trip to Japan", ["booked a flight to Tokyo in April","bought a Japan Rail Pass",
   "reading about ryokan etiquette","exchanged money into yen","packing light merino layers for Japan",
   "mapped a route through Kyoto temples","downloaded an offline Japanese phrasebook"],
   [("What am I organizing for April?","japan",["tokyo","trip to japan"],["kitchen","race"])]),
 ("kitchen", "renovating the kitchen", ["got quotes for new kitchen cabinets","picked a matte black faucet",
   "scheduled the electrician for Tuesday","comparing quartz vs granite counters","measuring the backsplash tile",
   "chose a slow-close drawer runner","ordered a deep basin sink"],
   [("What home project am I pulling together?","kitchen",["renovat","cabinets"],["japan","race"])]),
 ("race",    "training for a 10k race", ["started couch-to-5k week 3","bought new running shoes",
   "tracking daily protein intake","foam rolling after every run","signed up for a 10k in June",
   "mapped a hilly long-run loop","logging splits in a running app"],
   [("What am I training toward?","race",["10k","running"],["japan","kitchen"])]),
]

def build_corpus(R, emb, n_distractor_facts):
    facts=[]; i=0
    concepts=[t[1] for t in THEMES]+[f"unrelated topic {j}" for j in range(40)]   # codebook w/ decoys
    for key,label,members,_ in THEMES:
        for m in members:
            ents={w for w in _n(m).split() if len(w)>3}
            facts.append(Fact(i,m,ents,sal=R.uniform(.4,.9),age=R.uniform(1,120))); i+=1
    for _ in range(n_distractor_facts):
        topic=R.randint(0,999); m=f"random note about topic {topic} item {R.randint(0,999)}"
        facts.append(Fact(i,m,{f"topic{topic}"},sal=R.uniform(.1,.6),age=R.uniform(1,200))); i+=1
    cb=emb.hyper(concepts)
    return facts, cb, concepts

def run(real=False, seed=0, distractors=(0,40,120)):
    rng=np.random.default_rng(seed); emb=Embedder(real,rng); reader=Reader(real); R=random.Random(seed)
    print(f"\n===== GIST vs RECALL (real={real}) =====  budget={BUDGET_FACTS} facts  (c/f/a = correct/fabricate/abstain)")
    for nd in distractors:
        facts,cb,concepts=build_corpus(R,emb,nd)
        G=RecallGraph(emb,facts)
        agg={m:dict(correct=0,fabricate=0,abstain=0) for m in ("A_recall","B_recall+gist")}
        nq=0
        for key,label,members,qs in THEMES:
            for q,gold,syn,dis in qs:
                nq+=1
                got, hood = G.recall(q)
                cA=ctx(got)
                gl=gist_label(emb,hood,facts,cb,concepts)
                cB=cA+(f"\n\nOverall pattern: {gl}" if gl else "")
                aA=reader.ask(cA,q,gold=gold,distractors=dis)
                aB=reader.ask(cB,q,gold=gold,distractors=dis)
                agg["A_recall"][classify(aA,gold,dis,syn)]+=1
                agg["B_recall+gist"][classify(aB,gold,dis,syn)]+=1
        print(f"\n-- {nd} distractor facts ({nq} synthesis questions) --")
        for m in agg:
            d=agg[m]; t=sum(d.values()) or 1
            print(f"   {m:14} {100*d['correct']/t:3.0f}c {100*d['fabricate']/t:3.0f}f {100*d['abstain']/t:3.0f}a")
    print("\nWIN CONDITION for belief: B > A on synthesis as distractors rise (recall budget overflows,")
    print("gist still carries the whole-picture). If B == A everywhere -> recall+graph is enough; belief")
    print("stays research. Honest either way.")

if __name__=="__main__":
    run(real=("--selftest" not in sys.argv))
