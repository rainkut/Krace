class_name Track
extends RefCounted
## Segment-based road: sampled centreline (every STEP m) + procedural visuals.

const STEP := 4.0
const ROAD_HALF := 8.0
const LANES := [-6.0, -2.0, 2.0, 6.0]
const BARRIER := 9.6
const DIRT_OUT := 15.0
const F_BRIDGE := 1
const F_TUNNEL := 2
const F_INTER := 4
const CHUNK := 100  # samples per visual chunk (400 m)

var def: Dictionary = {}
var n := 0
var pos := PackedVector3Array()
var yaw := PackedFloat32Array()
var curve := PackedFloat32Array()
var slope := PackedFloat32Array()
var feat := PackedInt32Array()
var envs := PackedInt32Array()
var segs: Array = []
var length := 0.0        # total drivable length
var finish_s := 0.0      # race finish line
var shortcut := Vector2.ZERO
var shortcut_gain := 1.4
var checkpoints: Array = []
var chunks: Array = []   # [Node3D, s0, s1]
var inters: Array = []
var wet := false
var night := false
var refl: Texture2D
var road_mats: Array[ShaderMaterial] = []
var _win_mat: StandardMaterial3D
var _sign_mat: StandardMaterial3D

static func seg(len: float, c := 0.0, sl := 0.0, f := 0, e := 0) -> Dictionary:
	return {"len": len, "curve": c, "slope": sl, "feat": f, "env": e}

# ---------------------------------------------------------------- generation
static func generate(d: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d["seed"])
	var theme: int = d["theme"]
	var total_len: float = d["len"]
	var out: Array = []
	var total := 0.0
	var yaw_sum := 0.0
	var seen_bridge := false
	var seen_tunnel := false
	var seen_inter := 0
	out.append(seg(320, 0, 0, 0, 0 if theme != 2 else 2))
	total = 320.0
	while total < total_len - 200.0:
		var frac := total / total_len
		var e := theme
		if theme == 0 and frac > 0.5 and frac < 0.68:
			e = 1
		elif theme == 1 and frac < 0.14:
			e = 0
		var r := rng.randf()
		var s_list: Array = []
		if r < 0.2:
			s_list.append(seg(rng.randf_range(250, 500), 0, 0, 0, e))
		elif r < 0.52:
			var c := rng.randf_range(0.0016, 0.0034) * (1.0 if rng.randf() < 0.5 else -1.0)
			if absf(yaw_sum + c * 350.0) > 1.5:
				c = -signf(yaw_sum) * absf(c)
			var l := rng.randf_range(250, 480)
			s_list.append(seg(l, c, 0, 0, e))
		elif r < 0.62:
			var c2 := rng.randf_range(0.002, 0.003) * (1.0 if rng.randf() < 0.5 else -1.0)
			s_list.append(seg(300, c2, 0, 0, e))
			s_list.append(seg(300, -c2, 0, 0, e))
		elif r < 0.76:
			s_list.append(seg(rng.randf_range(300, 420), 0, 0.06, 0, e))
			s_list.append(seg(rng.randf_range(300, 420), 0, -0.06, 0, e))
		elif r < 0.84 and not seen_bridge and frac > 0.2:
			seen_bridge = true
			s_list.append(seg(480, 0, 0, F_BRIDGE, e))
		elif r < 0.92 and not seen_tunnel and frac > 0.3:
			seen_tunnel = true
			s_list.append(seg(rng.randf_range(520, 700), rng.randf_range(-0.0008, 0.0008), 0, F_TUNNEL, e))
		elif seen_inter < 2 and (e == 1 or rng.randf() < 0.5):
			seen_inter += 1
			s_list.append(seg(120, 0, 0, F_INTER, e))
		else:
			s_list.append(seg(rng.randf_range(250, 400), 0, 0, 0, e))
		for sg in s_list:
			out.append(sg)
			total += float(sg["len"])
			yaw_sum += float(sg["curve"]) * float(sg["len"]) * 0.8
	out.append(seg(300, 0, 0, 0, theme))
	return out

