extends Node3D
## The playable world: builds the town, spawns the player and opponents, runs the
## countdown / checkpoints / laps / results (race mode) or free roam with collectible stars.

signal race_finished(info: Dictionary)

const GRID_BACK := 8.0
const GRID_ROW := 9.0
const GRID_SIDE := 2.6

var mode := "race"
var race: Dictionary = {}
var town: Town
var player: Vehicle
var cam: ChaseCamera
var hud: HUD
var touch: TouchControls
var racers: Array = []
var route := PackedVector3Array()
var route_cells := {}
var laps := 2
var gate_every := 8
var state := "countdown"
var race_time := 0.0
var stars_collected := 0
var star_nodes: Array = []
var star_mesh: Mesh
var gate: Node3D
var gate_beam: MeshInstance3D
var arrow: Node3D
var autodrive := false
var _countdown := 3.5
var _last_count_shown := 99
var _wrong_way_t := 0.0
var _tilt_neutral := 0.0
var _player_racer: Dictionary
var _paused := false
var _last_gate_idx := -1
var osm: OsmWorld
var traffic: TrafficManager
var minimap: MapView
var circuit: CircuitRace
var _off_t := 0.0
var _recover_cd := 0.0

func _ready() -> void:
	var launch := Content.launch
	mode = str(launch.get("mode", "race"))
	autodrive = bool(launch.get("autodrive", false))
	race = Content.get_race(str(launch.get("race_id", Content.races[0]["id"] if not Content.races.is_empty() else "")))
	if mode == "race" and race.is_empty():
		mode = "roam"
	var town_id: String = str(race.get("town", "sunnyvale")) if mode == "race" else str(launch.get("town", "sunnyvale"))
	if not Content.towns.has(town_id):
		push_error("Town '%s' not found" % town_id)
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
		return
	var town_data: Dictionary = Content.towns[town_id]
	var is_osm := str(town_data.get("kind", "grid")) == "osm"
	if is_osm:
		Look.add_to(self, Settings.shadows, 150.0)
	else:
		_build_environment()
	if mode == "race" and race.has("circuit") and not town_data.has("township"):
		race = {}
		mode = "roam"
	_prepare_route(town_data)
	if is_osm:
		osm = OsmWorld.new()
		town = osm
	else:
		town = Town.new()
	add_child(town)
	town.build(town_data, route_cells)
	if mode == "race" and race.has("circuit"):
		_setup_circuit()
	_spawn_vehicles(town_data)
	_build_markers()
	_build_stars()
	cam = ChaseCamera.new()
	cam.far = 900.0 if is_osm else 500.0
	cam.target = player
	add_child(cam)
	cam.current = true
	cam.snap_to_target()
	_debug_camera()
	hud = HUD.new()
	add_child(hud)
	hud.set_mode(mode == "race")
	hud.pause_requested.connect(func(): _set_paused(true))
	hud.resume_requested.connect(func(): _set_paused(false))
	hud.restart_requested.connect(_restart)
	hud.menu_requested.connect(_to_menu)
	hud.roam_requested.connect(_to_roam)
	hud.set_stars(Save.stars)
	if Settings.touch_enabled():
		var layer := CanvasLayer.new()
		layer.layer = 9
		touch = TouchControls.new()
		layer.add_child(touch)
		add_child(layer)
	if is_osm:
		_setup_osm_extras()
	Sfx.start_engine()
	player.bumped.connect(func(s): Sfx.play("bump", 0.4 + s))
	var a := Input.get_accelerometer()
	_tilt_neutral = a.y
	if mode == "race":
		_set_frozen(true)
		state = "countdown"
		if circuit != null:
			_countdown = 5.4
			hud.set_start_lights(0)
			hud.set_lapinfo("Best --   Last --")
		hud.set_lap(1, laps)
		hud.set_place(_place_of(_player_racer), racers.size())
	else:
		state = "free"
		hud.show_message("Free roam!  Collect the stars", 2.2)

