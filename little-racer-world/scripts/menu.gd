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

func _process(dt: float) -> void:
	_orbit += dt * 0.5
	if turntable:
		turntable.rotation.y = _orbit
	if cam:
		cam.position = Vector3(sin(_orbit * 0.3) * 0.5 + 1.0, 1.7, 7.4)
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
	car_node = CarVisual.build(def, Save.paint_for(def["id"], int(def.get("default_paint", 0))), 0.0)
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
	for p in pages.values():
		ui_root.add_child(p)

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
	v.add_child(UI.button("Quit", func(): get_tree().quit()))
	return _left_column(v)

func _page_play() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_child(UI.label("Choose a game", 38, Color("ffe14a")))
	for r in Content.races:
		var best: float = Save.best_times.get(r["id"], 0.0)
		var cap: String = str(r["name"])
		var b := UI.button("Race: " + cap, func():
			Content.launch = {"mode": "race", "race_id": r["id"]}
			get_tree().change_scene_to_file("res://scenes/game.tscn"))
		v.add_child(b)
		var info := UI.label("%d laps%s" % [int(r.get("laps", 1)), ("   best " + UI.format_time(best)) if best > 0.0 else ""], 26, Color("cfe6ff"))
		v.add_child(info)
	v.add_child(UI.button("Free Roam", func():
		Content.launch = {"mode": "roam"}
		get_tree().change_scene_to_file("res://scenes/game.tscn")))
	v.add_child(UI.button("Back", func(): show_page("main"), Vector2(360, 64)))
	return _left_column(v)

func _page_cars() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	car_name_label = UI.label("", 44, Color("ffe14a"))
	v.add_child(car_name_label)
	car_blurb = UI.label("", 24, Color("cfe6ff"))
	car_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	car_blurb.custom_minimum_size = Vector2(560, 0)
	v.add_child(car_blurb)
	for key in ["Speed", "Acceleration", "Handling"]:
		var row := HBoxContainer.new()
		var l := UI.label(key, 26)
		l.custom_minimum_size = Vector2(190, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(300, 28)
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
	nav.add_child(UI.button("<", func(): _cycle(-1), Vector2(110, 76)))
	nav.add_child(UI.button(">", func(): _cycle(1), Vector2(110, 76)))
	use_btn = UI.button("Use this car", _use_car, Vector2(310, 76))
	nav.add_child(use_btn)
	v.add_child(nav)
	car_status = UI.label("", 26, Color("ffb3b3"))
	v.add_child(car_status)
	v.add_child(UI.label("Paint", 28))
	paint_row = HBoxContainer.new()
	paint_row.add_theme_constant_override("separation", 8)
	v.add_child(paint_row)
	for i in Content.paints.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(60, 60)
		var col := Content.paint_color(i)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(30)
			sb.border_width_left = 4; sb.border_width_right = 4; sb.border_width_top = 4; sb.border_width_bottom = 4
			sb.border_color = Color.WHITE if st != "normal" else Color(0, 0, 0, 0.35)
			sw.add_theme_stylebox_override(st, sb)
		var idx := i
		sw.pressed.connect(func(): _set_paint(idx))
		paint_row.add_child(sw)
	v.add_child(UI.button("Back", func(): show_page("main"), Vector2(360, 64)))
	var panel := _left_column(v, 600.0)
	panel.position = Vector2(40, 112)
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
	v.add_child(grid)
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
	v.add_child(UI.button("Back", func(): show_page("main"), Vector2(360, 64)))
	var panel := _left_column(v, 1000.0)
	panel.position = Vector2(40, 120)
	return panel

func _toggle(text: String, value: bool, setter: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.custom_minimum_size = Vector2(460, 60)
	c.add_theme_font_size_override("font_size", 28)
	c.toggled.connect(func(on):
		Sfx.play("click")
		setter.call(on)
		Settings.apply()
		Settings.save_settings())
	return c

func show_page(name: String) -> void:
	for k in pages:
		pages[k].visible = (k == name)
	stars_label.text = "* %d stars" % Save.stars
	if turntable:
		turntable.position.x = 2.3 if name == "cars" else (1.6 if name == "settings" else 0.0)
	if name == "cars":
		_refresh_car()
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
	_show_car()
	var def: Dictionary = Content.vehicles[car_index]
	car_name_label.text = str(def["name"])
	car_blurb.text = str(def.get("blurb", ""))
	stat_bars["Speed"].value = clampf(float(def.get("max_speed", 30)) / 40.0, 0.0, 1.0)
	stat_bars["Acceleration"].value = clampf(float(def.get("accel", 14)) / 20.0, 0.0, 1.0)
	stat_bars["Handling"].value = clampf(float(def.get("handling", 1.0)) / 1.2, 0.0, 1.0)
	var unlocked := Save.is_unlocked(def)
	use_btn.disabled = not unlocked
	use_btn.text = "Selected" if def["id"] == Save.selected_car else "Use this car"
	car_status.text = "" if unlocked else "Locked - collect %d stars (you have %d)" % [int(def.get("unlock_stars", 0)), Save.stars]

func _use_car() -> void:
	var def: Dictionary = Content.vehicles[car_index]
	if Save.is_unlocked(def):
		Save.selected_car = str(def["id"])
		Save.save_game()
		_refresh_car()

func _set_paint(i: int) -> void:
	var def: Dictionary = Content.vehicles[car_index]
	Save.paints[def["id"]] = i
	Save.save_game()
	Sfx.play("click")
	_show_car()
