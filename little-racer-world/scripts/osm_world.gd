class_name OsmWorld
extends Town
## Real-map town: roads/landuse/water come from OpenStreetMap (data/osm/sheoganj_world.json),
## everything else (buildings, trees, poles) is generated offline by tools/gen_world.py and baked
## into the same file, so the runtime only meshes roads and instances props (MultiMesh + a facade shader).

const SEG_CELL := 32.0
const FACADE_SHADER := preload("res://scripts/facade.gdshader")
const TREE_MODELS := ["tree_oak", "tree_default", "tree_simple", "tree_fat", "tree_small", "tree_detailed", "tree_oak", "tree_small"]
const TEX := "res://assets/textures/indian/"
## Real Sheoganj lanes are narrow: OSM class -> carriageway width in metres.
const REAL_WIDTH := {"secondary": 8.0, "tertiary": 6.5, "unclassified": 5.2, "residential": 4.0, "service": 3.2, "track": 3.2, "living_street": 3.5}

var world: Dictionary
var gen: Dictionary
var extent := 1100.0
var bounds := Rect2(-1100, -1100, 2200, 2200)
var township: Township
var spawn_xz := Vector2.ZERO
var spawn_dir := Vector2(1, 0)
var park_center := Vector3.ZERO
var has_park := false
var road_polylines: Array = []      # [{pts: PackedVector2Array, w: float, c: String}] for the map view
var landmark_nodes: Array = []

var _sa := PackedVector2Array()
var _sb := PackedVector2Array()
var _shw := PackedFloat32Array()
var _grid := {}
var _nodes := {}                    # osm node id -> Vector2
var _adj := {}                      # id -> Array[int] (drivable neighbours)
var _node_ids: Array = []
var _bodies: Array[RID] = []
var _shapes: Array[RID] = []

func build(town_data: Dictionary, _reserved: Dictionary = {}) -> void:
	data = town_data
	cell = 12.0
	cols = 0
	rows = 0
	var txt := FileAccess.get_file_as_string(str(data["world"]))
	world = JSON.parse_string(txt)
	gen = world.get("gen", {})
	extent = float(world.get("extent", 1100))
	var bd = world.get("bounds")
	if bd is Array:
		bounds = Rect2(float(bd[0]), float(bd[1]), float(bd[2]) - float(bd[0]), float(bd[3]) - float(bd[1]))
	else:
		bounds = Rect2(-extent, -extent, extent * 2.0, extent * 2.0)
	var sp: Array = data.get("spawn_xz", [0, 0])
	spawn_xz = Vector2(float(sp[0]), float(sp[1]))
	var sd: Array = data.get("spawn_dir", [1, 0])
	spawn_dir = Vector2(float(sd[0]), float(sd[1])).normalized()
	var ov = Content.launch.get("spawn_xz")
	if ov is Array:
		spawn_xz = Vector2(float(ov[0]), float(ov[1]))
	_rng.seed = 424242
	_col_body = StaticBody3D.new()
	_col_body.collision_layer = 1
	_col_body.collision_mask = 0
	add_child(_col_body)
	if data.has("township"):
		var tdata := Township.load_data(str(data["township"]))
		if not tdata.is_empty():
			township = Township.new()
			township.name = "Township"
			add_child(township)
			township.setup(self, tdata)
			township.integrate_gen(gen)
	_index_roads()
	if township != null:
		township.register_roads()
		if str(Content.launch.get("spawn", "")) == "ashapurna":
			var sd2: Array = township.spawn_xz_dir()
			spawn_xz = sd2[0]
			spawn_dir = sd2[1]
	_world_ground()
	_world_areas()
	_world_roads()
	_world_buildings()
	_world_trees()
	Compounds.build(self, road_polylines, _rng, _col_body, Settings.quality_level() == 2, func(p): return township != null and township.inside(p, 14.0), gen.get("buildings", []))
	_world_poles()
	var crushables := StreetClutter.build(self, road_polylines, _rng, _col_body, Settings.quality_level() == 2, func(p): return township != null and township.inside(p, 14.0), Settings.obstacles)
	if not crushables.is_empty():
		var crush := ClutterCrush.new()
		crush.setup(crushables)
		add_child(crush)
	_world_landmarks()
	_world_park()
	_make_stars()
	if township != null:
		township.build()

func _exit_tree() -> void:
	for b in _bodies:
		PhysicsServer3D.free_rid(b)
	for s in _shapes:
		PhysicsServer3D.free_rid(s)
	_bodies.clear()
	_shapes.clear()

