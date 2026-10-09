#!/usr/bin/env python3
"""Generate the *invented* parts of the Sheoganj world on top of the real OSM data, deterministically.

Real (from OSM, see osm_to_world.py): road centre-lines/classes/widths/names, landuse + water polygons,
POI positions (hospital, clinic, bus station), the 7 mapped building footprints.
Generated here (OSM has almost no building data for Sheoganj): row-house/shop footprints, heights, wall
colours, roadside trees, electric poles + wires, street lights, star positions, stunt-park location.
Result is written into data/osm/sheoganj_world.json under "gen"."""
import json, math, random

random.seed(20261009)
W = json.load(open("data/osm/sheoganj_world.json"))
W.pop("gen", None)
EXT = 1100.0
BOUNDS = (-2100.0, -1150.0, 1150.0, 1150.0)   # xmin, zmin, xmax, zmax - the east town plus the Ashapurna disc to the west
PIN = (-1241.0, 315.0)
def out_of_bounds(x, z): return x < BOUNDS[0] or x > BOUNDS[2] or z < BOUNDS[1] or z > BOUNDS[3]
roads = [r for r in W["roads"] if r["c"] != "track"]

# ---------------- road segment index ----------------
CELL = 32.0
segs = []        # (ax, az, bx, bz, hw)
grid = {}
def add_seg(a, b, hw):
    i = len(segs); segs.append((a[0], a[1], b[0], b[1], hw))
    for cx in range(int(math.floor(min(a[0], b[0]) / CELL)), int(math.floor(max(a[0], b[0]) / CELL)) + 1):
        for cz in range(int(math.floor(min(a[1], b[1]) / CELL)), int(math.floor(max(a[1], b[1]) / CELL)) + 1):
            grid.setdefault((cx, cz), []).append(i)
for r in W["roads"]:
    hw = r["w"] / 2
    p = r["p"]
    for a, b in zip(p, p[1:]):
        L = math.dist(a, b); n = max(1, int(math.ceil(L / 24)))
        for k in range(n):
            add_seg((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n),
                    (a[0] + (b[0] - a[0]) * (k + 1) / n, a[1] + (b[1] - a[1]) * (k + 1) / n), hw)

def seg_dist(px, pz, s):
    ax, az, bx, bz, hw = s
    dx, dz = bx - ax, bz - az
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz + 1e-9)))
    return math.hypot(px - (ax + dx * t), pz - (az + dz * t))

def edge_dist(px, pz, rad=1):
    """distance to the nearest road *edge* (negative = on the road); 99 if none within the searched cells"""
    cx, cz = int(math.floor(px / CELL)), int(math.floor(pz / CELL))
    best = 99.0; seen = set()
    for i in range(cx - rad, cx + rad + 1):
        for j in range(cz - rad, cz + rad + 1):
            for si in grid.get((i, j), ()):
                if si in seen: continue
                seen.add(si)
                d = seg_dist(px, pz, segs[si]) - segs[si][4]
                if d < best: best = d
    return best

