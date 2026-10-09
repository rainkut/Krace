class_name ModLoader
extends RefCounted
## Discovers, validates and reads mod packs. A mod is data only (JSON + .glb/.png); nothing is executed.
## See MODDING.md for the manifest schema.

const FORMAT := 1
const ID_RE := "^[a-z0-9_]{2,40}$"
const MAX_FILES := 400
const BANNED_EXT := ["gd", "gdc", "gdns", "gdnative", "gdextension", "so", "dll", "dylib", "exe", "apk", "pck", "tscn", "tres", "res", "cs", "sh", "bat", "py", "js", "jar", "dex"]
const ALLOWED_EXT := ["json", "glb", "gltf", "bin", "png", "jpg", "jpeg", "webp", "md", "txt"]
const PART_KINDS := ["wheels", "spoilers", "extras"]

static func search_dirs() -> Array:
	var out := ["user://mods"]
	if OS.get_name() == "Android":
		out.append("/storage/emulated/0/Android/data/com.hopique.littleracerworld/files/mods")
	return out

static func human_dirs() -> String:
	var d := [ProjectSettings.globalize_path("user://mods")]
	if OS.get_name() == "Android":
		d.append(search_dirs()[1])
	return "\n".join(d)

## Reads a JSON file; returns {"ok":bool, "data":Variant, "error":String}.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": null, "error": "missing"}
	var j := JSON.new()
	var txt := FileAccess.get_file_as_string(path)
	if j.parse(txt) != OK:
		return {"ok": false, "data": null, "error": "%s: invalid JSON (line %d: %s)" % [path.get_file(), j.get_error_line(), j.get_error_message()]}
	return {"ok": true, "data": j.data, "error": ""}

static func _scan_files(dir: String, depth: int, acc: Array) -> void:
	if depth > 4 or acc.size() > MAX_FILES:
		return
	for f in DirAccess.get_files_at(dir):
		acc.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_scan_files(dir + "/" + d, depth + 1, acc)

## Returns one report per mod folder: {folder, path, id, name, version, author, description, errors, warnings, pack}.
## `pack` is the parsed data (vehicles/races/towns/paints/parts) with "_root" set on vehicles.
static func discover() -> Array:
	var reports: Array = []
	for base in search_dirs():
		if not DirAccess.dir_exists_absolute(base):
			continue
		var dirs := Array(DirAccess.get_directories_at(base))
		dirs.sort()
		for d in dirs:
			reports.append(inspect(base + "/" + d, d))
	return reports

static func inspect(path: String, folder: String) -> Dictionary:
	var rep := {"folder": folder, "path": path, "id": folder, "name": folder, "version": "", "author": "", "description": "",
		"errors": [], "warnings": [], "pack": {}, "legacy": false}
	var files: Array = []
	_scan_files(path, 0, files)
	if files.size() > MAX_FILES:
		rep["errors"].append("Too many files (limit %d)." % MAX_FILES)
		return rep
	for f in files:
		var ext := str(f).get_extension().to_lower()
		if ext in BANNED_EXT:
			rep["errors"].append("Code or executable file not allowed: %s" % str(f).trim_prefix(path + "/"))
		elif not (ext in ALLOWED_EXT):
			rep["warnings"].append("Ignored unknown file type: %s" % str(f).trim_prefix(path + "/"))
	if not rep["errors"].is_empty():
		return rep
	var m := read_json(path + "/mod.json")
	if m["ok"]:
		if typeof(m["data"]) != TYPE_DICTIONARY:
			rep["errors"].append("mod.json must be a JSON object.")
			return rep
		var md: Dictionary = m["data"]
		var rx := RegEx.create_from_string(ID_RE)
		var id := str(md.get("id", ""))
		if rx.search(id) == null:
			rep["errors"].append("mod.json: \"id\" must be 2-40 characters of a-z, 0-9 or _ (got \"%s\")." % id)
		else:
			rep["id"] = id
		if str(md.get("name", "")).strip_edges() == "":
			rep["errors"].append("mod.json: \"name\" is required.")
		else:
			rep["name"] = str(md["name"]).left(40)
		rep["version"] = str(md.get("version", "")).left(20)
		if rep["version"] == "":
			rep["errors"].append("mod.json: \"version\" is required (e.g. \"1.0.0\").")
		rep["author"] = str(md.get("author", "")).left(40)
		rep["description"] = str(md.get("description", "")).left(200)
		if int(md.get("format", FORMAT)) != FORMAT:
			rep["errors"].append("mod.json: unsupported \"format\" %s (this game reads format %d)." % [str(md.get("format")), FORMAT])
	elif m["error"] == "missing":
		rep["legacy"] = true
		rep["warnings"].append("No mod.json: loaded as a legacy mod. Add one (see MODDING.md).")
	else:
		rep["errors"].append(m["error"])
		return rep
	if not rep["errors"].is_empty():
		return rep
	_read_pack(path, rep)
	return rep

