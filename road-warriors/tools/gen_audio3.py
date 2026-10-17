#!/usr/bin/env python3
"""Dramatic one-shots: tyre screech, launch whoosh, landing thud, trick stinger, heavy impact. 16-bit mono PCM @22050."""
import math, random, struct, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
random.seed(11)

def save(name, xs):
    peak = max(1e-6, max(abs(x) for x in xs))
    data = b"".join(struct.pack("<h", int(max(-1, min(1, x / peak * 0.9)) * 32000)) for x in xs)
    open(os.path.join(OUT, name + ".pcm"), "wb").write(data)
    print(name, round(len(xs) / SR, 2), "s")

def screech(dur=0.7):
    out = []; y = 0
    for i in range(int(SR * dur)):
        t = i / SR
        f = 1700 + 300 * math.sin(2 * math.pi * 7 * t) + 400 * t
        y += (random.uniform(-1, 1) - y) * 0.5
        v = 0.6 * math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * f * 1.51 * t) + 0.5 * y
        out.append(v * min(1, t / 0.05) * min(1, (dur - t) / 0.2))
    return out

def whoosh(dur=0.9):
    out = []; y = 0
    for i in range(int(SR * dur)):
        t = i / SR; p = t / dur
        lp = 0.04 + 0.5 * math.sin(math.pi * p) ** 2
        y += (random.uniform(-1, 1) - y) * lp
        out.append(y * math.sin(math.pi * p) ** 1.5)
    return out

def thud(dur=0.8):
    out = []; y = 0
    for i in range(int(SR * dur)):
        t = i / SR
        y += (random.uniform(-1, 1) - y) * 0.2
        sub = math.sin(2 * math.pi * (95 * math.exp(-3 * t) + 38) * t) * math.exp(-5 * t)
        out.append(sub * 1.2 + y * math.exp(-22 * t) * 0.9)
    return out

def stinger(dur=1.1):
    out = []
    for i in range(int(SR * dur)):
        t = i / SR; v = 0
        for k, f in enumerate((261.6, 329.6, 392.0, 523.3)):
            tt = t - k * 0.06
            if tt > 0:
                v += math.sin(2 * math.pi * f * tt) * 0.4 * math.exp(-2.8 * tt) * min(1, tt / 0.005)
        v += math.sin(2 * math.pi * (70 * math.exp(-4 * t) + 40) * t) * math.exp(-6 * t) * 0.9
        out.append(v)
    return out

def impact(dur=1.4):
    out = []; y = 0
    for i in range(int(SR * dur)):
        t = i / SR
        y += (random.uniform(-1, 1) - y) * 0.35
        v = y * math.exp(-9 * t) * 1.0
        v += math.sin(2 * math.pi * (80 * math.exp(-2.5 * t) + 32) * t) * math.exp(-3.2 * t) * 1.3
        for f in (410, 667, 1130):
            v += math.sin(2 * math.pi * f * t) * 0.25 * math.exp(-6 * t)
        out.append(v)
    return out

save("screech", screech()); save("whoosh", whoosh()); save("thud", thud()); save("stinger", stinger()); save("impact", impact())
