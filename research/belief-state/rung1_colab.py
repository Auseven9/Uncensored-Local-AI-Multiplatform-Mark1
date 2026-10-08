"""
RUNG-1, COLAB-READY. The gate experiment: does a small LLM reason BETTER over a
VSA-decoded working memory than over (b) a plain-text scratchpad or (c) RAG?

HOW TO RUN (free Colab T4, ~10 min):
  1. New Colab notebook, Runtime -> change type -> T4 GPU.
  2. First cell:   !pip -q install transformers accelerate torch
  3. Paste this whole file into the next cell and run it.

HONEST NOTE: written in a sandbox WITHOUT torch/GPU, so it is UNTESTED end-to-end.
Read it once before trusting the numbers; the logic is simple on purpose.
The fair test is the MANY-facts case: scratchpad dumps all facts, RAG retrieves
the relevant ones, belief-state decodes them from one vector. Winner must beat
BOTH to justify building the organ.
"""
import numpy as np, torch
from transformers import AutoModelForCausalLM, AutoTokenizer

MODEL = "Qwen/Qwen2.5-1.5B-Instruct"   # small, open-weight, like ALESIS ships
D, FLOOR = 10000, 0.08
rng = np.random.default_rng(0)

tok = AutoTokenizer.from_pretrained(MODEL)
model = AutoModelForCausalLM.from_pretrained(MODEL, torch_dtype="auto", device_map="auto").eval()

@torch.no_grad()
def embed(text):                       # the model's OWN embedding: mean-pooled last layer
    ids = tok(text, return_tensors="pt").to(model.device)
    h = model(**ids, output_hidden_states=True).hidden_states[-1][0]
    return h.mean(0).float().cpu().numpy()

@torch.no_grad()
def ask(context, q):
    msg = [{"role": "user", "content": f"{context}\n\nUsing ONLY the information above, answer in 1-5 words.\nQ: {q}\nA:"}]
    ids = tok.apply_chat_template(msg, add_generation_prompt=True, return_tensors="pt").to(model.device)
    out = model.generate(ids, max_new_tokens=16, do_sample=False, pad_token_id=tok.eos_token_id)
    return tok.decode(out[0, ids.shape[1]:], skip_special_tokens=True).strip()

# ---------- scenarios: many facts each, only some relevant per question ----------
SCEN = [
 {"facts": {"project":"ALESIS","device":"Samsung S24 Ultra","model_size":"4B","lang":"Dart",
            "chip":"Snapdragon 8 Gen 3","ram":"12GB","owner":"Dylon","goal":"local AI"},
  "qa": [("What device does it run on?","S24 Ultra"),("Who owns it?","Dylon"),
         ("What language?","Dart"),("How much RAM?","12GB")]},
 {"facts": {"pet":"a corgi named Biscuit","city":"Lisbon","job":"luthier","car":"blue Saab",
            "sister":"Mara","allergy":"peanuts","instrument":"cello","coffee":"oat flat white"},
  "qa": [("What is their job?","luthier"),("What's the pet's name?","Biscuit"),
         ("Which city?","Lisbon"),("What are they allergic to?","peanuts")]},
 {"facts": {"deadline":"March 3rd","budget":"4000 dollars","lead":"Dana","client":"Northwind",
            "stack":"Flutter","repo":"alesis-core","reviewer":"Sam","status":"in review"},
  "qa": [("Who is the lead?","Dana"),("What's the budget?","4000"),
         ("Who reviews?","Sam"),("Which client?","Northwind")]},
]

def hv(n): return rng.choice([-1.0, 1.0], size=(n, D))
ROLES = {}
def role(k):
    if k not in ROLES: ROLES[k] = hv(1)[0]
    return ROLES[k]

def build_vsa(facts):
    # value -> sign(embedding); bind role(key); bundle. Global cleanup memory = these values.
    item_mem = {}
    belief = np.zeros(D)
    for k, v in facts.items():
        fv = np.sign(embed(v)); fv = np.tile(fv, D // len(fv) + 1)[:D]   # pad emb -> D
        item_mem[k] = (v, fv)
        belief += role(k) * fv
    return np.sign(belief), item_mem

def vsa_decode_all(belief, item_mem):
    lines = []
    for k, (_, _) in item_mem.items():
        est = belief * role(k)
        best_v, best_s = "UNSURE", FLOOR
        for _, (v2, fv2) in item_mem.items():
            s = float(est @ fv2) / D
            if s > best_s: best_s, best_v = s, v2
        lines.append(f"{k}: {best_v}")
    return "Working memory:\n" + "\n".join(lines)

def rag_context(facts, q, topk=3):
    qe = embed(q)
    scored = sorted(((float(qe @ embed(f"{k}: {v}")), f"{k}: {v}") for k, v in facts.items()), reverse=True)
    return "Relevant memory:\n" + "\n".join(s for _, s in scored[:topk])

def scratchpad_context(facts):
    return "Notes:\n" + "\n".join(f"{k}: {v}" for k, v in facts.items())

def correct(ans, gold): return gold.lower() in ans.lower()

score = {"scratchpad":0, "rag":0, "belief":0}; n = 0
for sc in SCEN:
    belief, item_mem = build_vsa(sc["facts"])
    vsa_ctx = vsa_decode_all(belief, item_mem)
    for q, gold in sc["qa"]:
        n += 1
        score["scratchpad"] += correct(ask(scratchpad_context(sc["facts"]), q), gold)
        score["rag"]        += correct(ask(rag_context(sc["facts"], q), q), gold)
        score["belief"]     += correct(ask(vsa_ctx, q), gold)

print(f"\n=== RUNG-1 RESULT ({n} questions, model={MODEL}) ===")
for k in ("scratchpad","rag","belief"):
    print(f"  {k:11}: {score[k]}/{n} = {score[k]/n*100:.0f}%")
print("\nVERDICT: belief-state must beat BOTH scratchpad and rag to justify the organ.")
print("If it only ties or loses -> it's RAG with extra steps. Stop. (That's a WIN for the team: weeks saved.)")