# ---------------- polygons ----------------
def in_poly(px, pz, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, z1 = poly[i]; x2, z2 = poly[(i + 1) % n]
        if (z1 > pz) != (z2 > pz) and px < (x2 - x1) * (pz - z1) / (z2 - z1 + 1e-12) + x1:
            inside = not inside
    return inside
water = [a["p"] for a in W["areas"] if a["k"] == "water" and a["closed"]]
farm = [a["p"] for a in W["areas"] if a["k"] in ("farmland", "scrub") and a["closed"]]
river = [a["p"] for a in W["areas"] if a["k"] == "waterway:river"]
def dist_river(px, pz):
    best = 1e9
    for line in river:
        for a, b in zip(line, line[1:]):
            best = min(best, seg_dist(px, pz, (a[0], a[1], b[0], b[1], 0)))
    return best
def blocked_land(px, pz):
    if any(in_poly(px, pz, w) for w in water): return True
    if dist_river(px, pz) < 14: return True
    return False
def in_open_land(px, pz):
    return any(in_poly(px, pz, f) for f in farm)

# ---------------- building rects ----------------
rects = []   # (cx, cz, ux, uz, hx, hz)
rgrid = {}
RC = 16.0
def make_rect(cx, cz, yaw, w, d):
    return (cx, cz, math.cos(yaw), -math.sin(yaw), w / 2, d / 2)
def overlap(a, b, shrink=0.15):
    ua = (a[2], a[3]); va = (-a[3], a[2]); ub = (b[2], b[3]); vb = (-b[3], b[2])
    for ax in (ua, va, ub, vb):
        ra = (a[4] - shrink) * abs(ua[0] * ax[0] + ua[1] * ax[1]) + (a[5] - shrink) * abs(va[0] * ax[0] + va[1] * ax[1])
        rb = (b[4] - shrink) * abs(ub[0] * ax[0] + ub[1] * ax[1]) + (b[5] - shrink) * abs(vb[0] * ax[0] + vb[1] * ax[1])
        if abs((b[0] - a[0]) * ax[0] + (b[1] - a[1]) * ax[1]) > ra + rb: return False
    return True
def rect_cells(r):
    rad = math.hypot(r[4], r[5])
    for i in range(int(math.floor((r[0] - rad) / RC)), int(math.floor((r[0] + rad) / RC)) + 1):
        for j in range(int(math.floor((r[1] - rad) / RC)), int(math.floor((r[1] + rad) / RC)) + 1):
            yield (i, j)
def rect_free(r):
    seen = set()
    for c in rect_cells(r):
        for k in rgrid.get(c, ()):
            if k in seen: continue
            seen.add(k)
            if overlap(r, rects[k]): return False
    return True
def add_rect(r):
    rects.append(r)
    for c in rect_cells(r): rgrid.setdefault(c, []).append(len(rects) - 1)
def point_in_rect(px, pz, r, pad=0.0):
    dx, dz = px - r[0], pz - r[1]
    return abs(dx * r[2] + dz * r[3]) <= r[4] + pad and abs(-dx * r[3] + dz * r[2]) <= r[5] + pad
def near_rect(px, pz, pad):
    cx, cz = int(math.floor(px / RC)), int(math.floor(pz / RC))
    for i in (cx - 1, cx, cx + 1):
        for j in (cz - 1, cz, cz + 1):
            for k in rgrid.get((i, j), ()):
                if point_in_rect(px, pz, rects[k], pad): return True
    return False
def rect_on_road(r, margin=0.2):
    cx, cz, ux, uz, hx, hz = r
    vx, vz = -uz, ux
    for sx, sz in [(0, 0), (1, 1), (1, -1), (-1, 1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1)]:
        px = cx + ux * hx * sx + vx * hz * sz
        pz = cz + uz * hx * sx + vz * hz * sz
        if edge_dist(px, pz) < margin: return True
        if blocked_land(px, pz): return True
    return False

bld = []         # [x, z, yaw, w, d, floors, colour, shop, tank, kind]   kind 0 generated, 1 real, 2 landmark
landmarks = []

def push_off_road(px, pz, clearance):
    for _ in range(12):
        best = None
        cx, cz = int(math.floor(px / CELL)), int(math.floor(pz / CELL))
        for i in range(cx - 2, cx + 3):
            for j in range(cz - 2, cz + 3):
                for si in grid.get((i, j), ()):
                    s = segs[si]
                    ax, az, bx, bz, hw = s
                    dx, dz = bx - ax, bz - az
                    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz + 1e-9)))
                    qx, qz = ax + dx * t, az + dz * t
                    d = math.hypot(px - qx, pz - qz) - hw
                    if best is None or d < best[0]: best = (d, qx, qz)
        if best is None or best[0] >= clearance: break
        d, qx, qz = best
        vx, vz = px - qx, pz - qz
        n = math.hypot(vx, vz) or 1.0
        px += vx / n * (clearance - d + 0.5); pz += vz / n * (clearance - d + 0.5)
    return px, pz

