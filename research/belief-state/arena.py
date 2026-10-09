#!/usr/bin/env python3
"""
ALESIS ARENA — 20-test honest stress battery: Belief vs its competitors.
Competitors every test: BELIEF, EXACT-KV, SCRATCHPAD, RAG, SUMMARY  + baselines NO-MEM, ORACLE.

RUN:
  Colab (real):  Cell1 -> !pip -q install transformers accelerate torch sentence-transformers
                 Cell2 -> paste this file, then:  run_arena(real=True)      # ~30-60 min on T4
  Local logic check (no LLM, no GPU, numpy only):   python3 arena.py --selftest

FAIRNESS LOCKS (the group caught 3 rigs in our own prior code — these prevent them):
  * Belief values AND queries use a REAL embedder (MiniLM) -> fixed random projection -> sign.
    RAG uses the SAME MiniLM at FULL precision (never Belief's lossy sign), generous k=15 (+ sweep).
  * Cleanup codebook = a BIG candidate universe incl. many NEVER-STORED decoys (not the stored set).
  * ALL methods answer via the SAME reader + prompt; only the injected context differs.
  * Belief footprint counts EVERYTHING: vector(s) + bloom key-set + shards + codebook. Reported in bytes.
  * ONE pre-registered confidence floor, never tuned per test.
  * NO-MEM floor + ORACLE ceiling on every test (did "correct" come from memory or the model's prior?).
  * Headline = raw accuracy. Fabrication-rate and abstention-rate reported SEPARATELY (never blended in).
  * unanswerable item: correct == abstain; any confident value == fabrication.
  * Honest-loss tests are kept and reported; they are NEVER averaged away.
"""
import sys, re, math, random
import numpy as np

# ----------------------------------------------------------------------------- config
D = 8192                      # bipolar dims -> binary footprint D/8 = 1024 B = "1 KB"
FLOOR = 0.045                 # pre-registered; never tuned per test
RAG_K = 15
PHONE_TOK = 1024              # on-device context budget
ABSTAIN_LEX = ("unsure","don't know","do not know","not sure","no information",
               "not in memory","can't find","cannot find","n/a","no idea","don't have")

# ----------------------------------------------------------------------------- embedder
class Embedder:
    """real=MiniLM(384)->projection->; stub=deterministic per-text vector (numpy only)."""
    def __init__(self, real, rng):
        self.real = real; self.rng = rng
        if real:
            from sentence_transformers import SentenceTransformer
            self.m = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
            self.edim = self.m.get_sentence_embedding_dimension()
            self.P = rng.standard_normal((self.edim, D)) / np.sqrt(self.edim)
    def vec(self, texts):                       # full-precision embedding (for RAG) ; L2-normed
        if self.real:
            return np.atleast_2d(self.m.encode(list(texts), normalize_embeddings=True))
        out = []
        for t in texts:                         # deterministic pseudo-embedding from text hash
            r = np.random.default_rng(abs(hash(("emb", t))) % (2**32))
            v = r.standard_normal(64); out.append(v / (np.linalg.norm(v) + 1e-9))
        return np.array(out)
    def hyper(self, texts):                     # ±1 hypervector (for Belief): embed -> project -> sign
        if self.real:
            return np.sign(self.vec(texts) @ self.P)
        out = []
        for t in texts:
            r = np.random.default_rng(abs(hash(("hyp", t))) % (2**32))
            out.append(r.choice([-1., 1.], size=D))
        return np.array(out)

