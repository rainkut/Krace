class_name SmoothScroll
extends ScrollContainer
## Finger-drag scrolling with inertia that works even when the drag starts on a button.

const DEAD := 14.0
var _down := false
var _drag := false
var _y0 := 0.0
var _last_y := 0.0
var _pos := 0.0
var _vel := 0.0

func _ready() -> void:
	set("scroll_deadzone", 100000)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		if mb.pressed:
			if get_global_rect().has_point(mb.position):
				_down = true
				_drag = false
				_y0 = mb.position.y
				_last_y = mb.position.y
				_pos = float(scroll_vertical)
				_vel = 0.0
		elif _down:
			_down = false
			if _drag:
				get_viewport().set_input_as_handled()
				_drag = false
	elif e is InputEventMouseMotion and _down:
		var mm := e as InputEventMouseMotion
		if not _drag and absf(mm.position.y - _y0) > DEAD:
			_drag = true
			_cancel_press()
		if _drag:
			var dy := mm.position.y - _last_y
			_pos -= dy
			_vel = lerpf(_vel, -dy / maxf(get_process_delta_time(), 0.001), 0.35)
			_apply()
			get_viewport().set_input_as_handled()
		_last_y = mm.position.y

func _cancel_press() -> void:
	var h := get_viewport().gui_get_hovered_control()
	if h is BaseButton:
		var b := h as BaseButton
		var was := b.disabled
		b.disabled = true
		b.disabled = was

func _apply() -> void:
	var vb := get_v_scroll_bar()
	var mx := maxf(vb.max_value - vb.page, 0.0)
	_pos = clampf(_pos, 0.0, mx)
	scroll_vertical = int(_pos)

func _process(dt: float) -> void:
	if _down or absf(_vel) < 8.0:
		return
	_pos += _vel * dt
	_vel *= exp(-4.5 * dt)
	_apply()
	var vb := get_v_scroll_bar()
	if _pos <= 0.0 or _pos >= maxf(vb.max_value - vb.page, 0.0):
		_vel = 0.0