## Real road baked from OpenStreetMap by tools/fetch_route.py: points every 4 m, x east / z north.
static func from_route(d: Dictionary) -> Array:
	var f := FileAccess.open("res://data/routes/%s.json" % d["route"], FileAccess.READ)
	var js: Dictionary = JSON.parse_string(f.get_as_text())
	var pts: Array = js["pts"]
	var fl: Array = js["flags"]
	var m := mini(pts.size() - 1, int(float(d["len"]) / STEP) + 120)
	var hd: Array = []
	for i in m:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		hd.append(atan2(float(b[0]) - float(a[0]), float(b[1]) - float(a[1])))
	var raw: Array = []
	for i in range(1, hd.size()):
		raw.append(-wrapf(float(hd[i]) - float(hd[i - 1]), -PI, PI) / STEP)
	raw.append(0.0)
	var out: Array = []
	for i in raw.size():
		var acc := 0.0
		var cnt := 0
		for j in range(maxi(0, i - 4), mini(raw.size(), i + 5)):
			acc += float(raw[j]); cnt += 1
		var c := clampf(acc / cnt, -0.03, 0.03)
		var ft: int = int(fl[i]) & 3
		out.append(seg(STEP, c, 0.0, ft, int(d["theme"])))
	# drop bridge/tunnel runs shorter than 12 samples
	var i := 0
	while i < out.size():
		var ft: int = out[i]["feat"]
		if ft == 0:
			i += 1; continue
		var j := i
		while j < out.size() and out[j]["feat"] == ft:
			j += 1
		if j - i < 12:
			for k in range(i, j):
				out[k]["feat"] = 0
		i = j
	out.append(seg(300, 0, 0, 0, int(d["theme"])))
	return out

func build(d: Dictionary) -> void:
	def = d
	if d.has("segs"):
		segs = d["segs"]
	elif d.has("route"):
		segs = from_route(d)
	else:
		segs = generate(d)
	var total := 0.0
	for sg in segs:
		total += float(sg["len"])
	n = int(ceil(total / STEP)) + 2
	pos.resize(n); yaw.resize(n); curve.resize(n); slope.resize(n); feat.resize(n); envs.resize(n)
	var idx := 0
	var p := Vector3.ZERO
	var yw := 0.0
	for sg in segs:
		var cnt := int(round(float(sg["len"]) / STEP))
		for k in cnt:
			if idx >= n:
				break
			var t := (k + 0.5) / float(cnt)
			var ramp := smoothstep(0.0, 0.25, minf(t, 1.0 - t))
			var c: float = float(sg["curve"]) * ramp
			var sl: float = float(sg["slope"]) * sin(PI * t)
			pos[idx] = p; yaw[idx] = yw; curve[idx] = c; slope[idx] = sl
			feat[idx] = int(sg["feat"]); envs[idx] = int(sg["env"])
			p += Vector3(-sin(yw + 0.5 * c * STEP), 0, -cos(yw + 0.5 * c * STEP)) * STEP
			p.y += sl * STEP
			yw += c * STEP
			idx += 1
	while idx < n:
		pos[idx] = p; yaw[idx] = yw; curve[idx] = 0.0; slope[idx] = 0.0; feat[idx] = 0
		envs[idx] = envs[maxi(0, idx - 1)]
		p += Vector3(-sin(yw), 0, -cos(yw)) * STEP
		idx += 1
	length = float(n - 2) * STEP
	finish_s = float(d["len"])
	# checkpoints every ~2.5 km
	checkpoints = []
	var cp := 2500.0
	while cp < finish_s - 600.0:
		checkpoints.append(cp)
		cp += 2500.0
	# shortcut: first long clean straight after 25%
	shortcut = Vector2.ZERO
	if d.get("shortcut", false):
		var run_start := -1
		for i in range(int(finish_s * 0.25 / STEP), int((finish_s - 700.0) / STEP)):
			var ok: bool = feat[i] == 0 and absf(curve[i]) < 0.0001 and absf(slope[i]) < 0.005
			if ok and run_start < 0:
				run_start = i
			elif not ok:
				run_start = -1
			if run_start >= 0 and (i - run_start) * STEP >= 340.0:
				shortcut = Vector2(float(run_start + 12) * STEP, float(i) * STEP)
				break
	inters = []
	for i in range(1, n - 1):
		if feat[i] & F_INTER and not (feat[i - 1] & F_INTER):
			inters.append(float(i) * STEP + 40.0)

# ---------------------------------------------------------------- sampling
func _uv(s: float) -> Vector2:
	var f := clampf(s / STEP, 0.0, float(n - 2) - 0.001)
	var i := floorf(f)
	return Vector2(i, f - i)

func pos_at(s: float, x := 0.0, y := 0.0) -> Vector3:
	var u := _uv(s)
	var i := int(u.x)
	var p := pos[i].lerp(pos[i + 1], u.y)
	var yw := lerpf(yaw[i], yaw[i + 1], u.y)
	return p + Vector3(cos(yw) * x, y, -sin(yw) * x)

func yaw_at(s: float) -> float:
	var u := _uv(s)
	return lerpf(yaw[int(u.x)], yaw[int(u.x) + 1], u.y)

func curve_at(s: float) -> float:
	return curve[int(_uv(s).x)]

func slope_at(s: float) -> float:
	return slope[int(_uv(s).x)]

