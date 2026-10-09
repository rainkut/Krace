# Little Racer World — Phase 2

Family-friendly 3D arcade racing in Godot 4.7 (GDScript, `gl_compatibility` renderer, mobile-first).
Phase 1 = one complete, playable loop. No violence, no gambling, no ads, no network, no permissions.

## What is new in Phase 2
- **Real Sheoganj** (Rajasthan, 25.139 N 73.066 E): roads, junctions, roundabout, rivers, water, farmland and landmarks come from OpenStreetMap, meshed at runtime (`scripts/osm_world.gd`). ~220 road segments inside a 2.2 km square, drive on the left.
- Three Sheoganj races on real roads (Main Road, Old Town Lanes, Bus Station Run) next to the original Sunny Circuit; Free Roam works in both towns.
- Procedural Indian-town buildings (flat roofs, water tanks, rooftop stair rooms, shop shutters, pastel plaster), trees, electricity poles and sagging wires, street lights, hospital/clinic/bus-station landmarks with name labels.
- A **stunt park** (ramps, mound hill, cones, stars up on the ramps) with collectible stars; 80+ stars across town.
- Adjustable **traffic** (None / Light / Normal / Busy in Settings) that wanders real roads on the left and keeps its distance.
- **Auto-recovery**: leave the road for ~4 s (or fall off the world) and the car is put back on it with "Back on the road!"; invisible walls at the map edge.
- **Minimap** (top-left, heading-up) — tap it or press M for the full map with race route, next checkpoint and landmarks.
- 9 more vehicles (police, sedan, van, delivery, ambulance, fire truck, garbage truck, truck, sports sedan), all data-driven and star-unlocked.
- Realism pass: CC0 PBR textures (asphalt, ground, grass, concrete), HDRI sky, filmic tonemapping, warm sun with shadows, fog, bloom/colour grading, lane markings, speed breakers, facade shader for windows.
- Phase 1 fixes: brake no longer insta-reverses when stopped (needs ~0.7 s of held brake), AI reverse still works, unfinished racers are shown as DNF.

## Real data vs generated (Sheoganj)
| Real (OpenStreetMap, ODbL) | Generated (invented, deterministic seed) |
|---|---|
| Road centre-lines, classes, one-ways, junction topology | Road width per class (OSM has no widths here), markings, speed breakers |
| Farmland / scrub / residential / water polygons, the river | Textures and colours of those areas |
| Names/positions: Sheoganj, RSRTC Bus Station, 3 hospitals, Jaslok Clinic | Building models; hospital/clinic are 4/2-storey boxes with name labels |
| 7 mapped building footprints | ~6,000 other buildings placed along roads with setbacks (OSM coverage of Sheoganj buildings is almost empty) |
| — | Trees, poles, wires, street lights, the stunt park, stars, traffic |
So: **the road layout is the real Sheoganj; the buildings along it are plausible, not the real ones.** Terrain is flat (no real hills/overpasses exist to model), so the "hill" is a built mound in the stunt park.

Rebuild the data: `python3 tools/fetch_osm.py && python3 tools/osm_to_world.py && python3 tools/make_routes.py && python3 tools/gen_world.py` (cached JSON is committed in `data/osm/`, so the game needs no network).

Map data © OpenStreetMap contributors, ODbL (https://www.openstreetmap.org/copyright). Also shown in-game under Settings.

## What was in Phase 1
- Main menu: Play (Race / Free Roam), Car Selection (4 cars, 10 paints, stat bars, star unlocks), Settings, Quit
- Compact connected 3D town ("Sunnyvale", 23x23 cells of 12 m): roads, junctions, crossings, kerbs, houses, trees, street lights, parked cars
- Arcade car physics (RigidBody3D with a shaped planar velocity model), follow camera with wall avoidance and speed FOV
- Free roam with 32 collectible stars
- One race, "Sunny Circuit": 2 laps (~1 km each), checkpoint gates, 3-2-1-GO, 3 AI opponents, wrong-way hint, results screen with rewards, Race Again / Free Roam / Menu
- Pause, reset-car (R), horn, local save (`user://save.json`), settings (`user://settings.cfg`)
- Android touch controls (multi-touch), optional tilt steering, auto-accelerate; keyboard and gamepad
- Procedural sound (no audio files): engine, beeps, fanfare, horn, bump
- Data-driven: cars, paints, races and towns are JSON; mods load from `user://mods/<name>/data/` (see MODDING.md)

## Assets and licences
Textures: ambientCG (CC0). Sky HDRI: Poly Haven "Kloofendal 48d" (CC0). See `assets/pbr/LICENSE.txt`.
3D models: Kenney (kenney.nl) Car Kit, City Kit (Roads), City Kit (Suburban), Nature Kit — **CC0**. Licence files are
next to the models in `assets/kenney/*/License.txt`. Everything else (code, icon, sounds, town layout) is original.

## Project layout
```
data/            vehicles.json, races.json, towns/*.json   (all game content)
scripts/         game code (autoloads: settings, save_game, sfx, content)
scenes/          boot / menu / game (each one root node + script; the world is built in code)
tools/           fetch_osm.py / osm_to_world.py / make_routes.py / gen_world.py (Sheoganj data pipeline), gen_town.py (grid town generator), shot.gd + shoot.sh (screenshots), smoke_test.gd, drive_test.gd, sync_vm.sh
export_presets.cfg   Android (arm64, debug keystore, landscape, no permissions, no gradle)
```

## Run / build
```
godot --path .                                   # run (4.7.x)
godot --headless -s tools/smoke_test.gd          # needs a renderer (use xvfb on a server)
godot --headless --export-debug Android build/LittleRacerWorld-debug.apk
```
Android export needs the Android SDK (build-tools 34), JDK 17, the 4.7.2 export templates and a debug keystore set in
Editor Settings. The APK is signed with the **debug** key (fine for sideloading, not for Play Store).
Install: enable "install unknown apps", copy the APK to the phone, open it.

## Verification status (be honest)
Verified on a Linux VM (software GL under xvfb) — see the bottom of this file for the commands:
- Smoke test passes: mod loading/removal, simulated multi-touch -> Input actions, a full autodriven 2-lap race to the finish, results/standings sanity, save file written.
- Drive test passes: scripted accelerate / brake / steer inputs in free roam move the car as expected.
- Screenshots of menu, car select, settings, countdown, racing, touch layout, results were looked at.
- APK built, signed (v2/v3 verified with apksigner), `aapt` shows package `com.hopique.littleracerworld`, arm64-v8a, minSdk 24, **no permissions**.
- The exported pack was started headless with no script/resource errors.

**NOT verified: any real Android device.** Unknown until someone runs it on a phone: frame rate on real hardware, touch layout and
button size on real screens, tilt direction/sensitivity (accelerometer axis assumed), audio latency, thermal behaviour, the
`gl_compatibility` look on Mali/Adreno GPUs. AI opponents were only observed under software rendering; handling feel by a human
driver (rather than scripted input) is untested.

## Known issues / limits
- Results are shown the moment the player finishes; opponents still racing show "DNF".
- Compatibility renderer: no SSAO/SSR/real reflections; "GTA-like" photorealism is not reachable on a phone with free assets. It is a stylised-realistic look.
- Buildings are generic; ramps lift the car but the body cannot pitch (angular X/Z locked), so jumps are arcade-style.
- On-device frame rate is **unmeasured** (~6,000 buildings are instanced per 220 m chunk, 28 traffic cars on Busy). If it is slow: Settings -> Traffic None, shadows off.
- Debug-signed APK.

## Roadmap
See ROADMAP.md. Phase 3+ is deliberately not started.
