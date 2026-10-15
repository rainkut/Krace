extends Node
## Local save, settings and input bindings (autoload "Save").

const PATH := "user://rw_save.json"
# action, label, default key, alt key
const ACTIONS := [
	["accel", "Accelerate", KEY_W, KEY_UP],
	["brake", "Brake", KEY_S, KEY_DOWN],
	["left", "Steer left", KEY_A, KEY_LEFT],
	["right", "Steer right", KEY_D, KEY_RIGHT],
	["attack", "Attack (auto side)", KEY_SPACE, KEY_NONE],
	["atk_l", "Attack left", KEY_Q, KEY_NONE],
	["atk_r", "Attack right", KEY_R, KEY_NONE],
	["kick", "Kick / secondary", KEY_E, KEY_NONE],
	["nitro", "Nitro", KEY_SHIFT, KEY_NONE],
	["pause", "Pause", KEY_ESCAPE, KEY_P],
]

var d: Dictionary = {}

func _ready() -> void:
	d = defaults()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			_merge(d, j)
	apply_bindings()

func defaults() -> Dictionary:
	return {"money": 600, "rep": 0, "owned": ["dustrunner"], "bike": "dustrunner", "upg": {}, "done": {}, "best": {},
		"set": {"sfx": 0.8, "music": 0.5, "diff": 1, "shake": 1.0, "autothrottle": -1, "debug": false, "bind": {}, "tutorial": true}}

func _merge(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if base.has(k) and base[k] is Dictionary and over[k] is Dictionary:
			_merge(base[k], over[k])
		else:
			base[k] = over[k]

func write() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func reset() -> void:
	var keep: Dictionary = d["set"]
	d = defaults()
	d["set"] = keep
	write()

func setting(k: String) -> Variant:
	return d["set"][k]

func set_setting(k: String, v: Variant) -> void:
	d["set"][k] = v
	write()

func bike_upg(bike_id: String) -> Dictionary:
	if not d["upg"].has(bike_id):
		d["upg"][bike_id] = {}
	return d["upg"][bike_id]

func auto_throttle() -> bool:
	var a: int = int(setting("autothrottle"))
	if a < 0:
		return DisplayServer.is_touchscreen_available()
	return a == 1

# ---------- input bindings ----------
func apply_bindings() -> void:
	var bind: Dictionary = d["set"]["bind"]
	for a in ACTIONS:
		var name: String = a[0]
		if InputMap.has_action(name):
			InputMap.erase_action(name)
		InputMap.add_action(name, 0.2)
		var k1: int = int(bind.get(name, a[2]))
		var k2: int = a[3]
		if k1 != KEY_NONE:
			_add_key(name, k1)
		if k2 != KEY_NONE and not bind.has(name):
			_add_key(name, k2)
	_add_pad("accel", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_pad("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_pad("left", JOY_AXIS_LEFT_X, -1.0)
	_add_pad("right", JOY_AXIS_LEFT_X, 1.0)
	_add_btn("nitro", JOY_BUTTON_A)
	_add_btn("attack", JOY_BUTTON_X)
	_add_btn("kick", JOY_BUTTON_Y)
	_add_btn("atk_l", JOY_BUTTON_LEFT_SHOULDER)
	_add_btn("atk_r", JOY_BUTTON_RIGHT_SHOULDER)
	_add_btn("pause", JOY_BUTTON_START)

func _add_key(action: String, code: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	InputMap.action_add_event(action, e)

func _add_pad(action: String, axis: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis as JoyAxis
	e.axis_value = v
	InputMap.action_add_event(action, e)

func _add_btn(action: String, b: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b as JoyButton
	InputMap.action_add_event(action, e)

func rebind(action: String, code: int) -> void:
	d["set"]["bind"][action] = code
	write()
	apply_bindings()

func reset_bindings() -> void:
	d["set"]["bind"] = {}
	write()
	apply_bindings()

func key_name(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			var code: int = int(d["set"]["bind"].get(action, a[2]))
			return OS.get_keycode_string(code as Key) if code != KEY_NONE else "-"
	return "?"