def nearest_road_dir(px, pz):
    best = (1e9, 0, 1, 0, 1)
    cx, cz = int(math.floor(px / CELL)), int(math.floor(pz / CELL))
    for i in range(cx - 2, cx + 3):
        for j in range(cz - 2, cz + 3):
            for si in grid.get((i, j), ()):
                s = segs[si]; d = seg_dist(px, pz, s)
                if d < best[0]:
                    L = math.hypot(s[2] - s[0], s[3] - s[1]) or 1
                    dx, dz = s[2] - s[0], s[3] - s[1]
                    t = max(0.0, min(1.0, ((px - s[0]) * dx + (pz - s[1]) * dz) / (dx * dx + dz * dz + 1e-9)))
                    fx, fz = s[0] + dx * t - px, s[1] + dz * t - pz
                    fl_ = math.hypot(fx, fz) or 1.0
                    best = (d, dx / L, dz / L, fx / fl_, fz / fl_)
    return best

# 1) landmarks from OSM POIs
for p in W["pois"]:
    if p["k"] in ("hospital", "bus_station", "clinic"):
        px, pz = push_off_road(p["p"][0], p["p"][1], 6.5)
        d, tx, tz, fx, fz = nearest_road_dir(px, pz)
        yaw = math.atan2(fx, fz)
        if p["k"] == "hospital":
            w, dd, fl = 18.0, 12.0, 4
        elif p["k"] == "clinic":
            w, dd, fl = 12.0, 9.0, 2
        else:
            w, dd, fl = 0.0, 0.0, 0
        if w > 0:
            r = make_rect(px, pz, yaw, w, dd)
            if not rect_on_road(r) and rect_free(r):
                add_rect(r)
                bld.append([round(px, 1), round(pz, 1), round(yaw, 3), w, dd, fl, 8 if p["k"] == "hospital" else 9, 0, 1, 2])
        landmarks.append({"n": p["n"], "k": p["k"], "x": round(px, 1), "z": round(pz, 1), "h": fl * 3.2 + 3.0})

# 2) real footprints (Overture Maps: Google Open Buildings + Microsoft ML + OSM), see buildings_to_world.py
REAL = json.load(open("data/buildings/footprints.json"))["rects"]
main_segs = []
main_grid = {}
for r in W["roads"]:
    if r["c"] not in ("secondary", "tertiary"): continue
    for a, b in zip(r["p"], r["p"][1:]):
        i = len(main_segs); main_segs.append((a[0], a[1], b[0], b[1], r["w"] / 2))
        for cx in range(int(math.floor(min(a[0], b[0]) / CELL)) - 1, int(math.floor(max(a[0], b[0]) / CELL)) + 2):
            for cz in range(int(math.floor(min(a[1], b[1]) / CELL)) - 1, int(math.floor(max(a[1], b[1]) / CELL)) + 2):
                main_grid.setdefault((cx, cz), []).append(i)
def main_edge_dist(px, pz):
    best = 99.0
    for si in main_grid.get((int(math.floor(px / CELL)), int(math.floor(pz / CELL))), ()):
        best = min(best, seg_dist(px, pz, main_segs[si]) - main_segs[si][4])
    return best
