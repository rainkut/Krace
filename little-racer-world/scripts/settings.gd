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
var obstacles := 1  # street clutter: 0 off, 1 few, 2 normal
var large_text := false
var reduced_motion := false
var simple_steering := false
var easy_drive := true          # steering assist + speed cap in races
var minimap_north := false      # false = heading-up
var cam_sensitivity := 1.0
var quality := 0  # 0 auto, 1 normal, 2 high
var time_of_day := 1  # 0 morning, 1 noon, 2 evening, 3 dusk
var disabled_mods: Array = []   # mod folder names switched off in Parent settings
var mods_safe_mode := false     # true = ignore every mod (base game only)

const LOCK := "user://session.lock"
const BACKUP := "user://settings.backup.cfg"
var notices: Array = []   # one-time messages for the menu (recovery events)
var _in_game := false

const TOD_NAMES := ["Morning", "Noon", "Evening", "Dusk"]

const TRAFFIC_COUNT := [0, 8, 16, 28]
const DIFFICULTY_SCALE := [0.80, 0.90, 1.0]

func _ready() -> void:
	load_settings()
	apply()
	if FileAccess.file_exists(LOCK):
		DirAccess.remove_absolute(LOCK)
		if _any_mod_folder() and not mods_safe_mode:
			mods_safe_mode = true
			save_settings()
			notices.append("The game closed unexpectedly last time while mods were installed, so all mods were switched off. Re-enable them in Parents > Mods.")

func _any_mod_folder() -> bool:
	for d in ModLoader.search_dirs():
		if DirAccess.dir_exists_absolute(d) and not DirAccess.get_directories_at(d).is_empty():
			return true
	return false

## Called by the game scene when a race/free-roam begins and by the menu when it opens.
func session_begin() -> void:
	_in_game = true
	var f := FileAccess.open(LOCK, FileAccess.WRITE)
	if f:
		f.store_string("1")

func session_end() -> void:
	_in_game = false
	if FileAccess.file_exists(LOCK):
		DirAccess.remove_absolute(LOCK)

func _notification(what: int) -> void:
	# Backgrounding is not a crash: drop the lock while paused, re-arm when resumed in-game.
	if what == NOTIFICATION_APPLICATION_PAUSED and FileAccess.file_exists(LOCK):
		DirAccess.remove_absolute(LOCK)
	elif what == NOTIFICATION_APPLICATION_RESUMED and _in_game:
		session_begin()

func reset_to_defaults() -> void:
	var keep_mods := disabled_mods
	sfx_volume = 0.8; auto_accelerate = true; tilt_steering = false; tilt_invert = false; tilt_sensitivity = 1.0
	shadows = true; use_mph = false; difficulty = 1; force_touch = false; traffic = 2; obstacles = 1; quality = 0; time_of_day = 1
	easy_drive = true; minimap_north = false
	disabled_mods = keep_mods
	save_settings()
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
	var err := cf.load(PATH)
	if err == ERR_FILE_NOT_FOUND or err == ERR_CANT_OPEN:
		return
	if err != OK:
		DirAccess.rename_absolute(PATH, "user://settings.corrupt.cfg")
		notices.append("Your settings file was damaged, so settings were reset to defaults (a copy was kept as settings.corrupt.cfg).")
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
	obstacles = clampi(int(cf.get_value("game", "obstacles", obstacles)), 0, 2)
	quality = clampi(int(cf.get_value("video", "quality", quality)), 0, 2)
	time_of_day = clampi(int(cf.get_value("video", "time_of_day", time_of_day)), 0, 3)
	large_text = bool(cf.get_value("access", "large_text", large_text))
	reduced_motion = bool(cf.get_value("access", "reduced_motion", reduced_motion))
	simple_steering = bool(cf.get_value("access", "simple_steering", simple_steering))
	easy_drive = bool(cf.get_value("access", "easy_drive", easy_drive))
	minimap_north = bool(cf.get_value("access", "minimap_north", minimap_north))
	cam_sensitivity = clampf(float(cf.get_value("access", "cam_sensitivity", cam_sensitivity)), 0.5, 1.6)
	var dm = cf.get_value("mods", "disabled", [])
	disabled_mods = Array(dm) if dm is Array else []
	mods_safe_mode = bool(cf.get_value("mods", "safe_mode", false))

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
	cf.set_value("game", "obstacles", obstacles)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "time_of_day", time_of_day)
	cf.set_value("access", "large_text", large_text)
	cf.set_value("access", "reduced_motion", reduced_motion)
	cf.set_value("access", "simple_steering", simple_steering)
	cf.set_value("access", "easy_drive", easy_drive)
	cf.set_value("access", "minimap_north", minimap_north)
	cf.set_value("access", "cam_sensitivity", cam_sensitivity)
	cf.set_value("mods", "disabled", disabled_mods)
	cf.set_value("mods", "safe_mode", mods_safe_mode)
	cf.save(PATH)

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(sfx_volume, 0.0001)))
	changed.emit()
