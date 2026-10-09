#!/usr/bin/env python3
"""Generates data/township/ashapurna.json - the Ashapurna Township (Sheoganj, Sirohi) layout.

Local frame (metres): u = to the right when facing into the township, v = depth from the gate (inward).
The gate arch is at (0,0); the paver forecourt is v in [-62, 0]; the public road is at v ~ -66.
Everything here is an ORIGINAL schematic, sized from a private reference video (no footage, logos or
captions are used). Re-run to regenerate:  python3 tools/gen_ashapurna.py  [--preview out.png]
"""
import json, math, random, sys

rng = random.Random(20261009)
CENTER = (25.1389, 73.0655)          # world origin of sheoganj_world.json (lat, lon)
WORLD = "data/osm/sheoganj_world.json"
OUT = "data/township/ashapurna.json"

# ---------------------------------------------------------------- provisional anchor (world metres -> lat/lon)
world = json.load(open(WORLD))
def nearest_on(pts, p):
    best = None
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ab = (b[0] - a[0], b[1] - a[1]); L2 = ab[0] ** 2 + ab[1] ** 2
        t = max(0, min(1, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / L2))
        q = (a[0] + ab[0] * t, a[1] + ab[1] * t)
        d = math.dist(p, q)
        if best is None or d < best[0]:
            L = math.sqrt(L2); best = (d, q, (ab[0] / L, ab[1] / L))
    return best
PIN = (25.13606, 73.05319)   # Ankit's Google Maps pin, Plus Code 43P3+C76 (decoded by the coordinator)
MX = 111320.0 * math.cos(math.radians(CENTER[0])); M_LAT = 110574.0
pin_world = ((PIN[1] - CENTER[1]) * MX, -(PIN[0] - CENTER[0]) * M_LAT)
# the real road the township fronts = nearest secondary road (the RIICO Industrial Area road / Bamnera-Sheoganj highway)
cands = [(nearest_on(r["p"], pin_world), r) for r in world["roads"] if r["c"] in ("secondary", "tertiary", "unclassified")]
(dist_pin, q, dirv), frontage = min(cands, key=lambda c: c[0][0])
FORECOURT = 62.0
side = 1.0 if ((pin_world[0] - q[0]) * -dirv[1] + (pin_world[1] - q[1]) * dirv[0]) > 0 else -1.0
inward = (-dirv[1] * side, dirv[0] * side)         # from the road towards the pin's side
GATE_SETBACK = frontage["w"] / 2 + FORECOURT + 3.0  # road edge -> gate; keeps the full paver forecourt between road and gate
gate_world = (q[0] + inward[0] * GATE_SETBACK, q[1] + inward[1] * GATE_SETBACK)
bearing = math.degrees(math.atan2(inward[0], -inward[1])) % 360.0
lat = CENTER[0] - gate_world[1] / M_LAT
lon = CENTER[1] + gate_world[0] / MX
print("pin world (%.0f, %.0f) is %.1f m from the frontage road (%s, %.1f m wide); gate moved %.0f m inward" % (pin_world[0], pin_world[1], dist_pin, frontage["c"], frontage["w"], GATE_SETBACK - dist_pin))

W_HALF, DEPTH = 160.0, 390.0
LANE_V = [50, 100, 150, 200, 250]
LANE_W = 8.0
CARR_U = 5.0                    # carriageway centre-lines at u = -5 (inbound, left-hand drive) and +5 (outbound)
RING_C = (0.0, 335.0); RING_R = 34.0

roads = []
def road(name, kind, w, pts, closed=False):
    roads.append({"id": name, "kind": kind, "w": w, "pts": [[round(x, 2), round(y, 2)] for x, y in pts], "closed": closed})
