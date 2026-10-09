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
var quality := 0  # 0 auto, 1 normal, 2 high
var time_of_day := 1  # 0 morning, 1 noon, 2 evening, 3 dusk

const TOD_NAMES := ["Morning", "Noon", "Evening", "Dusk"]

const TRAFFIC_COUNT := [0, 8, 16, 28]
const DIFFICULTY_SCALE := [0.80, 0.90, 1.0]

func _ready() -> void:
	load_settings()
	apply()

func ai_scale() -> float:
	return DIFFICULTY_SCALE[clampi(difficulty, 0, 2)]

## Resolved graphics tier: 1 = Normal, 2 = High. LRW_QUALITY=high|normal overrides (VM screenshots).
func quality_level() -> int:
	var env := OS.get_environment("LRW_QUALITY").to_lower()
	if env == "high": return 2
	if env == "normal": return 1
	if quality != 0:
		return quality
	return 2 if auto_high() else 1

func auto_high() -> bool:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return false
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	if gpu.contains("llvmpipe") or gpu.contains("lavapipe") or gpu.contains("swiftshader") or gpu.contains("software"):
		return false
	for weak in ["adreno (tm) 5", "adreno (tm) 61", "adreno (tm) 62", "adreno (tm) 63", "mali-t", "mali-g5", "mali-g31", "powervr"]:
		if gpu.contains(weak):
			return false
	if OS.get_processor_count() < 6:
		return false
	var mem: Dictionary = OS.get_memory_info()
	var phys := int(mem.get("physical", -1))
	return phys < 0 or phys >= 5 * 1024 * 1024 * 1024

func quality_label() -> String:
	return "High" if quality_level() == 2 else "Normal"

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
	quality = clampi(int(cf.get_value("video", "quality", quality)), 0, 2)
	time_of_day = clampi(int(cf.get_value("video", "time_of_day", time_of_day)), 0, 3)

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
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "time_of_day", time_of_day)
	cf.save(PATH)

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(sfx_volume, 0.0001)))
	changed.emit()