func feat_at(s: float) -> int:
	return feat[int(_uv(s).x)]

func env_at(s: float) -> int:
	return envs[int(_uv(s).x)]

func in_shortcut(s: float) -> bool:
	return shortcut.y > 0.0 and s >= shortcut.x and s <= shortcut.y

func right_at(s: float) -> Vector3:
	var yw := yaw_at(s)
	return Vector3(cos(yw), 0, -sin(yw))

func forward_at(s: float) -> Vector3:
	var yw := yaw_at(s)
	return Vector3(-sin(yw), 0, -cos(yw))

# ---------------------------------------------------------------- visuals
func _right(i: int) -> Vector3:
	return Vector3(cos(yaw[i]), 0, -sin(yaw[i]))

func _p(i: int, x: float, y: float) -> Vector3:
	return pos[i] + _right(i) * x + Vector3(0, y, 0)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, nrm: Vector3) -> void:
	st.set_color(col); st.set_normal(nrm); st.add_vertex(a)
	st.set_color(col); st.set_normal(nrm); st.add_vertex(b)
	st.set_color(col); st.set_normal(nrm); st.add_vertex(c)
	st.set_color(col); st.set_normal(nrm); st.add_vertex(a)
	st.set_color(col); st.set_normal(nrm); st.add_vertex(c)
	st.set_color(col); st.set_normal(nrm); st.add_vertex(d)

func _strip(st: SurfaceTool, i: int, xa: float, xb: float, y: float, col: Color, ya := 0.0, yb := 0.0) -> void:
	_quad(st, _p(i, xa, y + ya), _p(i, xb, y + ya), _p(i + 1, xb, y + yb), _p(i + 1, xa, y + yb), col, Vector3.UP)

func _wall(st: SurfaceTool, i: int, x: float, y0: float, y1: float, col: Color) -> void:
	var nx := _right(i) * (-signf(x))
	_quad(st, _p(i, x, y0), _p(i, x, y1), _p(i + 1, x, y1), _p(i + 1, x, y0), col, nx)

func _ground_dy(i: int) -> float:
	# valley under bridges: ground sinks smoothly
	var best := 0.0
	for k in range(-10, 11, 2):
		var j := i + k
		if j >= 0 and j < n and (feat[j] & F_BRIDGE):
			best = maxf(best, 1.0 - absf(float(k)) / 12.0)
	return -14.0 * smoothstep(0.0, 0.8, best)

static func _ground_cols(e: int) -> Array:
	match e:
		1: return [Color(0.36, 0.36, 0.40), Color(0.33, 0.33, 0.37)]
		2: return [Color(0.80, 0.66, 0.42), Color(0.76, 0.62, 0.39)]
		_: return [Color(0.30, 0.47, 0.22), Color(0.27, 0.43, 0.20)]

static func tunnel_f(f: int) -> bool:
	return (f & F_TUNNEL) != 0

static func _beam(a: Vector3, b: Vector3, th: float) -> Transform3D:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x * th, y * d.length(), z * th), (a + b) * 0.5)

