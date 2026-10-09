# Modding Little Racer World

Mods are **data packs**: JSON plus models/images. They contain no code and the game refuses any pack that ships a script or
executable file (`.gd .cs .dll .so .exe .sh .apk ...`). The base game always runs with every mod off
(Parents -> "Safe mode: turn ALL mods off").

## Where mods go
| Platform | Folder |
|---|---|
| Linux | `~/.local/share/godot/app_userdata/Little Racer World/mods/` |
| Windows | `%APPDATA%\Godot\app_userdata\Little Racer World\mods\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Little Racer World/mods/` |
| Android | `/storage/emulated/0/Android/data/com.hopique.littleracerworld/files/mods/` (see note) |

The exact folders on your device are listed in **Main menu -> Parents -> Mods**. Quickest start: Parents -> **Install sample mods**,
then look at the two folders it creates. Press **Reload mods** after changing files.

Android note: that external path is the standard app-specific folder, reachable from a PC with
`adb push my_mod /storage/emulated/0/Android/data/com.hopique.littleracerworld/files/mods/`. It has **not** been tested on a
real phone yet; if the game does not list your mod, check what path Parents -> Mods shows.

## Layout of one mod
```
my_mod/
  mod.json                 required manifest
  data/vehicles.json       optional  {"vehicles":[...], "paints":[...]}
  data/parts.json          optional  {"wheels":[...], "spoilers":[...], "extras":[...]}
  data/races.json          optional  {"races":[...]}
  data/towns/<id>.json     optional  one grid town per file
  models/*.glb             vehicle models, referenced by relative path
  icons/*.png              optional icons
```
A folder without `mod.json` is still loaded ("legacy" pack) but shows a warning.

## mod.json
```json
{"format": 1, "id": "my_mod", "name": "My Mod", "version": "1.0.0", "author": "Me", "description": "What it adds"}
```
`id`: 2-40 chars of `a-z 0-9 _`, unique among mods. `format` must be 1. `name` and `version` are required.

## Vehicle fields (`data/vehicles.json`)
| Field | Range | Notes |
|---|---|---|
| `id` | `a-z0-9_`, 2-40 | unique across base game + all mods |
| `name`, `model` | required | `model` = relative `.glb`/`.gltf` path inside the mod |
| `icon` | optional | missing icon = warning only |
| `max_speed` | 10-80 | metres/second |
| `accel` | 4-40 | |
| `handling` | 0.5-1.6 | |
| `grip` | 3-20 | |
| `model_scale` | 0.4-4 | |
| `model_yaw` | -360..360 | degrees, to face the model forwards |
| `unlock_stars` | 0-500 | 0 = available at once |
| `default_paint` | 0-99 | index into the paint list |
| `blurb` | text | shown in the garage |

Glb files that use an external texture (like Kenney's `Textures/colormap.png`) must ship that texture next to them.
`procedural` and custom `class` values are reserved for the base game.

## Paints, parts, races, towns
* `paints`: `{"name":"Mint","color":"#7fffd4"}`.
* `parts.json`: each entry `{"id","name","color"(wheels),"unlock_stars","unlock_races"}`.
* `races.json`: `id`, `name`, `description`, `town` (must exist), `route` (list of `[col,row]` corners, at least 2), `laps` 1-10,
  `gate_every` 2-40, `opponents` (each `vehicle` must exist), `rewards`. `circuit` is reserved for the base game.
* Towns: `data/towns/<id>.json` must be a grid town (`map`, `cols`, `rows`); `world`/`township` are base-game only.

See `mods_samples/` in the project (or the installed copies): **sample_vehicle_mod** (a car + a wheel part) and
**sample_track_mod** (a race on Sunnyvale).

## Rules the loader enforces
* A mod is **all or nothing**: one error rejects the whole mod, the rest of the game is unaffected.
* Duplicate ids (against the base game or an earlier mod) are errors - mods cannot override base content.
* Out-of-range numbers, bad colours, missing required files, malformed JSON, code files: errors listed in Parents -> Mods.
* A missing *optional* asset (icon) or an unknown file type is only a warning.
* Mods load in folder-name order; the first one to claim an id wins.

## If a mod breaks something
If the game crashes while mods are installed, the next start comes up in **Safe mode** (mods off) with a notice. Open
Parents -> Mods, turn the culprit off or delete its folder, then turn Safe mode off. Nothing in a mod can alter your save.
