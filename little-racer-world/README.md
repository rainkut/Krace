# Little Racer World — Phase 3b

Family-friendly 3D arcade racing in Godot 4.7 (GDScript, Mobile (Vulkan) renderer with High/Normal quality, mobile-first).
Phase 1 = one complete, playable loop. No violence, no gambling, no ads, no network, no permissions.

## Phases 3-6 (v0.7.0)
* **Garage (Phase 3):** 14 cars; paint plus wheel caps, spoiler and decoration (stripe/flag/star), with live preview. Parts unlock by earning stars or finishing races (`data/parts.json`); ownership and your choices are saved per car.
* **Mods (Phase 4):** data-only packs with a validated `mod.json` manifest, enable/disable, duplicate-id and range checks, clear errors, two sample mods. No code is ever loaded. See `MODDING.md`.
* **Accessibility and parent area (Phase 5):** larger text, reduced motion, simple steering, camera-follow slider, difficulty, auto-accelerate, volume. Parents area (maths gate): mods, safe mode, save backup/restore, reset settings, erase progress. Corrupt save/settings are moved aside and recovered; a crash with mods installed starts in safe mode; Android Back pauses a race and Restart/Main Menu need two taps. No online features, ads, tracking or purchases.
* **Release docs (Phase 6):** `CONTROLS.md`, `MODDING.md`, `docs/QA.md` (repeatable checklist, device-only tests, save backup/restore), `tools/mod_test.gd`.

## Phase 3d: Realism pass 2 (v0.6.0)
- Compound walls, hedges and gate gaps along lanes (`scripts/compounds.gd`, with collision), dry-scrub/soil patches behind them instead of bare sand, three procedural neem tree variants, irregular worn-tar patches (no rectangles), and a drifting cloud dome over the HDR sky.
- UNVERIFIED: on-device frame rate (S24 Ultra).

## Phase 3c: Indian small-town realism pass (v0.5.0)
- Real lane widths (main road 8 m, lanes 4-5 m), no lane markings on lanes, faded broken centre line + concrete kerb on the main road only, sandy dust shoulders, patched/worn asphalt, speed breakers.
- Facade shader rebuilt: sun-faded wash, stained plaster, rain streaks, damp base, balconies with railings, jaali windows, AC units, hand-painted shop signboards, rolling shutters, some under-construction top floors.
- Street life (primitives, no external models): two-wheelers, auto-rickshaws, tempos, handcarts, fruit stalls, water drums, cows and dogs (kid-safe, blocky); transformers on poles; flatter olive neem/babool-style trees; dry fields instead of lawns; dustier haze.
- Textures added (all CC0, ambientCG, fetched by `tools/fetch_assets.py`): see `data/CREDITS-assets.md`.

## Phase 3b: Real building footprints + Mobile renderer (v0.4.0)

- **Real buildings**: Sheoganj and the Ashapurna surroundings now use real footprints from Overture Maps (Google Open Buildings + Microsoft ML Buildings + OSM): 8,393 footprints fetched for the whole world, 6,255 kept after dropping <12 m2 slivers and de-duplicating, 6,571 oriented rectangles (L/U-shaped outlines are split into up to 3 rectangles), **5,455 placed** in the game (the rest sat on mapped roads or overlapped another). Pipeline: `tools/buildings_to_world.py` (cached result `data/buildings/footprints.json`, raw download kept as `overture_raw.geojson`) -> `tools/gen_world.py`. Each building turns its front (windows, door, shop shutters) towards the nearest road; party walls (neighbour within 1 m) get blank sides; shop-shutter strips only on buildings within ~12 m of the Bamnera-Sheoganj road (76 of them: real coverage there is thin). Floors (1-4) are a deterministic guess from footprint area and road class, **not real heights** (the datasets have none here); colours, water tanks and stair rooms are generated.
- **Ashapurna Township** keeps its hand-built layout (to scale from the footage); real footprints are used only outside its boundary wall.
- **Renderer**: switched to Godot's **Mobile (Vulkan)** renderer. **Graphics** setting: Auto / Normal / High (Auto = High on Vulkan devices with >=6 cores, >=5 GB RAM and a non-weak GPU, else Normal). High = 4 shadow cascades out to ~285 m, 4096 atlas + high soft-shadow filter, 4x MSAA, stronger glow, aerial-perspective fog with sun scatter, sky reflections, longer view distance (820 m buildings), ~900 extra trees. Normal = the previous look (2 cascades, no MSAA, 2048 atlas). **Time of day** setting (Morning / Noon / Evening / Dusk): sun angle/colour, fog and ambient. Both apply to the next race.
- Per-chunk static physics bodies (one box per building) so cars hit real buildings.
- Dev: `LRW_QUALITY=high|normal` forces the tier; `tools/shoot.sh` uses `LRW_DRIVER_ARGS` (default Compatibility/GL; `--rendering-driver vulkan --rendering-method mobile` runs Mobile on the VM via lavapipe).

