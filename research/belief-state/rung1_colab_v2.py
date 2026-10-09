# ====================================================================
# RUNG-1 GATE v2 (corrected)  — the day-one lab signal for Belief.
#
# HOW TO RUN (free Colab, T4 GPU recommended; CPU works but slow):
#   Cell 1:  !pip -q install transformers accelerate torch sentence-transformers
#   Cell 2:  paste this whole file and run.  (~10 min on T4)
#
# WHAT IT TESTS: with MANY facts per scenario (only a few relevant per question),
# does a small LLM answer as well from a VSA "belief" vector as from a plain-text
# scratchpad (the ceiling) or RAG (retrieval)? scratchpad has everything in context;
# RAG retrieves top-k; belief decodes from ONE fixed-size vector.
#
# FIXES vs the old rung1_colab.py (which made belief look broken):
#   (1) a REAL sentence-transformer embedder (MiniLM), SEPARATE from the chat model
#       — the old code used the chat model's raw mean-pooled hidden states (anisotropic,
#       unnormalized) as "embeddings", which is the v3 "belief 8%" harness bug.
#   (2) a fixed RANDOM PROJECTION 384->D then sign, instead of TILING a short vector
#       (tiling secretly capped real capacity at ~embed_dim/41 facts regardless of D).
#   (3) L2-normalized embeddings; confidence floor -> UNSURE (never fabricate).
# ====================================================================
import numpy as np, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from sentence_transformers import SentenceTransformer

CHAT = "Qwen/Qwen2.5-1.5B-Instruct"     # the small model ALESIS-class ships
D, FLOOR, RAG_K = 8192, 0.05, 3
rng = np.random.default_rng(0)

tok  = AutoTokenizer.from_pretrained(CHAT)
chat = AutoModelForCausalLM.from_pretrained(CHAT, torch_dtype="auto", device_map="auto").eval()
emb  = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")   # REAL embedder (not the chat model)

Edim = emb.get_sentence_embedding_dimension()
P = rng.standard_normal((Edim, D)) / np.sqrt(Edim)        # fixed random projection 384 -> D

def embed(texts):
    return np.atleast_2d(emb.encode(list(texts), normalize_embeddings=True))
def hyper(texts):                                          # text -> semantic +/-1 hypervector (D-dim)
    return np.sign(embed(texts) @ P)

@torch.no_grad()
def ask(context, q):
    msg = [{"role":"user","content":f"{context}\n\nUsing ONLY the information above, answer in 1-5 words.\nQ: {q}\nA:"}]
    text = tok.apply_chat_template(msg, tokenize=False, add_generation_prompt=True)
    ids  = tok(text, return_tensors="pt").to(chat.device)
    out  = chat.generate(**ids, max_new_tokens=16, do_sample=False, pad_token_id=tok.eos_token_id)
    return tok.decode(out[0, ids["input_ids"].shape[1]:], skip_special_tokens=True).strip()

