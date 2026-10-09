#!/usr/bin/env python3
"""Turns a real place from OpenStreetMap into the `city` map for config.js.
Only needed if you want to make a new city. The game itself needs no tools.

    python3 tools/make-city.py 25.1389 73.0655 [--km 1.6] [--tile 12]

Map data (c) OpenStreetMap contributors, ODbL. Needs: pip install pillow
"""
import json, math, sys, urllib.parse, urllib.request
from PIL import Image, ImageDraw

lat, lon = float(sys.argv[1]), float(sys.argv[2])
km = float(sys.argv[sys.argv.index("--km") + 1]) if "--km" in sys.argv else 1.2   # width of the area
tile = float(sys.argv[sys.argv.index("--tile") + 1]) if "--tile" in sys.argv else 6  # metres per game tile
W = int(km * 1000 / tile); H = int(W * 0.75)
mlat = 111320.0; mlon = 111320.0 * math.cos(math.radians(lat))
half_w, half_h = W * tile / 2, H * tile / 2
bbox = (lat - half_h / mlat, lon - half_w / mlon, lat + half_h / mlat, lon + half_w / mlon)
q = f"""[out:json][timeout:60];(way["highway"]({bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]});
way["building"]({bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]});
way["natural"="water"]({bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]});way["waterway"="riverbank"]({bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]});
way["landuse"~"forest|grass|recreation_ground"]({bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]});way["leisure"~"park|garden"]({bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]});
way["landuse"="residential"]({bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]});way["natural"="wood"]({bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}););out geom;"""
req = urllib.request.Request("https://overpass-api.de/api/interpreter", data=urllib.parse.urlencode({"data": q}).encode(), headers={"User-Agent": "krace-game/0.1"})
data = json.load(urllib.request.urlopen(req, timeout=90))

def px(pt): return ((pt["lon"] - bbox[1]) * mlon / tile, (bbox[2] - pt["lat"]) * mlat / tile)
S = 4  # draw at 4x resolution, then shrink to tiles
layers = {k: Image.new("L", (W * S, H * S), 0) for k in ("green", "water", "build", "road", "house")}
d = {k: ImageDraw.Draw(v) for k, v in layers.items()}
road_m = {"motorway": 20, "trunk": 20, "primary": 18, "secondary": 16, "tertiary": 14}   # road width in metres (others: 12)
skip = {"footway", "path", "steps", "cycleway", "pedestrian", "bridleway", "corridor", "proposed", "construction"}
for el in data["elements"]:
    t = el.get("tags", {}); pts = [tuple(c * S for c in px(p)) for p in el.get("geometry", [])]
    if len(pts) < 2: continue
    if "highway" in t and t["highway"] not in skip:
        d["road"].line(pts, fill=255, width=int(road_m.get(t["highway"], 12) / tile * S), joint="curve")
    elif "building" in t and len(pts) > 2: d["build"].polygon(pts, fill=255)
    elif (t.get("natural") == "water" or t.get("waterway") == "riverbank") and len(pts) > 2: d["water"].polygon(pts, fill=255)
    elif t.get("landuse") == "residential" and len(pts) > 2: d["house"].polygon(pts, fill=255)
    elif len(pts) > 2: d["green"].polygon(pts, fill=255)

small = {k: v.resize((W, H), Image.BOX).load() for k, v in layers.items()}
rows = []
for y in range(H):
    r = ""
    for x in range(W):
        if x in (0, W - 1) or y in (0, H - 1): r += "T"
        elif small["road"][x, y] > 70: r += "#"
        elif small["water"][x, y] > 128: r += "W"
        elif small["build"][x, y] > 90: r += "B"
        elif small["house"][x, y] > 128 and x % 4 < 3 and y % 5 < 3 and (x * 7 + y * 11) % 7 != 0: r += "B"   # fill built-up areas with houses
        elif small["green"][x, y] > 128 and (x * 7 + y * 13) % 4 == 0: r += "T"
        else: r += "."
    rows.append(r)
# OpenStreetMap has very few buildings for many Indian towns, so we add houses beside the roads:
# find how far each tile is from a road, then put houses 2-5 tiles away (with gaps) and trees near the road.
from collections import deque
dist = [[99] * W for _ in range(H)]; dq = deque()
for y in range(H):
    for x in range(W):
        if rows[y][x] == "#": dist[y][x] = 0; dq.append((x, y))
while dq:
    x, y = dq.popleft()
    for nx, ny in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
        if 0 <= nx < W and 0 <= ny < H and dist[ny][nx] > dist[y][x] + 1: dist[ny][nx] = dist[y][x] + 1; dq.append((nx, ny))
rows = [list(r) for r in rows]
for y in range(1, H - 1):
    for x in range(1, W - 1):
        if rows[y][x] != ".": continue
        n = (x * 7 + y * 13) % 11
        if 2 <= dist[y][x] <= 5 and x % 3 != 2 and y % 3 != 2 and n not in (0, 5): rows[y][x] = "B"
        elif dist[y][x] == 1 and n in (0, 4): rows[y][x] = "T"
        elif dist[y][x] > 5 and (x * 2654435761 ^ y * 40503) % 23 == 0: rows[y][x] = "T"
rows = ["".join(r) for r in rows]
open("city.txt", "w").write("\n".join(rows))
print(f"{W}x{H} tiles ({tile} m each); wrote city.txt")