real_n = skipped = 0
PAL_W = [14, 14, 12, 10, 8, 8, 10, 6, 0, 3, 3, 4, 3, 2, 3, 3]
for cx, cz, ang, w, d, src, ar in REAL:
    if edge_dist(cx, cz) < 0.3 or blocked_land(cx, cz): skipped += 1; continue
    dist, tx, tz, fx, fz = nearest_road_dir(cx, cz)
    best = None
    for k in range(4):
        yaw = -ang + k * math.pi / 2
        dot = math.sin(yaw) * fx + math.cos(yaw) * fz
        if best is None or dot > best[0]: best = (dot, yaw, k)
    _, yaw, k = best
    ww, dd = (w, d) if k % 2 == 0 else (d, w)
    r = make_rect(cx, cz, yaw, ww, dd)
    if rect_on_road(r):
        ww *= 0.85; dd *= 0.85
        r = make_rect(cx, cz, yaw, ww, dd)
        if rect_on_road(r, 0.0): skipped += 1; continue
    if not rect_free(r): skipped += 1; continue
    add_rect(r)
    me = main_edge_dist(cx, cz)
    onmain = me < 18
    if ar < 40: fl = random.choices([1, 2], [75, 25])[0]
    elif ar < 110: fl = random.choices([1, 2, 3], [30, 52, 18])[0]
    else: fl = random.choices([2, 3, 4], [45, 40, 15])[0]
    if onmain and fl < 2 and random.random() < 0.5: fl += 1
    col = random.choices(range(16), PAL_W)[0]
    ux, uz = r[2], r[3]
    party = any(point_in_rect(cx + sg * ux * (ww / 2 + 1.0), cz + sg * uz * (ww / 2 + 1.0), x, 0.0) for sg in (1, -1) for x in [rects[kk] for kk in rgrid.get((int(math.floor((cx + sg * ux * (ww / 2 + 1.0)) / RC)), int(math.floor((cz + sg * uz * (ww / 2 + 1.0)) / RC))), ())])
    shop = 1 if (onmain and me < 12 and ar >= 20 and random.random() < 0.85) else (0.4 if party else 0)
    bld.append([round(cx, 1), round(cz, 1), round(yaw, 3), round(ww, 1), round(dd, 1), min(fl, 4), col, shop,
                1 if random.random() < 0.5 else 0, 1])
    real_n += 1
print("real footprints", real_n, "skipped", skipped)

# ---------------- helpers for trees/poles ----------------
def polyline_pts(p, step):
    out = []
    cum = 0.0
    for a, b in zip(p, p[1:]):
        L = math.dist(a, b)
        if L < 1e-6: continue
        tx, tz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        out.append((cum, L, a, tx, tz))
        cum += L
    return out, cum
def at(spans, s):
    for c0, L, a, tx, tz in spans:
        if s <= c0 + L: return a[0] + tx * (s - c0), a[1] + tz * (s - c0), tx, tz
    c0, L, a, tx, tz = spans[-1]
    return a[0] + tx * L, a[1] + tz * L, tx, tz

print("buildings", len(bld))

# ---------------- trees ----------------
trees = []   # [x, z, scale, kind, collide]
def tree_ok(px, pz):
    if out_of_bounds(px, pz) or blocked_land(px, pz): return False
    if edge_dist(px, pz) < 2.2 or near_rect(px, pz, 1.2): return False
    return True
for r in roads:
    spans, total = polyline_pts(r["p"], 1)
    if total < 12 or r["c"] == "service": continue
    hw = r["w"] / 2
    pr = 0.5 if r["c"] in ("secondary", "tertiary") else 0.22
    for side in (1, -1):
        s = random.uniform(2, 14)
        while s < total:
            x, z, tx, tz = at(spans, s)
            px, pz = x - tz * side * (hw + 3.8), z + tx * side * (hw + 3.8)
            if random.random() < pr and tree_ok(px, pz):
                trees.append([round(px, 1), round(pz, 1), round(random.uniform(2.6, 3.8), 2), random.randrange(8), 1])
            s += random.uniform(14, 26)
for f in W["areas"]:
    if f["k"] in ("farmland", "scrub") and f["closed"]:
        xs = [p[0] for p in f["p"]]; zs = [p[1] for p in f["p"]]
        area = (max(xs) - min(xs)) * (max(zs) - min(zs)) * 0.6
        n = min(220, int(area / 2200))
        for _ in range(n * 3):
            if n <= 0: break
            px, pz = random.uniform(min(xs), max(xs)), random.uniform(min(zs), max(zs))
            if in_poly(px, pz, f["p"]) and tree_ok(px, pz) and (math.hypot(px, pz) < 1000 or math.hypot(px - PIN[0], pz - PIN[1]) < 700):
                trees.append([round(px, 1), round(pz, 1), round(random.uniform(2.2, 3.4), 2), random.randrange(8), 0]); n -= 1