func _exit_tree() -> void:
	get_tree().paused = false
	Sfx.stop_engine()
	if touch:
		touch.release_all()
	Save.save_game()

# ---------------------------------------------------------------- setup
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("2f78d8")
	sm.sky_horizon_color = Color("bcd9f0")
	sm.ground_horizon_color = Color("bcd9f0")
	sm.ground_bottom_color = Color("7fa56a")
	sm.sky_energy_multiplier = 1.7
	sm.sun_angle_max = 6.0
	sm.sun_curve = 0.05
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9b4c4")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color("bcd9f0")
	env.fog_density = 0.0016
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 0.95
	sun.light_color = Color("fff1dc")
	sun.shadow_enabled = Settings.shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 130.0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.2
	add_child(sun)

func _prepare_route(town_data: Dictionary) -> void:
	if mode != "race":
		return
	laps = int(race.get("laps", 2))
	if race.has("circuit"):
		laps = int(Content.launch.get("laps", race.get("laps", 3)))
		return
	gate_every = int(race.get("gate_every", 8))
	if race.has("route_xz"):
		var pts: Array = race["route_xz"]
		for i in pts.size():
			var a := Vector3(float(pts[i][0]), 0.0, float(pts[i][1]))
			var b := Vector3(float(pts[(i + 1) % pts.size()][0]), 0.0, float(pts[(i + 1) % pts.size()][1]))
			var k := maxi(1, int(round(a.distance_to(b) / 11.0)))
			for j in k:
				route.append(a.lerp(b, float(j) / k))
		return
	var corners: Array = race["route"]
	var cells: Array[Vector2i] = [Vector2i(int(corners[0][0]), int(corners[0][1]))]
	for i in range(1, corners.size()):
		var a := cells[-1]
		var b := Vector2i(int(corners[i][0]), int(corners[i][1]))
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		if step.x != 0 and step.y != 0:
			push_warning("Race route segments must be axis-aligned")
		var c := a
		while c != b:
			c += step
			cells.append(c)
	if cells.size() > 1 and cells[-1] == cells[0]:
		cells.pop_back()
	var cell := float(town_data.get("cell", 12.0))
	var ox: float = -float(town_data["cols"]) * cell * 0.5
	var oz: float = -float(town_data["rows"]) * cell * 0.5
	for c in cells:
		route.append(Vector3(ox + (c.x + 0.5) * cell, 0.0, oz + (c.y + 0.5) * cell))
		route_cells[c] = true

func _make_vehicle(vehicle_id: String, paint: int) -> Vehicle:
	var v := Vehicle.create(Content.get_vehicle(vehicle_id), paint)
	add_child(v)
	v.road_query = Callable(town, "is_road_at")
	return v