v_ring_s = RING_C[1] - math.sqrt(RING_R ** 2 - CARR_U ** 2)
road("main_in", "main", LANE_W, [(-CARR_U, 0), (-CARR_U, v_ring_s + 3)])
road("main_out", "main", LANE_W, [(CARR_U, 0), (CARR_U, v_ring_s + 3)])
ring = [(RING_C[0] - RING_R * math.sin(a), RING_C[1] - RING_R * math.cos(a)) for a in [math.radians(i * 10) for i in range(36)]]
ring.append(ring[0])
road("ring", "ring", LANE_W, ring, True)
for v in LANE_V:
    road("lane_v%d" % v, "lane", LANE_W, [(-W_HALF + 12, v), (-9, v)])
    road("lane_v%d_e" % v, "lane", LANE_W, [(9, v), (W_HALF - 12, v)])
for u in (-75, 75):
    road("lane_u%d" % u, "lane", LANE_W, [(u, 50 - 4), (u, 250 + 4)])
for u in (-150, 150):
    road("perimeter_u%d" % u, "perimeter", 6.0, [(u, 12), (u, 300)])
# the paver forecourt is a wide "road" so the road queries (spawn / off-road recovery) know it is drivable
forecourt = {"u0": -40.0, "u1": 40.0, "v0": -FORECOURT, "v1": 0.0}
road("forecourt", "forecourt", 80.0, [(0, -FORECOURT), (0, 0)])

# ---------------------------------------------------------------- circuit (closed F1-style lap)
def rounded(pts, radii, step=3.5):
    """pts closed polyline of corners, radii per corner (0 = sharp/pass-through) -> dense points + corner records"""
    n = len(pts); out = []; corners = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        r = radii[i]
        d1 = (p1[0] - p0[0], p1[1] - p0[1]); d2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1 = math.hypot(*d1); l2 = math.hypot(*d2)
        d1 = (d1[0] / l1, d1[1] / l1); d2 = (d2[0] / l2, d2[1] / l2)
        cross = d1[0] * d2[1] - d1[1] * d2[0]; dot = d1[0] * d2[0] + d1[1] * d2[1]
        th = math.atan2(cross, dot)          # signed turn (+ = counter-clockwise in (u,v))
        if r <= 0 or abs(th) < 0.05:
            out.append((p1[0], p1[1], i)); continue
        t = r * math.tan(abs(th) / 2.0)
        assert t <= l1 * 0.5 + 0.01 and t <= l2 * 0.5 + 0.01, ("corner too tight", i, pts[i], t, l1, l2)
        a = (p1[0] - d1[0] * t, p1[1] - d1[1] * t)
        sgn = 1.0 if th > 0 else -1.0
        cen = (a[0] - d1[1] * r * sgn, a[1] + d1[0] * r * sgn)
        a0 = math.atan2(a[1] - cen[1], a[0] - cen[0])
        k = max(2, int(math.ceil(abs(th) * r / step)))
        arc = []
        for j in range(k + 1):
            ang = a0 + th * j / k
            arc.append((cen[0] + r * math.cos(ang), cen[1] + r * math.sin(ang), i))
        out.extend(arc)
        corners.append({"i": i, "c": [round(cen[0], 2), round(cen[1], 2)], "r": r, "turn": round(th, 3), "v": [round(p1[0], 2), round(p1[1], 2)]})
    # resample at constant spacing
    dense = []
    for i in range(len(out)):
        a = out[i]; b = out[(i + 1) % len(out)]
        L = math.hypot(b[0] - a[0], b[1] - a[1]); k = max(1, int(round(L / step)))
        for j in range(k):
            dense.append((a[0] + (b[0] - a[0]) * j / k, a[1] + (b[1] - a[1]) * j / k))
    return dense, corners

START_V = -8.0
corner_pts = [(-CARR_U, START_V), (-CARR_U, 100), (-75, 100), (-75, 200), (-CARR_U, 200), (-CARR_U, 285), (-CARR_U, v_ring_s + 1.5)]
radii = [0, 12, 12, 12, 12, 0, 0]
# ring: clockwise (left-hand traffic) from 25 to 335 degrees
for adeg in range(25, 336, 10):
    a = math.radians(adeg)
    corner_pts.append((RING_C[0] - RING_R * math.sin(a), RING_C[1] - RING_R * math.cos(a))); radii.append(0)
