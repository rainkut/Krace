#!/usr/bin/env python3
"""Bake a real road (OSRM route over OpenStreetMap) into data/routes/<name>.json.
usage: fetch_route.py <name> "lon,lat;lon,lat;..."  -> resampled every 4 m in local metres (x east, z north),
plus bridge/tunnel ranges from Overpass. Data (c) OpenStreetMap contributors (ODbL)."""
import json, math, sys, urllib.request, urllib.parse

def get(url, data=None, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": "road-warriors-dev/0.1"})
            return json.loads(urllib.request.urlopen(req, timeout=90).read())
        except Exception as e:
            err = e
    raise err

name, wp = sys.argv[1], sys.argv[2]
r = get(f"https://router.project-osrm.org/route/v1/driving/{wp}?overview=full&geometries=geojson")
co = r["routes"][0]["geometry"]["coordinates"]
lon0, lat0 = co[0]
kx = 111320 * math.cos(math.radians(lat0)); ky = 110574
pts = [((lo - lon0) * kx, (la - lat0) * ky) for lo, la in co]
# resample every 4 m
STEP = 4.0
out = [pts[0]]; acc = 0.0; i = 0; cur = pts[0]
while i < len(pts) - 1:
    a, b = cur, pts[i + 1]
    d = math.hypot(b[0] - a[0], b[1] - a[1])
    if d < 1e-6:
        i += 1; continue
    need = STEP - acc
    if d >= need:
        t = need / d
        cur = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        out.append(cur); acc = 0.0
    else:
        acc += d; cur = b; i += 1
# bridge / tunnel flags: sample every 100 m and ask Overpass for ways near the route
flags = [0] * len(out)
try:
    for kind, bit in (("bridge", 1), ("tunnel", 2)):
        sel = out[::25]
        poly = ",".join(f"{lat0 + p[1] / ky:.5f},{lon0 + p[0] / kx:.5f}" for p in sel)
        q = f'[out:json][timeout:60];way(around:14,{poly})["{kind}"~"yes|viaduct|building_passage|covered"];out geom;'
        res = get("https://overpass-api.de/api/interpreter", urllib.parse.urlencode({"data": q}).encode())
        nodes = [((n["lon"] - lon0) * kx, (n["lat"] - lat0) * ky) for w in res.get("elements", []) for n in w.get("geometry", [])]
        for idx, p in enumerate(out):
            if any((p[0] - n[0]) ** 2 + (p[1] - n[1]) ** 2 < 14 * 14 for n in nodes[::1]):
                flags[idx] |= bit
        print(kind, "ways:", len(res.get("elements", [])))
except Exception as e:
    print("overpass failed:", e)
json.dump({"name": name, "lat0": lat0, "lon0": lon0, "step": STEP, "pts": [[round(p[0], 1), round(p[1], 1)] for p in out], "flags": flags},
          open(f"data/routes/{name}.json", "w"))
print(name, len(out), "pts", round(len(out) * STEP / 1000, 2), "km; bridge", sum(f & 1 for f in flags), "tunnel", sum((f >> 1) & 1 for f in flags))
