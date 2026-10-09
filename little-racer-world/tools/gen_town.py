#!/usr/bin/env python3
"""Generates data/towns/sunnyvale.json (map, stars) - run once, output is committed."""
import json, random
N = 23
LINES = [1, 6, 11, 16, 21]
PARKS = {(1, 1), (2, 2), (0, 3), (3, 0)}
g = [["F"] * N for _ in range(N)]
for r in range(1, N - 1):
    for c in range(1, N - 1):
        g[r][c] = "."
for r in range(N):
    for c in range(N):
        if (r in LINES and 1 <= c <= N - 2) or (c in LINES and 1 <= r <= N - 2):
            g[r][c] = "#"
def block(c): 
    for i in range(4):
        if LINES[i] < c < LINES[i + 1]: return i
    return None
for r in range(N):
    for c in range(N):
        if g[r][c] == "." and (block(r), block(c)) in [(a, b) for (a, b) in PARKS]:
            g[r][c] = "P"
rng = random.Random(7)
road = [(c, r) for r in range(N) for c in range(N) if g[r][c] == "#"]
stars = []
while len(stars) < 32:
    c, r = rng.choice(road)
    if (c, r) in [(6, 21), (5, 21), (4, 21)]: continue
    x, z = c + 0.5 + rng.uniform(-0.25, 0.25), r + 0.5 + rng.uniform(-0.25, 0.25)
    stars.append([round(x, 2), round(z, 2)])
town = {"id": "sunnyvale", "name": "Sunnyvale", "cell": 12.0, "cols": N, "rows": N,
        "map": ["".join(row) for row in g], "stars": stars, "spawn": {"cell": [6, 21], "dir": [1, 0]}}
json.dump(town, open("data/towns/sunnyvale.json", "w"), indent=1)
print("\n".join(town["map"]))