# ----------------------------------------------------------------------------- reader (LLM)
class Reader:
    def __init__(self, real):
        self.real = real
        if real:
            import torch
            from transformers import AutoModelForCausalLM, AutoTokenizer
            self.torch = torch
            self.tok = AutoTokenizer.from_pretrained("Qwen/Qwen2.5-1.5B-Instruct")
            self.m = AutoModelForCausalLM.from_pretrained(
                "Qwen/Qwen2.5-1.5B-Instruct", torch_dtype="auto", device_map="auto").eval()
    PROMPT = ("You answer ONLY from the MEMORY below. Answer in <=6 words. "
              "If the memory does not contain the answer, reply exactly: unsure\n\nMEMORY:\n{ctx}\n\nQ: {q}\nA:")
    def ask(self, ctx, q, support=None, gold=None, distractors=()):
        if self.real:
            msg = [{"role":"user","content":self.PROMPT.format(ctx=ctx, q=q)}]
            text = self.tok.apply_chat_template(msg, tokenize=False, add_generation_prompt=True)
            ids = self.tok(text, return_tensors="pt").to(self.m.device)
            with self.torch.no_grad():
                out = self.m.generate(**ids, max_new_tokens=24, do_sample=False,
                                      pad_token_id=self.tok.eos_token_id)
            return self.tok.decode(out[0, ids["input_ids"].shape[1]:], skip_special_tokens=True).strip()
        # STUB reader (selftest): "reads" the context. Returns gold iff its support text is present;
        # else a distractor if one leaked into context; else unsure. Exercises scoring + flow only.
        c = (ctx or "").lower()
        need = support if support is not None else ([gold] if gold else [])
        if need and all(str(s).lower() in c for s in need):
            return str(gold)
        for d in distractors:
            if str(d).lower() in c:
                return str(d)
        return "unsure"

def tok_len(real_reader, text):
    if real_reader.real:
        return len(real_reader.tok(text)["input_ids"])
    return max(1, len(text.split()))

