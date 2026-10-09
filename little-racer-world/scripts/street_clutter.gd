class_name StreetClutter
extends RefCounted
## Everyday Rajasthan small-town street life, built from primitives (no external models):
## parked two-wheelers, auto-rickshaws, tempos, handcarts, fruit/veg stalls, water drums, cows and dogs.

static var _mats := {}

static func _m(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [c.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]

static func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b

static func _cyl(r: float, h: float, r2 := -1.0, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if r2 < 0.0 else r2
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	return c

static func _part(am: ArrayMesh, prim: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var st := SurfaceTool.new()
	st.append_from(prim, 0, Transform3D(Basis.from_euler(rot), pos))
	st.set_material(mat)
	st.commit(am)

static func _wheel(am: ArrayMesh, pos: Vector3, r: float, w: float) -> void:
	_part(am, _cyl(r, w, -1.0, 12), pos, _m(Color("151515"), 0.9), Vector3(0, 0, PI * 0.5))

static func bike(col: Color) -> ArrayMesh:
	var am := ArrayMesh.new()
	_wheel(am, Vector3(0, 0.32, 0.62), 0.32, 0.12)
	_wheel(am, Vector3(0, 0.32, -0.62), 0.32, 0.14)
	_part(am, _box(Vector3(0.22, 0.34, 0.9)), Vector3(0, 0.62, 0.0), _m(col, 0.45, 0.3))
	_part(am, _box(Vector3(0.26, 0.2, 0.5)), Vector3(0, 0.88, 0.2), _m(col, 0.45, 0.3))
	_part(am, _box(Vector3(0.3, 0.1, 0.62)), Vector3(0, 0.84, -0.25), _m(Color("1a1a1a"), 0.9))
	_part(am, _box(Vector3(0.7, 0.05, 0.05)), Vector3(0, 1.04, 0.5), _m(Color("222222"), 0.5, 0.5))
	_part(am, _box(Vector3(0.08, 0.7, 0.08)), Vector3(0, 0.7, 0.55), _m(Color("777777"), 0.4, 0.6), Vector3(0.3, 0, 0))
	return am

static func rickshaw(col: Color) -> ArrayMesh:
	var am := ArrayMesh.new()
	var black := _m(Color("17181a"), 0.8)
	_wheel(am, Vector3(0, 0.26, 1.15), 0.26, 0.12)
	_wheel(am, Vector3(-0.6, 0.26, -0.7), 0.26, 0.14)
	_wheel(am, Vector3(0.6, 0.26, -0.7), 0.26, 0.14)
	_part(am, _box(Vector3(1.3, 0.5, 2.5)), Vector3(0, 0.58, -0.1), black)
	_part(am, _box(Vector3(1.3, 0.4, 0.95)), Vector3(0, 1.0, 0.95), _m(col, 0.5))
	_part(am, _box(Vector3(1.3, 0.12, 1.8)), Vector3(0, 1.95, -0.6), _m(Color("1d2a24"), 0.9))
	_part(am, _box(Vector3(1.3, 0.12, 0.9)), Vector3(0, 1.82, 0.8), _m(col, 0.5), Vector3(-0.12, 0, 0))
	_part(am, _box(Vector3(0.06, 1.0, 0.06)), Vector3(-0.62, 1.4, 0.4), black)
	_part(am, _box(Vector3(0.06, 1.0, 0.06)), Vector3(0.62, 1.4, 0.4), black)
	_part(am, _box(Vector3(1.1, 0.5, 0.15)), Vector3(0, 1.1, -1.35), _m(col, 0.5))
	return am

static func tempo(col: Color) -> ArrayMesh:
	var am := ArrayMesh.new()
	for z in [1.2, -1.2]:
		for x in [-0.8, 0.8]:
			_wheel(am, Vector3(x, 0.38, z), 0.38, 0.22)
	_part(am, _box(Vector3(1.6, 0.25, 4.2)), Vector3(0, 0.62, 0), _m(Color("222222"), 0.8))
	_part(am, _box(Vector3(1.7, 1.25, 1.2)), Vector3(0, 1.4, 1.45), _m(col, 0.5))
	_part(am, _box(Vector3(1.6, 1.0, 2.6)), Vector3(0, 1.3, -0.9), _m(Color("b8a47a"), 0.9))
	_part(am, _box(Vector3(1.55, 0.35, 2.6)), Vector3(0, 2.15, -0.9), _m(Color("7a8a9a"), 0.8))
	return am

static func cart(produce: Color) -> ArrayMesh:
	var am := ArrayMesh.new()
	var wood := _m(Color("5c4331"), 0.95)
	_wheel(am, Vector3(-0.62, 0.38, 0.1), 0.38, 0.06)
	_wheel(am, Vector3(0.62, 0.38, 0.1), 0.38, 0.06)
	_part(am, _box(Vector3(1.1, 0.12, 1.9)), Vector3(0, 0.78, 0.2), wood)
	_part(am, _box(Vector3(0.06, 0.06, 1.2)), Vector3(-0.35, 0.75, -1.3), wood)
	_part(am, _box(Vector3(0.06, 0.06, 1.2)), Vector3(0.35, 0.75, -1.3), wood)
	_part(am, _box(Vector3(0.9, 0.35, 1.5)), Vector3(0, 1.0, 0.25), _m(produce, 0.8))
	_part(am, _box(Vector3(0.5, 0.2, 0.5)), Vector3(0.1, 1.28, 0.3), _m(produce.lightened(0.15), 0.8))
	return am

static func stall(canopy: Color, produce: Color) -> ArrayMesh:
	var am := ArrayMesh.new()
	_part(am, _cyl(0.04, 2.2), Vector3(0, 1.1, 0), _m(Color("444444"), 0.5, 0.5))
	_part(am, _cyl(1.5, 0.45, 0.05, 12), Vector3(0, 2.3, 0), _m(canopy, 0.9))
	_part(am, _box(Vector3(1.4, 0.7, 0.8)), Vector3(0, 0.35, 0.9), _m(Color("6a5a48"), 0.95))
	_part(am, _box(Vector3(1.2, 0.2, 0.6)), Vector3(0, 0.8, 0.9), _m(produce, 0.8))
	return am

static func cow(body: Color, patch: Color) -> ArrayMesh:
	var am := ArrayMesh.new()
	var bm := _m(body, 0.95)
	_part(am, _box(Vector3(0.62, 0.7, 1.5)), Vector3(0, 1.0, 0), bm)
	_part(am, _box(Vector3(0.5, 0.45, 0.5)), Vector3(0, 0.78, 0.55), _m(patch, 0.95))
	_part(am, _box(Vector3(0.32, 0.36, 0.5)), Vector3(0, 1.25, 0.95), bm)
	_part(am, _box(Vector3(0.09, 0.09, 0.2)), Vector3(-0.14, 1.5, 0.9), _m(Color("e8e0cc"), 0.6), Vector3(0, 0, 0.6))
	_part(am, _box(Vector3(0.09, 0.09, 0.2)), Vector3(0.14, 1.5, 0.9), _m(Color("e8e0cc"), 0.6), Vector3(0, 0, -0.6))
	_part(am, _box(Vector3(0.05, 0.6, 0.05)), Vector3(0, 0.9, -0.8), bm, Vector3(0.15, 0, 0))
	for x in [-0.2, 0.2]:
		for z in [0.55, -0.55]:
			_part(am, _box(Vector3(0.12, 0.7, 0.12)), Vector3(x, 0.35, z), bm)
	return am

static func dog() -> ArrayMesh:
	var am := ArrayMesh.new()
	var bm := _m(Color("a07c4e"), 0.95)
	_part(am, _box(Vector3(0.22, 0.26, 0.6)), Vector3(0, 0.38, 0), bm)
	_part(am, _box(Vector3(0.18, 0.2, 0.22)), Vector3(0, 0.5, 0.36), bm)
	for x in [-0.07, 0.07]:
		for z in [0.2, -0.2]:
			_part(am, _box(Vector3(0.06, 0.28, 0.06)), Vector3(x, 0.14, z), bm)
	return am

static func drum() -> ArrayMesh:
	var am := ArrayMesh.new()
	_part(am, _cyl(0.3, 0.9), Vector3(0, 0.45, 0), _m(Color("2a63a8"), 0.5))
	return am

static func build(parent: Node3D, roads: Array, rng: RandomNumberGenerator, col_body: StaticBody3D, high: bool, skip := Callable()) -> void:
	var bike_cols := [Color("1a1a1a"), Color("a82a2a"), Color("2a3f8a"), Color("c9c9c9"), Color("3a3a3a"), Color("6a1f1f")]
	var kinds := {
		"bike": [], "rick": [], "tempo": [], "cart": [], "stall": [], "cow": [], "dog": [], "drum": [],
	}
	var meshes := {}
	var variants := {
		"bike": bike_cols.map(func(c): return bike(c)),
		"rick": [rickshaw(Color("e0b81c")), rickshaw(Color("2f8a4a")), rickshaw(Color("e0b81c"))],
		"tempo": [tempo(Color("2a5aa0")), tempo(Color("c9c9c9")), tempo(Color("b83a2a"))],
		"cart": [cart(Color("c8501c")), cart(Color("4a9a3a")), cart(Color("d9b020")), cart(Color("a02828"))],
		"stall": [stall(Color("c0392b"), Color("e8a020")), stall(Color("2a6fa8"), Color("a02828")), stall(Color("e0b81c"), Color("4a9a3a"))],
		"cow": [cow(Color("e8e0d0"), Color("d4c8b0")), cow(Color("7a5a3a"), Color("6a4a2a")), cow(Color("2a2a2a"), Color("3a3a3a")), cow(Color("c9b898"), Color("a89878"))],
		"dog": [dog()],
		"drum": [drum()],
	}
	for k in variants:
		meshes[k] = []
		for _i in variants[k].size():
			meshes[k].append([])
	var every := 6.0 if high else 9.0
	for rp in roads:
		var c: String = rp["c"]
		if c == "track":
			continue
		var pts: PackedVector2Array = rp["pts"]
		var w: float = rp["w"]
		var main := c == "secondary" or c == "tertiary"
		var next := rng.randf_range(2.0, every)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var L := a.distance_to(b)
			if L < 1.0:
				continue
			var d := (b - a) / L
			var nrm := Vector2(-d.y, d.x)
			var yaw_road := atan2(d.x, d.y)
			var t := next
			while t < L:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var r := rng.randf()
				var kind := ""
				var off := w * 0.5 + 0.9
				var yaw := yaw_road + (PI if rng.randf() < 0.5 else 0.0)
				if r < 0.34:
					kind = "bike"
					off = w * 0.5 + rng.randf_range(0.5, 1.4)
					if rng.randf() < 0.25:
						yaw = yaw_road + PI * 0.5 * side
						off = w * 0.5 + 1.0
				elif r < 0.44:
					kind = "rick"
					off = w * 0.5 + 1.3
				elif r < 0.50:
					kind = "tempo"
					off = w * 0.5 + 1.6
				elif r < 0.60:
					kind = "cart"
					off = w * 0.5 + 1.1
				elif r < 0.66 and main:
					kind = "stall"
					off = w * 0.5 + 2.0
				elif r < 0.76:
					kind = "cow"
					off = w * 0.5 - rng.randf_range(0.0, 0.6) if rng.randf() < 0.4 else w * 0.5 + 1.0
					yaw = yaw_road + rng.randf_range(-0.6, 0.6) + (PI if rng.randf() < 0.5 else 0.0)
				elif r < 0.82:
					kind = "dog"
					off = w * 0.5 + rng.randf_range(0.2, 1.0)
					yaw = rng.randf() * TAU
				elif r < 0.90:
					kind = "drum"
					off = w * 0.5 + 0.9
				if kind != "" and skip.is_valid() and skip.call(a + d * t):
					kind = ""
				if kind != "":
					var p2 := a + d * t + nrm * off * side
					var vi: int = rng.randi() % variants[kind].size()
					var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p2.x, 0.12, p2.y))
					meshes[kind][vi].append(xf)
					if kind == "cow" or kind == "rick" or kind == "tempo":
						var sz := Vector3(1.0, 1.4, 1.8) if kind == "cow" else (Vector3(1.4, 1.8, 2.6) if kind == "rick" else Vector3(1.7, 2.2, 4.2))
						var cs := CollisionShape3D.new()
						var bs := BoxShape3D.new()
						bs.size = sz
						cs.shape = bs
						cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p2.x, sz.y * 0.5, p2.y))
						col_body.add_child(cs)
				t += rng.randf_range(every * 0.4, every * 1.6)
			next = t - L
	var cells := {}
	var total := 0
	for k in variants:
		for vi in variants[k].size():
			for xf in meshes[k][vi]:
				var ck := Vector3i(int(floor(xf.origin.x / 140.0)), int(floor(xf.origin.z / 140.0)), vi)
				var key := "%s_%d_%d_%d" % [k, ck.x, ck.y, ck.z]
				if not cells.has(key):
					cells[key] = [k, vi, []]
				cells[key][2].append(xf)
				total += 1
	for key in cells:
		var k: String = cells[key][0]
		var vi: int = cells[key][1]
		var xfs: Array = cells[key][2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[k][vi]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 320.0 if high else 220.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (high and k != "dog") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	print("street clutter: ", total, " in ", cells.size(), " chunks")
