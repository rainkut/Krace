extends Node
## Data-driven content: vehicles, races, towns, paints. Built-in data lives in res://data,
## extra content is merged from user://mods/<mod>/ (see MODDING.md).

const MODS_DIR := "user://mods"

var vehicles: Array = []
var races: Array = []
var towns := {}
var paints: Array = []
var launch := {}   # set by the menu before switching to the game scene: {mode, race_id}
var mod_names: Array = []
var _model_cache := {}

func _ready() -> void:
	reload()

func reload() -> void:
	vehicles.clear(); races.clear(); towns.clear(); paints.clear(); mod_names.clear()
	_load_pack("res://data", "res://")
	if DirAccess.dir_exists_absolute(MODS_DIR):
		for d in DirAccess.get_directories_at(MODS_DIR):
			var base := MODS_DIR + "/" + d
			_load_pack(base + "/data", base + "/")
			mod_names.append(d)

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_warning("Bad JSON in %s (skipped)" % path)
	return parsed

func _merge_by_id(into: Array, entry: Dictionary) -> void:
	for i in into.size():
		if into[i].get("id") == entry.get("id"):
			into[i] = entry
			return
	into.append(entry)

func _load_pack(data_dir: String, root: String) -> void:
	var v = _read_json(data_dir + "/vehicles.json")
	if typeof(v) == TYPE_DICTIONARY:
		if v.has("paints"):
			paints = v["paints"]
		for e in v.get("vehicles", []):
			if _valid_vehicle(e):
				e["_root"] = root
				_merge_by_id(vehicles, e)
	var r = _read_json(data_dir + "/races.json")
	if typeof(r) == TYPE_DICTIONARY:
		for e in r.get("races", []):
			if e is Dictionary and e.has("id") and e.has("route") and e.has("town"):
				_merge_by_id(races, e)
			else:
				push_warning("Skipping invalid race entry in %s" % data_dir)
	if DirAccess.dir_exists_absolute(data_dir + "/towns"):
		for f in DirAccess.get_files_at(data_dir + "/towns"):
			if f.ends_with(".json"):
				var t = _read_json(data_dir + "/towns/" + f)
				if typeof(t) == TYPE_DICTIONARY and t.has("map") and t.has("id"):
					towns[t["id"]] = t

func _valid_vehicle(e: Variant) -> bool:
	if typeof(e) != TYPE_DICTIONARY or not e.has("id") or not e.has("model"):
		push_warning("Skipping invalid vehicle entry")
		return false
	return true

func get_vehicle(id: String) -> Dictionary:
	for v in vehicles:
		if v["id"] == id:
			return v
	return vehicles[0] if not vehicles.is_empty() else {}

func get_race(id: String) -> Dictionary:
	for r in races:
		if r["id"] == id:
			return r
	return {}

func resolve_path(path: String, root: String = "res://") -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return root + path

func paint_color(index: int) -> Color:
	if paints.is_empty():
		return Color.WHITE
	return Color(paints[posmod(index, paints.size())]["color"])

## Instantiates a .glb: via the imported resource for res:// paths, or by runtime glTF loading
## for files that ship with a mod in user://.
func load_model(path: String) -> Node3D:
	if _model_cache.has(path):
		return _model_cache[path].duplicate()
	var node: Node = null
	if path.begins_with("res://"):
		var ps = load(path)
		if ps is PackedScene:
			node = ps.instantiate()
	else:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			node = doc.generate_scene(state)
	if node == null:
		push_warning("Could not load model %s" % path)
		return Node3D.new()
	_fix_node_materials(node, path.contains("/nature/"))
	_model_cache[path] = node
	return node.duplicate()

func _fix_node_materials(n: Node, nature: bool) -> void:
	if n is MeshInstance3D and n.mesh:
		for s in n.mesh.get_surface_count():
			var mat := n.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null:
				continue
			mat.metallic = 0.0
			mat.roughness = 0.9
			if nature:
				var nm := mat.resource_name.to_lower()
				if nm.contains("leaf") or nm.contains("grass") or nm.contains("bush"):
					mat.albedo_color = Color("3f7a2c") if nm.contains("dark") else Color("5e9f3a")
				elif nm.contains("wood") or nm.contains("bark"):
					mat.albedo_color = Color("7a5236")
	for c in n.get_children():
		_fix_node_materials(c, nature)
