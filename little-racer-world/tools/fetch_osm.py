#!/usr/bin/env python3
"""Download OSM data for Sheoganj (ODbL, (c) OpenStreetMap contributors) into data/osm/sheoganj_raw.json."""
import json, urllib.request, urllib.parse, sys
# two discs: the original town centre, and Ashapurna Township (Ankit's Google Maps pin, Plus Code 43P3+C76)
CENTRES = [(25.1389, 73.0655, 1100), (25.13606, 73.05319, 800)]
def query(LAT, LON, R):
  return f"""[out:json][timeout:90];
(
 way(around:{R},{LAT},{LON})["highway"];
 way(around:{R},{LAT},{LON})["building"];
 way(around:{R},{LAT},{LON})["landuse"];
 way(around:{R},{LAT},{LON})["natural"];
 way(around:{R},{LAT},{LON})["waterway"];
 way(around:{R},{LAT},{LON})["railway"];
 way(around:{R},{LAT},{LON})["amenity"];
 node(around:{R},{LAT},{LON})["amenity"];
 node(around:{R},{LAT},{LON})["shop"];
 node(around:{R},{LAT},{LON})["place"];
 node(around:{R},{LAT},{LON})["highway"~"bus_stop|traffic_signals|crossing"];
);
out body geom;"""
elems = {}
for c in CENTRES:
    q = query(*c)
    for url in ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]:
        try:
            d = urllib.request.urlopen(urllib.request.Request(url, urllib.parse.urlencode({"data": q}).encode(), {"User-Agent": "littleracerworld/1.0"}), timeout=120).read()
            for e in json.loads(d)["elements"]:
                elems[(e["type"], e["id"])] = e
            print(url, c, len(d)); break
        except Exception as e: print(url, e, file=sys.stderr)
    else:
        sys.exit("fetch failed for %s" % (c,))
json.dump({"elements": list(elems.values())}, open("data/osm/sheoganj_raw.json", "w"), separators=(",", ":"))
print(len(elems), "elements")