func _spawn_vehicles(town_data: Dictionary) -> void:
	var car_id: String = Save.selected_car
	var def := Content.get_vehicle(car_id)
	if circuit != null and str(def.get("class", "")) != str(race.get("require_class", "racer")):
		car_id = "gp_racer"
		def = Content.get_vehicle(car_id)
	if not Save.is_unlocked(def):
		car_id = "sunny_hatch"
		def = Content.get_vehicle(car_id)
	player = _make_vehicle(car_id, Save.paint_for(car_id, int(def.get("default_paint", 0))))
	var spawn_dir := Vector3(1, 0, 0)
	var spawn_pos := Vector3.ZERO
	if osm != null:
		var sp := osm.spawn_pose()
		spawn_pos = sp.origin
		spawn_dir = -sp.basis.z
	else:
		spawn_pos = town.cell_center(int(town_data["spawn"]["cell"][0]), int(town_data["spawn"]["cell"][1]))
	if mode == "race":
		spawn_pos = route[0]
		spawn_dir = (route[1] - route[0]).normalized()
	if circuit != null:
		_spawn_circuit_grid()
		return
	var right := Vector3(-spawn_dir.z, 0, spawn_dir.x)
	var slots := [[0, -1], [0, 1], [1, -1], [1, 1]]
	var yaw := atan2(-spawn_dir.x, -spawn_dir.z)
	var player_slot := 2 if mode == "race" else 0
	var xf := func(slot: int) -> Transform3D:
		var s: Array = slots[slot]
		var p: Vector3 = spawn_pos - spawn_dir * (GRID_BACK + GRID_ROW * s[0]) + right * (GRID_SIDE * s[1])
		p.y = 0.65
		return Transform3D(Basis(Vector3.UP, yaw), p)
	player.transform = xf.call(player_slot)
	_player_racer = {"name": "You", "vehicle": player, "count": 0, "frac": 0.0, "progress": 0.0, "finished": false, "finish_time": 0.0, "is_player": true}
	racers.append(_player_racer)
	if mode != "race":
		return
	var ai_slots := [0, 1, 3]
	var opponents: Array = race.get("opponents", [])
	for i in mini(opponents.size(), ai_slots.size()):
		var o: Dictionary = opponents[i]
		var v := _make_vehicle(str(o["vehicle"]), int(o.get("paint", 0)))
		v.transform = xf.call(ai_slots[i])
		var r := {"name": str(o["name"]), "vehicle": v, "count": 0, "frac": 0.0, "progress": 0.0, "finished": false, "finish_time": 0.0, "is_player": false}
		racers.append(r)
		_attach_ai(r, float(o.get("skill", 0.88)), float(o.get("lane", 0.0)))
	if autodrive:
		_attach_ai(_player_racer, 0.97, 0.0)

func _setup_circuit() -> void:
	circuit = CircuitRace.new()
	add_child(circuit)
	var c: Dictionary = osm.township.d["circuit"]
	circuit.setup(self, osm.township.circuit_world(), laps, c.get("sector_indices", [115, 239]), float(race.get("corner_g", 24.0)))
	route = circuit.pts
	circuit.lap_done.connect(_on_lap_done)
	circuit.racer_finished.connect(_on_circuit_finished)

func _new_racer(rname: String, v: Vehicle, is_player: bool) -> Dictionary:
	return {"name": rname, "vehicle": v, "count": 0, "frac": 0.0, "progress": 0.0, "finished": false, "finish_time": 0.0, "is_player": is_player}

func _attach_circuit_ai(r: Dictionary, skill: float, lane: float) -> CircuitDriver:
	var d := CircuitDriver.new()
	d.car = r["vehicle"]
	d.circuit = circuit
	d.racer = r
	d.skill = skill
	d.lane = lane
	r["driver"] = d
	add_child(d)
	return d

func _spawn_circuit_grid() -> void:
	var tw := osm.township
	player.transform = tw.grid_transform(2)
	_player_racer = _new_racer("You", player, true)
	racers.append(_player_racer)
	var ai_slots := [0, 1, 3, 4]
	var opponents: Array = race.get("opponents", [])
	for i in mini(opponents.size(), ai_slots.size()):
		var o: Dictionary = opponents[i]
		var v := _make_vehicle(str(o["vehicle"]), int(o.get("paint", 0)))
		v.transform = tw.grid_transform(ai_slots[i])
		var r := _new_racer(str(o["name"]), v, false)
		racers.append(r)
		_attach_circuit_ai(r, float(o.get("skill", 0.92)), float(o.get("lane", 0.0)))
	if autodrive:
		_attach_circuit_ai(_player_racer, 0.97, 0.0)
	for r in racers:
		circuit.init_racer(r)

