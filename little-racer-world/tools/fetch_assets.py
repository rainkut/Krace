#!/usr/bin/env python3
"""Download licensed (CC0) PBR textures from ambientCG into assets/textures/indian/.
All ambientCG assets are CC0 1.0. Source URLs are recorded in data/CREDITS-assets.md."""
import io, json, os, sys, urllib.request, zipfile
IDS = ["Plaster003", "Plaster006", "Plaster002", "Asphalt012", "Asphalt025B", "Ground054", "Ground033", "Concrete019", "Bricks075A"]
OUT = "assets/textures/indian"
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0"}
def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
d = json.loads(get("https://ambientcg.com/api/v2/full_json?include=downloadData&limit=50&id=" + ",".join(IDS)))
rows = []
for a in d["foundAssets"]:
    aid = a["assetId"]
    dl = [x for x in a["downloadFolders"]["default"]["downloadFiletypeCategories"]["zip"]["downloads"] if x["attribute"] == "1K-JPG"][0]
    z = zipfile.ZipFile(io.BytesIO(get(dl["downloadLink"])))
    for n in z.namelist():
        for suf, key in (("_Color.jpg", "color"), ("_NormalGL.jpg", "normal"), ("_Roughness.jpg", "rough")):
            if n.endswith(suf):
                open(f"{OUT}/{aid.lower()}_{key}.jpg", "wb").write(z.read(n))
    rows.append(f"| {aid} | ambientCG | CC0 1.0 | {a['shortLink']} |")
    print("ok", aid)
open("data/CREDITS-assets.md", "w").write("# Licensed assets added in v0.5.0\n\nAll CC0 (no attribution required; credited anyway).\n\n| Asset | Source | Licence | URL |\n|---|---|---|---|\n" + "\n".join(rows) + "\n")
