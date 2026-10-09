#!/usr/bin/env python3
"""Build race routes on the real Sheoganj road graph: snap anchor points (metres from centre) to the
nearest road node and chain shortest paths, penalising roads already used so loops don't double back.
Prints JSON waypoint lists (x,z metres) to paste into data/races.json (already done for shipped races)."""
import json, heapq, math, sys
W = json.load(open("data/osm/sheoganj_world.json"))
pos, adj = {}, {}
for r in W["roads"]:
    for a, b, pa, pb in zip(r["ids"], r["ids"][1:], r["p"], r["p"][1:]):
        pos[a], pos[b] = pa, pb
        d = math.dist(pa, pb)
        adj.setdefault(a, []).append((b, d)); adj.setdefault(b, [])
        if not r.get('oneway'): adj[b].append((a, d))
def nearest(pt): return min(adj, key=lambda n: math.dist(pos[n], pt))
def path(a, b, used):
    pq, best, prev = [(0, a)], {a: 0}, {}
    while pq:
        c, n = heapq.heappop(pq)
        if n == b: break
        if c > best[n]: continue
        for m, d in adj[n]:
            k = frozenset((n, m)); cc = c + d * (8 if k in used else 1)
            if cc < best.get(m, 1e18): best[m] = cc; prev[m] = n; heapq.heappush(pq, (cc, m))
    out = [b]
    while out[-1] != a: out.append(prev[out[-1]])
    return out[::-1]
def route(anchors):
    ids = [nearest(a) for a in anchors]; ids.append(ids[0])
    used, full = set(), [ids[0]]
    for a, b in zip(ids, ids[1:]):
        seg = path(a, b, used)
        for x, y in zip(seg, seg[1:]): used.add(frozenset((x, y)))
        full += seg[1:]
    pts = [pos[n] for n in full[:-1]]
    out = [pts[0]]
    for p in pts[1:]:
        if math.dist(p, out[-1]) >= 9: out.append(p)
    return out
ROUTES = {
 "main_road": [(-232, -461), (245, -133), (698, 289), (420, 330), (100, 100), (-300, -150)],
 "old_lanes": [(120, 40), (300, 250), (200, 420), (20, 250), (-60, 90)],
 "bus_station": [(-593, -410), (-300, -420), (-110, -80), (-330, 20), (-520, -250)],
}
res = {k: route(v) for k, v in ROUTES.items()}
for k, v in res.items():
    L = sum(math.dist(a, b) for a, b in zip(v, v[1:] + v[:1]))
    print(k, len(v), "pts", round(L), "m", file=sys.stderr)
json.dump(res, open("data/osm/routes.json", "w"), separators=(",", ":"))
