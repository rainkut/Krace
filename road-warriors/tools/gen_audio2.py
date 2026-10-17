import math, random, struct, sys
R = 22050
out = sys.argv[1] if len(sys.argv) > 1 else "assets/audio"
random.seed(5)

def save(name, xs):
    pk = max(1e-9, max(abs(x) for x in xs))
    b = b"".join(struct.pack("<h", int(max(-1, min(1, x / pk * 0.9)) * 32767)) for x in xs)
    open(f"{out}/{name}.pcm", "wb").write(b)

def lp(xs, a):
    y = 0.0
    r = []
    for x in xs:
        y += a * (x - y)
        r.append(y)
    return r

def loopable(xs, f=2000):
    n = len(xs) - f
    r = xs[:n]
    for i in range(f):
        t = i / f
        r[i] = xs[i] * t + xs[n + i] * (1 - t)
    return r

# engine: single-cylinder-ish thump, 2 s seamless (integer cycles)
n = R * 2
f0 = 50.0
eng = []
for i in range(n):
    t = i / R
    ph = 2 * math.pi * f0 * t
    v = 0.0
    for h in range(1, 14):
        v += math.sin(h * ph + 0.3 * h) / (h ** 0.85)
    fire = 0.65 + 0.35 * math.cos(ph / 2)
    v *= fire
    v += 0.25 * math.sin(2 * math.pi * 3 * f0 * t + 2 * math.sin(2 * math.pi * f0 * t))
    eng.append(v)
noise = [random.uniform(-1, 1) for _ in range(n)]
noise = lp(noise, 0.25)
eng = [e + 0.18 * nz * (0.6 + 0.4 * math.cos(2 * math.pi * f0 * i / R)) for i, (e, nz) in enumerate(zip(eng, noise))]
save("engine", eng)

# wind: broad filtered noise
w = [random.uniform(-1, 1) for _ in range(R * 3 + 2000)]
w = lp(w, 0.12)
w = [a - b for a, b in zip(w, lp(w, 0.01))]
save("wind", loopable(w))

# rain: bright noise with fine crackle
r = [random.uniform(-1, 1) for _ in range(R * 3 + 2000)]
r = [a - b for a, b in zip(r, lp(r, 0.35))]
r = [a * (1.0 + (0.8 if random.random() < 0.02 else 0.0)) for a in r]
save("rain", loopable(r))

# gear shift: short clunk + blip
s = []
for i in range(int(R * 0.18)):
    t = i / R
    e = math.exp(-t * 28)
    s.append(e * (math.sin(2 * math.pi * 140 * t) * 0.8 + random.uniform(-1, 1) * 0.4))
save("shift", s)

# scrape: metal grind
sc = []
for i in range(int(R * 0.5)):
    t = i / R
    e = min(1.0, t * 30) * math.exp(-t * 3)
    sc.append(e * (random.uniform(-1, 1) * 0.6 + math.sin(2 * math.pi * (1800 + 400 * math.sin(t * 40)) * t) * 0.4))
save("scrape", sc)
