extends Node
## Progress save (selected car, paints, stars, best times) in user://save.json.

const PATH := "user://save.json"
const BACKUP := "user://save.backup.json"
var notices_hint := ""   # one-time recovery message for the menu

var selected_car := "sunny_hatch"
var paints := {}        # vehicle id -> paint index
var best_times := {}    # race id -> seconds
var best_laps := {}     # race id -> best single lap (seconds)
var stars := 0
var parts := {}         # vehicle id -> {wheels, spoilers, extras} part ids
var races_finished := 0

func _ready() -> void:
	load_game()

func paint_for(vehicle_id: String, default_paint: int = 0) -> int:
	return int(paints.get(vehicle_id, default_paint))

func parts_for(vehicle_id: String) -> Dictionary:
	var p = parts.get(vehicle_id, {})
	return p if p is Dictionary else {}

## Chosen parts for a car, with any part that is no longer unlocked/known dropped.
func active_parts(vehicle_id: String) -> Dictionary:
	var out := {}
	var chosen := parts_for(vehicle_id)
	for kind in ["wheels", "spoilers", "extras"]:
		var def: Dictionary = Content.get_part(kind, str(chosen.get(kind, "")))
		if not def.is_empty() and part_unlocked(def):
			out[kind] = def["id"]
	return out

func part_unlocked(p: Dictionary) -> bool:
	return stars >= int(p.get("unlock_stars", 0)) and races_finished >= int(p.get("unlock_races", 0))

static func part_requirement(p: Dictionary) -> String:
	var bits := []
	if int(p.get("unlock_stars", 0)) > 0:
		bits.append("%d stars" % int(p["unlock_stars"]))
	if int(p.get("unlock_races", 0)) > 0:
		bits.append("finish %d race%s" % [int(p["unlock_races"]), "" if int(p["unlock_races"]) == 1 else "s"])
	return " + ".join(bits)

func is_unlocked(vehicle: Dictionary) -> bool:
	return stars >= int(vehicle.get("unlock_stars", 0))

func record_race(race_id: String, time_s: float) -> bool:
	races_finished += 1
	var best: float = best_times.get(race_id, INF)
	var is_new_best := time_s < best
	if is_new_best:
		best_times[race_id] = time_s
	save_game()
	make_backup()
	return is_new_best

func record_lap(race_id: String, lap_s: float) -> bool:
	var best: float = best_laps.get(race_id, INF)
	if lap_s < best:
		best_laps[race_id] = lap_s
		save_game()
		return true
	return false

func load_game() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f = null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file unreadable, starting fresh")
		DirAccess.rename_absolute(PATH, "user://save.corrupt.json")
		if FileAccess.file_exists(BACKUP):
			notices_hint = "Your save file was damaged. A copy was kept (save.corrupt.json). You can restore the last backup in Parents > Save."
		else:
			notices_hint = "Your save file was damaged, so progress was reset (a copy was kept as save.corrupt.json)."
		return
	selected_car = str(parsed.get("selected_car", selected_car))
	paints = parsed.get("paints", {})
	best_times = parsed.get("best_times", {})
	best_laps = parsed.get("best_laps", {})
	stars = int(parsed.get("stars", 0))
	races_finished = int(parsed.get("races_finished", 0))
	var pp = parsed.get("parts", {})
	parts = pp if pp is Dictionary else {}

func has_backup() -> bool:
	return FileAccess.file_exists(BACKUP)

func make_backup() -> bool:
	if not FileAccess.file_exists(PATH):
		save_game()
	return DirAccess.copy_absolute(PATH, BACKUP) == OK

func restore_backup() -> bool:
	if not has_backup():
		return false
	var txt := FileAccess.get_file_as_string(BACKUP)
	if typeof(JSON.parse_string(txt)) != TYPE_DICTIONARY:
		return false
	if DirAccess.copy_absolute(BACKUP, PATH) != OK:
		return false
	load_game()
	return true

func save_game() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Cannot write save file")
		return
	f.store_string(JSON.stringify({
		"version": 1, "selected_car": selected_car, "paints": paints, "parts": parts,
		"best_times": best_times, "best_laps": best_laps, "stars": stars, "races_finished": races_finished,
	}, "  "))
	f.close()
	DirAccess.rename_absolute(tmp, PATH)

func wipe() -> void:
	if FileAccess.file_exists(PATH) and (stars > 0 or races_finished > 0):
		make_backup()
	selected_car = "sunny_hatch"
	paints = {}
	parts = {}
	best_times = {}
	best_laps = {}
	stars = 0
	races_finished = 0
	save_game()