# ------------------------------------------------------------------ queries
func _index_roads() -> void:
	for r in world["roads"]:
		var pts: Array = r["p"]
		r["w"] = float(REAL_WIDTH.get(str(r["c"]), float(r["w"]) * 0.75))
		var hw := float(r["w"]) * 0.5
		var pv := PackedVector2Array()
		for p in pts:
			pv.append(Vector2(p[0], p[1]))
		road_polylines.append({"pts": pv, "w": float(r["w"]), "c": str(r["c"])})
		for i in pv.size() - 1:
			var a := pv[i]
			var b := pv[i + 1]
			var n := maxi(1, int(ceil(a.distance_to(b) / 24.0)))
			for k in n:
				_add_seg(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), hw)
		if r["c"] != "track" and r.has("ids"):
			var ids: Array = r["ids"]
			for i in ids.size():
				var id := int(ids[i])
				if not _nodes.has(id):
					_nodes[id] = pv[i]
					_adj[id] = []
			for i in ids.size() - 1:
				var a := int(ids[i])
				var b := int(ids[i + 1])
				if a == b:
					continue
				_adj[a].append(b)
				if not r.get("oneway", false):
					_adj[b].append(a)
	_node_ids = _nodes.keys()

func _add_seg(a: Vector2, b: Vector2, hw: float) -> void:
	var idx := _sa.size()
	_sa.append(a)
	_sb.append(b)
	_shw.append(hw)
	var x0 := int(floor(minf(a.x, b.x) / SEG_CELL))
	var x1 := int(floor(maxf(a.x, b.x) / SEG_CELL))
	var z0 := int(floor(minf(a.y, b.y) / SEG_CELL))
	var z1 := int(floor(maxf(a.y, b.y) / SEG_CELL))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var k := Vector2i(cx, cz)
			if not _grid.has(k):
				_grid[k] = PackedInt32Array()
			var arr: PackedInt32Array = _grid[k]
			arr.append(idx)
			_grid[k] = arr

## Nearest road: {d: distance to centre-line, edge: d - half width, q: closest point, dir: unit direction}
func nearest_road(p: Vector2, rad := 1) -> Dictionary:
	var best := {"edge": 999.0}
	var c := Vector2i(int(floor(p.x / SEG_CELL)), int(floor(p.y / SEG_CELL)))
	for i in range(c.x - rad, c.x + rad + 1):
		for j in range(c.y - rad, c.y + rad + 1):
			var arr = _grid.get(Vector2i(i, j))
			if arr == null:
				continue
			for si in arr:
				var a := _sa[si]
				var ab := _sb[si] - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				var q := a + ab * t
				var d := p.distance_to(q)
				var e := d - _shw[si]
				if e < float(best["edge"]):
					best = {"edge": e, "d": d, "q": q, "dir": ab.normalized(), "hw": _shw[si]}
	return best

func is_road_at(p: Vector3) -> bool:
	if has_park and Vector2(p.x - park_center.x, p.z - park_center.z).length() < 58.0:
		return true
	return float(nearest_road(Vector2(p.x, p.z))["edge"]) <= 1.4

func road_distance(p: Vector3) -> float:
	return float(nearest_road(Vector2(p.x, p.z), 3)["edge"])

func nearest_road_pose(p: Vector3, heading: float) -> Transform3D:
	var r := nearest_road(Vector2(p.x, p.z), 6)
	if not r.has("q"):
		return spawn_pose()
	var dir: Vector2 = r["dir"]
	var yaw := atan2(-dir.x, -dir.y)
	if absf(angle_difference(heading, yaw)) > PI * 0.5:
		yaw = atan2(dir.x, dir.y)
	var q: Vector2 = r["q"]
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, 0.7, q.y))

func spawn_pose() -> Transform3D:
	var r := nearest_road(spawn_xz, 4)
	var pos := spawn_xz
	var d := spawn_dir
	if r.has("q"):
		pos = r["q"]
		d = r["dir"]
		if d.dot(spawn_dir) < 0.0:
			d = -d
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)), Vector3(pos.x, 0.7, pos.y))

