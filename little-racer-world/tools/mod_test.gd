extends SceneTree
## Mod + recovery tests (no renderer needed): godot --headless -s tools/mod_test.gd
## Covers: valid/malformed/duplicate/banned/out-of-range/missing-asset mods, enable/disable, safe mode,
## base game with all mods off, bundled sample mods, corrupt save/settings recovery.
var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func write(path: String, txt: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(txt)
	f.close()

func rm_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + f)
	for d in DirAccess.get_directories_at(path):
		rm_tree(path + "/" + d)
	DirAccess.remove_absolute(path)

func rep_of(folder: String) -> Dictionary:
	for r in root.get_node("Content").mod_reports:
		if r["folder"] == folder:
			return r
	return {}

func _initialize() -> void:
	var Content = root.get_node("Content")
	var Settings = root.get_node("Settings")
	var Save = root.get_node("Save")
	rm_tree("user://mods")
	Settings.disabled_mods = []
	Settings.mods_safe_mode = false
	Content.reload()
	var base_v: int = Content.vehicles.size()
	var base_r: int = Content.races.size()
	check(base_v >= 13 and base_r >= 5, "base game content loads with no mods (%d vehicles, %d races)" % [base_v, base_r])
	check(Content.mod_reports.is_empty(), "no mod folders -> no reports")

	var good := '{"format":1,"id":"%s","name":"%s","version":"1.0.0"}'
	var car := '{"vehicles":[{"id":"%s","name":"T","model":"models/m.glb","max_speed":30,"accel":14,"handling":1.0}]}'
	var glb := FileAccess.get_file_as_bytes("res://assets/kenney/cars/taxi.glb")
	var put_model := func(folder: String):
		DirAccess.make_dir_recursive_absolute("user://mods/%s/models" % folder)
		var f := FileAccess.open("user://mods/%s/models/m.glb" % folder, FileAccess.WRITE)
		f.store_buffer(glb)
		f.close()

	# 1. valid mod
	write("user://mods/ok_mod/mod.json", good % ["ok_mod", "OK Mod"])
	write("user://mods/ok_mod/data/vehicles.json", car % "t_ok")
	put_model.call("ok_mod")
	# 2. malformed JSON
	write("user://mods/bad_json/mod.json", good % ["bad_json", "Bad"])
	write("user://mods/bad_json/data/vehicles.json", '{"vehicles":[{"id":')
	# 3. duplicate vehicle id with the base game
	write("user://mods/dup_base/mod.json", good % ["dup_base", "Dup"])
	write("user://mods/dup_base/data/vehicles.json", car % "sunny_hatch")
	put_model.call("dup_base")
	# 4. duplicate mod id across folders
	write("user://mods/zz_twin/mod.json", good % ["ok_mod", "Twin"])
	write("user://mods/zz_twin/data/vehicles.json", car % "t_twin")
	put_model.call("zz_twin")
	# 5. code file
	write("user://mods/has_code/mod.json", good % ["has_code", "Code"])
	write("user://mods/has_code/evil.gd", "extends Node")
	# 6. out-of-range stat
	write("user://mods/bad_stat/mod.json", good % ["bad_stat", "Stat"])
	write("user://mods/bad_stat/data/vehicles.json", '{"vehicles":[{"id":"t_fast","name":"T","model":"models/m.glb","max_speed":9999}]}')
	put_model.call("bad_stat")
	# 7. missing required model
	write("user://mods/no_model/mod.json", good % ["no_model", "NM"])
	write("user://mods/no_model/data/vehicles.json", car % "t_nomodel")
	# 8. missing OPTIONAL icon -> still loads (warning)
	write("user://mods/opt_icon/mod.json", good % ["opt_icon", "Icon"])
	write("user://mods/opt_icon/data/vehicles.json", '{"vehicles":[{"id":"t_icon","name":"T","model":"models/m.glb","icon":"icon.png"}]}')
	put_model.call("opt_icon")
	# 9. bad manifest id + missing version
	write("user://mods/bad_manifest/mod.json", '{"id":"Bad ID!","name":"x"}')
	# 10. legacy (no mod.json)
	write("user://mods/legacy/data/vehicles.json", car % "t_legacy")
	put_model.call("legacy")
	# 11. unknown town in race
	write("user://mods/bad_race/mod.json", good % ["bad_race", "BR"])
	write("user://mods/bad_race/data/races.json", '{"races":[{"id":"r_x","town":"nowhere","route":[[1,1],[2,2]]}]}')

	Content.reload()
	check(rep_of("ok_mod")["status"] == "ok" and Content.get_vehicle("t_ok")["id"] == "t_ok", "valid mod loads")
	check(rep_of("bad_json")["status"] == "error" and not rep_of("bad_json")["errors"].is_empty(), "malformed JSON -> clear error")
	print("      ", rep_of("bad_json")["errors"])
	check(rep_of("dup_base")["status"] == "error" and Content.get_vehicle("sunny_hatch")["name"] != "T", "duplicate base id rejected, base untouched")
	check(rep_of("zz_twin")["status"] == "error" and Content.get_vehicle("t_twin")["id"] != "t_twin", "duplicate mod id rejected")
	check(rep_of("has_code")["status"] == "error", "code file (.gd) rejected")
	check(rep_of("bad_stat")["status"] == "error", "out-of-range stat rejected")
	check(rep_of("no_model")["status"] == "error", "missing required model rejected")
	check(rep_of("opt_icon")["status"] == "ok" and not rep_of("opt_icon")["warnings"].is_empty() and Content.get_vehicle("t_icon")["id"] == "t_icon", "missing optional asset -> warning only, mod loads")
	check(rep_of("bad_manifest")["status"] == "error", "invalid manifest rejected")
	check(rep_of("legacy")["status"] == "ok" and rep_of("legacy")["legacy"], "legacy folder loads with a warning")
	check(rep_of("bad_race")["status"] == "error", "race with unknown town rejected")
	check(Content.vehicles.size() == base_v + 3, "only valid mods added vehicles (%d)" % (Content.vehicles.size() - base_v))

	Settings.disabled_mods = ["ok_mod"]
	Content.reload()
	check(rep_of("ok_mod")["status"] == "disabled" and Content.get_vehicle("t_ok")["id"] != "t_ok", "disabled mod is not loaded")
	Settings.disabled_mods = []
	Settings.mods_safe_mode = true
	Content.reload()
	check(Content.vehicles.size() == base_v and Content.races.size() == base_r, "safe mode: base game only (all mods off)")
	Settings.mods_safe_mode = false

	rm_tree("user://mods")
	var n: int = ModLoader.install_samples()
	check(n >= 6, "sample mods install (%d files)" % n)
	Content.reload()
	check(rep_of("sample_vehicle_mod").get("status", "") == "ok", "sample vehicle mod loads: " + str(rep_of("sample_vehicle_mod").get("errors", "")))
	check(rep_of("sample_track_mod").get("status", "") == "ok", "sample track mod loads: " + str(rep_of("sample_track_mod").get("errors", "")))
	check(Content.get_vehicle("mod_dusty_pickup")["id"] == "mod_dusty_pickup" and not Content.get_race("mod_sunny_sprint").is_empty(), "sample vehicle and race present")
	check(not Content.get_part("wheels", "mod_flame_caps").is_empty(), "sample wheel-cap part present")
	rm_tree("user://mods")
	Content.reload()
	check(Content.vehicles.size() == base_v, "mods removed -> base game unchanged")

	# recovery: corrupt save and settings
	write("user://save.json", "{not json")
	Save.notices_hint = ""
	Save.load_game()
	check(Save.notices_hint != "" and FileAccess.file_exists("user://save.corrupt.json") and not FileAccess.file_exists("user://save.json"), "corrupt save moved aside with a notice")
	write("user://settings.cfg", "[audio\nsfx_volume=")
	Settings.notices.clear()
	Settings.load_settings()
	check(not Settings.notices.is_empty() and FileAccess.file_exists("user://settings.corrupt.cfg"), "corrupt settings moved aside with a notice")
	Save.stars = 7
	Save.races_finished = 2
	Save.save_game()
	check(Save.make_backup() and Save.has_backup(), "save backup written")
	Save.wipe()
	check(Save.stars == 0, "progress erased")
	check(Save.restore_backup() and Save.stars == 7, "backup restores progress")
	Save.wipe()
	Settings.reset_to_defaults()
	Settings.session_begin()
	check(FileAccess.file_exists("user://session.lock"), "session lock armed")
	Settings.session_end()
	check(not FileAccess.file_exists("user://session.lock"), "session lock cleared on clean exit")
	print("MODTEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
