extends SceneTree
## Collision audit: godot --headless --path . -s tools/collision_audit.gd -- [race_id]
## Lists every solid shape on the driving layer by category, flags shapes with no rendered mesh
## nearby ("invisible"), shapes that intrude on the racing corridor, and sweeps a car-sized box
## along the circuit centreline to find anything that actually blocks it. Prints "AUDIT ..." lines.
var game: Node
var frame := 0
var shapes: Array = []   # {cat, c: Vector3, r: float, h: float, vis: bool, near_circuit: float}
var mesh_cells := {}
const CELL := 8.0
var verbose := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var rid := str(args[0]) if args.size() > 0 else "ashapurna_gp"
	verbose = args.size() > 1
	root.get_node("Save").wipe()
	root.get_node("Content").launch = {"mode": "race", "race_id": rid}
	change_scene_to_file("res://scenes/game.tscn")

func _process(_dt: float) -> bool:
	frame += 1
	if frame == 40 and current_scene != null:
		game = current_scene
		_build_corridor()
		_collect()
	return false

func _physics_process(_dt: float) -> bool:
	if frame >= 45 and game != null and not shapes.is_empty():
		_sweep()
		quit(0)
	return false

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))

func _index_meshes(n: Node) -> void:
	if n is MeshInstance3D and n.is_visible_in_tree() and n.mesh != null:
		var c: Vector3 = n.global_transform * n.mesh.get_aabb().get_center()
		_add_mesh(c)
	elif n is MultiMeshInstance3D and n.multimesh != null and n.is_visible_in_tree():
		var mm: MultiMesh = n.multimesh
		var ac: Vector3 = mm.mesh.get_aabb().get_center() if mm.mesh != null else Vector3.ZERO
		for i in mm.instance_count:
			_add_mesh(n.global_transform * (mm.get_instance_transform(i) * ac))
	for c in n.get_children():
		_index_meshes(c)

func _add_mesh(c: Vector3) -> void:
	var k := _cell(c)
	mesh_cells[k] = true

func _has_mesh_near(c: Vector3, r: float) -> bool:
	var rr := int(ceil((r + 2.0) / CELL))
	var k := _cell(c)
	for i in range(k.x - rr, k.x + rr + 1):
		for j in range(k.y - rr, k.y + rr + 1):
			if mesh_cells.has(Vector2i(i, j)):
				return true
	return false

var corridor: Array = []   # {p: Vector3, d: Vector3 (unit), hw: float}

func _build_corridor() -> void:
	var src: PackedVector3Array = PackedVector3Array()
	if game.circuit != null:
		src = game.circuit.pts
	else:
		for r in game.route:
			src.append(r)
	var n := src.size()
	for i in n:
		var a := src[i]
		var b := src[(i + 1) % n]
		var d := b - a
		d.y = 0.0
		var L := d.length()
		if L < 0.01:
			continue
		var k := maxi(1, int(ceil(L / 3.0)))
		for j in k:
			var p := a.lerp(b, float(j) / k)
			var hw := 4.0
			if game.circuit == null:
				var nr: Dictionary = game.osm.nearest_road(Vector2(p.x, p.z), 2)
				hw = float(nr.get("hw", 3.0))
			corridor.append({"p": p, "d": d / L, "hw": hw})

var ccells := {}

func _edge_to_corridor(p: Vector3) -> float:
	if ccells.is_empty():
		for i in corridor.size():
			var q: Vector3 = corridor[i]["p"]
			var k := Vector2i(int(floor(q.x / 16.0)), int(floor(q.z / 16.0)))
			if not ccells.has(k):
				ccells[k] = []
			ccells[k].append(i)
	var best := 99.0
	var c := Vector2i(int(floor(p.x / 16.0)), int(floor(p.z / 16.0)))
	for i in range(c.x - 1, c.x + 2):
		for j in range(c.y - 1, c.y + 2):
			for idx in ccells.get(Vector2i(i, j), []):
				var q: Vector3 = corridor[idx]["p"]
				var d := Vector2(q.x - p.x, q.z - p.z).length() - float(corridor[idx]["hw"])
				if d < best:
					best = d
	return best

func _classify(sh: Shape3D) -> String:
	if sh is BoxShape3D:
		var s: Vector3 = sh.size
		if s.y > 6.0 and s.x < 0.7:
			return "pillar"
		if s.z <= 0.35 and s.y < 2.2 and s.x > 3.0:
			return "wall"
		if absf(s.z - 0.6) < 0.01 and absf(s.y - 1.1) < 0.01:
			return "hedge"
		if absf(s.x - 0.8) < 0.01 and absf(s.y - 1.4) < 0.01:
			return "cow"
		if absf(s.x - 1.2) < 0.01 and absf(s.y - 1.8) < 0.01:
			return "rickshaw"
		if absf(s.x - 1.5) < 0.01 and absf(s.y - 2.2) < 0.01:
			return "tempo"
		if s.x > 200.0:
			return "ground/edge"
		return "box"
	if sh is CylinderShape3D:
		if absf(sh.radius - 0.42) < 0.01:
			return "tree"
		if absf(sh.radius - 0.38) < 0.01:
			return "tyre_barrier"
		return "cylinder"
	if sh is ConvexPolygonShape3D:
		return "hill/ramp"
	return "other"