func _on_lap_done(r: Dictionary, lap_time: float, is_best: bool) -> void:
	if not r["is_player"]:
		return
	var done: int = r["laps_done"]
	if done < laps:
		hud.set_lap(done + 1, laps)
		hud.show_message("Lap %d!" % (done + 1), 1.0, Color("6dff8a"))
		Sfx.play("ding")
	hud.set_lapinfo("Best %s   Last %s" % [UI.format_time(r["best_lap"]), UI.format_time(lap_time)])
	if is_best and done > 1:
		hud.set_sector("BEST LAP!", true)

func _on_circuit_finished(r: Dictionary) -> void:
	if r["is_player"]:
		_circuit_player_finished()
	else:
		var d = r.get("driver")
		if d != null:
			d.cool_down = true

func _attach_ai(r: Dictionary, skill: float, lane: float) -> void:
	var d := AIDriver.new()
	d.car = r["vehicle"]
	d.route = route
	d.racer = r
	d.skill = skill
	d.lane = lane
	r["driver"] = d
	add_child(d)

func _build_markers() -> void:
	if mode != "race" or circuit != null:
		return
	gate = Node3D.new()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.0
	torus.outer_radius = 5.7
	ring.mesh = torus
	ring.rotation_degrees.x = 90.0
	ring.position.y = 5.8
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("ffe14a")
	m.emission_enabled = true
	m.emission = Color("ffcc00")
	m.emission_energy_multiplier = 1.6
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(ring)
	gate_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 60.0
	gate_beam.mesh = cyl
	gate_beam.position.y = 30.0
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1, 0.9, 0.2, 0.28)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gate_beam.material_override = bm
	gate_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(gate_beam)
	add_child(gate)
	arrow = Node3D.new()
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.9
	cm.height = 2.4
	cone.mesh = cm
	cone.rotation_degrees.x = -90.0
	cone.scale = Vector3(1.5, 1.0, 0.28)
	var am := StandardMaterial3D.new()
	am.albedo_color = Color("ff7a1a")
	am.emission_enabled = true
	am.emission = Color("ff5a00")
	am.emission_energy_multiplier = 1.2
	cone.material_override = am
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(cone)
	add_child(arrow)
	_place_gate()

func _build_stars() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector2] = []
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		var rr := 1.0 if i % 2 == 0 else 0.46
		pts.append(Vector2(cos(a) * rr, sin(a) * rr))
	for i in 10:
		var p0 := pts[i]
		var p1 := pts[(i + 1) % 10]
		for zc in [0.28, -0.28]:
			var tri := [Vector3(0, 0, zc), Vector3(p0.x, p0.y, 0), Vector3(p1.x, p1.y, 0)]
			if zc < 0:
				tri.reverse()
			for p in tri:
				st.add_vertex(p)
	st.generate_normals()
	star_mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ffd21f")
	mat.emission_enabled = true
	mat.emission = Color("ffb800")
	mat.emission_energy_multiplier = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.metallic = 0.3
	mat.roughness = 0.35
	for p in town.star_positions:
		var n := MeshInstance3D.new()
		n.mesh = star_mesh
		n.material_override = mat
		n.scale = Vector3.ONE * 1.4
		n.position = p
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		star_nodes.append(n)

# ---------------------------------------------------------------- per-frame
func _set_frozen(on: bool) -> void:
	for r in racers:
		r["vehicle"].frozen_control = on