func _window_mat() -> StandardMaterial3D:
	if _win_mat != null:
		return _win_mat
	var alb := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var emi := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	alb.fill(Color(1, 1, 1))
	emi.fill(Color(0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for cy in 8:
		for cx in 8:
			var lit := r.randf() < 0.55
			var wc: Color = [Color(1.0, 0.8, 0.45), Color(1.0, 0.9, 0.65), Color(0.6, 0.85, 1.0)][r.randi() % 3]
			for py in range(cy * 32 + 8, cy * 32 + 24):
				for px in range(cx * 32 + 6, cx * 32 + 26):
					alb.set_pixel(px, py, Color(0.16, 0.2, 0.28))
					if lit:
						emi.set_pixel(px, py, wc)
	_win_mat = StandardMaterial3D.new()
	_win_mat.vertex_color_use_as_albedo = true
	_win_mat.albedo_texture = ImageTexture.create_from_image(alb)
	_win_mat.uv1_triplanar = true
	_win_mat.uv1_world_triplanar = true
	_win_mat.uv1_scale = Vector3(0.045, 0.045, 0.045)
	_win_mat.roughness = 0.7
	_win_mat.emission_enabled = true
	_win_mat.emission_texture = ImageTexture.create_from_image(emi)
	_win_mat.emission_energy_multiplier = 2.4 if night else 0.0
	return _win_mat

func _sign_material() -> StandardMaterial3D:
	if _sign_mat != null:
		return _sign_mat
	_sign_mat = StandardMaterial3D.new()
	_sign_mat.vertex_color_use_as_albedo = true
	_sign_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sign_mat.albedo_color = Color(1.7, 1.7, 1.7) if night else Color(1, 1, 1)
	return _sign_mat

func build_visuals(parent: Node3D) -> void:
	var mat: Material
	var puddle_mat: Material
	if wet and refl != null:
		var sh: Shader = load("res://assets/road_wet.gdshader")
		var rm := ShaderMaterial.new()
		rm.shader = sh
		rm.set_shader_parameter("refl", refl)
		var pm := ShaderMaterial.new()
		pm.shader = sh
		pm.set_shader_parameter("refl", refl)
		pm.set_shader_parameter("puddle", true)
		pm.render_priority = 1
		road_mats = [rm, pm]
		mat = rm
		puddle_mat = pm
	else:
		var sm := StandardMaterial3D.new()
		sm.vertex_color_use_as_albedo = true
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.roughness = 0.5 if wet else 0.95
		if wet:
			sm.metallic_specular = 0.9
		var pu := StandardMaterial3D.new()
		pu.vertex_color_use_as_albedo = true
		pu.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pu.roughness = 0.03
		pu.metallic = 0.3
		pu.metallic_specular = 1.0
		pu.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat = sm
		puddle_mat = pu
	var mumbai := str(def.get("route", "")) == "mumbai"
	var sph_mesh := SphereMesh.new()
	sph_mesh.radius = 0.5; sph_mesh.height = 1.0; sph_mesh.radial_segments = 7; sph_mesh.rings = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = int(def.get("seed", 1)) * 7919
	var tree_mesh := CylinderMesh.new()
	tree_mesh.top_radius = 0.0; tree_mesh.bottom_radius = 1.0; tree_mesh.height = 1.0; tree_mesh.radial_segments = 6; tree_mesh.rings = 1
	var box_mesh := BoxMesh.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = 0.5; cyl_mesh.bottom_radius = 0.5; cyl_mesh.height = 1.0; cyl_mesh.radial_segments = 6; cyl_mesh.rings = 1
	var c0 := 0
	while c0 < n - 1:
		var c1 := mini(c0 + CHUNK, n - 1)
		var node := Node3D.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var st2 := SurfaceTool.new()
		st2.begin(Mesh.PRIMITIVE_TRIANGLES)
		var props: Dictionary = {"tree": [], "box": [], "cyl": [], "sph": [], "bld": [], "sign": []}
		for i in range(c0, c1):
			var alt := (i / 4) % 2
			var f := feat[i]
			var e := envs[i]
			var gc: Array = _ground_cols(e)
			var gdy := _ground_dy(i)
			var gdy2 := _ground_dy(i + 1)
			# road
			var rc := Color(0.17, 0.17, 0.19) if alt == 0 else Color(0.19, 0.19, 0.215)
			_strip(st, i, -ROAD_HALF, ROAD_HALF, 0.0, rc)
			var shoulder := Color(0.30, 0.30, 0.32) if alt == 0 else Color(0.27, 0.27, 0.29)
			_strip(st, i, -BARRIER, -ROAD_HALF, 0.0, shoulder)
			var in_sc := shortcut.y > 0.0 and float(i) * STEP >= shortcut.x and float(i) * STEP <= shortcut.y
			if in_sc:
				_strip(st, i, BARRIER, DIRT_OUT, 0.0, Color(0.52, 0.38, 0.24) if alt == 0 else Color(0.48, 0.35, 0.22))
				_strip(st, i, ROAD_HALF, BARRIER, 0.0, Color(0.42, 0.34, 0.26))
			else:
				_strip(st, i, ROAD_HALF, BARRIER, 0.0, shoulder)
			if e != 1 and not tunnel_f(f) and not mumbai:
				for wx in [-1.2, 0.0, 1.2]:
					_strip(st, i, BARRIER + 5.0 + wx - 0.025, BARRIER + 5.0 + wx + 0.025, 8.5, Color(0.05, 0.05, 0.06))
			# lane marks
			if i % 3 == 0:
				for lx in [-4.0, 0.0, 4.0]:
					_strip(st, i, lx - 0.12, lx + 0.12, 0.03, Color(0.85, 0.85, 0.8))
			_strip(st, i, -ROAD_HALF + 0.1, -ROAD_HALF + 0.35, 0.03, Color(0.9, 0.9, 0.85))
			_strip(st, i, ROAD_HALF - 0.35, ROAD_HALF - 0.1, 0.03, Color(0.9, 0.9, 0.85))
			var tcl := rc * 0.78
			for lx2 in LANES:
				_strip(st, i, lx2 - 0.85, lx2 - 0.4, 0.012, tcl)
				_strip(st, i, lx2 + 0.4, lx2 + 0.85, 0.012, tcl)
			var hh := (i * 7919 + int(def.get("seed", 1)) * 131) % 211
			if hh < 6:
				var px := float(hh) * 2.5 - 7.0
				_strip(st, i, px, px + 1.8, 0.016, rc * (1.35 if hh % 2 == 0 else 0.6))
			elif hh == 20 or hh == 21:
				_strip(st, i, -6.0 + float(hh - 20) * 6.0 + 0.2, -6.0 + float(hh - 20) * 6.0 + 0.32, 0.017, rc * 0.5)
			if wet and hh >= 40 and hh < 52:
				var pxc: float = LANES[hh % 4] + float((hh * 7) % 20) * 0.1 - 1.0
				var ln := 3.0 + float(hh % 5)
				var pc := Color(0.04, 0.05, 0.09, 0.78)
				var ia := i
				_quad(st2, _p(ia, pxc - 1.0, 0.025), _p(ia, pxc + 1.0, 0.025), _p(ia + 1, pxc + 1.0, 0.025), _p(ia + 1, pxc - 1.0, 0.025), pc, Vector3.UP)
			var bridge: bool = (f & F_BRIDGE) != 0
			var tunnel: bool = (f & F_TUNNEL) != 0
			var inter: bool = (f & F_INTER) != 0
			# ground (sinks around bridges)
			if not bridge:
				var gcol: Color = gc[alt]
				_quad(st, _p(i, -140.0, -0.05 + gdy), _p(i, -BARRIER, -0.05), _p(i + 1, -BARRIER, -0.05), _p(i + 1, -140.0, -0.05 + gdy2), gcol, Vector3.UP)
				var rx0 := DIRT_OUT if in_sc else BARRIER
				if mumbai and not tunnel and not inter:
					_strip(st, i, BARRIER, BARRIER + 9.0, -0.05, Color(0.56, 0.54, 0.5) if alt == 0 else Color(0.5, 0.48, 0.45))
					_wall(st, i, BARRIER + 9.0, -2.4, -0.05, Color(0.4, 0.4, 0.42))
					_strip(st, i, BARRIER + 9.0, BARRIER + 320.0, -2.4, Color(0.02, 0.07, 0.15) if night else Color(0.12, 0.36, 0.5))
				else:
					_quad(st, _p(i, rx0, -0.05), _p(i, 140.0, -0.05 + gdy), _p(i + 1, 140.0, -0.05 + gdy2), _p(i + 1, rx0, -0.05), gcol, Vector3.UP)
			# barriers / walls
			var bcol := Color(0.78, 0.78, 0.8) if (i / 2) % 2 == 0 else Color(0.62, 0.62, 0.66)
			if tunnel:
				var tcol := Color(0.42, 0.42, 0.46)
				_wall(st, i, -BARRIER - 0.2, 0.0, 6.2, tcol)
				_wall(st, i, BARRIER + 0.2, 0.0, 6.2, tcol)
				_strip(st, i, -BARRIER - 0.2, BARRIER + 0.2, 6.2, Color(0.22, 0.22, 0.26))
				if i % 4 == 0:
					_strip(st, i, -1.0, 1.0, 6.15, Color(1.0, 0.95, 0.75))
					_wall(st, i, -BARRIER - 0.15, 3.2, 3.5, Color(1.0, 0.8, 0.3))
					_wall(st, i, BARRIER + 0.15, 3.2, 3.5, Color(1.0, 0.8, 0.3))
			elif not inter:
				var hgt := 1.3 if bridge else 0.9
				_wall(st, i, -BARRIER, 0.0, hgt, bcol)
				_strip(st, i, -BARRIER - 0.3, -BARRIER + 0.3, hgt, bcol)
				if not in_sc:
					_wall(st, i, BARRIER, 0.0, hgt, bcol)
					_strip(st, i, BARRIER - 0.3, BARRIER + 0.3, hgt, bcol)
			if bridge:
				_wall(st, i, -BARRIER, -1.6, 0.0, Color(0.5, 0.5, 0.54))
				_wall(st, i, BARRIER, -1.6, 0.0, Color(0.5, 0.5, 0.54))
				_strip(st, i, -BARRIER, BARRIER, -1.6, Color(0.4, 0.4, 0.44))
				if mumbai and i % 40 == 0:
					for sx in [-1.0, 1.0]:
						var pb := _p(i, (BARRIER + 0.6) * sx, 0.0)
						props["box"].append([Transform3D(Basis.from_scale(Vector3(1.4, 52.0, 1.4)), pb + Vector3(0, 26.0, 0)), Color(0.82, 0.82, 0.84)])
						var top := pb + Vector3(0, 48.0, 0)
						for k in range(1, 8):
							for dd in [-1, 1]:
								var tgt := _p(clampi(i + dd * k * 5, 0, n - 1), (BARRIER - 0.3) * sx, 1.3)
								props["box"].append([_beam(top - Vector3(0, float(k) * 1.2, 0), tgt, 0.12), Color(0.85, 0.85, 0.88)])
				if i % 8 == 0:
					for sx in [-1.0, 1.0]:
						var pp := _p(i, 5.0 * sx, -9.0 + _ground_dy(i) * 0.0)
						props["box"].append([Transform3D(Basis.from_scale(Vector3(1.8, 16.0, 1.8)), pp + Vector3(0, -8.0, 0)), Color(0.55, 0.55, 0.58)])
		# intersections handled per chunk
		for ic in inters:
			var ii := int(ic / STEP)
			if ii >= c0 and ii < c1:
				var cpos := _p(ii, 0.0, 0.04)
				var rt := _right(ii)
				var fw := Vector3(-sin(yaw[ii]), 0, -cos(yaw[ii]))
				_quad(st, cpos - rt * 90.0 - fw * 7.0, cpos + rt * 90.0 - fw * 7.0, cpos + rt * 90.0 + fw * 7.0, cpos - rt * 90.0 + fw * 7.0, Color(0.19, 0.19, 0.21), Vector3.UP)
				for k in range(-20, 21):
					if absf(k * 4.0) > 9.0:
						_quad(st, cpos + rt * (k * 4.0 - 1.0) - fw * 0.15 + Vector3(0, 0.02, 0), cpos + rt * (k * 4.0 + 1.0) - fw * 0.15 + Vector3(0, 0.02, 0), cpos + rt * (k * 4.0 + 1.0) + fw * 0.15 + Vector3(0, 0.02, 0), cpos + rt * (k * 4.0 - 1.0) + fw * 0.15 + Vector3(0, 0.02, 0), Color(0.8, 0.8, 0.75), Vector3.UP)
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var base: Vector3 = cpos + rt * (11.5 * sx) + fw * (9.0 * sz)
						props["box"].append([Transform3D(Basis.from_scale(Vector3(0.3, 6.0, 0.3)), base + Vector3(0, 3.0, 0)), Color(0.2, 0.2, 0.22)])
						props["box"].append([Transform3D(Basis.from_scale(Vector3(0.9, 2.2, 0.9)), base + Vector3(0, 6.4, 0)), Color(0.9, 0.2, 0.15)])
		# finish line checker
		var fi := int(finish_s / STEP)
		if fi >= c0 and fi < c1:
			for k in 16:
				for r in 2:
					var col := Color(0.95, 0.95, 0.95) if (k + r) % 2 == 0 else Color(0.08, 0.08, 0.08)
					var xa := -ROAD_HALF + k
					var ia := fi + r
					_quad(st, _p(ia, xa, 0.05), _p(ia, xa + 1.0, 0.05), _p(ia + 1, xa + 1.0, 0.05), _p(ia + 1, xa, 0.05), col, Vector3.UP)
		# scenery
		var step := 3
		for i in range(c0, c1, step):
			if feat[i] != 0:
				continue
			var e2 := envs[i]
			var gdy2 := _ground_dy(i)
			if gdy2 < -0.5:
				continue
			for side in [-1.0, 1.0]:
				if side > 0 and shortcut.y > 0.0 and float(i) * STEP >= shortcut.x - 20.0 and float(i) * STEP <= shortcut.y + 20.0:
					continue
				if e2 == 1:
					if rng.randf() < 0.62:
						var w := rng.randf_range(9.0, 18.0)
						var h := rng.randf_range(10.0, 48.0)
						var xo: float = rng.randf_range(16.0, 46.0) * side
						var base := _p(i, xo, 0.0)
						var shade := rng.randf_range(0.35, 0.8)
						var tint: Color = [Color(0.9, 0.85, 0.75), Color(0.7, 0.78, 0.88), Color(0.85, 0.7, 0.65), Color(0.75, 0.75, 0.78)][rng.randi() % 4]
						props["bld"].append([Transform3D(Basis.from_euler(Vector3(0, yaw[i], 0)).scaled_local(Vector3(w, h, rng.randf_range(10.0, 18.0))), base + Vector3(0, h * 0.5, 0)), Color(tint.r * shade, tint.g * shade, tint.b * shade)])
					var sg: Color = [Color(1.0, 0.25, 0.2), Color(0.2, 0.8, 1.0), Color(1.0, 0.8, 0.1), Color(0.9, 0.3, 0.9), Color(0.3, 1.0, 0.5)][rng.randi() % 5]
					if i % 6 == 0 and not (mumbai and side > 0):
						var shp := _p(i, 14.0 * side, 0.0)
						var bas := Basis.from_euler(Vector3(0, yaw[i], 0))
						props["box"].append([Transform3D(bas.scaled_local(Vector3(5.0, 3.6, 7.0)), shp + Vector3(0, 1.8, 0)), Color(0.55, 0.5, 0.45) * rng.randf_range(0.7, 1.2)])
						var face := _p(i, 11.4 * side, 3.9)
						props["sign"].append([Transform3D(bas.scaled_local(Vector3(0.25, 0.9, 4.2)), face), sg])
					if i % 15 == 0 and not (mumbai and side > 0):
						var bp := _p(i, 17.0 * side, 0.0)
						var bas2 := Basis.from_euler(Vector3(0, yaw[i], 0))
						props["box"].append([Transform3D(bas2.scaled_local(Vector3(0.4, 10.0, 0.4)), bp + Vector3(0, 5.0, 0)), Color(0.3, 0.3, 0.33)])
						props["sign"].append([Transform3D(bas2.scaled_local(Vector3(0.3, 4.2, 9.0)), bp + Vector3(0, 11.0, 0)), sg])
					if i % 12 == 3 and not (mumbai and side > 0):
						var cp := _p(i, 12.2 * side, 0.0)
						var bas3 := Basis.from_euler(Vector3(0, yaw[i], 0))
						var pcol: Color = [Color(0.8, 0.15, 0.15), Color(0.15, 0.35, 0.75), Color(0.85, 0.85, 0.85), Color(0.2, 0.2, 0.22)][rng.randi() % 4]
						props["box"].append([Transform3D(bas3.scaled_local(Vector3(1.8, 0.7, 4.2)), cp + Vector3(0, 0.6, 0)), pcol])
						props["box"].append([Transform3D(bas3.scaled_local(Vector3(1.6, 0.55, 2.2)), cp + Vector3(0, 1.2, 0.2)), Color(0.1, 0.12, 0.16)])
					if mumbai and side > 0:
						var tb := _p(i, BARRIER + 10.6, -1.3)
						props["box"].append([Transform3D(Basis.from_euler(Vector3(rng.randf() * 3.0, rng.randf() * 3.0, rng.randf() * 3.0)).scaled_local(Vector3(2.1, 2.1, 2.1)), tb), Color(0.55, 0.55, 0.57)])
					if i % 9 == 0:
						var lb := _p(i, 10.6 * side, 0.0)
						props["box"].append([Transform3D(Basis.from_scale(Vector3(0.25, 7.5, 0.25)), lb + Vector3(0, 3.75, 0)), Color(0.45, 0.45, 0.5)])
				elif e2 == 2:
					if rng.randf() < 0.45:
						var xo2: float = rng.randf_range(14.0, 70.0) * side
						var base2 := _p(i, xo2, 0.0)
						var sc := rng.randf_range(1.5, 5.0)
						props["box"].append([Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf() * 6.0, rng.randf() * 0.4)).scaled_local(Vector3(sc * 1.4, sc, sc * 1.1)), base2 + Vector3(0, sc * 0.3, 0)), Color(0.58, 0.40, 0.26) * rng.randf_range(0.8, 1.15)])
					if rng.randf() < 0.12:
						var base3 := _p(i, rng.randf_range(14.0, 50.0) * side, 0.0)
						var hh := rng.randf_range(2.5, 5.0)
						props["cyl"].append(Transform3D(Basis.from_scale(Vector3(0.7, hh, 0.7)), base3 + Vector3(0, hh * 0.5, 0)))
				else:
					if rng.randf() < 0.55:
						var xo3: float = rng.randf_range(13.0, 75.0) * side
						var base4 := _p(i, xo3, 0.0)
						var ht := rng.randf_range(5.0, 11.0)
						if rng.randf() < 0.5:
							props["tree"].append(Transform3D(Basis.from_scale(Vector3(ht * 0.28, ht, ht * 0.28)), base4 + Vector3(0, ht * 0.5, 0)))
						else:
							var cr := ht * 0.4
							props["box"].append([Transform3D(Basis.from_scale(Vector3(0.45, ht * 0.55, 0.45)), base4 + Vector3(0, ht * 0.27, 0)), Color(0.32, 0.22, 0.14)])
							props["sph"].append([Transform3D(Basis.from_scale(Vector3(cr * 1.9, cr * 1.5, cr * 1.9)), base4 + Vector3(0, ht * 0.7, 0)), Color(0.16, 0.38, 0.14) * rng.randf_range(0.8, 1.3)])
							props["sph"].append([Transform3D(Basis.from_scale(Vector3(cr * 1.3, cr * 1.1, cr * 1.3)), base4 + Vector3(cr * 0.5, ht * 0.95, 0.4)), Color(0.2, 0.44, 0.16) * rng.randf_range(0.8, 1.3)])
					if i % 12 == 0 and side > 0:
						var pl := _p(i, BARRIER + 5.0, 0.0)
						props["box"].append([Transform3D(Basis.from_euler(Vector3(0, yaw[i], 0)).scaled_local(Vector3(0.3, 9.0, 0.3)), pl + Vector3(0, 4.5, 0)), Color(0.35, 0.28, 0.22)])
						props["box"].append([Transform3D(Basis.from_euler(Vector3(0, yaw[i], 0)).scaled_local(Vector3(3.0, 0.2, 0.2)), pl + Vector3(0, 8.6, 0)), Color(0.3, 0.24, 0.2)])
		var rmi := _instance(st, mat)
		node.add_child(rmi)
		if refl != null:
			rmi.layers = 2
		if wet:
			var pmi := _instance(st2, puddle_mat)
			if refl != null:
				pmi.layers = 2
			node.add_child(pmi)
		_add_multi(node, tree_mesh, props["tree"], Color(0.14, 0.34, 0.16), rng)
		_add_multi(node, sph_mesh, props["sph"], Color(0.16, 0.38, 0.14), rng)
		_add_multi(node, box_mesh, props["bld"], Color(0.62, 0.62, 0.66), rng, _window_mat())
		_add_multi(node, box_mesh, props["sign"], Color(1, 1, 1), rng, _sign_material())
		_add_multi(node, box_mesh, props["box"], Color(0.62, 0.62, 0.66), rng)
		_add_multi(node, cyl_mesh, props["cyl"], Color(0.2, 0.5, 0.25), rng)
		parent.add_child(node)
		chunks.append([node, float(c0) * STEP, float(c1) * STEP])
		c0 = c1
	# water under bridge zones
	var bi := -1
	for i in range(n):
		if feat[i] & F_BRIDGE:
			if bi < 0:
				bi = i
		elif bi >= 0:
			_water(parent, bi, i)
			bi = -1
	_add_gates(parent)

