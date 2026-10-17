#!/usr/bin/env python3
"""0.7.0 sounds: crunch (takedown), kick (leg thump + snap), siren (looping two-tone). 16-bit mono PCM @22050."""
import math, random, struct, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
random.seed(7)

def save(name, xs):
    peak = max(1e-6, max(abs(x) for x in xs))
    data = b"".join(struct.pack("<h", int(max(-1, min(1, x / peak * 0.9)) * 32000)) for x in xs)
    open(os.path.join(OUT, name + ".pcm"), "wb").write(data)
    print(name, round(len(xs) / SR, 2), "s")

def crunch(dur=0.7):
    out = []; y = 0
    for i in range(int(SR * dur)):
        t = i / SR
        y += (random.uniform(-1, 1) - y) * (0.7 if t < 0.08 else 0.25)
        thump = math.sin(2 * math.pi * (90 - 50 * t) * t) * math.exp(-t * 7)
        crack = y * (math.exp(-t * 9) + (0.5 * math.exp(-((t - 0.18) * 30) ** 2)))
        out.append(thump * 1.1 + crack)
    return out

def kick(dur=0.32):
    out = []; y = 0
    for i in range(int(SR * dur)):
        t = i / SR
        y += (random.uniform(-1, 1) - y) * 0.6
        thump = math.sin(2 * math.pi * (140 - 90 * t) * t) * math.exp(-t * 14)
        snap = y * math.exp(-t * 40)
        out.append(thump * 1.2 + snap * 0.8)
    return out

def siren(dur=1.6):
    out = []; ph = 0
    n = int(SR * dur)
    for i in range(n):
        t = i / SR
        f = 760 + 380 * (1 if (t % 0.8) < 0.4 else 0)
        ph += 2 * math.pi * f / SR
        v = math.sin(ph) + 0.35 * math.sin(2 * ph) + 0.15 * math.sin(3 * ph)
        out.append(v * 0.6)
    return out

save("crunch", crunch()); save("kick", kick()); save("siren", siren())
