extends Node3D
## Main menu: a 3D turntable showroom with Play / Car Selection / Settings / Quit pages.

var ui_root: Control
var pages := {}
var turntable: Node3D
var car_node: Node3D
var cam: Camera3D
var car_index := 0
var car_name_label: Label
var car_blurb: Label
var car_status: Label
var stat_bars := {}
var paint_row: HBoxContainer
var part_labels := {}
var part_status: Label
var part_view := {}   # kind -> index being previewed (may be locked)
var use_btn: Button
var stars_label: Label
var _orbit := 0.0

func _ready() -> void:
	_build_scene()
	_build_ui()
	for i in Content.vehicles.size():
		if Content.vehicles[i]["id"] == Save.selected_car:
			car_index = i
	_refresh_car()
	show_page("main")
	_recovery_banner()

func _process(dt: float) -> void:
	_orbit += dt * 0.5
	if turntable:
		turntable.rotation.y = _orbit
	if cam:
		cam.position = Vector3(sin(_orbit * 0.3) * 0.5 + 2.2, 2.0, 10.4)
		cam.look_at(Vector3(-1.4, 0.6, 0))

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("pause_game") and not pages["main"].visible:
		show_page("main")

# ---------------------------------------------------------------- 3D backdrop
func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("3f86dc")
	sm.sky_horizon_color = Color("d6e8f5")
	sm.ground_horizon_color = Color("d6e8f5")
	sm.ground_bottom_color = Color("7fa56a")
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9b4c4")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color("d6e8f5")
	env.fog_density = 0.01
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = Settings.shadows
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("5f9e45")
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	turntable = Node3D.new()
	add_child(turntable)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.4
	cm.bottom_radius = 3.6
	cm.height = 0.3
	disc.mesh = cm
	disc.position.y = -0.15
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("30343b")
	dm.roughness = 0.6
	disc.material_override = dm
	turntable.add_child(disc)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.3
	tm.outer_radius = 3.5
	rim.mesh = tm
	rim.position.y = 0.02
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("ffd21f")
	rm.emission_enabled = true
	rm.emission = Color("ffb800")
	rim.material_override = rm
	turntable.add_child(rim)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tree_files := ["tree_oak", "tree_default", "tree_pineTallA", "tree_fat", "tree_simple"]
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(9.0, 34.0)
		var t := Content.load_model("res://assets/kenney/nature/%s.glb" % tree_files[rng.randi() % tree_files.size()])
		t.position = Vector3(cos(a) * d, 0, sin(a) * d - 4.0)
		t.scale = Vector3.ONE * rng.randf_range(4.0, 6.5)
		t.rotation.y = rng.randf() * TAU
		add_child(t)
	for i in 5:
		var h := Content.load_model("res://assets/kenney/suburban/building-type-%s.glb" % "abcdefghijklmnopqrstu"[rng.randi() % 21])
		h.scale = Vector3.ONE * 8.0
		h.position = Vector3(-26 + i * 13, 0, -22)
		h.rotation.y = rng.randf_range(-0.3, 0.3)
		add_child(h)
	cam = Camera3D.new()
	cam.fov = 42
	add_child(cam)
	cam.current = true

func _show_car() -> void:
	if car_node:
		car_node.queue_free()
	var def: Dictionary = Content.vehicles[car_index]
	car_node = CarVisual.build(def, Save.paint_for(def["id"], int(def.get("default_paint", 0))), 0.0, Save.parts_for(str(def["id"])))
	turntable.add_child(car_node)

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.theme = UI.make_theme()
	layer.add_child(ui_root)
	var title := UI.label("LITTLE RACER WORLD", 76, Color("ffe14a"))
	title.add_theme_constant_override("outline_size", 14)
	title.position = Vector2(40, 22)
	ui_root.add_child(title)
	stars_label = UI.label("", 40, Color("ffd21f"))
	stars_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stars_label.position = Vector2(-330, 30)
	stars_label.custom_minimum_size = Vector2(290, 0)
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_root.add_child(stars_label)
	pages["main"] = _page_main()
	pages["play"] = _page_play()
	pages["cars"] = _page_cars()
	pages["settings"] = _page_settings()
	pages["parents"] = _page_parents()
	for p in pages.values():
		ui_root.add_child(p)