func _instance(st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _add_multi(parent: Node3D, mesh: Mesh, items: Array, default_col: Color, rng: RandomNumberGenerator, material: Material = null) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for k in items.size():
		var it: Variant = items[k]
		var c: Color = default_col * rng.randf_range(0.8, 1.2)
		if it is Array:
			mm.set_instance_transform(k, it[0])
			c = it[1]
		else:
			mm.set_instance_transform(k, it)
		c.a = 1.0
		mm.set_instance_color(k, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	mmi.material_override = material if material != null else m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)

func _water(parent: Node3D, i0: int, i1: int) -> void:
	var mid := (i0 + i1) / 2
	var pm := PlaneMesh.new()
	pm.size = Vector2(float(i1 - i0) * STEP * 1.6 + 400.0, float(i1 - i0) * STEP * 1.6 + 400.0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.35, 0.55)
	m.roughness = 0.15
	mi.material_override = m
	mi.position = pos[mid] + Vector3(0, -11.0, 0)
	parent.add_child(mi)

func _gate(parent: Node3D, s: float, col: Color, tall := 7.0) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var holder := Node3D.new()
	holder.position = pos_at(s)
	holder.rotation.y = yaw_at(s)
	parent.add_child(holder)
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, tall, 0.7)
		post.mesh = bm; post.material_override = m
		post.position = Vector3(10.4 * sx, tall * 0.5, 0)
		holder.add_child(post)
	var bar := MeshInstance3D.new()
	var bm2 := BoxMesh.new()
	bm2.size = Vector3(21.5, 1.1, 0.7)
	bar.mesh = bm2; bar.material_override = m
	bar.position = Vector3(0, tall, 0)
	holder.add_child(bar)

func _add_gates(parent: Node3D) -> void:
	_gate(parent, 20.0, Color(0.3, 0.8, 0.4))
	for cp in checkpoints:
		_gate(parent, float(cp), Color(0.25, 0.55, 1.0))
	_gate(parent, finish_s, Color(0.95, 0.95, 0.95), 7.5)
	if shortcut.y > 0.0:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.8, 0.1)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for off in [-160.0, -60.0]:
			var holder := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(4.0, 2.4, 0.3)
			holder.mesh = bm; holder.material_override = m
			holder.position = pos_at(shortcut.x + off, 12.0, 3.0)
			holder.rotation.y = yaw_at(shortcut.x + off)
			parent.add_child(holder)
			var pole := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.3, 4.0, 0.3)
			pole.mesh = pm; pole.material_override = m
			pole.position = pos_at(shortcut.x + off, 12.0, 1.5)
			parent.add_child(pole)

func update_visibility(s: float, view := 950.0) -> void:
	for c in chunks:
		(c[0] as Node3D).visible = c[2] > s - 120.0 and c[1] < s + view
