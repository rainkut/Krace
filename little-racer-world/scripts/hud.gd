class_name HUD
extends CanvasLayer
## Heads-up display, pause menu and race-results panel (all built in code).

signal pause_requested
signal resume_requested
signal restart_requested
signal menu_requested
signal roam_requested

var speed_label: Label
var pos_label: Label
var lap_label: Label
var time_label: Label
var star_label: Label
var msg_label: Label
var hint_label: Label
var pause_panel: Control
var results_panel: Control
var lapinfo_label: Label
var sector_label: Label
var lights_box: HBoxContainer
var _lights: Array[Panel] = []
var _sector_tween: Tween
var _msg_tween: Tween
var race_mode := true

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.make_theme()
	add_child(root)

	pos_label = UI.label("", 64, Color("ffe14a"))
	pos_label.position = Vector2(30, 14)
	root.add_child(pos_label)
	lap_label = UI.label("", 34)
	lap_label.position = Vector2(34, 92)
	root.add_child(lap_label)

	lapinfo_label = UI.label("", 28, Color("cfe6ff"))
	lapinfo_label.position = Vector2(34, 138)
	root.add_child(lapinfo_label)
	sector_label = UI.label("", 40, Color("6dff8a"))
	sector_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sector_label.position = Vector2(-150, 74)
	sector_label.custom_minimum_size = Vector2(300, 0)
	sector_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sector_label.modulate.a = 0.0
	root.add_child(sector_label)
	lights_box = HBoxContainer.new()
	lights_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lights_box.position = Vector2(-190, 130)
	lights_box.add_theme_constant_override("separation", 16)
	lights_box.visible = false
	for i in 5:
		var pnl := Panel.new()
		pnl.custom_minimum_size = Vector2(60, 60)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("2a0a0a")
		sb.set_corner_radius_all(30)
		sb.border_color = Color("111111")
		sb.set_border_width_all(5)
		pnl.add_theme_stylebox_override("panel", sb)
		lights_box.add_child(pnl)
		_lights.append(pnl)
	root.add_child(lights_box)

	time_label = UI.label("0:00.00", 44)
	time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	time_label.position = Vector2(-90, 14)
	time_label.custom_minimum_size = Vector2(180, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(time_label)

	star_label = UI.label("* 0", 44, Color("ffd21f"))
	star_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	star_label.position = Vector2(-330, 14)
	star_label.custom_minimum_size = Vector2(190, 0)
	star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(star_label)

	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.custom_minimum_size = Vector2(96, 80)
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(-124, 14)
	pause_btn.pressed.connect(func():
		Sfx.play("click")
		pause_requested.emit())
	root.add_child(pause_btn)

	speed_label = UI.label("0", 70, Color.WHITE)
	speed_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	speed_label.position = Vector2(500, -130)
	root.add_child(speed_label)

	msg_label = UI.label("", 120, Color("ffe14a"))
	msg_label.set_anchors_preset(Control.PRESET_CENTER)
	msg_label.custom_minimum_size = Vector2(1000, 160)
	msg_label.position = Vector2(-500, -240)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_constant_override("outline_size", 16)
	msg_label.modulate.a = 0.0
	root.add_child(msg_label)

	hint_label = UI.label("", 40, Color("ff8a8a"))
	hint_label.set_anchors_preset(Control.PRESET_CENTER)
	hint_label.custom_minimum_size = Vector2(1000, 60)
	hint_label.position = Vector2(-500, 40)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint_label)

	pause_panel = _make_pause()
	root.add_child(pause_panel)
	results_panel = Control.new()
	results_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_panel.visible = false
	root.add_child(results_panel)

func set_mode(is_race: bool) -> void:
	race_mode = is_race
	pos_label.visible = is_race
	lap_label.visible = is_race
	time_label.visible = is_race

