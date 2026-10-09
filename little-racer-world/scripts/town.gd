class_name Town
extends Node3D
## Builds a 3D town from a grid map (see data/towns/*.json). Roads, markings and kerbs are
## generated as a few merged meshes; houses/trees use MultiMesh so the whole town costs a
## few dozen draw calls (important on phones).

const HOUSE_SCALE := 8.0
const HOUSES := ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u"]
const TREES := ["tree_oak","tree_default","tree_simple","tree_fat","tree_pineTallA","tree_pineRoundA","tree_small","tree_detailed"]
const SMALL := ["plant_bush","plant_bushLarge","rock_smallA","flower_redA","flower_yellowA","flower_purpleA"]
const FRONT_YAW := 0.0   # house models face +Z; yaw so the front looks at the road

var data: Dictionary
var cell := 12.0
var cols := 0
var rows := 0
var grid: Array = []
var origin := Vector2.ZERO
var star_positions: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _model_info := {}
var _col_body: StaticBody3D

func build(town_data: Dictionary, reserved_cells: Dictionary = {}) -> void:
	data = town_data
	cell = float(data.get("cell", 12.0))
	cols = int(data["cols"])
	rows = int(data["rows"])
	grid = data["map"]
	origin = -Vector2(cols, rows) * cell * 0.5
	_rng.seed = 1234
	_col_body = StaticBody3D.new()
	_col_body.collision_layer = 1
	_col_body.collision_mask = 0
	add_child(_col_body)
	_build_ground()
	_build_roads()
	_build_lots()
	_build_street_props()
	_build_parked_cars(reserved_cells)
	for s in data.get("stars", []):
		star_positions.append(Vector3(origin.x + float(s[0]) * cell, 1.6, origin.y + float(s[1]) * cell))

# ---------- coordinates ----------
func cell_center(c: float, r: float) -> Vector3:
	return Vector3(origin.x + (c + 0.5) * cell, 0.0, origin.y + (r + 0.5) * cell)

func is_road_cell(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return false
	return grid[r][c] == "#"

func is_road_at(p: Vector3) -> bool:
	# A car counts as "on road" if it is on tarmac or on the kerb strip right next to it.
	for o in [Vector2.ZERO, Vector2(2.2, 0), Vector2(-2.2, 0), Vector2(0, 2.2), Vector2(0, -2.2)]:
		var c := int(floor((p.x + o.x - origin.x) / cell))
		var r := int(floor((p.z + o.y - origin.y) / cell))
		if is_road_cell(c, r):
			return true
	return false

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / cell)), int(floor((p.z - origin.y) / cell)))

## Nearest tarmac pose with the heading snapped along the road axis; used by "reset car".
func nearest_road_pose(p: Vector3, heading: float) -> Transform3D:
	var best := Vector2i(-1, -1)
	var bd := INF
	var pc := world_to_cell(p)
	for dr in range(-6, 7):
		for dc in range(-6, 7):
			var c := pc.x + dc
			var r := pc.y + dr
			if is_road_cell(c, r):
				var d := cell_center(c, r).distance_squared_to(p)
				if d < bd:
					bd = d
					best = Vector2i(c, r)
	if best.x < 0:
		best = Vector2i(int(data["spawn"]["cell"][0]), int(data["spawn"]["cell"][1]))
	var snapped := roundf(heading / (PI * 0.5)) * (PI * 0.5)
	var horizontal := is_road_cell(best.x + 1, best.y) or is_road_cell(best.x - 1, best.y)
	var vertical := is_road_cell(best.x, best.y + 1) or is_road_cell(best.x, best.y - 1)
	if horizontal and not vertical:
		snapped = -PI * 0.5 if absf(angle_difference(heading, -PI * 0.5)) < PI * 0.5 else PI * 0.5
	elif vertical and not horizontal:
		snapped = 0.0 if absf(angle_difference(heading, 0.0)) < PI * 0.5 else PI
	var pos := cell_center(best.x, best.y)
	pos.y = 0.62
	return Transform3D(Basis(Vector3.UP, snapped), pos)