corner_pts += [(CARR_U, v_ring_s + 1.5), (CARR_U, 250), (75, 250), (75, 150), (CARR_U, 150), (CARR_U, -30), (CARR_U, -56), (-25, -56), (-25, -38), (-CARR_U, -38)]
radii += [0, 12, 12, 12, 12, 0, 8, 8, 8, 8]
# the segment (CARR_U,250) is reached from the ring exit going south
dense, corners = rounded(corner_pts, radii)
length = sum(math.dist(dense[i], dense[(i + 1) % len(dense)]) for i in range(len(dense)))
cum = [0.0]
for i in range(1, len(dense)):
    cum.append(cum[-1] + math.dist(dense[i - 1], dense[i]))
sectors = [0.33, 0.66]
sector_idx = [min(range(len(cum)), key=lambda i: abs(cum[i] - s * length)) for s in sectors]

def heading(i):
    a = dense[i]; b = dense[(i + 1) % len(dense)]
    return math.atan2(b[1] - a[1], b[0] - a[0])
# kerbs on the inside of sharp corners, tyre barriers on the outside (race-mode dressing)
kerbs = []; barriers = []
def turn_at(i, span=4):
    h0 = heading((i - span) % len(dense)); h1 = heading((i + span) % len(dense))
    d = h1 - h0
    return math.atan2(math.sin(d), math.cos(d))
flag = [abs(turn_at(i)) > 0.30 for i in range(len(dense))]
k_alt = 0
for i in range(len(dense)):
    if not flag[i]:
        continue
    t = turn_at(i)
    h = heading(i)
    nx, ny = -math.sin(h), math.cos(h)            # left normal in (u,v)
    side = 1.0 if t > 0 else -1.0                 # inside = left when turning left
    ix = dense[i][0] + nx * side * (LANE_W / 2 + 0.5); iy = dense[i][1] + ny * side * (LANE_W / 2 + 0.5)
    j = (i + 1) % len(dense)
    hx, hy = -math.sin(heading(j)), math.cos(heading(j))
    jx = dense[j][0] + hx * side * (LANE_W / 2 + 0.5); jy = dense[j][1] + hy * side * (LANE_W / 2 + 0.5)
    kerbs.append([round(ix, 2), round(iy, 2), round(jx, 2), round(jy, 2), k_alt % 2]); k_alt += 1
    if i % 2 == 0 and abs(t) > 0.45:
        ox = dense[i][0] - nx * side * (LANE_W / 2 + 2.6); oy = dense[i][1] - ny * side * (LANE_W / 2 + 2.6)
        barriers.append([round(ox, 2), round(oy, 2), round(h, 3)])
# the whole ring gets kerbs on its inside (clockwise => inside is to the right of travel)
circuit = {"width": LANE_W, "line": [[round(x, 2), round(y, 2)] for x, y in dense], "closed": True, "length_m": round(length, 1),
           "start_index": 0, "start_v": START_V, "sector_indices": sector_idx, "sector_fractions": sectors,
           "corners": corners, "kerbs": kerbs, "barriers": barriers,
           "grid_rows_v": [-14.0, -22.0, -30.0], "grid_note": "cars line up behind the start line on the inbound carriageway, 2 abreast, 8 m rows"}

