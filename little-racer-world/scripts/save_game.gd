extends Node
## Progress save (selected car, paints, stars, best times) in user://save.json.

const PATH := "user://save.json"

var selected_car := "sunny_hatch"
var paints := {}        # vehicle id -> paint index
var best_times := {}    # race id -> seconds
var stars := 0
var races_finished := 0

func _ready() -> void:
	load_game()

func paint_for(vehicle_id: String, default_paint: int = 0) -> int:
	return int(paints.get(vehicle_id, default_paint))

func is_unlocked(vehicle: Dictionary) -> bool:
	return stars >= int(vehicle.get("unlock_stars", 0))

func record_race(race_id: String, time_s: float) -> bool:
	races_finished += 1
	var best: float = best_times.get(race_id, INF)
	var is_new_best := time_s < best
	if is_new_best:
		best_times[race_id] = time_s
	save_game()
	return is_new_best

func load_game() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file unreadable, starting fresh")
		return
	selected_car = str(parsed.get("selected_car", selected_car))
	paints = parsed.get("paints", {})
	best_times = parsed.get("best_times", {})
	stars = int(parsed.get("stars", 0))
	races_finished = int(parsed.get("races_finished", 0))

func save_game() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Cannot write save file")
		return
	f.store_string(JSON.stringify({
		"version": 1, "selected_car": selected_car, "paints": paints,
		"best_times": best_times, "stars": stars, "races_finished": races_finished,
	}, "  "))
	f.close()
	DirAccess.rename_absolute(tmp, PATH)

func wipe() -> void:
	selected_car = "sunny_hatch"
	paints = {}
	best_times = {}
	stars = 0
	races_finished = 0
	save_game()