**Verification**: VERIFIED on the VM: smoke test passes (all checks, incl. race finish, spawn on road, township, GP) under Compatibility; the Mobile renderer + High tier starts and renders (software Vulkan/lavapipe) and screenshots were inspected. UNVERIFIED: frame rate on a real phone (S24 Ultra target 60 fps High / 30+ Normal is a design target, not a measurement), the real-GPU look of Mobile, the Auto heuristic's choice on the actual phone, time-of-day on-device. If it stutters: Settings -> Graphics -> Normal.

## Phase 3a: Ashapurna Township + Ashapurna Grand Prix (v0.3.0)

A to-scale (metres) model of Ashapurna Township, Sheoganj, placed on the real Sheoganj map, with an F1-style circuit on its roads.

- **Data-driven**: `data/township/ashapurna.json` (generated by `tools/gen_ashapurna.py`) holds boundary, gate, forecourt, roads, plots, buildings, playground, garden/temple, apartment block, circuit. `scripts/township.gd` renders it.
- **Where it sits / how to move it**: `anchor` in the JSON = `lat`, `lon` (gate arch centre) and `rotation_deg` (compass bearing you drive INTO the township). Edit these three numbers and the whole township moves/rotates, no code change. Current anchor derives from Ankit's pin (Plus Code 43P3+C76, lat 25.13606, lon 73.05319): the gate is set back 70 m from the real frontage road so the 62 m paver forecourt fits. Re-run `python3 tools/gen_ashapurna.py` only if you want to regenerate the layout.
- **Bigger map**: the pin is ~1.25 km west of the old centre, so `tools/fetch_osm.py` now fetches two discs (1100 m + 800 m) and the world JSON carries a `bounds` rect; ground, walls and minimap use it.
- **Look**: striped pink/maroon/beige paver forecourt, arched gate with sign, two gatehouses, yellow-cream walls, unmarked roads, median neem trees and poles, varied houses, under-construction houses, old hip-roof villa, 5-6 storey RCC block with scaffolding, playground with net and hedge, dusty plots with scrub, hazy hills.
- **Grand Prix**: `ashapurna_gp` (Races menu): 1195 m closed loop, 5-light start, 3 laps (1/3/5 selectable), 4 AI rivals on a racing line (`circuit_race.gd`, `circuit_driver.gd`), 11 checkpoints (missing one voids the lap), 3 sector splits, best/last lap, red-white kerbs, tyre barriers, podium screen. New original open-wheel car **Comet GP**; racer-class cars are faster/grippier. No damage, auto-recovery unchanged. Free roam: menu "Free Roam: Ashapurna Township".

**Assumptions** (footage was only private reference, nothing from it ships): plot sizes, lane count/spacing, house mix, hill shape and the 5-6 storey apartment position are estimates. Kundan Hotel is not in OSM so it is not modelled. The real frontage is a 10.5 m secondary road ~30 m from the pin; its geometry matched the footage (gate faces a road, ~60 m paver apron) only after the 70 m setback assumption.

