#!/usr/bin/env python3
"""Convert data/osm/sheoganj_raw.json (OSM, (c) OpenStreetMap contributors, ODbL) into the
compact local-metre world file data/osm/sheoganj_world.json that the game generates its 3D town from.
x = east (m), z = south (m) from the centre point, matching Godot's +Z-toward-camera convention."""
import json, math
LAT0, LON0 = 25.1389, 73.0655
MX = 111320.0 * math.cos(math.radians(LAT0)); MY = 110574.0
def proj(lat, lon): return [round((lon - LON0) * MX, 1), round(-(lat - LAT0) * MY, 1)]
raw = json.load(open("data/osm/sheoganj_raw.json"))["elements"]
W = {"center": [LAT0, LON0], "extent": 1100, "roads": [], "buildings": [], "areas": [], "pois": []}
WIDTH = {"motorway":16,"trunk":14,"primary":12,"secondary":10.5,"tertiary":9,"unclassified":7.5,"residential":6.5,"service":4.5,"track":3.8,"living_street":5,"path":2.5,"footway":2.2}
for e in raw:
    t = e["tags"]
    if e["type"] == "way" and "geometry" in e:
        pts = [proj(g["lat"], g["lon"]) for g in e["geometry"]]
        ids = e.get("nodes", [])
        keep = [i for i, q in enumerate(pts) if -2100 <= q[0] <= 1150 and abs(q[1]) <= 1150]
        if "highway" in t and len(keep) >= 2:
            lo, hi = keep[0], keep[-1]
            pts = pts[lo:hi + 1]; ids = ids[lo:hi + 1]
        elif "highway" in t:
            continue
        if "highway" in t and t["highway"] in WIDTH:
            if t["highway"] in ("path","footway"): continue
            w = WIDTH[t["highway"]]
            if "lanes" in t and t["highway"] in ("secondary","tertiary","primary"):
                try: w = max(w, int(t["lanes"]) * 3.4 + 1.5)
                except: pass
            W["roads"].append({"c": t["highway"], "w": w, "n": t.get("name", ""), "oneway": t.get("oneway") == "yes", "p": pts, "ids": ids})
        elif "building" in t:
            W["buildings"].append({"k": t["building"], "n": t.get("name", ""), "p": pts, "lv": t.get("building:levels", "")})
        elif "landuse" in t or "natural" in t or "waterway" in t or "amenity" in t:
            kind = t.get("landuse") or t.get("natural") or ("waterway:" + t["waterway"] if "waterway" in t else "amenity:" + t["amenity"])
            W["areas"].append({"k": kind, "n": t.get("name", ""), "closed": pts[0] == pts[-1], "p": pts})
    elif e["type"] == "node":
        k = t.get("amenity") or t.get("shop") or t.get("place") or t.get("highway")
        W["pois"].append({"k": k, "n": t.get("name", ""), "p": proj(e["lat"], e["lon"])})
json.dump(W, open("data/osm/sheoganj_world.json", "w"), separators=(",", ":"))
print({k: len(v) for k, v in W.items() if isinstance(v, list)})
for p in W["pois"]: print(p)
names = sorted({r["n"] for r in W["roads"] if r["n"]}); print(names)