func _shape_extent(sh: Shape3D, xf: Transform3D) -> Dictionary:
	var a: AABB = xf * sh.get_debug_mesh().get_aabb() if sh.get_debug_mesh() != null else AABB(xf.origin, Vector3.ZERO)
	var c := a.get_center()
	return {"c": c, "r": maxf(a.size.x, a.size.z) * 0.5, "h": a.size.y, "top": a.end.y}

func _collect() -> void:
	_index_meshes(game)
	var seen := {}
	_walk(game, seen)
	var osm = game.osm
	for body in osm._bodies:
		for i in PhysicsServer3D.body_get_shape_count(body):
			var sh: RID = PhysicsServer3D.body_get_shape(body, i)
			var half: Vector3 = PhysicsServer3D.shape_get_data(sh)
			var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(body, i)
			_add({"cat": "building", "c": xf.origin, "r": maxf(half.x, half.z) * 1.0, "h": half.y * 2.0, "top": half.y * 2.0})

func _walk(n: Node, seen: Dictionary) -> void:
	if n is CollisionShape3D and n.get_parent() is CollisionObject3D and n.shape != null:
		var body: CollisionObject3D = n.get_parent()
		if (body.collision_layer & 1) != 0 and not (body is RigidBody3D):
			var e := _shape_extent(n.shape, n.global_transform)
			e["cat"] = _classify(n.shape)
			_add(e)
	for c in n.get_children():
		_walk(c, seen)

func _add(e: Dictionary) -> void:
	if e["cat"] == "ground/edge":
		return
	e["vis"] = _has_mesh_near(e["c"], e["r"])
	if e.has("pts"):
		var best := 99.0
		for q in e["pts"]:
			best = minf(best, _edge_to_corridor(q))
		e["dc"] = best - float(e["thin"])
	else:
		e["dc"] = _edge_to_corridor(e["c"]) - float(e["r"])
	shapes.append(e)

func _sweep() -> void:
	var cats := {}
	for e in shapes:
		var k: String = e["cat"]
		if not cats.has(k):
			cats[k] = {"n": 0, "invisible": 0, "in_corridor": 0, "within_4m_of_edge": 0}
		cats[k]["n"] += 1
		if not e["vis"]:
			cats[k]["invisible"] += 1
		if e["dc"] < 0.9 and float(e["top"]) > 0.25:
			cats[k]["in_corridor"] += 1
		if e["dc"] < 4.0:
			cats[k]["within_4m_of_edge"] += 1
	print("AUDIT shapes=%d" % shapes.size())
	for k in cats:
		print("AUDIT cat %-14s n=%-5d invisible=%-4d in_corridor=%-3d within_4m_of_edge=%d" % [k, cats[k]["n"], cats[k]["invisible"], cats[k]["in_corridor"], cats[k]["within_4m_of_edge"]])
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(2.3, 1.0, 4.4)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1
	var blocked := {}
	var samples := 0
	var n := corridor.size()
	for i in n:
		var a: Vector3 = corridor[i]["p"]
		var d: Vector3 = corridor[i]["d"]
		var hw: float = corridor[i]["hw"]
		var yaw := atan2(-d.x, -d.z)
		var right := Vector3(-d.z, 0.0, d.x).normalized()
		var edge := maxf(hw - 1.2, 0.0)
		for off in [-edge, -edge * 0.5, 0.0, edge * 0.5, edge]:
			var p: Vector3 = a + right * off
			q.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.9, p.z))
			samples += 1
			var hits := space.intersect_shape(q, 4)
			for h in hits:
				var col = h["collider"]
				var what := "building(server body)"
				if col is CollisionObject3D:
					var owner_id: int = col.shape_find_owner(int(h["shape"]))
					var cs = col.shape_owner_get_owner(owner_id)
					what = _classify(cs.shape) if cs is CollisionShape3D and cs.shape != null else "node"
				blocked[what] = int(blocked.get(what, 0)) + 1
				if what != "ground/edge":
					if verbose:
						print("AUDIT block idx=%d off=%.1f at=(%.1f,%.1f) by=%s" % [i, off, p.x, p.z, what])
	var total := 0
	for k in blocked:
		if k != "ground/edge":
			total += int(blocked[k])
	print("AUDIT sweep samples=%d blocked_hits=%d by=%s" % [samples, total, str(blocked)])
	var inv := 0
	for e in shapes:
		if not e["vis"]:
			inv += 1
	print("AUDIT invisible_total=%d" % inv)
	print("AUDIT DONE")