# ---------- textures ----------
func _noise_texture(c1: Color, c2: Color, freq: float, size := 128) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.seed = 3
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var t := n.get_noise_2d(x, y) * 0.5 + 0.5
			var fine := _rng.randf() * 0.12
			img.set_pixel(x, y, c1.lerp(c2, clampf(t + fine, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _mat(color: Color, tex: Texture2D = null, uv_scale := 1.0, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if tex:
		m.albedo_texture = tex
		m.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ---------- ground ----------
func _build_ground() -> void:
	var w := cols * cell
	var h := rows * cell
	var plane := PlaneMesh.new()
	plane.size = Vector2(w + 600.0, h + 600.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = _mat(Color.WHITE, _noise_texture(Color("4e8f3a"), Color("79b44f"), 0.09), (w + 600.0) / 9.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var floor_shape := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(w + 600.0, 2.0, h + 600.0)
	floor_shape.shape = fb
	floor_shape.position.y = -1.0
	_col_body.add_child(floor_shape)
	for side in 4:
		var wall := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		var horiz := side < 2
		wb.size = Vector3(w + 40.0, 12.0, 4.0) if horiz else Vector3(4.0, 12.0, h + 40.0)
		wall.shape = wb
		var sgn := 1.0 if side % 2 == 0 else -1.0
		wall.position = Vector3(0.0, 6.0, sgn * (h * 0.5 + 2.0)) if horiz else Vector3(sgn * (w * 0.5 + 2.0), 6.0, 0.0)
		_col_body.add_child(wall)

# ---------- roads ----------
func _quad(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float, uv0 := Vector2(0, 0), uv1 := Vector2(1, 1)) -> void:
	st.set_normal(Vector3.UP)
	var pts := [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
	var uvs := [Vector2(uv0.x, uv0.y), Vector2(uv1.x, uv0.y), Vector2(uv1.x, uv1.y), Vector2(uv0.x, uv1.y)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])

func _box(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, h: float) -> void:
	_quad(st, x0, z0, x1, z1, h)
	var c := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var nrm := Vector3(b.z - a.z, 0.0, -(b.x - a.x)).normalized()
		st.set_normal(nrm)
		for p in [a, b, Vector3(b.x, h, b.z), a, Vector3(b.x, h, b.z), Vector3(a.x, h, a.z)]:
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(p)

func _build_roads() -> void:
	var asphalt := SurfaceTool.new(); asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := SurfaceTool.new(); white.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yellow := SurfaceTool.new(); yellow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb := SurfaceTool.new(); kerb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := cell * 0.5
	for r in rows:
		for c in cols:
			if not is_road_cell(c, r):
				continue
			var cx := origin.x + (c + 0.5) * cell
			var cz := origin.y + (r + 0.5) * cell
			_quad(asphalt, cx - half, cz - half, cx + half, cz + half, 0.05)
			var n := is_road_cell(c, r - 1)
			var s := is_road_cell(c, r + 1)
			var e := is_road_cell(c + 1, r)
			var w := is_road_cell(c - 1, r)
			var count := int(n) + int(s) + int(e) + int(w)
			if n and s and not e and not w:
				for dz in [-3.0, 3.0]:
					_quad(yellow, cx - 0.14, cz + dz - 1.75, cx + 0.14, cz + dz + 1.75, 0.07)
				_quad(white, cx - 5.3, cz - half, cx - 4.95, cz + half, 0.07)
				_quad(white, cx + 4.95, cz - half, cx + 5.3, cz + half, 0.07)
			elif e and w and not n and not s:
				for dx in [-3.0, 3.0]:
					_quad(yellow, cx + dx - 1.75, cz - 0.14, cx + dx + 1.75, cz + 0.14, 0.07)
				_quad(white, cx - half, cz - 5.3, cx + half, cz - 4.95, 0.07)
				_quad(white, cx - half, cz + 4.95, cx + half, cz + 5.3, 0.07)
			elif count >= 3:
				for k in range(-4, 5):
					var o := k * 1.15
					if n: _quad(white, cx + o - 0.3, cz - half + 0.6, cx + o + 0.3, cz - half + 3.4, 0.07)
					if s: _quad(white, cx + o - 0.3, cz + half - 3.4, cx + o + 0.3, cz + half - 0.6, 0.07)
					if e: _quad(white, cx + half - 3.4, cz + o - 0.3, cx + half - 0.6, cz + o + 0.3, 0.07)
					if w: _quad(white, cx - half + 0.6, cz + o - 0.3, cx - half + 3.4, cz + o + 0.3, 0.07)
	# kerbs/sidewalks: a strip inside each lot cell that borders a road
	var strip := 2.0
	for r in rows:
		for c in cols:
			if is_road_cell(c, r) or grid[r][c] == "F":
				continue
			var x0 := origin.x + c * cell
			var z0 := origin.y + r * cell
			if is_road_cell(c, r - 1): _box(kerb, x0, z0, x0 + cell, z0 + strip, 0.16)
			if is_road_cell(c, r + 1): _box(kerb, x0, z0 + cell - strip, x0 + cell, z0 + cell, 0.16)
			if is_road_cell(c - 1, r): _box(kerb, x0, z0, x0 + strip, z0 + cell, 0.16)
			if is_road_cell(c + 1, r): _box(kerb, x0 + cell - strip, z0, x0 + cell, z0 + cell, 0.16)
	var asphalt_tex := _noise_texture(Color("3a3d42"), Color("4d5157"), 0.35)
	_add_surface(asphalt, _mat(Color.WHITE, asphalt_tex, 1.0, 0.9), false)
	_add_surface(white, _mat(Color("f4f4f0"), null, 1.0, 0.8), false)
	_add_surface(yellow, _mat(Color("f2c230"), null, 1.0, 0.8), false)
	_add_surface(kerb, _mat(Color("b9b6ad"), _noise_texture(Color("a9a69d"), Color("cfccc2"), 0.5), 0.1, 0.9), true)

func _add_surface(st: SurfaceTool, mat: Material, shadows: bool) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ---------- models via MultiMesh ----------
func _collect_meshes(n: Node, acc: Transform3D, out: Array) -> void:
	var xf := acc
	if n is Node3D and n != null:
		xf = acc * (n as Node3D).transform
	if n is MeshInstance3D:
		out.append({"mesh": (n as MeshInstance3D).mesh, "xf": xf})
	for ch in n.get_children():
		_collect_meshes(ch, xf, out)

func _model_meshes(path: String) -> Dictionary:
	if _model_info.has(path):
		return _model_info[path]
	var inst := Content.load_model(path)
	var list: Array = []
	for ch in inst.get_children():
		_collect_meshes(ch, Transform3D.IDENTITY, list)
	if inst is MeshInstance3D:
		list.append({"mesh": (inst as MeshInstance3D).mesh, "xf": Transform3D.IDENTITY})
	var aabb := AABB()
	var first := true
	for m in list:
		var a: AABB = (m["xf"] as Transform3D) * (m["mesh"] as Mesh).get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	inst.free()
	_model_info[path] = {"meshes": list, "aabb": aabb}
	return _model_info[path]

func _scatter(path: String, xforms: Array, shadows := true) -> void:
	if xforms.is_empty():
		return
	var info := _model_meshes(path)
	for m in info["meshes"]:
		_fix_materials(m["mesh"], path.contains("/nature/"))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m["mesh"]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, (xforms[i] as Transform3D) * (m["xf"] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

func _fix_materials(mesh: Mesh, nature: bool) -> void:
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s) as StandardMaterial3D
		if mat == null:
			continue
		mat.metallic = 0.0
		mat.roughness = 0.9
		if nature:
			var n := mat.resource_name.to_lower()
			if n.contains("leaf") or n.contains("grass") or n.contains("bush"):
				mat.albedo_color = Color("7d8f45") if not n.contains("dark") else Color("5d6e34")
			elif n.contains("wood") or n.contains("bark"):
				mat.albedo_color = Color("7a5236")

func _add_box_collider(center: Vector3, size: Vector3, yaw: float) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	_col_body.add_child(cs)

func _add_trunk_collider(p: Vector3, radius: float) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = 6.0
	cs.shape = s
	cs.position = Vector3(p.x, 3.0, p.z)
	_col_body.add_child(cs)

# ---------- lots: houses, parks, forest ----------
func _facing_to_road(c: int, r: int) -> float:
	var best := 99
	var best_dir := Vector2(0, 1)
	for d in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
		for k in range(1, 6):
			if is_road_cell(c + int(d.x) * k, r + int(d.y) * k):
				if k < best:
					best = k
					best_dir = d
				break
	return atan2(best_dir.x, best_dir.y) + FRONT_YAW

func _build_lots() -> void:
	var house_xf := {}
	var tree_xf := {}
	var small_xf := {}
	for h in HOUSES:
		house_xf[h] = []
	for t in TREES:
		tree_xf[t] = []
	for s in SMALL:
		small_xf[s] = []
	for r in rows:
		for c in cols:
			var ch: String = grid[r][c]
			var ctr := cell_center(c, r)
			if ch == ".":
				var kind: String = HOUSES[_rng.randi() % HOUSES.size()]
				var yaw := _facing_to_road(c, r)
				house_xf[kind].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * HOUSE_SCALE), ctr))
				var bb: AABB = _model_meshes("res://assets/kenney/suburban/building-type-%s.glb" % kind)["aabb"]
				var size := bb.size * HOUSE_SCALE
				var center_local := (bb.position + bb.size * 0.5) * HOUSE_SCALE
				_add_box_collider(ctr + Basis(Vector3.UP, yaw) * Vector3(center_local.x, size.y * 0.5, center_local.z), Vector3(size.x, size.y, size.z), yaw)
				if _rng.randf() < 0.55:
					_place_small(ctr + Basis(Vector3.UP, yaw) * Vector3(_rng.randf_range(-5, 5), 0, 5.6), tree_xf, small_xf, true)
			elif ch == "P":
				for i in 5:
					_place_small(ctr + Vector3(_rng.randf_range(-5.2, 5.2), 0, _rng.randf_range(-5.2, 5.2)), tree_xf, small_xf, i < 3)
			elif ch == "F":
				for i in 4:
					_place_small(ctr + Vector3(_rng.randf_range(-5.5, 5.5), 0, _rng.randf_range(-5.5, 5.5)), tree_xf, small_xf, true)
	for h in HOUSES:
		_scatter("res://assets/kenney/suburban/building-type-%s.glb" % h, house_xf[h])
	for t in TREES:
		_scatter("res://assets/kenney/nature/%s.glb" % t, tree_xf[t])
	for s in SMALL:
		_scatter("res://assets/kenney/nature/%s.glb" % s, small_xf[s], false)

func _place_small(p: Vector3, tree_xf: Dictionary, small_xf: Dictionary, tree: bool) -> void:
	var yaw := _rng.randf() * TAU
	if tree:
		var kind: String = TREES[_rng.randi() % TREES.size()]
		var sc := _rng.randf_range(2.6, 3.6)
		tree_xf[kind].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), p))
		_add_trunk_collider(p, 0.7)
	else:
		var kind: String = SMALL[_rng.randi() % SMALL.size()]
		var sc := _rng.randf_range(2.2, 3.6)
		small_xf[kind].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), p))

