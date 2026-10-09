# Modding (Phase 1 foundation)

Everything the game plays is data. A mod is a folder in the app's `user://mods/` directory:
```
user://mods/<mod_name>/data/vehicles.json   -> {"vehicles":[{...}], "paints":[...optional...]}
user://mods/<mod_name>/data/races.json      -> {"races":[{...}]}
user://mods/<mod_name>/data/towns/<id>.json -> a town (map grid + settings)
user://mods/<mod_name>/models/*.glb         -> referenced by a vehicle's "model" (relative path)
```
Entries are merged **by `id`**: reuse a base id to override it, use a new id to add. Invalid entries are skipped with a warning.
Vehicle fields: see `data/vehicles.json` (id, name, model, model_scale, model_yaw, top_speed, acceleration, handling, unlock_stars...).
Race fields: see `data/races.json` (id, town, route corners, laps, opponents, rewards).
`user://` on desktop is `~/.local/share/godot/app_userdata/Little Racer World/`; on Android it is app-private storage, so on a
non-rooted phone mods can't be dropped in yet — a proper in-app mod import is a later phase. The loader itself is covered by `tools/smoke_test.gd`.