SCEN = [
 {"facts":{"project":"ALESIS","device":"Samsung S24 Ultra","model_size":"4B","lang":"Dart",
           "chip":"Snapdragon 8 Gen 3","ram":"12GB","owner":"Dylon","goal":"local AI","db":"SQLite"},
  "qa":[("What device?","S24 Ultra"),("Who owns it?","Dylon"),("What language?","Dart"),("How much RAM?","12GB"),("What database?","SQLite")]},
 {"facts":{"pet":"a corgi named Biscuit","city":"Lisbon","job":"luthier","car":"blue Saab",
           "sister":"Mara","allergy":"peanuts","instrument":"cello","coffee":"oat flat white"},
  "qa":[("What job?","luthier"),("Pet's name?","Biscuit"),("Which city?","Lisbon"),("Allergic to what?","peanuts"),("What car?","Saab")]},
 {"facts":{"deadline":"March 3rd","budget":"4000 dollars","lead":"Dana","client":"Northwind",
           "stack":"Flutter","repo":"alesis-core","reviewer":"Sam","status":"in review"},
  "qa":[("Who is lead?","Dana"),("The budget?","4000"),("Who reviews?","Sam"),("Which client?","Northwind"),("What deadline?","March 3")]},
 {"facts":{"flight":"BA249","seat":"14C","gate":"B22","depart":"7:40pm","hotel":"The Marlowe","room":"508","confirmation":"XK7T2","bags":"2"},
  "qa":[("Which seat?","14C"),("What gate?","B22"),("Hotel name?","Marlowe"),("Room number?","508"),("Confirmation code?","XK7T2")]},
 {"facts":{"recipe":"carbonara","eggs":"3","pecorino":"80g","guanciale":"120g","pasta":"spaghetti","serves":"2","time":"20 minutes","tip":"no cream"},
  "qa":[("How many eggs?","3"),("What cheese?","pecorino"),("Serves how many?","2"),("Which pasta?","spaghetti"),("Cooking time?","20")]},
 {"facts":{"patient":"Room 4","med":"amoxicillin","dose":"500mg","freq":"three times daily","allergy":"sulfa","doctor":"Okafor","start":"Tuesday"},
  "qa":[("Which drug?","amoxicillin"),("What dose?","500"),("Allergic to?","sulfa"),("Which doctor?","Okafor"),("How often?","three times")]},
 {"facts":{"team":"Rovers","captain":"Ortiz","coach":"Villa","stadium":"Elm Park","colors":"green and white","founded":"1921","rival":"City"},
  "qa":[("Who is captain?","Ortiz"),("Which stadium?","Elm Park"),("Team colors?","green"),("Founded when?","1921"),("Who is coach?","Villa")]},
 {"facts":{"wifi":"Starlink-7A","password":"copper-otter-49","printer":"HP-2200","server":"nas01","backup":"Sunday 2am","admin":"Priya","vpn":"on"},
  "qa":[("Wifi name?","Starlink-7A"),("Who is admin?","Priya"),("Backup when?","Sunday"),("Which printer?","HP-2200"),("Server name?","nas01")]},
 {"facts":{"book":"The Glass Hours","author":"N. Reyes","pages":"312","chapter":"7","character":"Ada","setting":"a lighthouse","genre":"mystery"},
  "qa":[("Who wrote it?","Reyes"),("Main character?","Ada"),("How many pages?","312"),("What setting?","lighthouse"),("Which genre?","mystery")]},
 {"facts":{"car_service":"oil change","mileage":"62000","next":"67000","tire":"front-left low","shop":"Vince's","cost":"89 dollars","oil":"5W-30"},
  "qa":[("Current mileage?","62000"),("Which shop?","Vince"),("What oil?","5W-30"),("What cost?","89"),("Which tire is low?","front-left")]},
 {"facts":{"meeting":"Q3 review","when":"Thursday 10am","room":"Birch","owner":"Lena","topic":"churn","decision":"ship v4","followup":"email board"},
  "qa":[("When is it?","Thursday"),("Which room?","Birch"),("Who owns it?","Lena"),("What decision?","ship v4"),("Main topic?","churn")]},
 {"facts":{"plant":"monstera","water":"every 9 days","light":"indirect","fertilizer":"monthly","repotted":"April","pot":"terracotta","issue":"yellow leaf"},
  "qa":[("Which plant?","monstera"),("Water how often?","9 days"),("What light?","indirect"),("Repotted when?","April"),("What pot?","terracotta")]},
 {"facts":{"song":"Ember","artist":"Ko Vale","bpm":"104","key":"D minor","length":"3:48","album":"Tidewater","producer":"J. Marsh"},
  "qa":[("Who is the artist?","Ko Vale"),("What BPM?","104"),("Which key?","D minor"),("How long?","3:48"),("Which album?","Tidewater")]},
]

ROLES = {}
def role(k):
    if k not in ROLES: ROLES[k] = rng.choice([-1.,1.], size=D)
    return ROLES[k]

def build_belief(facts):
    keys = list(facts.keys()); vals = list(facts.values())
    vecs = hyper(vals)                                   # batch-embed the values
    belief = np.zeros(D)
    for i,k in enumerate(keys): belief += role(k) * vecs[i]
    return np.sign(belief), keys, vals, vecs

def belief_context(belief, keys, vals, vecs):
    lines = []
    for k in keys:
        est  = belief * role(k)
        sims = (vecs @ est) / D                          # cleanup against this scenario's values
        j = int(np.argmax(sims))
        lines.append(f"{k}: {vals[j] if sims[j] >= FLOOR else 'UNSURE'}")
    return "Working memory:\n" + "\n".join(lines)

def rag_context(facts, q):
    items = [f"{k}: {v}" for k,v in facts.items()]
    order = np.argsort(-(embed(items) @ embed([q])[0]))[:RAG_K]
    return "Relevant memory:\n" + "\n".join(items[i] for i in order)

def scratch(facts): return "Notes:\n" + "\n".join(f"{k}: {v}" for k,v in facts.items())
def correct(a,g):   return g.lower() in a.lower()

score = {"scratchpad":0, "rag":0, "belief":0}; n = 0
for sc in SCEN:
    belief, keys, vals, vecs = build_belief(sc["facts"])
    bctx = belief_context(belief, keys, vals, vecs)
    for q, gold in sc["qa"]:
        n += 1
        score["scratchpad"] += correct(ask(scratch(sc["facts"]), q), gold)
        score["rag"]        += correct(ask(rag_context(sc["facts"], q), q), gold)
        score["belief"]     += correct(ask(bctx, q), gold)

print(f"\n=== RUNG-1 v2  ({n} questions | chat={CHAT} | embedder=MiniLM | D={D}) ===")
for k in ("scratchpad","rag","belief"):
    print(f"  {k:11}: {score[k]}/{n} = {score[k]/n*100:.0f}%")
print("""
READING THE RESULT (honest):
  scratchpad = ceiling (everything in context). The real question is belief vs rag.
  belief << rag : harness/representation still off (NOT 'belief is bad') -> tell Claude the numbers.
  belief ~= rag : PARITY -> belief carries the same facts in ONE fixed ~1KB vector that
                  never grows -> gate's first bar passed; the decisive edge (aggregate +
                  scale, where context OVERFLOWS) is the next test.
  belief  > rag : gate passed outright -> build it.
""")
