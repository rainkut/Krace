extends Node
## Player-facing options, persisted to user://settings.cfg.

const PATH := "user://settings.cfg"
signal changed

var sfx_volume := 0.8
var auto_accelerate := true
var tilt_steering := false
var tilt_invert := false
var tilt_sensitivity := 1.0
var shadows := true
var use_mph := false
var difficulty := 1  # 0 easy, 1 normal, 2 hard
var force_touch := false
var traffic := 2  # 0 off, 1 light, 2 normal, 3 busy

const TRAFFIC_COUNT := [0, 8, 16, 28]
const DIFFICULTY_SCALE := [0.80, 0.90, 1.0]

func _ready() -> void:
	load_settings()
	apply()

func ai_scale() -> float:
	return DIFFICULTY_SCALE[clampi(difficulty, 0, 2)]

func touch_enabled() -> bool:
	return force_touch or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	sfx_volume = clampf(cf.get_value("audio", "sfx_volume", sfx_volume), 0.0, 1.0)
	auto_accelerate = cf.get_value("controls", "auto_accelerate", auto_accelerate)
	tilt_steering = cf.get_value("controls", "tilt_steering", tilt_steering)
	tilt_invert = cf.get_value("controls", "tilt_invert", tilt_invert)
	tilt_sensitivity = clampf(cf.get_value("controls", "tilt_sensitivity", tilt_sensitivity), 0.3, 2.5)
	force_touch = cf.get_value("controls", "force_touch", force_touch)
	shadows = cf.get_value("video", "shadows", shadows)
	use_mph = cf.get_value("game", "use_mph", use_mph)
	difficulty = clampi(int(cf.get_value("game", "difficulty", difficulty)), 0, 2)
	traffic = clampi(int(cf.get_value("game", "traffic", traffic)), 0, 3)

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("controls", "auto_accelerate", auto_accelerate)
	cf.set_value("controls", "tilt_steering", tilt_steering)
	cf.set_value("controls", "tilt_invert", tilt_invert)
	cf.set_value("controls", "tilt_sensitivity", tilt_sensitivity)
	cf.set_value("controls", "force_touch", force_touch)
	cf.set_value("video", "shadows", shadows)
	cf.set_value("game", "use_mph", use_mph)
	cf.set_value("game", "difficulty", difficulty)
	cf.set_value("game", "traffic", traffic)
	cf.save(PATH)

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(sfx_volume, 0.0001)))
	changed.emit()
