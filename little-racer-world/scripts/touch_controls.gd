class_name TouchControls
extends Control
## On-screen controls with true multi-touch: every finger is tracked separately so the player
## can steer and brake at the same time. Buttons feed the normal Input actions.

class TouchButton extends Control:
	var action := ""
	var caption := ""
	var held_count := 0
	var base_color := Color(1, 1, 1, 0.22)
	func _draw() -> void:
		var c := Color(1, 1, 1, 0.5) if held_count > 0 else base_color
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, Color(0, 0, 0, 0.25))
		draw_circle(size * 0.5, r * 0.94, c)
		draw_arc(size * 0.5, r * 0.94, 0, TAU, 48, Color(1, 1, 1, 0.8), 4.0)
		var font := ThemeDB.fallback_font
		var fs := int(r * 0.42)
		var ts := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, Vector2((size.x - ts.x) * 0.5, size.y * 0.5 + fs * 0.35), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.1, 0.2, 0.95))

var buttons := {}   # action -> TouchButton
var fingers := {}   # finger index -> TouchButton

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_add("steer_left", "<")
	_add("steer_right", ">")
	_add("accelerate", "GO")
	_add("brake", "BRAKE")
	_add("reverse", "REVERSE")
	_add("handbrake", "DRIFT")
	_add("reset_car", "RESET")
	_add("interact", "HONK")
	get_viewport().size_changed.connect(layout)
	Settings.changed.connect(layout)
	layout()

func _add(action: String, caption: String) -> void:
	var b := TouchButton.new()
	b.action = action
	b.caption = caption
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(b)
	buttons[action] = b

func _place(action: String, rect: Rect2, visible_flag := true) -> void:
	var b: TouchButton = buttons[action]
	b.position = rect.position
	b.size = rect.size
	b.visible = visible_flag
	b.queue_redraw()

func layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var m := 30.0
	var big := 210.0
	var tilt := Settings.tilt_steering
	_place("steer_left", Rect2(m, s.y - m - big, big, big), not tilt)
	_place("steer_right", Rect2(m + big + 24, s.y - m - big, big, big), not tilt)
	var gas := Rect2(s.x - m - 230, s.y - m - 230, 230, 230)
	_place("accelerate", gas, not Settings.auto_accelerate)
	_place("brake", Rect2(gas.position.x - 24 - 170, s.y - m - 170, 170, 170) if not Settings.auto_accelerate else Rect2(s.x - m - 230, s.y - m - 230, 230, 230))
	_place("handbrake", Rect2(s.x - m - 150, gas.position.y - 20 - 150, 150, 150) if not Settings.auto_accelerate else Rect2(s.x - m - 230 - 24 - 150, s.y - m - 150, 150, 150))
	_place("reverse", Rect2(gas.position.x - 24 - 170, s.y - m - 170 - 16 - 120, 170, 120) if not Settings.auto_accelerate else Rect2(s.x - m - 230 - 24 - 150, s.y - m - 150 - 16 - 120, 150, 120))
	_place("reset_car", Rect2(s.x - m - 110, s.y * 0.30, 110, 110))
	_place("interact", Rect2(s.x - m - 110 - 130, s.y * 0.30, 110, 110))
	for b in buttons.values():
		b.base_color = Color(1, 0.8, 0.2, 0.28) if b.action in ["accelerate", "brake"] else Color(1, 1, 1, 0.22)

func _hit(pos: Vector2) -> TouchButton:
	for b: TouchButton in buttons.values():
		if b.visible and Rect2(b.position, b.size).grow(14.0).has_point(pos):
			return b
	return null

func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_press(ev.index, ev.position)
		else:
			_release(ev.index)
	elif ev is InputEventScreenDrag:
		var cur: TouchButton = fingers.get(ev.index)
		var now := _hit(ev.position)
		if now != cur:
			_release(ev.index)
			if now != null:
				_press(ev.index, ev.position)

func _press(idx: int, pos: Vector2) -> void:
	var b := _hit(pos)
	if b == null:
		return
	fingers[idx] = b
	b.held_count += 1
	Input.action_press(b.action)
	b.queue_redraw()

func _release(idx: int) -> void:
	if not fingers.has(idx):
		return
	var b: TouchButton = fingers[idx]
	fingers.erase(idx)
	b.held_count = maxi(0, b.held_count - 1)
	if b.held_count == 0:
		Input.action_release(b.action)
	b.queue_redraw()

func release_all() -> void:
	for idx in fingers.keys():
		_release(idx)

func _exit_tree() -> void:
	release_all()