**Verification**: VERIFIED on the VM (headless + software GL): township loads, circuit points on road, GP 1-lap autodrive finishes with lap/sector data, podium renders, free-roam spawn on road, APK exports/signs (v2/v3, versionCode 2). UNVERIFIED: on-device frame rate, touch feel in the GP, rival times shown after the player finishes are partly estimated, the 3 touch-simulation smoke checks fail headlessly (also fail on the Phase 2 base commit).

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
| ~5,450 real building footprints (Overture: Google Open Buildings CC BY 4.0, Microsoft ML ODbL, OSM) - position, outline, orientation | Building heights/floors (guessed from area), colours, windows/doors/shutters, water tanks, stair rooms |
| — | Trees, poles, wires, street lights, the stunt park, stars, traffic |
So: **the road layout and the building footprints are the real Sheoganj; building heights, colours and details are guessed.** Terrain is flat (no real hills/overpasses exist to model), so the "hill" is a built mound in the stunt park.

Rebuild the data: `python3 tools/fetch_osm.py && python3 tools/osm_to_world.py && python3 tools/make_routes.py && python3 tools/buildings_to_world.py && python3 tools/gen_world.py` (re-download footprints with `overturemaps download --bbox=73.040,25.126,73.080,25.152 -f geojson --type=building -o data/buildings/overture_raw.geojson`) (cached JSON is committed in `data/osm/`, so the game needs no network).

Map data © OpenStreetMap contributors, ODbL (https://www.openstreetmap.org/copyright). Building footprints: Overture Maps Foundation, incl. Google Open Buildings (CC BY 4.0), Microsoft Building Footprints (ODbL), OpenStreetMap contributors (ODbL). Also shown in-game under Settings.

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
| Asset | Source | Licence | Used as |
|---|---|---|---|
| Plaster003 / Plaster006 / Bricks075A | ambientCG | CC0 | facade weathering, rooftops |
| Asphalt025B / Asphalt012 | ambientCG | CC0 | worn road, patches |
| Ground054 / Ground033 | ambientCG | CC0 | dust, dry fields, shoulders |
| Concrete019 | ambientCG | CC0 | main-road kerb |
| Earlier PBR set, sky HDRI | ambientCG / Poly Haven | CC0 | see `assets/pbr/LICENSE.txt` |
| Car/nature/roads models | Kenney | CC0 | vehicles, trees |
| Buildings / roads data | Overture (CC BY 4.0, ODbL), OpenStreetMap (ODbL) | attributed in-game | layout |
No CC BY-SA / NC / all-rights-reserved image is shipped. Street props are built in code.

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
godot --headless -s tools/mod_test.gd            # mods + recovery tests, no GPU needed
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
Mobile-renderer look on Adreno GPUs. AI opponents were only observed under software rendering; handling feel by a human
driver (rather than scripted input) is untested.

## Known issues / limits
- The Android external mods folder (`.../Android/data/<package>/files/mods`) and the Back-button handling are untested on a real phone; mods can always be installed from inside the app via Parents -> Install sample mods (app-private folder).
- Mod vehicles must be `.glb` with textures shipped alongside; mods cannot add new world maps beyond simple grid towns.
- Sound is the existing synthesised set; no new music this release.
- Results are shown the moment the player finishes; opponents still racing show "DNF".
- Mobile renderer: no SSAO/SSR/SDFGI (not available on Mobile); sky reflections only; "GTA-like" photorealism is not reachable on a phone with free assets. It is a stylised-realistic look.
- Building heights are guessed; ramps lift the car but the body cannot pitch (angular X/Z locked), so jumps are arcade-style.
- On-device frame rate is **unmeasured** (~5,500 buildings are instanced per 220 m chunk, 28 traffic cars on Busy). If it is slow: Settings -> Traffic None, shadows off.
- Debug-signed APK.

## Roadmap
See ROADMAP.md. Phase 3+ is deliberately not started.
