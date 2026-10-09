#!/usr/bin/env python3
"""Download OSM data for Sheoganj (ODbL, (c) OpenStreetMap contributors) into data/osm/sheoganj_raw.json."""
import json, urllib.request, urllib.parse, sys
LAT, LON, R = 25.1389, 73.0655, 1100
q = f"""[out:json][timeout:90];
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
for url in ["https://overpass-api.de/api/interpreter","https://overpass.kumi.systems/api/interpreter"]:
    try:
        d = urllib.request.urlopen(urllib.request.Request(url, urllib.parse.urlencode({"data": q}).encode(), {"User-Agent":"littleracerworld/1.0"}), timeout=120).read()
        open("data/osm/sheoganj_raw.json","wb").write(d); print(url, len(d)); break
    except Exception as e: print(url, e, file=sys.stderr)
