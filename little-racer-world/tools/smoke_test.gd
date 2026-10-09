extends SceneTree
## Headless smoke test: godot --headless -s tools/smoke_test.gd
## Covers: mod loading from user://, simulated multi-touch -> Input actions, a full autodriven
## race to the finish, results sanity, and the save file being written.
var fails: Array[String] = []
var phase := 0
var frames := 0
var info := {}
var game: Node
var t0 := 0.0
var recovery_tested := false
var recovery_checked := false

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails.append(msg)

func _initialize() -> void:
	t0 = Time.get_ticks_msec() / 1000.0
	var Content = root.get_node("Content")
	var Save = root.get_node("Save")
	var Settings = root.get_node("Settings")
	Save.wipe()
	var dir := "user://mods/smoketest/data"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/vehicles.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"vehicles": [{"id": "smoke_car", "name": "Smoke Car", "model": "res://assets/kenney/cars/taxi.glb", "model_scale": 1.75, "top_speed": 30.0, "acceleration": 10.0, "handling": 1.0}]}))
	f.close()
	Content.reload()
	check(Content.get_vehicle("smoke_car")["id"] == "smoke_car", "mod vehicle loaded from user://mods")
	check(Content.get_vehicle("sunny_hatch")["id"] == "sunny_hatch", "base vehicle still present after mods")
	check(Content.races.size() >= 1 and Content.towns.size() >= 1, "races and towns loaded")
	DirAccess.remove_absolute(dir + "/vehicles.json")
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute("user://mods/smoketest/data")
	DirAccess.remove_absolute("user://mods/smoketest")
	Content.reload()
	check(Content.get_vehicle("smoke_car")["id"] != "smoke_car", "mod removed cleanly")
	Settings.force_touch = true
	Content.launch = {"mode": "race", "race_id": "sunny_circuit", "autodrive": true}
	Engine.time_scale = 3.0
	change_scene_to_file("res://scenes/game.tscn")

func _process(_dt: float) -> bool:
	frames += 1
	var elapsed := Time.get_ticks_msec() / 1000.0 - t0
	if elapsed > 600.0:
		check(false, "races finished within 600 s wall-clock")
		return _finish()
	if phase == 0 and frames > 20 and current_scene != null:
		game = current_scene
		game.race_finished.connect(func(i): info = i)
		phase = 1
	elif phase == 1 and frames > 60 and game.touch != null:
		_touch_test()
		phase = 2
	elif phase == 2 and not info.is_empty():
		_check_results()
		var Content = root.get_node("Content")
		Content.launch = {"mode": "race", "race_id": "sheoganj_lanes", "autodrive": true}
		info = {}
		phase = 3
		frames = 0
		change_scene_to_file("res://scenes/game.tscn")
	elif phase == 3 and frames > 40 and current_scene != null and current_scene.get("osm") != null:
		game = current_scene
		game.race_finished.connect(func(i): info = i)
		_osm_checks()
		phase = 4
	elif phase == 4 and frames > 400 and not recovery_tested:
		recovery_tested = true
		game.player.teleport_to(Transform3D(Basis.IDENTITY, Vector3(game.player.global_position.x, -12.0, game.player.global_position.z)))
	elif phase == 4 and frames > 440 and recovery_tested and not recovery_checked:
		recovery_checked = true
		check(game.player.global_position.y > -2.0, "fell off world -> auto-recovered (y=%.1f)" % game.player.global_position.y)
	elif phase == 4 and not info.is_empty():
		check(info["place"] >= 1 and info["place"] <= 4, "Sheoganj race finished (place %s, %.0f s)" % [info["place"], info["time"]])
		return _finish()
	return false

func _centre(touch, action: String) -> Vector2:
	var b: Control = touch.buttons[action]
	return b.global_position + b.size * 0.5

func _tap(idx: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _touch_test() -> void:
	var t = game.touch
	_tap(0, _centre(t, "steer_left"), true)
	_tap(1, _centre(t, "brake"), true)
	check(Input.is_action_pressed("steer_left"), "touch finger 0 -> steer_left")
	check(Input.is_action_pressed("brake"), "touch finger 1 -> brake (multi-touch)")
	_tap(0, _centre(t, "steer_left"), false)
	check(not Input.is_action_pressed("steer_left") and Input.is_action_pressed("brake"), "release finger 0 keeps finger 1 held")
	_tap(1, _centre(t, "brake"), false)
	check(not Input.is_action_pressed("brake"), "release finger 1 -> brake up")

func _check_results() -> void:
	check(info["place"] >= 1 and info["place"] <= 4, "player place is 1..4 (got %s)" % info["place"])
	check(info["time"] > 30.0 and info["time"] < 600.0, "race time sane (%.1f s)" % info["time"])
	check((info["standings"] as Array).size() == 4, "4 racers in standings")
	var Save = root.get_node("Save")
	check(FileAccess.file_exists("user://save.json"), "save file written")
	var d = JSON.parse_string(FileAccess.get_file_as_string("user://save.json"))
	check(d is Dictionary and int(d.get("races_finished", 0)) >= 1, "save records the finished race")
	check(d is Dictionary and d.get("best_times", {}).has("sunny_circuit"), "best time saved")
	check(Save.stars > 0, "stars rewarded (%d)" % Save.stars)

func _osm_checks() -> void:
	var Settings = root.get_node("Settings")
	var w = game.osm
	check(w != null and w.extent > 500.0, "Sheoganj OSM world loaded")
	var sp: Transform3D = w.spawn_pose()
	check(w.is_road_at(sp.origin), "spawn is on a real road")
	check(not w.is_road_at(Vector3(5000, 0, 5000)), "far field is not road")
	check(w.star_positions.size() >= 60, "stars placed (%d)" % w.star_positions.size())
	check(w.has_park, "stunt park exists")
	check(game.route.size() > 100, "route densified (%d pts)" % game.route.size())
	var want: int = Settings.TRAFFIC_COUNT[Settings.traffic]
	check(game.traffic != null and game.traffic.cars.size() == want, "traffic count matches setting (%d)" % want)
	check(game.minimap != null, "minimap created")
	var rr: PackedVector3Array = w.random_route(w.nearest_node(Vector2(0, 0)), 400.0)
	check(rr.size() > 10, "traffic random route on real roads (%d pts)" % rr.size())

func _finish() -> bool:
	Engine.time_scale = 1.0
	print("SMOKE %s  (%d failures, %.0f s)" % ["PASS" if fails.is_empty() else "FAIL", fails.size(), Time.get_ticks_msec() / 1000.0 - t0])
	quit(0 if fails.is_empty() else 1)
	return true
