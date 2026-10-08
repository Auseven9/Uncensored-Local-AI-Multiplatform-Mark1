"""
A micro-transformer X-ray. Real mechanism, toy (random, UNTRAINED) weights.
Goal: see that a 'hidden state' is literally a vector, watch each layer transform
it, then READ it and INJECT into it with hooks -- the two moves behind reaching
inside an open-weight model.
"""
import numpy as np
rng = np.random.default_rng(42)

d_model, n_heads, d_ff, n_layers, vocab = 16, 2, 32, 3, 32
d_head = d_model // n_heads

def ln(x, g, b, eps=1e-5):
    mu, var = x.mean(-1, keepdims=True), x.var(-1, keepdims=True)
    return (x - mu) / np.sqrt(var + eps) * g + b
def gelu(x): return 0.5*x*(1+np.tanh(np.sqrt(2/np.pi)*(x+0.044715*x**3)))
def softmax(x):
    x = x - x.max(-1, keepdims=True); e = np.exp(x); return e/e.sum(-1, keepdims=True)
def randw(*s): return rng.standard_normal(s)*0.3

W_emb = randw(vocab, d_model)
W_pos = randw(16, d_model)
layers = [dict(
    ln1_g=np.ones(d_model), ln1_b=np.zeros(d_model),
    Wq=randw(d_model,d_model), Wk=randw(d_model,d_model), Wv=randw(d_model,d_model), Wo=randw(d_model,d_model),
    ln2_g=np.ones(d_model), ln2_b=np.zeros(d_model),
    W1=randw(d_model,d_ff), b1=np.zeros(d_ff), W2=randw(d_ff,d_model), b2=np.zeros(d_model),
) for _ in range(n_layers)]

def attn(x, L):
    T = x.shape[0]
    q, k, v = x@L['Wq'], x@L['Wk'], x@L['Wv']
    out = np.zeros_like(x)
    mask = np.triu(np.ones((T,T)), 1).astype(bool)   # causal: can't see the future
    for h in range(n_heads):
        sl = slice(h*d_head, (h+1)*d_head)
        s = q[:,sl] @ k[:,sl].T / np.sqrt(d_head)
        s[mask] = -1e9
        out[:,sl] = softmax(s) @ v[:,sl]
    return out @ L['Wo']

def mlp(x, L): return gelu(x@L['W1'] + L['b1']) @ L['W2'] + L['b2']

def forward(tokens, hooks=None):
    hooks = hooks or {}
    x = W_emb[tokens] + W_pos[:len(tokens)]          # tokens -> starting vectors
    trace = [('embed', x.copy())]
    for i, L in enumerate(layers):
        x = x + attn(ln(x, L['ln1_g'], L['ln1_b']), L)   # attention + residual
        x = x + mlp(ln(x, L['ln2_g'], L['ln2_b']), L)    # MLP + residual
        if i in hooks: x = hooks[i](x)                   # <-- hook point: read/modify
        trace.append((f'after L{i+1}', x.copy()))
    return x, trace

tokens = [3, 14, 7, 1, 22]   # a pretend 5-token "sentence"
LAST = -1

x, trace = forward(tokens)
print("1) A HIDDEN STATE IS JUST A VECTOR. Last token, flowing through the model:")
print("   (d_model=16, so 16 numbers; showing first 8)\n")
for name, act in trace:
    v = act[LAST]
    print(f"   {name:9} | norm={np.linalg.norm(v):5.2f} | {np.round(v[:8],2)}")

print("\n2) EACH LAYER TRANSFORMS IT. How far it moved from the previous layer:")
for i in range(1, len(trace)):
    prev, cur = trace[i-1][1][LAST], trace[i][1][LAST]
    cos = prev@cur/(np.linalg.norm(prev)*np.linalg.norm(cur))
    print(f"   {trace[i][0]:9} | moved {np.linalg.norm(cur-prev):5.2f} | direction cos-to-prev {cos:+.2f}")

captured = {}
def read_hook(x):
    captured['v'] = x[LAST].copy(); return x          # look, don't touch
forward(tokens, hooks={0: read_hook})
print("\n3) READ HOOK @ layer 1  ('reading out its internal sense of the moment'):")
print("   ", np.round(captured['v'][:8], 2))

steer = rng.standard_normal(d_model) * 1.5
def inject_hook(x):
    x = x.copy(); x[LAST] = x[LAST] + steer; return x  # add a vector INTO the stream
x2, _ = forward(tokens, hooks={0: inject_hook})
print("\n4) INJECT HOOK @ layer 1  ('feeding a belief-state vector inside, no words'):")
print(f"   we added a vector at layer 1; by the end the final state moved {np.linalg.norm(x2[LAST]-x[LAST]):.2f}")
print("   -> it propagated through every later layer and changed the model's output state.")
print("   THAT is the whole mechanism. (Weights are random here, so the MECHANISM is")
print("    real; the meaning is not. In a trained model, these vectors carry meaning.)")
