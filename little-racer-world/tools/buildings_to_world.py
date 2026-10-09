#!/usr/bin/env python3
"""Overture Maps buildings (Google Open Buildings CC BY 4.0, Microsoft ML Buildings ODbL, OpenStreetMap ODbL)
-> data/buildings/footprints.json : de-duplicated, simplified, local-metre rectangles per real building.

Fetch (on a machine with `pip install overturemaps`):
  overturemaps download --bbox=73.040,25.126,73.080,25.152 -f geojson --type=building -o data/buildings/overture_raw.geojson
Run from the repo root:  python3 tools/buildings_to_world.py
Output rows: [cx, cz, angle_rad, w, d, source(0 osm,1 google,2 microsoft), area_m2]; irregular (L/U-shaped)
footprints become up to 3 rectangles that together cover the real outline."""
import json, math
LAT0, LON0 = 25.1389, 73.0655
MX = 111320.0 * math.cos(math.radians(LAT0)); MY = 110574.0
BOUNDS = (-2100.0, -1150.0, 1150.0, 1150.0)
MIN_AREA = 12.0
PRI = {"OpenStreetMap": 0, "Google Open Buildings": 1, "Microsoft ML Buildings": 2}

def area(p):
    return abs(sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))) / 2
def inpoly(x, z, p):
    c = False
    for i in range(len(p)):
        x1, z1 = p[i]; x2, z2 = p[(i + 1) % len(p)]
        if (z1 > z) != (z2 > z) and x < (x2 - x1) * (z - z1) / (z2 - z1) + x1: c = not c
    return c
def rdp(pts, eps):
    if len(pts) < 3: return pts
    a, b = pts[0], pts[-1]; dx, dz = b[0] - a[0], b[1] - a[1]; L = math.hypot(dx, dz) or 1e-9
    m, k = 0, 0
    for i in range(1, len(pts) - 1):
        d = abs((pts[i][0] - a[0]) * dz - (pts[i][1] - a[1]) * dx) / L
        if d > m: m, k = d, i
    if m > eps: return rdp(pts[:k + 1], eps)[:-1] + rdp(pts[k:], eps)
    return [a, b]
def simplify(p, eps=0.5):
    q = rdp(p + [p[0]], eps)[:-1]
    return q if len(q) >= 3 else p
def obb(p):
    best = None
    for deg in range(0, 90, 3):
        a = math.radians(deg); c, s = math.cos(a), math.sin(a)
        xs = [x * c + z * s for x, z in p]; zs = [-x * s + z * c for x, z in p]
        ar = (max(xs) - min(xs)) * (max(zs) - min(zs))
        if best is None or ar < best[0]: best = (ar, a, min(xs), max(xs), min(zs), max(zs))
    return best
def to_world(a, mx, mz):
    c, s = math.cos(a), math.sin(a)
    return mx * c - mz * s, mx * s + mz * c

def decompose(p, a, x0, x1, z0, z1, oarea):
    """greedy max-rectangles in the OBB frame (raster), for irregular outlines"""
    step = 0.5 if oarea < 400 else 1.0
    c, s = math.cos(a), math.sin(a)
    q = [(x * c + z * s, -x * s + z * c) for x, z in p]
    nx = max(1, int((x1 - x0) / step)); nz = max(1, int((z1 - z0) / step))
    g = [[inpoly(x0 + (i + .5) * step, z0 + (j + .5) * step, q) for i in range(nx)] for j in range(nz)]
    total = sum(sum(r) for r in g) or 1
    out = []; covered = 0
    for _ in range(3):
        h = [0] * nx; best = (0, 0, 0, 0, 0)
        for j in range(nz):
            for i in range(nx): h[i] = h[i] + 1 if g[j][i] else 0
            st = []
            for i in range(nx + 1):
                cur = h[i] if i < nx else 0
                start = i
                while st and st[-1][1] >= cur:
                    si, sh = st.pop()
                    if sh * (i - si) > best[0]: best = (sh * (i - si), si, i, j - sh + 1, j + 1)
                    start = si
                st.append((start, cur))
        n, i0, i1, j0, j1 = best
        if n < 6 or (out and n < total * 0.12): break
        out.append((x0 + i0 * step, x0 + i1 * step, z0 + j0 * step, z0 + j1 * step))
        covered += n
        for j in range(j0, j1):
            for i in range(i0, i1): g[j][i] = False
        if covered > total * 0.88: break
    return out