func _process(dt: float) -> void:
	if player == null:
		return
	Sfx.engine_level = clampf(absf(player.speed) / player.max_speed, 0.0, 1.0)
	hud.set_speed(player.speed)
	var t := Time.get_ticks_msec() * 0.001
	for n in star_nodes:
		if is_instance_valid(n):
			n.rotation.y += dt * 2.4
			n.position.y = 1.7 + sin(t * 2.0 + n.position.x) * 0.2
	if state == "countdown" and circuit != null:
		_countdown -= dt
		var lit := clampi(int((5.4 - _countdown) / 0.9), 0, 5)
		if lit != _last_count_shown:
			_last_count_shown = lit
			hud.set_start_lights(lit)
			Sfx.play("beep", 0.8)
		if _countdown <= 0.0:
			hud.set_start_lights(-1)
			hud.show_message("GO!", 0.9, Color("6dff8a"))
			Sfx.play("go")
			_set_frozen(false)
			state = "racing"
			race_time = 0.0
	elif state == "countdown":
		_countdown -= dt
		var shown := ceili(_countdown - 0.5)
		if shown != _last_count_shown and shown >= 0:
			_last_count_shown = shown
			if shown > 0:
				hud.show_message(str(shown), 0.7)
				Sfx.play("beep")
			else:
				hud.show_message("GO!", 0.9, Color("6dff8a"))
				Sfx.play("go")
				_set_frozen(false)
				state = "racing"
				race_time = 0.0
	elif state == "racing" or state == "finished":
		if state == "racing":
			race_time += dt
			hud.set_time(race_time)

func _physics_process(dt: float) -> void:
	if player == null:
		return
	if not autodrive:
		_drive_player(dt)
	if Input.is_action_just_pressed("interact"):
		Sfx.play("horn")
	if Input.is_action_just_pressed("reset_car"):
		_reset_player()
	if Input.is_action_just_pressed("pause_game"):
		_set_paused(not _paused)
	_collect_stars()
	if osm != null:
		_check_recovery(dt)
	if circuit != null and state != "countdown":
		circuit.physics(dt)
		hud.set_place(_place_of(_player_racer), racers.size())
	elif mode == "race" and state != "countdown":
		for r in racers:
			_update_racer(r)
		_update_markers(dt)
		hud.set_place(_place_of(_player_racer), racers.size())
		_check_wrong_way(dt)

func _drive_player(dt: float) -> void:
	if state == "finished":
		if circuit == null:
			player.throttle = 0.0
			player.steer = 0.0
		return
	var br := Input.get_action_strength("brake")
	var th := Input.get_action_strength("accelerate")
	var touch_on := Settings.touch_enabled()
	if touch_on and Settings.auto_accelerate:
		th = 1.0 if br < 0.1 else 0.0
	var target := Input.get_axis("steer_left", "steer_right")
	if touch_on and Settings.tilt_steering:
		var a := Input.get_accelerometer()
		var tilt := (a.y - _tilt_neutral) / 4.0 * Settings.tilt_sensitivity
		if Settings.tilt_invert:
			tilt = -tilt
		target = clampf(tilt * 1.5, -1.0, 1.0) if absf(tilt) > 0.05 else 0.0
	var rate := 6.5 if absf(target) > absf(player.steer) else 10.0
	player.steer = move_toward(player.steer, target, rate * dt)
	player.throttle = th
	player.brake = br
	player.handbrake = Input.is_action_pressed("handbrake")

func _collect_stars() -> void:
	var pp := player.global_position
	for i in range(star_nodes.size() - 1, -1, -1):
		var n: MeshInstance3D = star_nodes[i]
		var d := Vector2(n.position.x - pp.x, n.position.z - pp.z).length()
		if d < 4.2:
			star_nodes.remove_at(i)
			n.queue_free()
			stars_collected += 1
			Save.stars += 1
			hud.set_stars(Save.stars)
			Sfx.play("star")

func _update_racer(r: Dictionary) -> void:
	if r["finished"]:
		return
	var n := route.size()
	var idx: int = int(r["count"]) % n
	var p := route[idx]
	var pos: Vector3 = (r["vehicle"] as Vehicle).global_position
	var d := Vector2(p.x - pos.x, p.z - pos.z).length()
	var radius := 15.0 if r["is_player"] else 12.0
	if d < radius:
		r["count"] = int(r["count"]) + 1
		_on_waypoint(r)
		idx = int(r["count"]) % n
		p = route[idx]
		d = Vector2(p.x - pos.x, p.z - pos.z).length()
	r["frac"] = clampf(1.0 - d / town.cell, 0.0, 0.99)
	r["progress"] = float(r["count"]) + float(r["frac"])