func _make_pause() -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(dim)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(holder)
	var panel := PanelContainer.new()
	holder.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var t := UI.label("Paused", 56, Color("ffe14a"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(UI.button("Resume", func(): resume_requested.emit()))
	v.add_child(UI.button("Restart", func(): restart_requested.emit()))
	v.add_child(UI.button("Main Menu", func(): menu_requested.emit()))
	wrap.visible = false
	return wrap

func show_pause(on: bool) -> void:
	pause_panel.visible = on

func set_speed(mps: float) -> void:
	if Settings.use_mph:
		speed_label.text = "%d mph" % int(absf(mps) * 2.23694)
	else:
		speed_label.text = "%d km/h" % int(absf(mps) * 3.6)

func set_place(place: int, total: int) -> void:
	var suffix := "th"
	if place == 1: suffix = "st"
	elif place == 2: suffix = "nd"
	elif place == 3: suffix = "rd"
	pos_label.text = "%d%s / %d" % [place, suffix, total]

func set_lap(lap: int, total: int) -> void:
	lap_label.text = "Lap %d / %d" % [lap, total]

func set_lapinfo(text: String) -> void:
	lapinfo_label.text = text

func set_sector(text: String, purple: bool) -> void:
	sector_label.text = text
	sector_label.add_theme_color_override("font_color", Color("d68bff") if purple else Color("ffe14a"))
	if _sector_tween:
		_sector_tween.kill()
	sector_label.modulate.a = 1.0
	_sector_tween = create_tween()
	_sector_tween.tween_property(sector_label, "modulate:a", 0.0, 0.4).set_delay(2.0)

## n lit red lights (0..5); n < 0 hides the gantry. After GO call with -1.
func set_start_lights(n: int) -> void:
	lights_box.visible = n >= 0
	for i in _lights.size():
		var sb: StyleBoxFlat = _lights[i].get_theme_stylebox("panel")
		sb.bg_color = Color("ff2222") if i < n else Color("2a0a0a")

func set_time(t: float) -> void:
	time_label.text = UI.format_time(t)

func set_stars(n: int) -> void:
	star_label.text = "* %d" % n

func show_message(text: String, secs := 0.9, color := Color("ffe14a")) -> void:
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", color)
	if _msg_tween:
		_msg_tween.kill()
	msg_label.modulate.a = 1.0
	msg_label.scale = Vector2.ONE
	msg_label.pivot_offset = msg_label.size * 0.5
	_msg_tween = create_tween()
	_msg_tween.tween_property(msg_label, "modulate:a", 0.0, 0.35).set_delay(secs)

func set_hint(text: String) -> void:
	hint_label.text = text

func show_results(info: Dictionary) -> void:
	for ch in results_panel.get_children():
		ch.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_panel.add_child(dim)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	results_panel.add_child(holder)
	var panel := PanelContainer.new()
	holder.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var place: int = info["place"]
	if info.get("circuit", false):
		_show_podium(info)
		return
	var heading := "You win!" if place == 1 else ("Great race!" if place <= 3 else "Nice try!")
	var t := UI.label(heading, 64, Color("ffe14a"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var line := UI.label("Finished %s   Time %s%s" % [info["place_text"], UI.format_time(info["time"]), "   NEW BEST!" if info["new_best"] else ""], 34)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(line)
	for row in info["standings"]:
		var l := UI.label(row, 30, Color("cfe6ff"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var reward := UI.label("Stars earned: %d  (total %d)" % [info["stars_earned"], info["stars_total"]], 36, Color("ffd21f"))
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(reward)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(UI.button("Race Again", func(): restart_requested.emit(), Vector2(280, 76)))
	buttons.add_child(UI.button("Free Roam", func(): roam_requested.emit(), Vector2(280, 76)))
	buttons.add_child(UI.button("Menu", func(): menu_requested.emit(), Vector2(220, 76)))
	v.add_child(buttons)
	results_panel.visible = true

func _show_podium(info: Dictionary) -> void:
	var dim: Node = results_panel.get_child(0)
	var holder: Node = results_panel.get_child(1)
	var panel: Node = holder.get_child(0)
	panel.get_child(0).queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var place: int = info["place"]
	var t := UI.label("PODIUM" if place <= 3 else "Race over", 56, Color("ffe14a"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var rows: Array = info["podium"]
	var steps := HBoxContainer.new()
	steps.alignment = BoxContainer.ALIGNMENT_CENTER
	steps.add_theme_constant_override("separation", 10)
	var order := [1, 0, 2]
	var heights := [150.0, 110.0, 80.0]
	var cols := [Color("d9a521"), Color("aab2bd"), Color("b4713a")]
	for k in order:
		if k >= rows.size():
			continue
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_END
		col.custom_minimum_size = Vector2(190, 215)
		var nm := UI.label(str(rows[k]["name"]), 28, Color.WHITE if not rows[k]["is_player"] else Color("6dff8a"))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nm)
		var block := ColorRect.new()
		block.color = cols[k]
		block.custom_minimum_size = Vector2(190, heights[k])
		var num := UI.label(str(k + 1), 56, Color("2a2a2a"))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.set_anchors_preset(Control.PRESET_CENTER_TOP)
		block.add_child(num)
		col.add_child(block)
		steps.add_child(col)
	v.add_child(steps)
	var line := UI.label("You: %s   Time %s%s" % [info["place_text"], UI.format_time(info["time"]), "   NEW BEST!" if info["new_best"] else ""], 32)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(line)
	var best := UI.label("Your best lap %s%s    Fastest lap %s (%s)" % [UI.format_time(info["best_lap"]), "  NEW!" if info["new_best_lap"] else "", UI.format_time(info["fastest_lap"]), info["fastest_name"]], 26, Color("d68bff"))
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(best)
	var lt: Array = info["lap_times"]
	var parts: PackedStringArray = []
	for i in lt.size():
		parts.append("L%d %s" % [i + 1, UI.format_time(lt[i])])
	var laps_l := UI.label("   ".join(parts), 24, Color("cfe6ff"))
	laps_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(laps_l)
	for row in info["standings"]:
		var l := UI.label(row, 24, Color("cfe6ff"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var reward := UI.label("Stars earned: %d  (total %d)" % [info["stars_earned"], info["stars_total"]], 30, Color("ffd21f"))
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(reward)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(UI.button("Race Again", func(): restart_requested.emit(), Vector2(280, 76)))
	buttons.add_child(UI.button("Free Roam", func(): roam_requested.emit(), Vector2(280, 76)))
	buttons.add_child(UI.button("Menu", func(): menu_requested.emit(), Vector2(220, 76)))
	v.add_child(buttons)
	results_panel.visible = true