# ---------- street lights ----------
func _build_street_props() -> void:
	var lights := []
	for r in rows:
		for c in cols:
			if not is_road_cell(c, r):
				continue
			var cnt := int(is_road_cell(c, r - 1)) + int(is_road_cell(c, r + 1)) + int(is_road_cell(c + 1, r)) + int(is_road_cell(c - 1, r))
			if cnt >= 3:
				var ctr := cell_center(c, r)
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var p := ctr + Vector3(sx * 6.9, 0.0, sz * 6.9)
						if not is_road_cell(c + int(sx), r + int(sz)):
							lights.append(Transform3D(Basis(Vector3.UP, atan2(-sx, -sz)).scaled(Vector3.ONE * 9.0), p))
	_scatter("res://assets/kenney/roads/light-square.glb", lights)

# ---------- parked cars (decor on side streets) ----------
func _build_parked_cars(reserved: Dictionary) -> void:
	var models := ["sedan", "hatchback-sports", "suv", "van", "taxi", "sedan-sports", "delivery", "police"]
	var placed := 0
	for r in rows:
		for c in cols:
			if placed >= 20 or not is_road_cell(c, r) or reserved.has(Vector2i(c, r)):
				continue
			var n := is_road_cell(c, r - 1)
			var s := is_road_cell(c, r + 1)
			var e := is_road_cell(c + 1, r)
			var w := is_road_cell(c - 1, r)
			var straight_v := n and s and not e and not w
			var straight_h := e and w and not n and not s
			if (not straight_v and not straight_h) or _rng.randf() > 0.2:
				continue
			var ctr := cell_center(c, r)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var pos := ctr + (Vector3(side * 3.9, 0.0, _rng.randf_range(-2, 2)) if straight_v else Vector3(_rng.randf_range(-2, 2), 0.0, side * 3.9))
			var yaw := 0.0 if straight_v else PI * 0.5
			var m: String = models[_rng.randi() % models.size()]
			var def := {"model": "res://assets/kenney/cars/%s.glb" % m, "model_scale": 1.75, "model_yaw": 180}
			var vis := CarVisual.build(def, _rng.randi() % 10, 0.0)
			vis.position = pos + Vector3(0, 0.0, 0)
			vis.rotation.y = yaw
			add_child(vis)
			_add_box_collider(pos + Vector3(0, 0.6, 0), Vector3(2.4, 1.2, 4.4) if straight_v else Vector3(4.4, 1.2, 2.4), 0.0)
			placed += 1