func _on_waypoint(r: Dictionary) -> void:
	var n := route.size()
	var count: int = r["count"]
	var passed_idx := (count - 1) % n
	var done_laps := (count - 1) / n
	var finish_count := laps * n + 1
	if count >= finish_count:
		_finish_racer(r)
		return
	if not r["is_player"]:
		return
	if passed_idx == 0 and count > 1:
		hud.show_message("Lap %d!" % (done_laps + 1), 1.0, Color("6dff8a"))
		Sfx.play("ding")
	elif passed_idx % gate_every == 0 and passed_idx != 0:
		hud.show_message("Checkpoint!", 0.6, Color("ffe14a"))
		Sfx.play("ding", 0.7)
	hud.set_lap(mini(laps, done_laps + 1), laps)

func _finish_racer(r: Dictionary) -> void:
	r["finished"] = true
	r["finish_time"] = race_time
	r["finish_order"] = racers.filter(func(x): return x["finished"]).size()
	if r["is_player"]:
		_player_finished()

func _place_of(r: Dictionary) -> int:
	return _sorted_racers().find(r) + 1

func _sorted_racers() -> Array:
	var list := racers.duplicate()
	list.sort_custom(func(a, b):
		if a["finished"] != b["finished"]:
			return a["finished"]
		if a["finished"]:
			return a["finish_order"] < b["finish_order"]
		return a["progress"] > b["progress"])
	return list

func _place_gate() -> void:
	if gate == null:
		return
	var n := route.size()
	var idx: int = int(_player_racer["count"]) % n
	var gi := idx
	if gi % gate_every != 0:
		gi = ((idx / gate_every) + 1) * gate_every
	gi = gi % n
	if gi == _last_gate_idx:
		return
	_last_gate_idx = gi
	var prev := route[(gi - 1 + n) % n]
	var nxt := route[(gi + 1) % n]
	var dir := (nxt - prev).normalized()
	gate.position = route[gi]
	gate.rotation.y = atan2(-dir.x, -dir.z)

func _update_markers(dt: float) -> void:
	if state == "finished":
		gate.visible = false
		arrow.visible = false
		return
	_place_gate()
	var n := route.size()
	var target: Vector3 = route[int(_player_racer["count"]) % n]
	var pp := player.global_position
	var dir := target - pp
	dir.y = 0.0
	if dir.length() < 1.0:
		dir = -player.global_transform.basis.z
	var want := atan2(-dir.x, -dir.z)
	arrow.rotation.y = lerp_angle(arrow.rotation.y, want, 1.0 - exp(-10.0 * dt))
	arrow.position = pp + Vector3(0, 3.8 + sin(Time.get_ticks_msec() * 0.006) * 0.25, 0)

func _check_wrong_way(dt: float) -> void:
	if state != "racing":
		return
	var n := route.size()
	var target: Vector3 = route[int(_player_racer["count"]) % n]
	var to := target - player.global_position
	to.y = 0.0
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	var ang := absf(fwd.angle_to(to))
	if ang > 2.2 and to.length() > 20.0 and absf(player.speed) > 3.0:
		_wrong_way_t += dt
	else:
		_wrong_way_t = maxf(0.0, _wrong_way_t - dt * 2.0)
	hud.set_hint("Wrong way!  Follow the arrow  (R = reset)" if _wrong_way_t > 1.5 else "")