func nearest_node(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for id in _node_ids:
		var d: float = (_nodes[id] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = id
	return best

func node_pos(id: int) -> Vector2:
	return _nodes[id]

func random_node_near(center: Vector2, min_d: float, max_d: float) -> int:
	for _i in 40:
		var id: int = _node_ids[_rng.randi() % _node_ids.size()]
		var d := (_nodes[id] as Vector2).distance_to(center)
		if d >= min_d and d <= max_d:
			return id
	return _node_ids[_rng.randi() % _node_ids.size()]

## A random drive along real roads, starting at `start`, roughly `length` metres, respecting one-way roads.
func random_route(start: int, length: float, avoid_prev := -1) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cur := start
	var prev := avoid_prev
	var travelled := 0.0
	var first := _nodes[cur] as Vector2
	out.append(Vector3(first.x, 0.0, first.y))
	while travelled < length:
		var opts: Array = _adj.get(cur, [])
		if opts.is_empty():
			break
		var choices := opts.filter(func(n): return n != prev)
		if choices.is_empty():
			choices = opts
		var nxt: int = choices[_rng.randi() % choices.size()]
		var a := _nodes[cur] as Vector2
		var b := _nodes[nxt] as Vector2
		var seg := a.distance_to(b)
		var steps := maxi(1, int(ceil(seg / 14.0)))
		for k in range(1, steps + 1):
			var q := a.lerp(b, float(k) / steps)
			out.append(Vector3(q.x, 0.0, q.y))
		travelled += seg
		prev = cur
		cur = nxt
	return out

func last_node_of(route: PackedVector3Array) -> int:
	return nearest_node(Vector2(route[route.size() - 1].x, route[route.size() - 1].z))

# ------------------------------------------------------------------ materials
func _pbr(name: String, tile_m: float, tint := Color.WHITE, normal_scale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/pbr/%s_color.jpg" % name)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://assets/pbr/%s_normal.jpg" % name)
	m.normal_scale = normal_scale
	m.roughness_texture = load("res://assets/pbr/%s_rough.jpg" % name)
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _itex(name: String, tile_m: float, tint := Color.WHITE, normal_scale := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + name + "_color.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX + name + "_normal.jpg")
	m.normal_scale = normal_scale
	m.roughness_texture = load(TEX + name + "_rough.jpg")
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _flat_mat(color: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ------------------------------------------------------------------ ground, landuse, water
func _world_ground() -> void:
	var size := maxf(bounds.size.x, bounds.size.y) + 900.0
	var bc := bounds.get_center()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.position = Vector3(bc.x, 0.0, bc.y)
	mi.mesh = plane
	mi.material_override = _itex("ground054", 8.0, Color("e0cfa6"), 0.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var floor_shape := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(size, 2.0, size)
	floor_shape.shape = fb
	floor_shape.position = Vector3(bc.x, 0.08 - 1.0, bc.y)
	_col_body.add_child(floor_shape)
	var hx := bounds.size.x * 0.5 + 70.0
	var hz := bounds.size.y * 0.5 + 70.0
	for side in 4:
		var wall := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		var horiz := side < 2
		wb.size = Vector3(hx * 2.0 + 8.0, 14.0, 4.0) if horiz else Vector3(4.0, 14.0, hz * 2.0 + 8.0)
		wall.shape = wb
		var sgn := 1.0 if side % 2 == 0 else -1.0
		wall.position = Vector3(bc.x, 7.0, bc.y + sgn * (hz + 2.0)) if horiz else Vector3(bc.x + sgn * (hx + 2.0), 7.0, bc.y)
		_col_body.add_child(wall)

func _fill_polygon(st: SurfaceTool, poly: PackedVector2Array, y: float, uv_scale: float) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size() - 2, 3):
		_tri(st, poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]], y, uv_scale)

func _world_areas() -> void:
	var farm := SurfaceTool.new(); farm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var scrub := SurfaceTool.new(); scrub.begin(Mesh.PRIMITIVE_TRIANGLES)
	var town := SurfaceTool.new(); town.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wat := SurfaceTool.new(); wat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var river := SurfaceTool.new(); river.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in world["areas"]:
		var k: String = a["k"]
		if k.begins_with("waterway:"):
			var pv := PackedVector2Array()
			for p in a["p"]:
				pv.append(Vector2(p[0], p[1]))
			_ribbon(river, pv, 13.0, 0.03, 0.05)
			continue
		if not a["closed"]:
			continue
		var poly := PackedVector2Array()
		for p in a["p"]:
			poly.append(Vector2(p[0], p[1]))
		poly.remove_at(poly.size() - 1)
		match k:
			"farmland": _fill_polygon(farm, poly, 0.03, 1.0 / 6.0)
			"scrub": _fill_polygon(scrub, poly, 0.035, 1.0 / 7.0)
			"residential": _fill_polygon(town, poly, 0.025, 1.0 / 6.0)
			"water": _fill_polygon(wat, poly, 0.03, 0.05)
	_surface(farm, _itex("ground054", 7.0, Color("c2ad78"), 0.6), false)
	_surface(scrub, _itex("ground033", 7.0, Color("b49f72"), 0.6), false)
	_surface(town, _itex("ground054", 6.0, Color("d6c39b"), 0.6), false)
	var wm := _flat_mat(Color("4b7f8a"), 0.12)
	wm.metallic = 0.25
	wm.metallic_specular = 0.8
	_surface(wat, wm, false)
	_surface(river, wm, false)

func _surface(st: SurfaceTool, mat: Material, shadows: bool) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ------------------------------------------------------------------ roads
func _tri(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, y: float, uvs: float) -> void:
	var cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if cross < 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		st.set_normal(Vector3.UP)
		st.set_uv(p * uvs)
		st.add_vertex(Vector3(p.x, y, p.y))

func _ribbon(st: SurfaceTool, pts: PackedVector2Array, width: float, y: float, uvs: float, joins := true) -> void:
	var hw := width * 0.5
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a)
		if d.length() < 0.01:
			continue
		var n := Vector2(-d.y, d.x).normalized() * hw
		_tri(st, a + n, b + n, b - n, y, uvs)
		_tri(st, a + n, b - n, a - n, y, uvs)
	if not joins:
		return
	for i in pts.size():
		var turn := 0.0
		if i > 0 and i < pts.size() - 1:
			var d1 := (pts[i] - pts[i - 1]).normalized()
			var d2 := (pts[i + 1] - pts[i]).normalized()
			turn = absf(d1.angle_to(d2))
			if turn < 0.12:
				continue
		var c := pts[i]
		var segs_n := 8
		for k in segs_n:
			var a0 := TAU * k / segs_n
			var a1 := TAU * (k + 1) / segs_n
			_tri(st, c, c + Vector2(cos(a0), sin(a0)) * hw, c + Vector2(cos(a1), sin(a1)) * hw, y, uvs)

func _junction_points() -> PackedVector2Array:
	var count := {}
	var pos := {}
	for r in world["roads"]:
		if r["c"] == "track" or not r.has("ids"):
			continue
		var ids: Array = r["ids"]
		for i in ids.size():
			var id := int(ids[i])
			count[id] = int(count.get(id, 0)) + (1 if (i == 0 or i == ids.size() - 1) else 2)
			pos[id] = Vector2(r["p"][i][0], r["p"][i][1])
	var out := PackedVector2Array()
	for id in count:
		if int(count[id]) >= 3:
			out.append(pos[id])
	return out

func _world_roads() -> void:
	var asphalt := SurfaceTool.new(); asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shoulder := SurfaceTool.new(); shoulder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb := SurfaceTool.new(); kerb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirt := SurfaceTool.new(); dirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := SurfaceTool.new(); paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var patches := SurfaceTool.new(); patches.begin(Mesh.PRIMITIVE_TRIANGLES)
	var junctions := _junction_points()
	for rp in road_polylines:
		var pts: PackedVector2Array = rp["pts"]
		var w: float = rp["w"]
		var c: String = rp["c"]
		if c == "track":
			_ribbon(dirt, pts, w, 0.09, 1.0 / 5.0)
			continue
		# sandy, uneven shoulder instead of a kerb; worn-in dust spills over the tar edge
		_ribbon(shoulder, pts, w + (4.0 if c == "secondary" else 2.6), 0.06, 1.0 / 4.0, false)
		_ribbon(asphalt, pts, w, 0.10, 1.0 / 5.0)
		if c == "secondary":
			# only the main road has a raised concrete kerb strip and a faded broken centre line
			_ribbon(kerb, pts, w + 1.4, 0.085, 1.0 / 4.0, false)
			_dashes(paint, pts, junctions, 0.0, 0.14, 2.2, 5.5)
		_patch_road(patches, pts, w, 0.114 if c != "secondary" else 0.118)
	_surface(asphalt, _itex("asphalt025b", 4.0, Color("a9a399"), 1.0), false)
	_surface(shoulder, _itex("ground054", 4.0, Color("d9c79a"), 0.6), false)
	_surface(kerb, _itex("concrete019", 4.0, Color("b9b2a2"), 0.6), false)
	_surface(dirt, _itex("ground033", 5.0, Color("b49a72"), 0.7), false)
	var pm := _flat_mat(Color("cfc8b0"), 0.9)
	pm.albedo_color = Color("cfc8b0")
	_surface(paint, pm, false)
	_surface(patches, _itex("asphalt012", 3.0, Color("8d877d"), 0.8), false)
	_speed_breakers()

func _patch_road(st: SurfaceTool, pts: PackedVector2Array, w: float, y: float) -> void:
	var next := _rng.randf_range(6.0, 30.0)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		if L < 0.5:
			continue
		var d := (b - a) / L
		var n := Vector2(-d.y, d.x)
		var t := next
		while t < L:
			var c0 := a + d * t + n * _rng.randf_range(-w * 0.3, w * 0.3)
			var pw := _rng.randf_range(0.7, w * 0.45)
			var pl := _rng.randf_range(1.2, 4.0)
			var ring: Array[Vector2] = []
			for k in 9:
				var ang := TAU * float(k) / 9.0
				var rr := _rng.randf_range(0.65, 1.0)
				ring.append(c0 + d * cos(ang) * pl * 0.5 * rr + n * sin(ang) * pw * 0.5 * rr)
			for k in 9:
				_tri(st, c0, ring[k], ring[(k + 1) % 9], y, 1.0)
			t += _rng.randf_range(6.0, 30.0)
		next = t - L

func _offset(pts: PackedVector2Array, off: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var d: Vector2
		if i == 0:
			d = pts[1] - pts[0]
		elif i == pts.size() - 1:
			d = pts[i] - pts[i - 1]
		else:
			d = (pts[i + 1] - pts[i - 1])
		d = d.normalized()
		out.append(pts[i] + Vector2(-d.y, d.x) * off)
	return out

func _dashes(st: SurfaceTool, pts: PackedVector2Array, junctions: PackedVector2Array, y_extra: float, width: float, dash: float, gap: float) -> void:
	var s := 0.0
	var period := dash + gap
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		if L < 0.01:
			continue
		var d := (b - a) / L
		var n := Vector2(-d.y, d.x) * width * 0.5
		var t := 0.0
		while t < L:
			var phase := fposmod(s + t, period)
			var seg_len := minf(L - t, (dash - phase) if phase < dash else (period - phase))
			if phase < dash and seg_len > 0.01:
				var p0 := a + d * t
				var p1 := a + d * (t + seg_len)
				var mid := (p0 + p1) * 0.5
				var near := false
				for j in junctions:
					if j.distance_squared_to(mid) < 100.0:
						near = true
						break
				if not near:
					_tri(st, p0 + n, p1 + n, p1 - n, 0.125 + y_extra, 1.0)
					_tri(st, p0 + n, p1 - n, p0 - n, 0.125 + y_extra, 1.0)
			t += maxf(seg_len, 0.02)
		s += L

func _speed_breakers() -> void:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st2 := SurfaceTool.new(); st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for rp in road_polylines:
		if rp["c"] != "residential" and rp["c"] != "unclassified":
			continue
		var pts: PackedVector2Array = rp["pts"]
		if pts.size() < 3 or _rng.randf() > 0.12:
			continue
		var i := 1 + (_rng.randi() % (pts.size() - 2))
		var d := (pts[i + 1] - pts[i - 1]).normalized()
		var nrm := Vector2(-d.y, d.x)
		var hw: float = float(rp["w"]) * 0.5
		for k in 6:
			var c0 := pts[i] + d * (k * 0.5)
			var tgt := st if k % 2 == 0 else st2
			_tri(tgt, c0 + nrm * hw, c0 + d * 0.5 + nrm * hw, c0 + d * 0.5 - nrm * hw, 0.14, 1.0)
			_tri(tgt, c0 + nrm * hw, c0 + d * 0.5 - nrm * hw, c0 - nrm * hw, 0.14, 1.0)
		n += 1
	_surface(st, _flat_mat(Color("e8c21e"), 0.7), false)
	_surface(st2, _flat_mat(Color("222222"), 0.8), false)

# ------------------------------------------------------------------ buildings (MultiMesh + facade shader) + trees/poles
func _world_buildings() -> void:
	var list: Array = gen.get("buildings", [])
	if list.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = FACADE_SHADER
	mat.set_shader_parameter("plaster_a", load(TEX + "plaster003_color.jpg"))
	mat.set_shader_parameter("plaster_b", load(TEX + "plaster006_color.jpg"))
	mat.set_shader_parameter("stone_t", load(TEX + "bricks075a_color.jpg"))
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var chunks := {}
	for b in list:
		var k := Vector2i(int(floor(float(b[0]) / 220.0)), int(floor(float(b[1]) / 220.0)))
		if not chunks.has(k):
			chunks[k] = []
		chunks[k].append(b)
	var tank_xf: Array = []
	var stair_xf: Array = []
	var space := get_world_3d().space
	for k in chunks:
		var arr: Array = chunks[k]
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.body_set_collision_layer(body, 1)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		_bodies.append(body)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = box
		mm.instance_count = arr.size()
		for i in arr.size():
			var b: Array = arr[i]
			var w := float(b[3])
			var d := float(b[4])
			var h := int(b[5]) * 3.2 + 0.4
			var yaw := float(b[2])
			var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(w, h, d))
			var pos := Vector3(float(b[0]), h * 0.5, float(b[1]))
			mm.set_instance_transform(i, Transform3D(basis, pos))
			var sd := fmod(absf(float(b[0]) * 12.9898 + float(b[1]) * 78.233), 1.0)
			mm.set_instance_custom_data(i, Color(float(b[6]) / 15.0, float(b[7]), float(int(b[5])) / 15.0, sd))
			var shape := PhysicsServer3D.box_shape_create()
			PhysicsServer3D.shape_set_data(shape, Vector3(w, h, d) * 0.5)
			_shapes.append(shape)
			PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(Vector3.UP, yaw), pos))
			if int(b[8]) == 1 and int(b[9]) != 2:
				var t := Transform3D(Basis(Vector3.UP, yaw), pos + Basis(Vector3.UP, yaw) * Vector3(w * 0.25, h * 0.5 + 0.7, -d * 0.2))
				tank_xf.append(t)
			if int(b[9]) != 2 and sd > 0.55:
				stair_xf.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(2.6, 2.4, 3.0)), pos + Basis(Vector3.UP, yaw) * Vector3(-w * 0.28, h * 0.5 + 1.2, d * 0.22)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.visibility_range_end = 820.0 if Settings.quality_level() == 2 else 560.0
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mmi.custom_aabb = AABB(Vector3(k.x * 220.0 - 40.0, -2.0, k.y * 220.0 - 40.0), Vector3(300.0, 30.0, 300.0))
		add_child(mmi)
	_instances(CylinderMesh.new(), tank_xf, _flat_mat(Color("1d2327"), 0.5), func(m): m.top_radius = 0.75; m.bottom_radius = 0.85; m.height = 1.4; m.radial_segments = 10)
	_instances(box, stair_xf, _flat_mat(Color("bdb4a4"), 0.95), Callable())

