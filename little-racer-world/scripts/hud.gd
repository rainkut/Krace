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