var gp_laps := 3

func _build_pages_for_text() -> void:
	call_deferred("_rebuild_pages")

func _rebuild_pages() -> void:
	for k in pages:
		pages[k].queue_free()
	pages.clear()
	pages["main"] = _page_main()
	pages["play"] = _page_play()
	pages["cars"] = _page_cars()
	pages["settings"] = _page_settings()
	pages["parents"] = _page_parents()
	for p in pages.values():
		ui_root.add_child(p)
	show_page("settings")

func _left_column(content: Control, width := 440.0) -> Control:
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 150)
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_child(content)
	return panel

func _page_main() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.add_child(UI.button("Play", func(): show_page("play")))
	v.add_child(UI.button("Car Selection", func(): show_page("cars")))
	v.add_child(UI.button("Settings", func(): show_page("settings")))
	v.add_child(UI.button("Parents", func(): show_page("parents"), Vector2(360, 60)))
	v.add_child(UI.button("Quit", func(): get_tree().quit()))
	return _left_column(v)

func _page_play() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(UI.label("Choose a game", 38, Color("ffe14a")))
	for r in Content.races:
		var best: float = Save.best_times.get(r["id"], 0.0)
		var town_name := str(Content.towns.get(r["town"], {}).get("name", ""))
		var txt := "%s\n%s  -  %d lap%s%s" % [r["name"], town_name, int(r.get("laps", 1)), "" if int(r.get("laps", 1)) == 1 else "s", ("  -  best " + UI.format_time(best)) if best > 0.0 else ""]
		v.add_child(UI.button(txt, func():
			Content.launch = {"mode": "race", "race_id": r["id"]}
			if r.has("lap_options"):
				Content.launch["laps"] = gp_laps
			get_tree().change_scene_to_file("res://scenes/game.tscn"), Vector2(420, 96)))
		if r.has("lap_options"):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(UI.label("Laps:", 28))
			for lo in r["lap_options"]:
				var n: int = int(lo)
				var b := UI.button(str(n), func():
					gp_laps = n
					show_page("play"), Vector2(88, 64))
				b.modulate = Color("ffe14a") if n == gp_laps else Color.WHITE
				row.add_child(b)
			v.add_child(row)
	for t in Content.towns.values():
		var tid: String = t["id"]
		v.add_child(UI.button("Free Roam: " + str(t.get("name", tid)), func():
			Content.launch = {"mode": "roam", "town": tid}
			get_tree().change_scene_to_file("res://scenes/game.tscn"), Vector2(420, 76)))
	v.add_child(UI.button("Free Roam: Ashapurna Township", func():
		Content.launch = {"mode": "roam", "town": "sheoganj", "spawn": "ashapurna"}
		get_tree().change_scene_to_file("res://scenes/game.tscn"), Vector2(420, 76)))
	v.add_child(UI.button("Back", func(): show_page("main"), Vector2(360, 64)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(470, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.custom_minimum_size = Vector2(440, 0)
	sc.add_child(v)
	return _left_column(sc, 500.0)

func _page_cars() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	car_name_label = UI.label("", 38, Color("ffe14a"))
	v.add_child(car_name_label)
	car_blurb = UI.label("", 22, Color("cfe6ff"))
	car_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	car_blurb.custom_minimum_size = Vector2(560, 0)
	v.add_child(car_blurb)
	for key in ["Speed", "Acceleration", "Handling"]:
		var row := HBoxContainer.new()
		var l := UI.label(key, 22)
		l.custom_minimum_size = Vector2(170, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(300, 18)
		bar.show_percentage = false
		bar.max_value = 1.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("6dff8a")
		fill.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		stat_bars[key] = bar
		v.add_child(row)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	nav.add_child(UI.button("<", func(): _cycle(-1), Vector2(90, 62)))
	nav.add_child(UI.button(">", func(): _cycle(1), Vector2(90, 62)))
	use_btn = UI.button("Use this car", _use_car, Vector2(210, 62))
	nav.add_child(use_btn)
	nav.add_child(UI.button("Back", func(): show_page("main"), Vector2(140, 62)))
	v.add_child(nav)
	car_status = UI.label("", 20, Color("ffb3b3"))
	v.add_child(car_status)
	paint_row = HBoxContainer.new()
	paint_row.add_theme_constant_override("separation", 8)
	v.add_child(paint_row)
	for i in Content.paints.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(46, 46)
		var col := Content.paint_color(i)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(23)
			sb.border_width_left = 4; sb.border_width_right = 4; sb.border_width_top = 4; sb.border_width_bottom = 4
			sb.border_color = Color.WHITE if st != "normal" else Color(0, 0, 0, 0.35)
			sw.add_theme_stylebox_override(st, sb)
		var idx := i
		sw.pressed.connect(func(): _set_paint(idx))
		paint_row.add_child(sw)
	for kind in [["wheels", "Wheels"], ["spoilers", "Spoiler"], ["extras", "Decoration"]]:
		var pr := HBoxContainer.new()
		pr.add_theme_constant_override("separation", 8)
		var pl := UI.label(kind[1], 22)
		pl.custom_minimum_size = Vector2(130, 0)
		pr.add_child(pl)
		var pb := UI.button("", func(): _cycle_part(kind[0], -1), Vector2(52, 44))
		pb.text = "<"
		pr.add_child(pb)
		var plabel := UI.label("", 22, Color("cfe6ff"))
		plabel.custom_minimum_size = Vector2(280, 0)
		plabel.clip_text = true
		pr.add_child(plabel)
		part_labels[kind[0]] = plabel
		var nb := UI.button(">", func(): _cycle_part(kind[0], 1), Vector2(52, 44))
		pr.add_child(nb)
		v.add_child(pr)
	part_status = UI.label("", 20, Color("ffb3b3"))
	part_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(part_status)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(580, 570)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(v)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel := _left_column(sc, 600.0)
	panel.position = Vector2(40, 104)
	return panel

func _page_settings() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(UI.label("Settings", 40, Color("ffe14a")))
	var vol_row := HBoxContainer.new()
	vol_row.add_child(UI.label("Volume", 28))
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(300, 40)
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.sfx_volume
	slider.value_changed.connect(func(val):
		Settings.sfx_volume = val
		Settings.apply()
		Settings.save_settings())
	vol_row.add_child(slider)
	v.add_child(vol_row)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_child(_toggle("Auto-accelerate (touch)", Settings.auto_accelerate, func(on): Settings.auto_accelerate = on))
	grid.add_child(_toggle("Tilt steering (touch)", Settings.tilt_steering, func(on): Settings.tilt_steering = on))
	grid.add_child(_toggle("Invert tilt", Settings.tilt_invert, func(on): Settings.tilt_invert = on))
	grid.add_child(_toggle("Show touch controls on PC", Settings.force_touch, func(on): Settings.force_touch = on))
	grid.add_child(_toggle("Shadows", Settings.shadows, func(on): Settings.shadows = on))
	grid.add_child(_toggle("Speed in mph", Settings.use_mph, func(on): Settings.use_mph = on))
	grid.add_child(_toggle("Larger text", Settings.large_text, func(on):
		Settings.large_text = on
		ui_root.theme = UI.make_theme()
		_build_pages_for_text()))
	grid.add_child(_toggle("Reduced motion", Settings.reduced_motion, func(on): Settings.reduced_motion = on))
	grid.add_child(_toggle("Simple steering", Settings.simple_steering, func(on): Settings.simple_steering = on))
	v.add_child(grid)
	var cs_row := HBoxContainer.new()
	cs_row.add_child(UI.label("Camera follow", 28))
	var cs := HSlider.new()
	cs.custom_minimum_size = Vector2(300, 40)
	cs.min_value = 0.5
	cs.max_value = 1.6
	cs.step = 0.1
	cs.value = Settings.cam_sensitivity
	cs.value_changed.connect(func(val):
		Settings.cam_sensitivity = val
		Settings.save_settings())
	cs_row.add_child(cs)
	v.add_child(cs_row)
	var diff_row := HBoxContainer.new()
	diff_row.add_child(UI.label("Opponents", 28))
	var ob := OptionButton.new()
	ob.add_item("Easy", 0)
	ob.add_item("Normal", 1)
	ob.add_item("Hard", 2)
	ob.select(Settings.difficulty)
	ob.custom_minimum_size = Vector2(200, 56)
	ob.item_selected.connect(func(i):
		Settings.difficulty = i
		Settings.save_settings())
	diff_row.add_child(ob)
	v.add_child(diff_row)
	var tr_row := HBoxContainer.new()
	tr_row.add_child(UI.label("Traffic", 28))
	var tb := OptionButton.new()
	for i in 4:
		tb.add_item(["None", "Light", "Normal", "Busy"][i], i)
	tb.select(Settings.traffic)
	tb.custom_minimum_size = Vector2(200, 56)
	tb.item_selected.connect(func(i):
		Settings.traffic = i
		Settings.save_settings())
	tr_row.add_child(tb)
	v.add_child(tr_row)
	var obs_row := HBoxContainer.new()
	obs_row.add_child(UI.label("Obstacles", 28))
	var obb := OptionButton.new()
	for i in 3:
		obb.add_item(["Off", "Few", "Normal"][i], i)
	obb.select(Settings.obstacles)
	obb.custom_minimum_size = Vector2(200, 56)
	obb.item_selected.connect(func(i):
		Settings.obstacles = i
		Settings.save_settings())
	obs_row.add_child(obb)
	v.add_child(obs_row)
	var gfx_row := HBoxContainer.new()
	gfx_row.add_theme_constant_override("separation", 14)
	gfx_row.add_child(UI.label("Graphics", 28))
	var qb := OptionButton.new()
	qb.add_item("Auto (%s)" % ("High" if Settings.auto_high() else "Normal"), 0)
	qb.add_item("Normal", 1)
	qb.add_item("High", 2)
	qb.select(Settings.quality)
	qb.custom_minimum_size = Vector2(230, 56)
	qb.item_selected.connect(func(i):
		Settings.quality = i
		Settings.save_settings())
	gfx_row.add_child(qb)
	gfx_row.add_child(UI.label("Time", 28))
	var tdb := OptionButton.new()
	for i in 4:
		tdb.add_item(Settings.TOD_NAMES[i], i)
	tdb.select(Settings.time_of_day)
	tdb.custom_minimum_size = Vector2(190, 56)
	tdb.item_selected.connect(func(i):
		Settings.time_of_day = i
		Settings.save_settings())
	gfx_row.add_child(tdb)
	v.add_child(gfx_row)
	var credit := UI.label("Map: (c) OpenStreetMap contributors (ODbL); buildings: Overture Maps Foundation - Google Open Buildings (CC BY 4.0), Microsoft Building Footprints (ODbL). Textures (plaster, asphalt, ground, concrete, brick): ambientCG (CC0); sky: Poly Haven (CC0). Car/props: Kenney (CC0). Graphics changes apply next race.", 18, Color("9fb4c8"))
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.custom_minimum_size = Vector2(900, 0)
	v.add_child(credit)
	v.add_child(UI.button("Back", func(): show_page("main"), Vector2(360, 64)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(980, 530)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(v)
	var panel := _left_column(sc, 1000.0)
	panel.position = Vector2(40, 135)
	return panel

# ---------------------------------------------------------------- parents area (gate, mods, save tools)
var _parent_unlocked := false
var _confirm := ""

func _page_parents() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UI.label("Parents", 40, Color("ffe14a")))
	if not _parent_unlocked:
		var a := randi_range(3, 9)
		var b := randi_range(3, 9)
		var l := UI.label("This area is for grown-ups. What is %d + %d ?" % [a, b], 28)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(760, 0)
		v.add_child(l)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var answers := [a + b, a + b + 1, a + b - 2, a + b + 3]
		answers.shuffle()
		for ans in answers:
			var correct: bool = (ans == a + b)
			row.add_child(UI.button(str(ans), func():
				if correct:
					_parent_unlocked = true
					show_page("parents")
				else:
					show_page("parents"), Vector2(150, 76)))
		v.add_child(row)
		v.add_child(UI.button("Back", func(): show_page("main"), Vector2(360, 64)))
		return _left_column(v, 800.0)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in Settings.notices:
		var nl := UI.label(str(n), 22, Color("ffd9a0"))
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(900, 0)
		inner.add_child(nl)
	var sec := func(t: String): inner.add_child(UI.label(t, 32, Color("9be7ff")))
	sec.call("Mods")
	var info := UI.label("Put mod folders in:\n%s\nSee MODDING.md. Mods are data only (no code) and are checked before use." % ModLoader.human_dirs(), 20, Color("cfe6ff"))
	info.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	info.custom_minimum_size = Vector2(900, 0)
	inner.add_child(info)
	inner.add_child(_toggle("Safe mode: turn ALL mods off", Settings.mods_safe_mode, func(on):
		Settings.mods_safe_mode = on
		Content.reload()
		show_page("parents")))
	if Content.mod_reports.is_empty():
		inner.add_child(UI.label("No mods installed.", 24))
	for rep in Content.mod_reports:
		var box := VBoxContainer.new()
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		var st := str(rep["status"])
		var col: Color = {"ok": Color("8dff9b"), "disabled": Color("c9ced6"), "error": Color("ff9a9a")}.get(st, Color.WHITE)
		var title := UI.label("%s %s - %s" % [rep["name"], rep["version"], {"ok": "ON", "disabled": "OFF", "error": "PROBLEM"}.get(st, st)], 24, col)
		title.custom_minimum_size = Vector2(620, 0)
		title.clip_text = true
		head.add_child(title)
		if st != "error":
			var folder := str(rep["folder"])
			var on_now: bool = st == "ok"
			head.add_child(UI.button("Turn off" if on_now else "Turn on", func():
				if on_now:
					if not (folder in Settings.disabled_mods):
						Settings.disabled_mods.append(folder)
				else:
					Settings.disabled_mods.erase(folder)
				Settings.mods_safe_mode = false
				Settings.save_settings()
				Content.reload()
				show_page("parents"), Vector2(190, 56)))
		box.add_child(head)
		var detail := "%d vehicles, %d races, %d towns" % [rep["counts"]["vehicles"], rep["counts"]["races"], rep["counts"]["towns"]]
		if str(rep["description"]) != "":
			detail = str(rep["description"]) + "  (" + detail + ")"
		var dl := UI.label(detail, 18, Color("9fb4c8"))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(880, 0)
		box.add_child(dl)
		var shown := 0
		for e in rep["errors"]:
			if shown >= 4:
				box.add_child(UI.label("... and %d more problems" % (rep["errors"].size() - 4), 18, Color("ff9a9a")))
				break
			var el := UI.label("Problem: " + str(e), 18, Color("ff9a9a"))
			el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			el.custom_minimum_size = Vector2(880, 0)
			box.add_child(el)
			shown += 1
		for w in rep["warnings"]:
			var wl := UI.label("Note: " + str(w), 18, Color("ffd9a0"))
			wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wl.custom_minimum_size = Vector2(880, 0)
			box.add_child(wl)
		inner.add_child(box)
	inner.add_child(UI.button("Install sample mods", func():
		var n := ModLoader.install_samples()
		Content.reload()
		_parent_msg("Installed %d sample file(s)." % n if n >= 0 else "Could not install the samples."), Vector2(360, 60)))
	inner.add_child(UI.button("Reload mods", func():
		Content.reload()
		show_page("parents"), Vector2(300, 60)))
	sec.call("Save and settings")
	var srow := HFlowContainer.new()
	srow.add_theme_constant_override("h_separation", 10)
	srow.add_theme_constant_override("v_separation", 8)
	srow.custom_minimum_size = Vector2(900, 0)
	srow.add_child(UI.button("Back up save", func():
		_parent_msg("Save backed up." if Save.make_backup() else "Could not back up the save."), Vector2(270, 60)))
	var rb := UI.button("Restore backup", func():
		_parent_msg("Backup restored." if Save.restore_backup() else "No usable backup found."), Vector2(270, 60))
	rb.disabled = not Save.has_backup()
	srow.add_child(rb)
	srow.add_child(UI.button("Reset settings", func(): _ask("reset_settings"), Vector2(270, 60)))
	srow.add_child(UI.button("Erase progress", func(): _ask("erase_save"), Vector2(270, 60)))
	inner.add_child(srow)
	if _confirm != "":
		var cl := UI.label("Are you sure? %s" % {"reset_settings": "All settings go back to defaults.", "erase_save": "Stars, times and unlocks are erased (a backup is kept)."}.get(_confirm, ""), 22, Color("ffd9a0"))
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.custom_minimum_size = Vector2(900, 0)
		inner.add_child(cl)
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 10)
		crow.add_child(UI.button("Yes, do it", func():
			if _confirm == "reset_settings":
				Settings.reset_to_defaults()
				_parent_msg("Settings reset.")
			else:
				Save.wipe()
				_parent_msg("Progress erased. Backup kept.")
			_confirm = "", Vector2(240, 60)))
		crow.add_child(UI.button("Cancel", func():
			_confirm = ""
			show_page("parents"), Vector2(200, 60)))
		inner.add_child(crow)
	var msg := UI.label(_parent_note, 22, Color("8dff9b"))
	inner.add_child(msg)
	inner.add_child(UI.button("Lock and go back", func():
		_parent_unlocked = false
		_confirm = ""
		_parent_note = ""
		show_page("main"), Vector2(360, 64)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(940, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(inner)
	var panel := _left_column(sc, 980.0)
	panel.position = Vector2(40, 104)
	return panel

var _parent_note := ""

func _ask(what: String) -> void:
	_confirm = what
	show_page("parents")

func _parent_msg(t: String) -> void:
	_parent_note = t
	show_page("parents")

func _recovery_banner() -> void:
	var msgs: Array = Settings.notices.duplicate()
	if Save.notices_hint != "":
		msgs.append(Save.notices_hint)
	if msgs.is_empty():
		return
	var pc := PanelContainer.new()
	pc.position = Vector2(300, 500)
	pc.custom_minimum_size = Vector2(900, 0)
	var vb := VBoxContainer.new()
	var l := UI.label("\n".join(msgs), 22, Color("ffe9b0"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(860, 0)
	vb.add_child(l)
	vb.add_child(UI.button("OK", func():
		Settings.notices.clear()
		Save.notices_hint = ""
		pc.queue_free(), Vector2(160, 56)))
	pc.add_child(vb)
	ui_root.add_child(pc)

func _toggle(text: String, value: bool, setter: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.custom_minimum_size = Vector2(460, 60)
	c.add_theme_font_size_override("font_size", UI.fs(28))
	c.toggled.connect(func(on):
		Sfx.play("click")
		setter.call(on)
		Settings.apply()
		Settings.save_settings())
	return c

var _back_t := 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not pages.is_empty() and not pages["main"].visible:
			show_page("main")
		elif Time.get_ticks_msec() / 1000.0 - _back_t < 2.0:
			get_tree().quit()
		else:
			_back_t = Time.get_ticks_msec() / 1000.0

func show_page(name: String) -> void:
	for k in pages:
		pages[k].visible = (k == name)
	stars_label.text = "* %d stars" % Save.stars
	if turntable:
		turntable.position.x = 2.3 if name == "cars" else (1.6 if name == "settings" else 0.0)
	if name == "cars":
		_refresh_car()
	if name == "parents":
		ui_root.remove_child(pages["parents"])
		pages["parents"].queue_free()
		pages["parents"] = _page_parents()
		ui_root.add_child(pages["parents"])
		pages["parents"].visible = true
	if name == "play":
		ui_root.remove_child(pages["play"])
		pages["play"].queue_free()
		pages["play"] = _page_play()
		ui_root.add_child(pages["play"])

# ---------------------------------------------------------------- car selection
func _cycle(d: int) -> void:
	car_index = posmod(car_index + d, Content.vehicles.size())
	_refresh_car()

func _refresh_car() -> void:
	if turntable == null or Content.vehicles.is_empty():
		return
	car_index = clampi(car_index, 0, Content.vehicles.size() - 1)
	_show_car()
	var def: Dictionary = Content.vehicles[car_index]
	car_name_label.text = str(def["name"])
	car_blurb.text = str(def.get("blurb", ""))
	stat_bars["Speed"].value = clampf(float(def.get("max_speed", 30)) / 40.0, 0.0, 1.0)
	stat_bars["Acceleration"].value = clampf(float(def.get("accel", 14)) / 20.0, 0.0, 1.0)
	stat_bars["Handling"].value = clampf(float(def.get("handling", 1.0)) / 1.2, 0.0, 1.0)
	_refresh_parts()
	var unlocked := Save.is_unlocked(def)
	use_btn.disabled = not unlocked
	use_btn.text = "Selected" if def["id"] == Save.selected_car else "Use this car"
	car_status.visible = not unlocked
	car_status.text = "" if unlocked else "Locked - collect %d stars (you have %d)" % [int(def.get("unlock_stars", 0)), Save.stars]

func _use_car() -> void:
	var def: Dictionary = Content.vehicles[car_index]
	if Save.is_unlocked(def):
		Save.selected_car = str(def["id"])
		Save.save_game()
		_refresh_car()

func _part_list(kind: String) -> Array:
	var none := {"id": "none" if kind != "wheels" else "stock", "name": "None" if kind != "wheels" else "Stock"}
	var out := [none]
	for p in Content.parts.get(kind, []):
		if p["id"] != none["id"]:
			out.append(p)
	return out

func _cycle_part(kind: String, d: int) -> void:
	var list := _part_list(kind)
	var id := str(Content.vehicles[car_index]["id"])
	var cur: String = str(Save.parts_for(id).get(kind, ""))
	var idx := 0
	for i in list.size():
		if list[i]["id"] == cur:
			idx = i
	idx = posmod(idx + d, list.size())
	var p: Dictionary = list[idx]
	var chosen := Save.parts_for(id).duplicate()
	chosen[kind] = p["id"]
	Save.parts[id] = chosen
	if Save.part_unlocked(p):
		Save.save_game()
	Sfx.play("click")
	_refresh_parts()
	_show_car()

func _refresh_parts() -> void:
	if part_status == null:
		return
	var id := str(Content.vehicles[car_index]["id"])
	var msg := ""
	for kind in ["wheels", "spoilers", "extras"]:
		var list := _part_list(kind)
		var cur := str(Save.parts_for(id).get(kind, ""))
		var p: Dictionary = list[0]
		for q in list:
			if q["id"] == cur:
				p = q
		var ok := Save.part_unlocked(p)
		part_labels[kind].text = str(p["name"]) + ("" if ok else " (locked)")
		if not ok:
			msg = "%s: earn %s to unlock (preview only)" % [p["name"], Save.part_requirement(p)]
	part_status.text = msg

func _set_paint(i: int) -> void:
	var def: Dictionary = Content.vehicles[car_index]
	Save.paints[def["id"]] = i
	Save.save_game()
	Sfx.play("click")
	_show_car()