func _instances(mesh: Mesh, xforms: Array, mat: Material, setup: Callable) -> void:
	if xforms.is_empty():
		return
	if setup.is_valid():
		setup.call(mesh)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = 560.0 if Settings.quality_level() == 2 else 380.0
	add_child(mmi)

func _world_trees() -> void:
	var by_kind := {}
	for t in TREE_MODELS:
		by_kind[t] = []
	var shape := CylinderShape3D.new()
	shape.radius = 0.42
	shape.height = 4.0
	var high := Settings.quality_level() == 2
	for t in gen.get("trees", []):
		if t.size() > 5 and not high:
			continue
		var kind: String = TREE_MODELS[int(t[3]) % TREE_MODELS.size()]
		var p := Vector3(float(t[0]), 0.0, float(t[1]))
		var sc := float(t[2])
		by_kind[kind].append(Transform3D(Basis(Vector3.UP, fmod(float(t[0]) * 7.31, TAU)).scaled(Vector3(1.35, 0.85, 1.35) * sc), p))
		if int(t[4]) == 1:
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.position = Vector3(p.x, 2.0, p.z)
			_col_body.add_child(cs)
	var tmeshes := Compounds.tree_meshes()
	for v in tmeshes.size():
		var xf: Array = []
		for k in by_kind:
			if TREE_MODELS.find(k) % 3 == v:
				xf.append_array(by_kind[k])
		_scatter_mesh(tmeshes[v], xf)