# ---------------------------------------------------------------- plots
cols = [(-147.0, -79.0), (-71.0, -12.0), (12.0, 71.0), (79.0, 147.0)]
bands = [(8.0, 46.0), (54.0, 96.0), (104.0, 146.0), (154.0, 196.0), (204.0, 246.0), (254.0, 296.0)]
apartment = {"u": -48.0, "v": 27.0, "w": 34.0, "d": 16.0, "floors": 6, "facing": -1}
villa_plot = None
plots = []
for bi, (v0, v1) in enumerate(bands):
    for ci, (u0, u1) in enumerate(cols):
        pw = (u1 - u0) / 4.0
        for k in range(4):
            for row in (0, 1):
                dd = (v1 - v0) / 2.0
                p = {"u": round(u0 + pw * (k + 0.5), 2), "v": round(v0 + dd * (row + 0.5), 2), "w": round(pw, 2), "d": round(dd, 2),
                     "facing": -1 if row == 0 else 1, "band": bi, "col": ci}
                plots.append(p)
def overlaps_apartment(p):
    return abs(p["u"] - apartment["u"]) < (p["w"] + apartment["w"]) / 2 and abs(p["v"] - apartment["v"]) < (p["d"] + apartment["d"]) / 2
plots = [p for p in plots if not overlaps_apartment(p)]
villa_idx = None
for i, p in enumerate(plots):
    if p["band"] == 2 and p["col"] == 2 and p["facing"] == 1 and p["u"] > 40:
        villa_idx = i; break
PALETTE = [0, 6, 8, 14, 3, 4, 5, 1]
VARIANTS = ["plain", "plain", "green_glass", "stone", "plain"]
for i, p in enumerate(plots):
    r = rng.random()
    if i == villa_idx:
        p["kind"] = "villa"; continue
    near_gate = p["band"] == 0
    if r < 0.24:
        p["kind"] = "house"; p["floors"] = rng.choice([1, 2, 2, 2, 3]); p["palette"] = rng.choice(PALETTE)
        p["variant"] = rng.choice(VARIANTS)
    elif r < 0.37:
        p["kind"] = "construction"; p["floors"] = rng.choice([1, 2, 2, 3]); p["done"] = round(rng.uniform(0.35, 0.95), 2)
    else:
        p["kind"] = "empty"; p["wall"] = rng.random() < 0.55
    p["seed"] = rng.randrange(1000)
for p in plots:
    p.setdefault("seed", rng.randrange(1000))

# ---------------------------------------------------------------- landmarks / props
def near_lane(v, margin=6.5):
    return any(abs(v - lv) < margin for lv in LANE_V) or v > v_ring_s - 8
trees = []   # [u, v, scale, kind, collide]
for i in range(0, 300, 1):
    v = 8 + i * 9.5
    if v > v_ring_s - 6: break
    if near_lane(v): continue
    trees.append([0.0, round(v, 1), round(rng.uniform(1.25, 1.6), 2), 1, 0])      # neem-like median, no collider
for tv in range(-50, -6, 9):
    trees.append([0.0, float(tv), 1.2, 1, 0])
for u in (-75, 75):
    for v in range(58, 246, 15):
        if near_lane(v, 7.5): continue
        for side in (-7.0, 7.0):
            trees.append([u + side, float(v), round(rng.uniform(1.0, 1.4), 2), rng.choice([0, 1, 2, 6]), 0])
for v in range(14, 380, 13):
    for u in (-155.0, 155.0):
        trees.append([u, float(v), round(rng.uniform(1.3, 1.9), 2), rng.choice([0, 1, 3, 7]), 0])
for u in range(-150, 151, 15):
    trees.append([float(u), 386.0, round(rng.uniform(1.3, 1.8), 2), rng.choice([0, 1, 3]), 0])
for i in range(24):
    a = i / 24 * math.tau
    trees.append([round(RING_C[0] + 46 * math.cos(a), 1), round(RING_C[1] + 46 * math.sin(a), 1), round(rng.uniform(1.1, 1.5), 2), rng.choice([0, 1, 2]), 0])
poles = [[12.5, float(v)] for v in range(12, 296, 28)]
wires = [[poles[i][0], poles[i][1], poles[i + 1][0], poles[i + 1][1]] for i in range(len(poles) - 1)]
lights = [[-15.0, -22.0, 0.0], [15.0, -22.0, 0.0], [-15.0, -52.0, 0.0], [15.0, -52.0, 0.0]]
stars = []
for v in (40, 90, 140, 190, 240):
    stars.append([-CARR_U, float(v)]); stars.append([CARR_U, float(v) + 25])