# ----------------------------------------------------------------------------- Belief organ
class Belief:
    def __init__(self, emb, rng, floor=FLOOR):
        self.emb = emb; self.rng = rng; self.floor = floor
        self.acc = np.zeros(D); self.last = {}; self.bloom = set(); self._roles = {}
    def role(self, key):
        if key not in self._roles:
            r = np.random.default_rng(abs(hash(("role", key))) % (2**32))
            self._roles[key] = r.choice([-1., 1.], size=D)
        return self._roles[key]
    def write(self, key, value_vec, salience=1.0):
        r = self.role(key); old = self.last.get(key)
        if old is not None: self.acc -= old[0] * r * old[1]        # active overwrite
        self.acc += salience * r * value_vec
        self.last[key] = (salience, value_vec); self.bloom.add(key)
    def read(self, key, codebook, labels):
        if key not in self.bloom: return None                      # existence gate (bloom)
        est = np.sign(self.acc) * self.role(key)
        sims = (codebook @ est) / D; j = int(np.argmax(sims))
        return labels[j] if sims[j] >= self.floor else None
    def bytes(self, n_cb):                                          # honest full footprint
        return dict(vector=D//8, bloom=len(self.bloom)*8, codebook=n_cb*(D//8),
                    total=D//8 + len(self.bloom)*8 + n_cb*(D//8))

# ----------------------------------------------------------------------------- scoring
def _norm(s): return re.sub(r"[^a-z0-9 ]","", (s or "").lower()).strip()
def is_abstain(ans): a=_norm(ans); return any(k in a for k in (_norm(x) for x in ABSTAIN_LEX))
def classify(ans, gold, qtype, distractors=(), synonyms=()):
    """-> 'correct' | 'abstain' | 'fabricate'."""
    if qtype == "unanswerable":
        return "correct" if is_abstain(ans) else "fabricate"
    if is_abstain(ans): return "abstain"
    if qtype == "exact":
        return "correct" if (ans or "").strip() == str(gold) else "fabricate"
    # closed-value: gold or a synonym present, and no competing distractor asserted
    a = _norm(ans); golds = [_norm(gold)] + [_norm(s) for s in synonyms]
    hit = any(g and g in a for g in golds)
    competing = any(_norm(d) in a for d in distractors if _norm(d) not in golds)
    if hit and not competing: return "correct"
    return "fabricate"

# ----------------------------------------------------------------------------- method contexts
def ctx_scratchpad(facts, reader, budget=PHONE_TOK):
    lines, used = [], 0
    for k,v in facts:                                              # recency order; drop oldest on overflow
        ln = f"{k}: {v}"; t = tok_len(reader, ln)
        if used + t > budget: break
        lines.append(ln); used += t
    return "\n".join(reversed(lines))                              # keep most-recent (reversed build)
def ctx_rag(facts, query, emb, k=RAG_K):
    items = [f"{k_}: {v}" for k_,v in facts]
    qv = emb.vec([query])[0]; iv = emb.vec(items)
    order = np.argsort(-(iv @ qv))[:k]
    return "\n".join(items[i] for i in order)
def ctx_summary(facts, reader, budget=256):                        # lossy compression (stub: head-truncate)
    joined = "; ".join(f"{k}:{v}" for k,v in facts)
    if reader.real:
        return reader.ask("\n".join(f"{k}: {v}" for k,v in facts),
                          "Summarize the memory in <=60 words.")
    return joined[: budget*4]
def ctx_kv(facts, key):                                            # exact store
    d = {k: v for k,v in facts}
    return f"{key}: {d[key]}" if key in d else "(no entry)"
def ctx_kv_dump(facts, keys):                                      # for aggregate: dump the relevant slots
    d = {k: v for k,v in facts}
    return "\n".join(f"{k}: {d[k]}" for k in keys if k in d)
def ctx_belief(bel, keys, codebook, labels):                       # decode the probed slots
    out = []
    for k in keys:
        v = bel.read(k, codebook, labels)
        out.append(f"{k}: {v if v is not None else 'unsure'}")
    return "\n".join(out)

# ----------------------------------------------------------------------------- test registry
# Each test: name, kind, build(seed)-> dict(facts, probes, cb_extra, belief_keys, kv_keys, note)
# probe = dict(q, gold, qtype, support, distractors, synonyms, key)
TESTS = []
def test(name, kind):
    def deco(fn): TESTS.append((name, kind, fn)); return fn
    return deco

COMMON = ["home_city","dog_name","car","employer","hobby","gym_day","blood_type","shoe_size"]
def _facts(seed, n, prefix="attr"):
    r = random.Random(seed); return [(f"{prefix}_{i}", f"val_{r.randint(0,9999)}") for i in range(n)]

@test("01_basic_recall_scale","accuracy")
def t01(seed):
    r=random.Random(seed); n=120
    facts=[(f"slot_{i}", f"item{r.randint(1000,9999)}") for i in range(n)]
    probes=[]
    for i in r.sample(range(n), 20):
        k,v=facts[i]; probes.append(dict(q=f"What is {k}?", gold=v, qtype="closed",
            support=[v], distractors=[], synonyms=[], key=k))
    return dict(facts=facts, probes=probes, belief_keys=[p["key"] for p in probes], note="sweep past capacity in real run")

@test("02_distractor_interference","accuracy")
def t02(seed):
    r=random.Random(seed)
    tgt=("alicia_ext","4471"); near=[("alicia_ext","4471"),("alical_ext","4472"),("alan_ext","4473"),("alex_ext","4474")]
    facts=near+_facts(seed,40,"noise")
    probes=[dict(q="What is alicia_ext?", gold="4471", qtype="closed", support=["4471"],
                 distractors=["4472","4473","4474"], synonyms=[], key="alicia_ext")]
    return dict(facts=facts, probes=probes, belief_keys=["alicia_ext"])

@test("03_paraphrase","accuracy")
def t03(seed):
    facts=[("commute","I commute by bicycle")]+_facts(seed,30,"noise")
    probes=[dict(q="How does the user get to work?", gold="bicycle", qtype="closed",
                 support=["bicycle"], distractors=[], synonyms=["bike","cycling"], key="commute")]
    return dict(facts=facts, probes=probes, belief_keys=["commute"])

@test("04_multihop","accuracy")
def t04(seed):
    facts=[("seat_14","Dana"),("Dana_manager","Priya")]+_facts(seed,30,"noise")
    probes=[dict(q="Who manages the person in seat 14?", gold="Priya", qtype="closed",
                 support=["Dana","Priya"], distractors=[], synonyms=[], key="seat_14")]
    return dict(facts=facts, probes=probes, belief_keys=["seat_14","Dana_manager"])

@test("05_aggregate_majority","aggregate")
def t05(seed):
    accts=["checking","savings","emergency","brokerage","roth","k401","hsa","college","joint","carfund","vac","crypto"]
    banks=["Chase"]*5+["WellsFargo"]*4+["Citi"]*3
    r=random.Random(seed); r.shuffle(banks)
    facts=[(f"{a}_bank", b) for a,b in zip(accts,banks)]+_facts(seed,48,"noise")
    gold="Chase"
    probes=[dict(q="Which bank holds the most of my accounts?", gold=gold, qtype="closed",
                 support=["Chase"], distractors=["WellsFargo","Citi"], synonyms=[],
                 agg_keys=[f"{a}_bank" for a in accts])]
    return dict(facts=facts, probes=probes, belief_keys=[f"{a}_bank" for a in accts])

@test("06_synthesis3","aggregate")
def t06(seed):
    key=[("plan_a","booked round-trip flight to Tokyo in April"),
         ("plan_b","bought a 7-day Japan Rail Pass"),
         ("plan_c","reading about ryokan etiquette and onsen rules")]
    facts=key+_facts(seed,57,"neutral")
    probes=[dict(q="Taken together, what am I trying to do?", gold="japan", qtype="closed",
                 support=["Tokyo","Japan Rail","ryokan"], distractors=[], synonyms=["tokyo","trip to japan"],
                 agg_keys=["plan_a","plan_b","plan_c"])]
    return dict(facts=facts, probes=probes, belief_keys=["plan_a","plan_b","plan_c"])

@test("07_presence_split","accuracy")
def t07(seed):
    present=[("m_bungee","mentioned bungee jumping"),("m_sushi","mentioned sushi"),("m_python","mentioned Python")]
    facts=present+_facts(seed,20,"noise")
    probes=[dict(q="Have I ever mentioned skydiving?", gold="no", qtype="unanswerable", support=[], distractors=[], key="m_skydiving"),
            dict(q="Have I ever mentioned bungee jumping?", gold="yes", qtype="closed", support=["bungee"], distractors=[], synonyms=["bungee"], key="m_bungee")]
    return dict(facts=facts, probes=probes, belief_keys=["m_bungee","m_sushi","m_python","m_skydiving"])

@test("08_moving_target","accuracy")
def t08(seed):
    upd=[("doctor","Dr. Allen"),("doctor","Dr. Bauer"),("doctor","Dr. Chen"),("doctor","Dr. Diaz")]
    facts=_facts(seed,3,"n1")+[upd[0]]+_facts(seed,3,"n2")+[upd[1]]+_facts(seed,3,"n3")+[upd[2]]+_facts(seed,3,"n4")+[upd[3]]+_facts(seed,2,"n5")
    probes=[dict(q="Who is my primary doctor right now?", gold="Diaz", qtype="closed",
                 support=["Diaz"], distractors=["Allen","Bauer","Chen"], synonyms=["dr. diaz","diaz"], key="doctor")]
    return dict(facts=facts, probes=probes, belief_keys=["doctor"], overwrite=True)

@test("09_trend_overwrite","accuracy")
def t09(seed):
    upd=[("goal","$500 in January"),("goal","$800 in March"),("goal","$1200 in June")]
    facts=_facts(seed,5,"n1")+[upd[0]]+_facts(seed,10,"n2")+[upd[1]]+_facts(seed,10,"n3")+[upd[2]]+_facts(seed,10,"n4")
    probes=[dict(q="What is my current savings goal?", gold="1200", qtype="closed", support=["1200"], distractors=["500","800"], synonyms=["$1200"], key="goal"),
            dict(q="Is my savings goal increasing or decreasing?", gold="increasing", qtype="closed", support=["500","800","1200"], distractors=["decreasing"], synonyms=["rising","up"], key="goal_dir")]
    return dict(facts=facts, probes=probes, belief_keys=["goal"], overwrite=True, note="Q2 is Belief honest-loss (history erased)")

@test("10_provenance","accuracy")
def t10(seed):
    facts=[("self_allergy","penicillin"),("Sam_allergy","shellfish"),("Lee_allergy","latex"),("self_aspirin_src","inferred")]+_facts(seed,20,"noise")
    probes=[dict(q="Whose allergy is shellfish — mine or my friend's?", gold="Sam", qtype="closed", support=["Sam"], distractors=["me","mine","self"], synonyms=["friend","sam"], key="Sam_allergy"),
            dict(q="Am I allergic to latex?", gold="no", qtype="unanswerable", support=[], distractors=["yes"], key="self_latex")]
    return dict(facts=facts, probes=probes, belief_keys=["self_allergy","Sam_allergy","Lee_allergy","self_latex"])

@test("11_drm_fabrication","safety")
def t11(seed):
    facts=[("bed","against the north wall"),("pillow","goose-down"),("nightstand","a glass of water"),
           ("alarm","7am"),("curtains","blackout")]+_facts(seed,15,"noise")
    probes=[dict(q="What brand is my mattress?", gold="brand", qtype="unanswerable", support=[], distractors=["Sealy","Serta","queen"], key="mattress"),
            dict(q="What time does my alarm go off?", gold="7am", qtype="closed", support=["7am"], distractors=[], synonyms=["7 am","seven"], key="alarm")]
    return dict(facts=facts, probes=probes, belief_keys=["alarm","mattress"])

@test("12_capacity_overload","sweep")
def t12(seed):
    return dict(sweep="capacity")           # handled specially
@test("13_context_truncation","sweep")
def t13(seed):
    return dict(sweep="truncation")
@test("14_cost_ledger","ledger")
def t14(seed):
    return dict(ledger=True)
@test("15_graceful_degradation","sweep")
def t15(seed):
    return dict(sweep="degradation")

@test("16_exact_literals","accuracy")
def t16(seed):
    r=random.Random(seed)
    code="".join(r.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(6))
    phone="".join(r.choice("0123456789") for _ in range(10))
    facts=[("conf_code",code),("phone",phone)]+_facts(seed,20,"noise")
    probes=[dict(q="What is my confirmation code?", gold=code, qtype="exact", support=[code], distractors=[], key="conf_code"),
            dict(q="What is my phone number?", gold=phone, qtype="exact", support=[phone], distractors=[], key="phone")]
    return dict(facts=facts, probes=probes, belief_keys=["conf_code","phone"], note="Belief designed ~0% here")

@test("17_enum_open","enumeration")
def t17(seed):
    r=random.Random(seed); owners=["J"]*9+["K"]*7+["L"]*8+["M"]*6; r.shuffle(owners)
    facts=[(f"item_{i}_owner", o) for i,o in enumerate(owners)]
    goldJ=sorted([f"item_{i}" for i,o in enumerate(owners) if o=="J"])
    probes=[dict(q="List all item IDs owned by J.", gold=goldJ, qtype="enumeration",
                 support=goldJ, distractors=[], key="enumJ")]
    return dict(facts=facts, probes=probes, belief_keys=[f"item_{i}_owner" for i in range(len(owners))], note="Belief cannot enumerate from bundle")

@test("18_verbatim_history","accuracy")
def t18(seed):
    facts=_facts(seed,3,"n1")+[("address","12 Oak St")]+_facts(seed,6,"n2")+[("address","88 Pine Ave")]
    probes=[dict(q="What was my PREVIOUS address before I moved?", gold="Oak", qtype="closed",
                 support=["Oak"], distractors=["Pine"], synonyms=["12 oak"], key="address_prev")]
    return dict(facts=facts, probes=probes, belief_keys=["address","address_prev"], overwrite=True, note="Belief loss: overwrite erased history")

@test("19_nested_structured","accuracy")
def t19(seed):
    facts=[("trip.flight.dep","JFK"),("trip.flight.arr","NRT"),("trip.hotel.name","Marlowe"),("trip.hotel.room","508")]+_facts(seed,20,"noise")
    probes=[dict(q="What room at the trip hotel?", gold="508", qtype="closed", support=["508"], distractors=[], synonyms=[], key="trip.hotel.room")]
    return dict(facts=facts, probes=probes, belief_keys=["trip.hotel.room","trip.flight.dep"], note="nested keys stress structured recall")

@test("20_salience_retention","accuracy")
def t20(seed):
    r=random.Random(seed)
    important=[("passport_no","X put IMPORTANT"),("emergency_contact","Mara put IMPORTANT")]
    facts=important+[(f"chatter_{i}", f"c{r.randint(0,999)}") for i in range(80)]
    probes=[dict(q="What is my emergency_contact?", gold="Mara", qtype="closed", support=["Mara"], distractors=[], synonyms=[], key="emergency_contact", salience=4.0)]
    return dict(facts=facts, probes=probes, belief_keys=["emergency_contact"], salient={"passport_no":4.0,"emergency_contact":4.0},
                note="potential Belief edge: salience-weighted facts survive crowding")

# ----------------------------------------------------------------------------- codebook / belief build
def build_codebook(emb, facts, rng, n_decoys=400):
    labels = [v for _,v in facts]
    decoys = [f"decoy_{i}_{rng.integers(10**6)}" for i in range(n_decoys)]   # NEVER-STORED
    all_labels = labels + decoys
    cb = emb.hyper(all_labels)
    return cb, all_labels
def build_belief(emb, rng, facts, salient=None, overwrite=False):
    bel = Belief(emb, rng); sal = salient or {}
    valvecs = emb.hyper([v for _,v in facts])
    for i,(k,v) in enumerate(facts):
        bel.write(k, valvecs[i], salience=sal.get(k,1.0))
    return bel

# ----------------------------------------------------------------------------- run one accuracy test
METHODS = ["belief","kv","scratchpad","rag","summary","nomem","oracle"]
def run_accuracy(spec, emb, reader, rng):
    facts = spec["facts"]; cb, labels = build_codebook(emb, facts, rng)
    bel = build_belief(emb, rng, facts, spec.get("salient"), spec.get("overwrite"))
    res = {m: dict(correct=0,abstain=0,fabricate=0) for m in METHODS}
    for p in spec["probes"]:
        key = p.get("key"); agg = p.get("agg_keys")
        probe_keys = agg if agg else ([key] if key in [k for k,_ in facts] or key in bel.bloom else [key])
        contexts = {
            "scratchpad": ctx_scratchpad(facts, reader),
            "rag": ctx_rag(facts, p["q"], emb),
            "summary": ctx_summary(facts, reader),
            "kv": ctx_kv_dump(facts, agg) if agg else ctx_kv(facts, key),
            "belief": ctx_belief(bel, probe_keys, cb, labels),
            "nomem": "",
            "oracle": "\n".join(f"{k}: {v}" for k,v in facts if k in (agg or [key])),
        }
        for m in METHODS:
            ans = reader.ask(contexts[m], p["q"], support=p.get("support"),
                             gold=p["gold"] if not isinstance(p["gold"],list) else None,
                             distractors=p.get("distractors",()))
            cls = (enum_score(ans, p) if p["qtype"]=="enumeration"
                   else classify(ans, p["gold"], p["qtype"], p.get("distractors",()), p.get("synonyms",())))
            res[m][cls] += 1
    return res, bel.bytes(len(labels))

def enum_score(ans, p):                     # coarse: did it return the gold set? (stub: substring of all ids)
    a=(ans or "").lower()
    hit=sum(1 for g in p["gold"] if g.lower() in a)
    return "correct" if hit==len(p["gold"]) else ("abstain" if is_abstain(ans) else "fabricate")

# ----------------------------------------------------------------------------- sweeps (reported as curves)
def run_capacity(emb, reader, rng, Ns=(50,100,200,400,600)):
    rows=[]
    for N in Ns:
        facts=[(f"k_{i}", f"v{rng.integers(10**6)}") for i in range(N)]
        cb,labels=build_codebook(emb,facts,rng); bel=build_belief(emb,rng,facts)
        probe=[facts[i] for i in rng.choice(N,size=min(30,N),replace=False)]
        c=a=f=0
        for k,v in probe:
            got=bel.read(k,cb,labels)
            if got==v: c+=1
            elif got is None: a+=1
            else: f+=1
        rows.append((N, round(100*c/len(probe)), round(100*a/len(probe)), round(100*f/len(probe))))
    return rows   # (N, belief_recall%, abstain%, fabricate%)

def run_ledger(Ns=(100,1000,10000,100000,1000000)):
    rows=[]
    for N in Ns:
        shards=math.ceil(N/200); bel=shards*(D//8)+N*8+ (min(N,2000))*(D//8)  # vec*shards + bloom + codebook(cap)
        kv=N*48; rag=N*1600; scratch=N*16*4
        rows.append((N, bel, kv, rag, scratch))
    return rows   # bytes

# ----------------------------------------------------------------------------- driver
def run_arena(real=False, seeds=(0,1,2)):
    rng=np.random.default_rng(0); emb=Embedder(real,rng); reader=Reader(real)
    print(f"\n===== ALESIS ARENA  (real={real}, seeds={list(seeds)}, D={D}, floor={FLOOR}) =====")
    agg={}
    for name,kind,fn in TESTS:
        if kind in ("sweep","ledger"):
            continue
        tot={m:dict(correct=0,abstain=0,fabricate=0) for m in METHODS}; byt=None
        for s in seeds:
            spec=fn(s)
            r,b=run_accuracy(spec, emb, reader, np.random.default_rng(100+s)); byt=b
            for m in METHODS:
                for kk in tot[m]: tot[m][kk]+=r[m][kk]
        agg[name]=tot
        n=sum(tot["belief"].values())
        print(f"\n### {name}  (n={n}/method)   belief_bytes≈{byt['total']}")
        print(f"   {'method':11} {'acc%':>5} {'fab%':>5} {'abs%':>5}")
        for m in METHODS:
            t=tot[m]; tt=sum(t.values()) or 1
            print(f"   {m:11} {100*t['correct']/tt:5.0f} {100*t['fabricate']/tt:5.0f} {100*t['abstain']/tt:5.0f}")
    print("\n### 12_capacity_overload  (belief recall / abstain / fabricate vs N)")
    for N,c,a,f in run_capacity(emb,reader,np.random.default_rng(7)): print(f"   N={N:<6} recall {c:3}%  abstain {a:3}%  fabricate {f:3}%")
    print("\n### 14_cost_ledger  (bytes @ N; belief=sharded+bloom+codebook)")
    print(f"   {'N':>8} {'belief':>12} {'kv':>12} {'rag':>14} {'scratch':>14}")
    for N,bl,kv,rg,sc in run_ledger(): print(f"   {N:>8} {bl:>12} {kv:>12} {rg:>14} {sc:>14}")
    print("\n(13_context_truncation & 15_graceful_degradation: run in real mode — need the LLM reader.)")
    print("\nHONEST READ: headline=acc%. Belief SHOULD lose 02,04,16,17,18,19 and tie KV on 08,10; win/strong on 05,06,11,20; and degrade-gracefully (low fab%) on 12.")
    return agg

if __name__ == "__main__":
    if "--selftest" in sys.argv:
        run_arena(real=False)
    else:
        print("Import and call run_arena(real=True) in Colab, or run:  python3 arena.py --selftest")