func _scatter_mesh(mesh: Mesh, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = 600.0 if Settings.quality_level() == 2 else 420.0
	mmi.custom_aabb = AABB(Vector3(bounds.position.x - 100.0, -2.0, bounds.position.y - 100.0), Vector3(bounds.size.x + 200.0, 30.0, bounds.size.y + 200.0))
	add_child(mmi)

func _world_poles() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.16
	cyl.height = 7.5
	cyl.radial_segments = 6
	var arm := BoxMesh.new()
	arm.size = Vector3(2.2, 0.12, 0.12)
	var pole_xf: Array = []
	var arm_xf: Array = []
	for p in gen.get("poles", []):
		var pos := Vector3(float(p[0]), 3.75, float(p[1]))
		pole_xf.append(Transform3D(Basis.IDENTITY, pos))
		arm_xf.append(Transform3D(Basis(Vector3.UP, fmod(float(p[0]) * 3.7, PI)), Vector3(pos.x, 7.0, pos.z)))
	var tf_xf: Array = []
	var pi := 0
	for p in gen.get("poles", []):
		pi += 1
		if pi % 9 == 0:
			tf_xf.append(Transform3D(Basis(Vector3.UP, fmod(float(p[0]) * 3.7, PI)), Vector3(float(p[0]) + 0.35, 6.0, float(p[1]))))
	_instances(BoxMesh.new(), tf_xf, _flat_mat(Color("5a5d5f"), 0.6), func(m): m.size = Vector3(0.7, 1.1, 0.7))
	_instances(cyl, pole_xf, _flat_mat(Color("8d8a84"), 0.9), Callable())
	_instances(arm, arm_xf, _flat_mat(Color("3a3a3a"), 0.7), Callable())
	var lines := PackedVector3Array()
	for w in gen.get("wires", []):
		var a := Vector3(float(w[0]), 7.0, float(w[1]))
		var b := Vector3(float(w[2]), 7.0, float(w[3]))
		for off in [-0.8, 0.0, 0.8]:
			var prev := a
			var steps := 5
			var side: Vector3 = Vector3(-(b.z - a.z), 0.0, b.x - a.x).normalized() * float(off)
			for k in range(1, steps + 1):
				var t := float(k) / steps
				var q: Vector3 = a.lerp(b, t) + side
				q.y -= sin(t * PI) * 0.55
				lines.append(prev)
				lines.append(q)
				prev = q
	if lines.size() > 0:
		var am := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = lines
		am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(0.08, 0.08, 0.08)
		mi.material_override = lm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 260.0
		add_child(mi)
	var light_xf: Array = []
	for l in gen.get("lights", []):
		light_xf.append(Transform3D(Basis(Vector3.UP, float(l[2])).scaled(Vector3.ONE * 8.0), Vector3(float(l[0]), 0.0, float(l[1]))))
	_scatter("res://assets/kenney/roads/light-square.glb", light_xf)

# ------------------------------------------------------------------ landmarks, stunt park, stars
func _label(text: String, pos: Vector3, size := 0.06) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = size
	l.font_size = 48
	l.outline_size = 14
	l.modulate = Color("ffffff")
	l.outline_modulate = Color("1c2a3a")
	l.no_depth_test = false
	l.fixed_size = false
	l.visibility_range_end = 320.0
	add_child(l)

func _world_landmarks() -> void:
	for lm in gen.get("landmarks", []):
		var pos := Vector3(float(lm["x"]), float(lm["h"]) + 3.5, float(lm["z"]))
		var text: String = str(lm["n"])
		if lm["k"] == "hospital":
			text = "+ " + text
		_label(text, pos)
		landmark_nodes.append({"name": text, "pos": Vector2(float(lm["x"]), float(lm["z"])), "kind": lm["k"]})
	for p in world["pois"]:
		if p["k"] == "town":
			_label("SHEOGANJ", Vector3(float(p["p"][0]), 40.0, float(p["p"][1])), 0.2)
		elif p["k"] == "bus_station":
			_build_bus_stand(Vector2(float(p["p"][0]), float(p["p"][1])))

func _build_bus_stand(p: Vector2) -> void:
	var q := nearest_road(p, 4)
	var pos := p
	var yaw := 0.0
	if q.has("q"):
		var qq: Vector2 = q["q"]
		var away := (p - qq).normalized()
		pos = qq + away * (float(q["hw"]) + 7.5)
		yaw = atan2(-away.x, -away.y)
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.y)
	root.rotation.y = yaw
	var roof := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(16.0, 0.35, 5.5)
	roof.mesh = rb
	roof.position.y = 4.2
	roof.material_override = _flat_mat(Color("c2452d"), 0.7)
	root.add_child(roof)
	var post_mat := _flat_mat(Color("e9e4d8"), 0.8)
	for x in [-7.0, -2.5, 2.5, 7.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.35, 4.2, 0.35)
		post.mesh = pb
		post.position = Vector3(x, 2.1, -2.2)
		post.material_override = post_mat
		root.add_child(post)
	var bench := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(10.0, 0.5, 0.8)
	bench.mesh = bb
	bench.position = Vector3(0, 0.45, -2.5)
	bench.material_override = _flat_mat(Color("5a4636"), 0.9)
	root.add_child(bench)
	add_child(root)
	_add_box_collider(Vector3(pos.x, 2.0, pos.y), Vector3(16.0, 4.0, 1.0), yaw)