func _player_finished() -> void:
	state = "finished"
	player.frozen_control = true
	Sfx.play("fanfare")
	hud.show_message("FINISH!", 2.0, Color("6dff8a"))
	hud.set_hint("")
	var order := _sorted_racers()
	var place := order.find(_player_racer) + 1
	var rewards: Dictionary = race.get("rewards", {})
	var bonus := int(rewards.get(str(place), 0))
	Save.stars += bonus
	var new_best := Save.record_race(str(race["id"]), race_time)
	var rows: Array = []
	for i in order.size():
		var r: Dictionary = order[i]
		var t_text := UI.format_time(r["finish_time"]) if r["finished"] else "DNF"
		rows.append("%d.  %s%s   %s" % [i + 1, r["name"], "  (you)" if r["is_player"] else "", t_text])
	var info := {
		"place": place, "place_text": _ordinal(place), "time": race_time, "new_best": new_best,
		"standings": rows, "stars_earned": stars_collected + bonus, "stars_total": Save.stars,
	}
	hud.set_stars(Save.stars)
	race_finished.emit(info)
	await get_tree().create_timer(1.8).timeout
	if is_inside_tree():
		hud.show_results(info)

func _circuit_player_finished() -> void:
	state = "finished"
	Sfx.play("fanfare")
	hud.show_message("CHEQUERED FLAG!", 2.2, Color("6dff8a"))
	hud.set_hint("")
	var r := _player_racer
	if r.get("driver") == null:
		_attach_circuit_ai(r, 0.6, 0.0)
	else:
		r["driver"].skill = 0.6
		r["driver"].cool_down = true
	var place: int = int(r["finish_order"]) + 1
	var t: float = r["finish_time"]
	var rewards: Dictionary = race.get("rewards", {})
	var bonus := int(rewards.get(str(place), 0))
	Save.stars += bonus
	var new_best := Save.record_race("%s_L%d" % [race["id"], laps], t)
	var new_lap := Save.record_lap(str(race["id"]), r["best_lap"])
	var waited := 0.0
	while waited < 14.0 and racers.any(func(x): return not x["finished"]) and is_inside_tree():
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if not is_inside_tree():
		return
	var order := _sorted_racers()
	var rows: Array = []
	var podium: Array = []
	for i in order.size():
		var x: Dictionary = order[i]
		var t_text := UI.format_time(x["finish_time"]) if x["finished"] else "DNF"
		rows.append("%d.  %s%s   %s   best lap %s" % [i + 1, x["name"], "  (you)" if x["is_player"] else "", t_text, UI.format_time(x["best_lap"]) if x["best_lap"] < INF else "--"])
		podium.append({"name": x["name"], "is_player": x["is_player"], "time": x["finish_time"]})
	var info := {
		"circuit": true, "place": place, "place_text": _ordinal(place), "time": t, "new_best": new_best,
		"standings": rows, "podium": podium, "lap_times": r["lap_times"], "best_lap": r["best_lap"],
		"new_best_lap": new_lap, "fastest_lap": circuit.best_lap, "fastest_name": circuit.best_lap_name,
		"sector_times": r["sec_times"], "laps": laps,
		"stars_earned": stars_collected + bonus, "stars_total": Save.stars,
	}
	hud.set_stars(Save.stars)
	race_finished.emit(info)
	await get_tree().create_timer(1.2).timeout
	if is_inside_tree():
		hud.show_results(info)

func _debug_camera() -> void:
	var wc = Content.launch.get("wcam")
	if wc is Dictionary and osm != null:
		cam.set_physics_process(false)
		cam.set_process(false)
		var wp: Array = wc["pos"]
		var wl: Array = wc["look"]
		cam.fov = float(wc.get("fov", 70.0))
		cam.global_position = Vector3(float(wp[0]), float(wp[1]), float(wp[2]))
		var wup := Vector3.UP
		if absf(float(wp[1]) - float(wl[1])) > 0.9 * Vector2(float(wp[0]) - float(wl[0]), float(wp[2]) - float(wl[2])).length():
			wup = Vector3(0, 0, -1)
		cam.look_at(Vector3(float(wl[0]), float(wl[1]), float(wl[2])), wup)
		return
	var c = Content.launch.get("cam")
	if not (c is Dictionary) or osm == null or osm.township == null:
		return
	cam.set_physics_process(false)
	cam.set_process(false)
	var tw := osm.township
	var pos: Array = c["pos"]
	var look: Array = c["look"]
	cam.fov = float(c.get("fov", 70.0))
	cam.global_position = tw.world3(float(pos[0]), float(pos[2]), float(pos[1]))
	var tgt := tw.world3(float(look[0]), float(look[2]), float(look[1]))
	var up := Vector3.UP
	if absf(float(pos[1]) - float(look[1])) > 0.9 * Vector2(float(pos[0]) - float(look[0]), float(pos[2]) - float(look[2])).length():
		up = Vector3(tw.N.x, 0, tw.N.y)
	cam.look_at(tgt, up)

