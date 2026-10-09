# Little Racer World — Phase 1

Family-friendly 3D arcade racing in Godot 4.7 (GDScript, `gl_compatibility` renderer, mobile-first).
Phase 1 = one complete, playable loop. No violence, no gambling, no ads, no network, no permissions.

## What is in Phase 1
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
3D models: Kenney (kenney.nl) Car Kit, City Kit (Roads), City Kit (Suburban), Nature Kit — **CC0**. Licence files are
next to the models in `assets/kenney/*/License.txt`. Everything else (code, icon, sounds, town layout) is original.

## Project layout
```
data/            vehicles.json, races.json, towns/*.json   (all game content)
scripts/         game code (autoloads: settings, save_game, sfx, content)
scenes/          boot / menu / game (each one root node + script; the world is built in code)
tools/           gen_town.py (town generator), shot.gd + shoot.sh (screenshots), smoke_test.gd, drive_test.gd, sync_vm.sh
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
- Results are shown the moment the player finishes; opponents still racing show "racing..." (their final times are not waited for).
- Only one town and one race. Brake is strong (arcade) and will reverse if held when stopped.
- Debug-signed APK, version 0.1.0.

## Phase 2+ (not started)
Larger open world, more races, more cars/upgrades, mod workshop tooling. Deliberately not started.
