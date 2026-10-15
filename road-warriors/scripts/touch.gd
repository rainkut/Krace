class_name TouchControls
extends Control
## On-screen buttons for phones. Presses map straight to input actions.

var btns: Array = []
var fingers: Dictionary = {}   # touch index -> button index
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# name, action, centre, radius, colour, steer-slide group
	btns = [
		{"n": "<", "a": "left", "c": Vector2(120, 600), "r": 82, "col": Color(1, 1, 1), "g": 1},
		{"n": ">", "a": "right", "c": Vector2(300, 600), "r": 82, "col": Color(1, 1, 1), "g": 1},
		{"n": "BRAKE", "a": "brake", "c": Vector2(210, 440), "r": 56, "col": Color(0.9, 0.3, 0.3), "g": 0},
		{"n": "NITRO", "a": "nitro", "c": Vector2(1150, 600), "r": 78, "col": Color(0.3, 0.8, 1.0), "g": 0},
		{"n": "HIT L", "a": "atk_l", "c": Vector2(900, 620), "r": 62, "col": Color(1.0, 0.55, 0.12), "g": 0},
		{"n": "HIT R", "a": "atk_r", "c": Vector2(1030, 480), "r": 62, "col": Color(1.0, 0.55, 0.12), "g": 0},
		{"n": "KICK", "a": "kick", "c": Vector2(1170, 430), "r": 48, "col": Color(0.95, 0.8, 0.2), "g": 0},
	]

func _pos(b: Dictionary) -> Vector2:
	var c: Vector2 = b["c"]
	return Vector2(size.x - (1280.0 - c.x), c.y) if c.x > 640.0 else c

func _hit(p: Vector2) -> int:
	var best := -1
	var bd := 1e9
	for i in btns.size():
		var d: float = p.distance_to(_pos(btns[i]))
		if d < float(btns[i]["r"]) * 1.2 and d < bd:
			bd = d
			best = i
	return best

func _press(i: int) -> void:
	Input.action_press(btns[i]["a"], 1.0)

func _release(i: int) -> void:
	Input.action_release(btns[i]["a"])

func release_all() -> void:
	for f in fingers:
		_release(fingers[f])
	fingers.clear()

func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventScreenTouch:
		var p: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * e.position
		if e.pressed:
			var i := _hit(p)
			if i >= 0:
				fingers[e.index] = i
				_press(i)
		elif fingers.has(e.index):
			_release(fingers[e.index])
			fingers.erase(e.index)
	elif e is InputEventScreenDrag and fingers.has(e.index):
		var cur: int = fingers[e.index]
		if int(btns[cur]["g"]) == 1:
			var p2: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * e.position
			var j := _hit(p2)
			if j >= 0 and j != cur and int(btns[j]["g"]) == 1:
				_release(cur)
				fingers[e.index] = j
				_press(j)

func _process(_dt: float) -> void:
	size = get_viewport_rect().size
	queue_redraw()

func _draw() -> void:
	var on := {}
	for f in fingers:
		on[fingers[f]] = true
	for i in btns.size():
		var b: Dictionary = btns[i]
		var col: Color = b["col"]
		var pressed := on.has(i) or Input.is_action_pressed(b["a"])
		draw_circle(_pos(b), float(b["r"]), Color(col.r, col.g, col.b, 0.42 if pressed else 0.18))
		draw_arc(_pos(b), float(b["r"]), 0, TAU, 32, Color(col.r, col.g, col.b, 0.8), 3.0)
		var sz := 34 if String(b["n"]).length() <= 1 else 20
		draw_string(font, _pos(b) + Vector2(-float(b["r"]), sz * 0.35), b["n"], HORIZONTAL_ALIGNMENT_CENTER, float(b["r"]) * 2.0, sz, Color(1, 1, 1, 0.9))