func _ordinal(n: int) -> String:
	if n == 1: return "1st"
	if n == 2: return "2nd"
	if n == 3: return "3rd"
	return "%dth" % n

func _reset_player() -> void:
	if state == "finished":
		return
	var xf: Transform3D
	if circuit != null:
		xf = circuit.reset_pose(_player_racer)
	elif mode == "race":
		var n := route.size()
		var c: int = int(_player_racer["count"])
		var a := route[maxi(c - 1, 0) % n] if c > 0 else route[0] - (route[1] - route[0]).normalized() * GRID_BACK
		var b := route[c % n]
		var dir := (b - a)
		dir.y = 0.0
		if dir.length() < 0.1:
			dir = Vector3(1, 0, 0)
		dir = dir.normalized()
		xf = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), Vector3(a.x, 0.65, a.z))
	else:
		xf = town.nearest_road_pose(player.global_position, player.heading())
	player.teleport_to(xf)
	player.steer = 0.0
	cam.snap_to_target()

# ---------------------------------------------------------------- Sheoganj extras
func _setup_osm_extras() -> void:
	if Settings.traffic > 0 and int(race.get("traffic", 1)) > 0:
		traffic = TrafficManager.new()
		add_child(traffic)
		traffic.setup(osm, player, int(Settings.TRAFFIC_COUNT[Settings.traffic]))
	var layer := CanvasLayer.new()
	layer.layer = 8
	minimap = MapView.new()
	minimap.world = osm
	minimap.player = player
	minimap.route = route
	if mode == "race":
		if circuit != null:
			minimap.targets_fn = func(): return circuit.next_checkpoint_pos(_player_racer)
		else:
			minimap.targets_fn = func(): return route[int(_player_racer["count"]) % route.size()]
	layer.add_child(minimap)
	add_child(layer)

func _unhandled_input(e: InputEvent) -> void:
	if minimap != null and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_M:
		minimap.toggle()

func _check_recovery(dt: float) -> void:
	_recover_cd = maxf(0.0, _recover_cd - dt)
	if state == "finished" or state == "countdown":
		return
	var p := player.global_position
	var in_park := osm.has_park and Vector2(p.x - osm.park_center.x, p.z - osm.park_center.z).length() < 62.0
	var off := (not in_park) and osm.road_distance(p) > 7.0
	if p.y < -3.0 or p.y > 40.0:
		off = true
		_off_t = 99.0
	_off_t = _off_t + dt if off else maxf(0.0, _off_t - dt * 2.0)
	if _off_t > 4.0 and _recover_cd <= 0.0:
		_off_t = 0.0
		_recover_cd = 3.0
		_reset_player()
		hud.show_message("Back on the road!", 1.4, Color("8fe3ff"))

# ---------------------------------------------------------------- flow
func _set_paused(on: bool) -> void:
	if state == "finished" and on:
		return
	_paused = on
	get_tree().paused = on
	hud.show_pause(on)
	if touch:
		touch.release_all()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _to_roam() -> void:
	var l := {"mode": "roam", "town": str(race.get("town", Content.launch.get("town", "sunnyvale")))}
	if circuit != null:
		l["spawn"] = "ashapurna"
	Content.launch = l
	_restart()

func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