static func _read_pack(path: String, rep: Dictionary) -> void:
	var pack := {"vehicles": [], "races": [], "towns": {}, "paints": [], "parts": {"wheels": [], "spoilers": [], "extras": []}}
	var data := path + "/data"
	var v := read_json(data + "/vehicles.json")
	if not v["ok"] and v["error"] != "missing":
		rep["errors"].append(v["error"])
	elif v["ok"]:
		if typeof(v["data"]) != TYPE_DICTIONARY:
			rep["errors"].append("vehicles.json must be an object like {\"vehicles\": [...]}.")
		else:
			for e in v["data"].get("vehicles", []):
				pack["vehicles"].append(e)
			for e in v["data"].get("paints", []):
				pack["paints"].append(e)
	var r := read_json(data + "/races.json")
	if not r["ok"] and r["error"] != "missing":
		rep["errors"].append(r["error"])
	elif r["ok"]:
		if typeof(r["data"]) != TYPE_DICTIONARY:
			rep["errors"].append("races.json must be an object like {\"races\": [...]}.")
		else:
			for e in r["data"].get("races", []):
				pack["races"].append(e)
	var p := read_json(data + "/parts.json")
	if not p["ok"] and p["error"] != "missing":
		rep["errors"].append(p["error"])
	elif p["ok"] and typeof(p["data"]) == TYPE_DICTIONARY:
		for kind in PART_KINDS:
			for e in p["data"].get(kind, []):
				pack["parts"][kind].append(e)
	if DirAccess.dir_exists_absolute(data + "/towns"):
		for f in DirAccess.get_files_at(data + "/towns"):
			if f.ends_with(".json"):
				var t := read_json(data + "/towns/" + f)
				if not t["ok"]:
					rep["errors"].append(t["error"])
				elif typeof(t["data"]) == TYPE_DICTIONARY:
					pack["towns"][str(t["data"].get("id", f.get_basename()))] = t["data"]
	for e in pack["vehicles"]:
		if e is Dictionary:
			e["_root"] = path + "/"
	rep["pack"] = pack

# ---------------------------------------------------------------- validation
static func _num(e: Dictionary, key: String, lo: float, hi: float, what: String, errs: Array) -> void:
	if not e.has(key):
		return
	var val = e[key]
	if not (val is float or val is int) or float(val) < lo or float(val) > hi:
		errs.append("%s: \"%s\" must be a number between %s and %s." % [what, key, str(lo), str(hi)])

static func _asset_ok(root: String, rel: Variant, what: String, exts: Array, errs: Array, required: bool, warns: Array) -> void:
	var s := str(rel)
	if s == "":
		return
	if s.begins_with("/") or s.contains("..") or s.contains(":"):
		errs.append("%s: path \"%s\" must be relative to the mod folder (no .. or absolute paths)." % [what, s])
		return
	if not (s.get_extension().to_lower() in exts):
		errs.append("%s: \"%s\" must be one of: %s." % [what, s, ", ".join(exts)])
		return
	if not FileAccess.file_exists(root + s):
		if required:
			errs.append("%s: missing file \"%s\"." % [what, s])
		else:
			warns.append("%s: optional file \"%s\" not found (ignored)." % [what, s])