func _world_park() -> void:
	var pk = gen.get("park")
	if pk == null:
		return
	has_park = true
	park_center = Vector3(float(pk["x"]), 0.0, float(pk["z"]))
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 56.0
	cm.bottom_radius = 56.0
	cm.height = 0.04
	cm.radial_segments = 36
	disc.mesh = cm
	var pm := _pbr("grass004", 6.0, Color("9fb06a"))
	disc.material_override = pm
	disc.position = park_center + Vector3(0, 0.05, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_label("STUNT PARK", park_center + Vector3(0, 14.0, 0), 0.12)
	var hazard := _flat_mat(Color("f2c230"), 0.6)
	var specs := [
		[Vector3(-30, 0, 20), 0.0, 9.0, 16.0, 2.4],
		[Vector3(30, 0, -20), PI, 9.0, 16.0, 2.4],
		[Vector3(0, 0, 38), PI * 0.5, 10.0, 22.0, 3.6],
		[Vector3(-8, 0, -38), -PI * 0.5, 8.0, 14.0, 2.0],
	]
	for s in specs:
		_make_ramp(park_center + (s[0] as Vector3), float(s[1]), float(s[2]), float(s[3]), float(s[4]), hazard)
	_make_hill(park_center + Vector3(2, 0, 0), 30.0, 12.0, 5.5)
	var cone_model := "res://assets/kenney/cars/cone.glb"
	var cxf: Array = []
	for i in 14:
		var a := TAU * i / 14.0
		cxf.append(Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * 2.0), park_center + Vector3(cos(a) * 48.0, 0, sin(a) * 48.0)))
	_scatter(cone_model, cxf)