stars += [[RING_C[0] + 0.0, RING_C[1] - 12.0], [RING_C[0] + 9.0, RING_C[1] + 6.0], [RING_C[0] - 9.0, RING_C[1] + 6.0]]
cars = [[-18.0, 62.0, 0.0, "hatchback-sports"], [26.0, 112.0, 3.14, "hatchback-sports"], [-62.0, 164.0, 1.57, "sedan"], [64.0, 212.0, 0.0, "hatchback-sports"], [-100.0, 66.0, 3.14, "delivery"], [100.0, 106.0, 0.0, "hatchback-sports"]]
gate = {"u": 0.0, "v": 0.0, "opening": 22.0, "pillar_h": 7.0, "name": "ASHAPURNA TOWNSHIP", "sub": "SHEOGANJ"}
gatehouses = [{"u": -19.0, "v": 1.5, "w": 7.0, "d": 10.0}, {"u": 19.0, "v": 1.5, "w": 7.0, "d": 10.0}]
walls = [
    {"a": [-W_HALF, 0], "b": [-24, 0]}, {"a": [24, 0], "b": [W_HALF, 0]},
    {"a": [-W_HALF, 0], "b": [-W_HALF, DEPTH]}, {"a": [W_HALF, 0], "b": [W_HALF, DEPTH]},
    {"a": [-W_HALF, DEPTH], "b": [W_HALF, DEPTH]},
]
data = {
    "id": "ashapurna", "name": "Ashapurna Township, Sheoganj",
    "anchor": {"lat": round(lat, 6), "lon": round(lon, 6), "rotation_deg": round(bearing, 2),
               "_doc": "lat/lon = the gate arch centre; rotation_deg = compass bearing (0 = north, clockwise) of the direction you drive INTO the township (gate faces the road it fronts). Derived from Ankit's Google Maps pin (see pin) by tools/gen_ashapurna.py: the pin is on the road frontage, the gate is set back so the paver forecourt fits. Edit lat/lon/rotation_deg here to move/rotate the whole township; no code change needed.",
               "pin": {"lat": PIN[0], "lon": PIN[1], "plus_code": "43P3+C76"}, "provisional": False},
    "size": {"half_width": W_HALF, "depth": DEPTH},
    "gate": gate, "gatehouses": gatehouses, "forecourt": forecourt, "walls": walls,
    "roads": roads, "circuit": circuit,
    "plots": plots, "apartment": apartment,
    "playground": {"c": list(RING_C), "r": 28.0, "ring_r": RING_R, "net_u": [RING_C[0] - 9.0, RING_C[0] + 9.0]},
    "garden": {"u": 96.0, "v": 346.0, "w": 66.0, "d": 62.0},
    "temple": {"u": -96.0, "v": 346.0, "w": 11.0, "d": 11.0},
    "trees": trees, "poles": poles, "wires": wires, "lights": lights, "stars": stars, "cars": cars,
    "hills": [{"u": 40.0, "v": 640.0, "w": 320.0, "h": 46.0, "kind": "peak"}, {"u": -200.0, "v": 720.0, "w": 700.0, "h": 26.0, "kind": "ridge"}],
    "assumptions": [
        "Footprint 320 x 390 m with a 62 m paver forecourt; boundary wall 2.2 m; gate opening 22 m. Sizes are estimates from reference stills, not a survey.",
        "Main road = two 8 m carriageways (drive on the left) with a 2 m planted median, running gate -> playground roundabout.",
        "Five 8 m cross lanes, two 8 m side lanes (u=+-75) and 6 m perimeter lanes; 144+ plots ~15 x 19 m. Plot states (empty/house/construction/villa) are randomised with a fixed seed.",
        "Apartment block (6 floors, under construction) left of the gate; old hip-roof villa on the east side; playground = sandy disc inside the roundabout.",
        "Temple and garden positions are NOT from the footage (not clearly visible there); placed in the two far corners as plausible features.",
    ],
}
json.dump(data, open(OUT, "w"), separators=(",", ":"))
print("circuit length %.0f m, %d pts, sectors %s, kerbs %d, barriers %d, plots %d (%s)" % (
    length, len(dense), sector_idx, len(kerbs), len(barriers), len(plots),
    {k: sum(1 for p in plots if p["kind"] == k) for k in ("empty", "house", "construction", "villa")}))