## Validates a parsed pack against ids already taken (`taken`: {"vehicles":{id:true}, ...}) and the towns available.
static func validate(rep: Dictionary, taken: Dictionary) -> void:
	var errs: Array = rep["errors"]
	var warns: Array = rep["warnings"]
	var pack: Dictionary = rep["pack"]
	if pack.is_empty():
		return
	var rx := RegEx.create_from_string(ID_RE)
	var seen := {"vehicles": {}, "races": {}, "towns": {}, "wheels": {}, "spoilers": {}, "extras": {}}
	var root: String = rep["path"] + "/"
	for e in pack["vehicles"]:
		if typeof(e) != TYPE_DICTIONARY:
			errs.append("vehicles.json: every vehicle must be an object.")
			continue
		var id := str(e.get("id", ""))
		var what := "Vehicle \"%s\"" % id
		if rx.search(id) == null:
			errs.append("Vehicle id \"%s\" is invalid (2-40 chars of a-z, 0-9, _)." % id)
			continue
		if taken["vehicles"].has(id) or seen["vehicles"].has(id):
			errs.append("%s: duplicate id (already used by the base game or another mod)." % what)
		seen["vehicles"][id] = true
		if str(e.get("name", "")).strip_edges() == "":
			errs.append("%s: \"name\" is required." % what)
		if str(e.get("model", "")) == "":
			errs.append("%s: \"model\" (a .glb path) is required." % what)
		else:
			_asset_ok(root, e["model"], what + " model", ["glb", "gltf"], errs, true, warns)
		_asset_ok(root, e.get("icon", ""), what + " icon", ["png", "jpg", "jpeg", "webp"], errs, false, warns)
		_num(e, "max_speed", 10, 80, what, errs)
		_num(e, "accel", 4, 40, what, errs)
		_num(e, "handling", 0.5, 1.6, what, errs)
		_num(e, "grip", 3, 20, what, errs)
		_num(e, "model_scale", 0.4, 4.0, what, errs)
		_num(e, "model_yaw", -360, 360, what, errs)
		_num(e, "unlock_stars", 0, 500, what, errs)
		_num(e, "default_paint", 0, 99, what, errs)
		if e.has("procedural") or str(e.get("class", "")) not in ["", "car", "racer"]:
			errs.append("%s: \"procedural\" and custom \"class\" values are reserved for the base game." % what)
	for e in pack["paints"]:
		if typeof(e) != TYPE_DICTIONARY or not str(e.get("color", "")).is_valid_html_color() or str(e.get("name", "")) == "":
			errs.append("Paint entries need a \"name\" and a valid \"color\" like \"#ff8800\".")
	for kind in PART_KINDS:
		for e in pack["parts"][kind]:
			if typeof(e) != TYPE_DICTIONARY:
				errs.append("parts.json: every %s entry must be an object." % kind)
				continue
			var id := str(e.get("id", ""))
			if rx.search(id) == null:
				errs.append("Part id \"%s\" (%s) is invalid." % [id, kind])
				continue
			if taken[kind].has(id) or seen[kind].has(id):
				errs.append("Part \"%s\" (%s): duplicate id." % [id, kind])
			seen[kind][id] = true
			if str(e.get("name", "")) == "":
				errs.append("Part \"%s\": \"name\" is required." % id)
			if kind == "wheels" and str(e.get("color", "")) != "" and not str(e["color"]).is_valid_html_color():
				errs.append("Part \"%s\": invalid \"color\"." % id)
			_num(e, "unlock_stars", 0, 500, "Part \"%s\"" % id, errs)
			_num(e, "unlock_races", 0, 500, "Part \"%s\"" % id, errs)
	for tid in pack["towns"]:
		var t: Dictionary = pack["towns"][tid]
		if rx.search(str(tid)) == null:
			errs.append("Town id \"%s\" is invalid." % tid)
			continue
		if taken["towns"].has(tid):
			errs.append("Town \"%s\": duplicate id." % tid)
		if not t.has("map") or not t.has("cols") or not t.has("rows"):
			errs.append("Town \"%s\": needs \"map\", \"cols\" and \"rows\" (mod towns must be grid towns)." % tid)
		if t.has("world") or t.has("township"):
			errs.append("Town \"%s\": \"world\"/\"township\" are reserved for the base game." % tid)
	for e in pack["races"]:
		if typeof(e) != TYPE_DICTIONARY:
			errs.append("races.json: every race must be an object.")
			continue
		var id := str(e.get("id", ""))
		var what := "Race \"%s\"" % id
		if rx.search(id) == null:
			errs.append("Race id \"%s\" is invalid." % id)
			continue
		if taken["races"].has(id) or seen["races"].has(id):
			errs.append("%s: duplicate id." % what)
		seen["races"][id] = true
		var town := str(e.get("town", ""))
		if not (taken["towns"].has(town) or pack["towns"].has(town)):
			errs.append("%s: unknown town \"%s\"." % [what, town])
		if not (e.has("route") or e.has("route_xz")):
			errs.append("%s: needs a \"route\" (list of [col,row] corners)." % what)
		elif e.has("route"):
			var rt = e["route"]
			if typeof(rt) != TYPE_ARRAY or rt.size() < 2:
				errs.append("%s: \"route\" needs at least 2 corners." % what)
			else:
				for c in rt:
					if typeof(c) != TYPE_ARRAY or c.size() != 2:
						errs.append("%s: route corners must be [col,row] pairs." % what)
						break
		if e.has("circuit"):
			errs.append("%s: \"circuit\" is reserved for the base game." % what)
		_num(e, "laps", 1, 10, what, errs)
		_num(e, "gate_every", 2, 40, what, errs)
		if e.has("opponents") and typeof(e["opponents"]) != TYPE_ARRAY:
			errs.append("%s: \"opponents\" must be a list." % what)
		for o in e.get("opponents", []):
			if typeof(o) == TYPE_DICTIONARY:
				var vid := str(o.get("vehicle", ""))
				if not (taken["vehicles"].has(vid) or seen["vehicles"].has(vid)):
					errs.append("%s: opponent vehicle \"%s\" does not exist." % [what, vid])

## Copies the bundled sample mods (res://mods_samples) into user://mods. Returns files copied, or -1 on failure.
static func install_samples() -> int:
	var n := 0
	for d in DirAccess.get_directories_at("res://mods_samples"):
		n += _copy_tree("res://mods_samples/" + d, "user://mods/" + d)
	return n

static func _copy_tree(src: String, dst: String) -> int:
	DirAccess.make_dir_recursive_absolute(dst)
	var n := 0
	for f in DirAccess.get_files_at(src):
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		var data := FileAccess.get_file_as_bytes(src + "/" + f)
		var out := FileAccess.open(dst + "/" + f, FileAccess.WRITE)
		if out == null:
			return -1
		out.store_buffer(data)
		n += 1
	for d in DirAccess.get_directories_at(src):
		var k := _copy_tree(src + "/" + d, dst + "/" + d)
		if k < 0:
			return -1
		n += k
	return n