trees = trees[:2600]
for t in list(trees):   # High-quality-only extras: a second row of trees/bushes behind the roadside ones
    for _ in range(2):
        a = random.uniform(0, math.tau); r = random.uniform(4.5, 10.0)
        px, pz = t[0] + math.cos(a) * r, t[1] + math.sin(a) * r
        if tree_ok(px, pz) and not near_rect(px, pz, 2.5):
            trees.append([round(px, 1), round(pz, 1), round(random.uniform(1.8, 3.2), 2), random.randrange(8), 0, 1]); break
print("trees", len(trees))

# ---------------- poles, wires, lights ----------------
poles, wires, lights = [], [], []
for r in roads:
    spans, total = polyline_pts(r["p"], 1)
    if total < 30: continue
    hw = r["w"] / 2
    side = 1 if random.random() < 0.5 else -1
    if r["c"] in ("secondary", "tertiary"):
        s = 10.0; k = 0
        while s < total - 5:
            x, z, tx, tz = at(spans, s)
            sd = side if k % 2 == 0 else -side
            px, pz = x - tz * sd * (hw + 1.6), z + tx * sd * (hw + 1.6)
            if tree_ok(px, pz) or edge_dist(px, pz) > 0.4:
                lights.append([round(px, 1), round(pz, 1), round(math.atan2(tz * sd, -tx * sd), 3)])
            s += 48.0; k += 1
    if r["c"] in ("residential", "unclassified", "tertiary", "secondary"):
        s = 6.0; prev = None
        while s < total - 3:
            x, z, tx, tz = at(spans, s)
            px, pz = x - tz * side * (hw + 1.1), z + tx * side * (hw + 1.1)
            if edge_dist(px, pz) > 0.3 and not near_rect(px, pz, 0.3) and not out_of_bounds(px, pz):
                poles.append([round(px, 1), round(pz, 1)])
                if prev is not None and math.dist(prev, (px, pz)) < 60:
                    wires.append([round(prev[0], 1), round(prev[1], 1), round(px, 1), round(pz, 1)])
                prev = (px, pz)
            else:
                prev = None
            s += 38.0
print("poles", len(poles), "lights", len(lights))

# ---------------- stars and stunt park ----------------
stars = []
pool = []
for r in roads:
    if r["c"] in ("service",): continue
    spans, total = polyline_pts(r["p"], 1)
    s = 8.0
    while s < total - 4:
        x, z, tx, tz = at(spans, s)
        if math.hypot(x, z) < 900: pool.append((round(x, 1), round(z, 1)))
        s += 40.0
random.shuffle(pool)
for p in pool:
    if all(math.dist(p, q) > 70 for q in stars): stars.append(list(p))
    if len(stars) >= 70: break

best = None
for gx in range(-700, 701, 25):
    for gz in range(-700, 701, 25):
        if blocked_land(gx, gz): continue
        clr = 99.0
        for dx in range(-60, 61, 20):
            for dz in range(-60, 61, 20):
                if dx * dx + dz * dz > 3600: continue
                e = edge_dist(gx + dx, gz + dz, 3)
                if e < 0.5 or near_rect(gx + dx, gz + dz, 3.0) or blocked_land(gx + dx, gz + dz): clr = -1; break
                clr = min(clr, e)
            if clr < 0: break
        if clr < 0: continue
        score = -math.hypot(gx, gz) * 0.05 + min(clr, 50)
        if best is None or score > best[0]: best = (score, gx, gz, clr)
print("park", best)
park = {"x": best[1], "z": best[2], "r": 55} if best else None

W["bounds"] = list(BOUNDS)
W["gen"] = {"buildings": bld, "landmarks": landmarks, "trees": trees, "poles": poles, "wires": wires,
            "lights": lights, "stars": stars, "park": park}
json.dump(W, open("data/osm/sheoganj_world.json", "w"), separators=(",", ":"))
print("written", len(json.dumps(W)) // 1024, "KB")