def main():
    feats = json.load(open("data/buildings/overture_raw.geojson"))["features"]
    items = []
    for f in feats:
        ring = f["geometry"]["coordinates"][0]
        p = [((lo - LON0) * MX, -(la - LAT0) * MY) for lo, la in ring[:-1]]
        if len(p) < 3: continue
        cx = sum(x for x, _ in p) / len(p); cz = sum(z for _, z in p) / len(p)
        if cx < BOUNDS[0] or cx > BOUNDS[2] or cz < BOUNDS[1] or cz > BOUNDS[3]: continue
        a = area(p)
        if a < MIN_AREA: continue
        ds = (f["properties"].get("sources") or [{}])[0].get("dataset")
        items.append((PRI.get(ds, 2), -a, p, a))
    items.sort(key=lambda t: (t[0], t[1]))
    grid = {}; kept = []
    def cell_range(p):
        xs = [x for x, _ in p]; zs = [z for _, z in p]
        return range(int(min(xs) // 40), int(max(xs) // 40) + 1), range(int(min(zs) // 40), int(max(zs) // 40) + 1)
    dup = 0
    for pri, _, p, a in items:
        xs = [x for x, _ in p]; zs = [z for _, z in p]
        samples = [(min(xs) + (max(xs) - min(xs)) * (i + .5) / 6, min(zs) + (max(zs) - min(zs)) * (j + .5) / 6) for i in range(6) for j in range(6)]
        samples = [s for s in samples if inpoly(s[0], s[1], p)] or [(sum(xs) / len(xs), sum(zs) / len(zs))]
        ri, rj = cell_range(p)
        near = {k for i in ri for j in rj for k in grid.get((i, j), ())}
        hit = sum(1 for s in samples if any(inpoly(s[0], s[1], kept[k]) for k in near))
        if hit / len(samples) > 0.35: dup += 1; continue
        kept.append(p)
        for i in ri:
            for j in rj: grid.setdefault((i, j), []).append(len(kept) - 1)
        kept[-1] = p
        kept_meta.append((pri, a))
    rows = []
    for p, (pri, a) in zip(kept, kept_meta):
        q = simplify(p)
        ar, ang, x0, x1, z0, z1 = obb(q)
        fill = a / max(ar, 1e-6)
        rects = [(x0, x1, z0, z1)]
        if fill < 0.78 and a > 45: rects = decompose(q, ang, x0, x1, z0, z1, ar) or rects
        for rx0, rx1, rz0, rz1 in rects:
            w, d = rx1 - rx0, rz1 - rz0
            if w < 2.2 or d < 2.2: continue
            cx, cz = to_world(ang, (rx0 + rx1) / 2, (rz0 + rz1) / 2)
            rows.append([round(cx, 1), round(cz, 1), round(ang, 3), round(w, 1), round(d, 1), pri, round(a)])
    json.dump({"src": "Overture Maps Foundation 2026 (Google Open Buildings CC BY 4.0, Microsoft ML Buildings ODbL, OpenStreetMap contributors ODbL)",
               "n_raw": len(feats), "n_dup_dropped": dup, "rects": rows}, open("data/buildings/footprints.json", "w"), separators=(",", ":"))
    print("raw", len(feats), "kept buildings", len(kept), "dup dropped", dup, "rects", len(rows))
kept_meta = []
if __name__ == "__main__": main()
