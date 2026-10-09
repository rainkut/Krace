# QA checklist (repeatable)

Automated (needs Godot 4.7.2; first two need no GPU):
```
godot --headless --path . --import
godot --headless --path . -s tools/mod_test.gd          # mods, recovery, backup, session lock  -> "MODTEST PASS"
xvfb-run -a godot --rendering-driver opengl3 --path . -s tools/smoke_test.gd   # full game flow -> "SMOKE PASS"
godot --headless --path . -s tools/drive_test.gd        # scripted driving
```
`smoke_test` wipes the player's save - run it on a throwaway machine/profile.

| # | Scenario | How | Status |
|---|---|---|---|
| 1 | First launch, no save | delete `save.json`, start | smoke_test (wipes save first) |
| 2 | Driving and reversing | Free roam: W then S | drive_test |
| 3 | Collisions / getting stuck | drive into a wall, wait 4 s off-road or press R | auto-recover in code; manual |
| 4 | Vehicle reset | R / RESET button | manual + code path in smoke |
| 5 | Race start, checkpoint, finish | autodriven 2-lap race | smoke_test |
| 6 | Retry / race reset | Pause -> Restart (2 taps), or results -> Retry | manual |
| 7 | Close and restart | quit, relaunch, stars/cars/parts still there | smoke (save written) + manual |
| 8 | Save persistence | stars, owned cars, paint, wheels/spoiler/decoration | manual; mod_test covers backup/restore |
| 9 | Missing mod / malformed mod | mod_test: bad_json, no_model, bad_manifest | mod_test |
| 10 | Duplicate mod ids | mod_test: dup_base, zz_twin | mod_test |
| 11 | All mods disabled | Safe mode / disabled list | mod_test |
| 12 | Missing optional asset | mod_test: opt_icon | mod_test |
| 13 | Corrupt save / settings | mod_test | mod_test |
| 14 | Crash with mods installed -> safe mode | kill the app during a race, relaunch | mod_test (lock logic) + manual |
| 15 | Accessibility toggles | Settings: larger text, reduced motion, simple steering | screenshot-checked; feel is manual |

## Cannot be tested on the build VM (do these on a phone)
* Frame rate / heat on a real device (Galaxy S24 Ultra): enable Settings -> Graphics = Normal if slow; `adb shell dumpsys gfxinfo com.hopique.littleracerworld`.
* Touch layout and feel, tilt direction, audio latency, the Android Back-button pause.
* The Android external mods folder: `adb push sample_vehicle_mod /storage/emulated/0/Android/data/com.hopique.littleracerworld/files/mods/` then Parents -> Reload mods.
* Logs: `adb logcat -s godot`.

## Save backup and restore
* In the game: Parents -> Back up save / Restore backup. A backup is also made automatically after every race and before
  "Erase progress".
* Manually: copy `save.json` and `save.backup.json` from the user-data folder (see MODDING.md for paths; on Android
  `adb exec-out run-as com.hopique.littleracerworld cat files/save.json` on a debuggable build, or use Parents -> Back up).
* A damaged save is moved to `save.corrupt.json` and the game starts fresh with a notice.