func _make_ramp(pos: Vector3, yaw: float, w: float, length: float, h: float, mat: Material) -> void:
	# local forward is -Z: low edge at z = +length/2, high edge at z = -length/2
	var hl := length * 0.5
	var hw := w * 0.5
	var pts := PackedVector3Array([
		Vector3(-hw, 0, hl), Vector3(hw, 0, hl), Vector3(-hw, 0, -hl), Vector3(hw, 0, -hl),
		Vector3(-hw, h, -hl), Vector3(hw, h, -hl)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [[0, 1, 5], [0, 5, 4], [2, 4, 5], [2, 5, 3], [0, 4, 2], [1, 3, 5]]
	for t in tris:
		for i in t:
			st.set_uv(Vector2(pts[i].x, pts[i].z) * 0.25)
			st.add_vertex(pts[i])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	cs.shape = sh
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.08, 0))
	_col_body.add_child(cs)

func _make_hill(pos: Vector3, base: float, top: float, h: float) -> void:
	var b := base * 0.5
	var t := top * 0.5
	var pts := PackedVector3Array([
		Vector3(-b, 0, -b), Vector3(b, 0, -b), Vector3(b, 0, b), Vector3(-b, 0, b),
		Vector3(-t, h, -t), Vector3(t, h, -t), Vector3(t, h, t), Vector3(-t, h, t)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]
	for q in quads:
		for i in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.set_uv(Vector2(pts[i].x, pts[i].z) * 0.2)
			st.add_vertex(pts[i])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _pbr("grass004", 6.0, Color("8fa35e"))
	mi.position = pos + Vector3(0, 0.05, 0)
	add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	cs.shape = sh
	cs.position = pos + Vector3(0, 0.08, 0)
	_col_body.add_child(cs)

func _make_stars() -> void:
	for s in gen.get("stars", []):
		star_positions.append(Vector3(float(s[0]), 1.6, float(s[1])))
	if has_park:
		for i in 10:
			var a := TAU * i / 10.0
			star_positions.append(park_center + Vector3(cos(a) * 24.0, 1.6, sin(a) * 24.0))
		for off in [Vector3(-30, 4.8, 3), Vector3(30, 4.8, -3), Vector3(0, 6.0, 52), Vector3(2, 8.4, 0)]:
			star_positions.append(park_center + (off as Vector3))
