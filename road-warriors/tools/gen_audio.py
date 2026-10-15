#!/usr/bin/env python3
"""Generates placeholder game audio as raw 16-bit mono PCM @22050 Hz into assets/audio/*.pcm"""
import math, random, struct, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)
random.seed(7)

def save(name, samples):
    data = b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples)
    open(os.path.join(OUT, name + ".pcm"), "wb").write(data)
    print(name, len(samples) / SR, "s")

def env(i, n, a=0.01, r=0.3):
    t = i / SR; d = n / SR
    return min(1, t / a) * max(0, 1 - max(0, t - (d - r)) / r) if r else min(1, t / a)

def noise_burst(dur, lp=0.3, decay=6.0, boom=0.0, boomf=60):
    n = int(SR * dur); out = []; y = 0
    for i in range(n):
        t = i / SR
        y += (random.uniform(-1, 1) - y) * lp
        v = y * math.exp(-decay * t)
        if boom: v += boom * math.sin(2 * math.pi * boomf * t * (1 - 0.5 * t / dur)) * math.exp(-decay * 0.7 * t)
        out.append(v * 0.9)
    return out

# engine: harmonic stack with whole cycles per second so the 1 s loop is seamless
n = SR
eng = []
for i in range(n):
    t = i / SR
    v = 0
    for h, a in ((1, 1.0), (2, 0.7), (3, 0.5), (4, 0.35), (6, 0.2), (8, 0.12)):
        v += a * math.sin(2 * math.pi * 55 * h * t + 0.7 * h)
    v *= 0.55 + 0.25 * math.sin(2 * math.pi * 11 * t)
    eng.append(math.tanh(v * 0.6) * 0.55)
save("engine", eng)

# nitro loop: filtered noise + rising tone (1 s, seamless-ish via periodic tone)
nit = []; y = 0
for i in range(SR):
    t = i / SR
    y += (random.uniform(-1, 1) - y) * 0.18
    nit.append(y * 0.8 + 0.25 * math.sin(2 * math.pi * 220 * t) * (0.6 + 0.4 * math.sin(2 * math.pi * 7 * t)))
save("nitro", nit)

save("hit", noise_burst(0.28, 0.35, 14, 0.9, 90))
save("swing", [s * 0.5 for s in noise_burst(0.16, 0.9, 18)])
save("crash", noise_burst(0.9, 0.22, 4.5, 1.0, 55))
save("bump", noise_burst(0.2, 0.25, 16, 0.8, 70))

def chirp(f0, f1, dur, vol=0.6):
    out = []; ph = 0; n = int(SR * dur)
    for i in range(n):
        f = f0 + (f1 - f0) * i / n; ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) * env(i, n, 0.005, dur * 0.5) * vol)
    return out
save("pickup", chirp(600, 1200, 0.1) + chirp(900, 1500, 0.16))
save("beep", chirp(880, 880, 0.2))
save("go", chirp(1320, 1320, 0.5))
save("click", chirp(500, 300, 0.05, 0.5))
save("overtake", chirp(500, 900, 0.09) + chirp(700, 1100, 0.12))
save("nearmiss", chirp(300, 1400, 0.18, 0.4))

# music: 4 bars @ 132 bpm, A minor, bass + kick + hat + arp lead
bpm = 132; beat = 60 / bpm; bars = 4; total = int(SR * beat * 4 * bars)
mus = [0.0] * total
def add(start, samples, vol=1.0):
    for k, s in enumerate(samples):
        j = start + k
        if j < total: mus[j] += s * vol
def note(f, dur, kind="saw", vol=0.3):
    n = int(SR * dur); out = []
    for i in range(n):
        t = i / SR; ph = (t * f) % 1.0
        v = (2 * ph - 1) if kind == "saw" else (1 if ph < 0.5 else -1)
        out.append(v * vol * env(i, n, 0.004, min(0.12, dur * 0.6)))
    return out
roots = [55.0, 55.0, 43.65, 49.0]  # A1 A1 F1 G1
scale = [1, 1.2, 1.5, 1.8, 2.0]
for bar in range(bars):
    for b in range(8):
        at = int(SR * (bar * 4 + b * 0.5) * beat)
        add(at, note(roots[bar] * (2 if b % 4 == 3 else 1), beat * 0.45, "sq", 0.32))
    for b in range(4):
        at = int(SR * (bar * 4 + b) * beat)
        kick = [math.sin(2 * math.pi * (110 - 70 * (i / (SR * 0.18))) * i / SR) * math.exp(-i / (SR * 0.05)) * 0.9 for i in range(int(SR * 0.18))]
        add(at, kick)
    for b in range(8):
        at = int(SR * (bar * 4 + b * 0.5 + 0.25) * beat)
        add(at, [random.uniform(-1, 1) * math.exp(-i / (SR * 0.012)) * 0.18 for i in range(int(SR * 0.05))])
    for b in range(16):
        f = roots[bar] * 4 * scale[(b * 3 + bar) % 5]
        add(int(SR * (bar * 4 + b * 0.25) * beat), note(f, beat * 0.22, "saw", 0.10))
peak = max(abs(x) for x in mus)
save("music", [x / peak * 0.8 for x in mus])