print("anchor lat %.6f lon %.6f bearing %.2f  gate_world (%.1f, %.1f)" % (lat, lon, bearing, *gate_world))

# ---------------------------------------------------------------- sanity: circuit lies on registered roads
def dist_to_road(p):
    best = 1e9
    for r in roads:
        if r["kind"] == "forecourt":
            u0, u1, v0, v1 = forecourt["u0"], forecourt["u1"], forecourt["v0"], forecourt["v1"]
            if u0 <= p[0] <= u1 and v0 <= p[1] <= v1: return -999
            continue
        pts = r["pts"]
        for i in range(len(pts) - 1):
            d, _, _ = nearest_on(pts[i:i + 2], p) if True else (0, 0, 0)
            best = min(best, d - r["w"] / 2)
    return best
worst = max(dist_to_road(p) for p in dense)
print("max circuit point distance outside road edge: %.2f m (<=0 means fully on tarmac)" % worst)
mn = min(abs(c["r"]) for c in corners)
print("corners:", [(c["r"], round(math.degrees(c["turn"]))) for c in corners])

if "--preview" in sys.argv:
    from PIL import Image, ImageDraw
    S = 2.0; PAD = 40
    W = int((2 * W_HALF + 2 * PAD) * S); H = int((DEPTH + FORECOURT + 2 * PAD) * S)
    im = Image.new("RGB", (W, H), (205, 190, 150)); dr = ImageDraw.Draw(im)
    T = lambda u, v: ((u + W_HALF + PAD) * S, (DEPTH + PAD - v) * S)
    for r in roads:
        if r["kind"] == "forecourt":
            dr.rectangle([T(forecourt["u0"], 0), T(forecourt["u1"], -FORECOURT)], fill=(200, 140, 150)); continue
        pts = [T(*p) for p in r["pts"]]
        dr.line(pts, fill=(60, 60, 64), width=int(r["w"] * S), joint="curve")
    for p in plots:
        col = {"empty": (190, 170, 120), "house": (240, 235, 220), "construction": (130, 130, 130), "villa": (240, 220, 140)}[p["kind"]]
        dr.rectangle([T(p["u"] - p["w"] / 2 + 1, p["v"] + p["d"] / 2 - 1), T(p["u"] + p["w"] / 2 - 1, p["v"] - p["d"] / 2 + 1)], fill=col, outline=(120, 100, 80))
    a = apartment
    dr.rectangle([T(a["u"] - a["w"] / 2, a["v"] + a["d"] / 2), T(a["u"] + a["w"] / 2, a["v"] - a["d"] / 2)], fill=(100, 100, 100))
    dr.ellipse([T(RING_C[0] - 28, RING_C[1] + 28), T(RING_C[0] + 28, RING_C[1] - 28)], fill=(225, 205, 150))
    dr.line([T(*p) for p in dense + [dense[0]]], fill=(255, 120, 0), width=2)
    for k in kerbs:
        dr.line([T(k[0], k[1]), T(k[2], k[3])], fill=(255, 0, 0) if k[4] else (255, 255, 255), width=3)
    for b in barriers:
        x, y = T(b[0], b[1]); dr.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(10, 10, 10))
    dr.rectangle([T(-W_HALF, DEPTH), T(W_HALF, 0)], outline=(240, 220, 150), width=3)
    im.save(sys.argv[sys.argv.index("--preview") + 1])
