class_name Compounds
extends RefCounted
## Fills the empty frontage between roads and buildings: compound walls (with gate gaps), hedges,
## scrub, soil/dry-grass blotches; plus procedural neem trees and a cloud dome.

const TEX := "res://assets/textures/indian/"
const WALL_COLS := ["e9dcc0", "d9c9a3", "efe6d2", "cdbfa0", "e2c9b8", "d3d0c4", "e8d9a8", "c9b99a"]
static var _mats := {}

static func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var key := "%s_%s" % [c.to_html(), rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[key] = m
	return _mats[key]

# ------------------------------------------------------------------ queries
class BldIndex:
	var cells := {}
	func _init(list: Array) -> void:
		for b in list:
			var k := Vector2i(int(floor(float(b[0]) / 24.0)), int(floor(float(b[1]) / 24.0)))
			if not cells.has(k):
				cells[k] = []
			cells[k].append(b)
	func near(p: Vector2, margin: float) -> bool:
		var c := Vector2i(int(floor(p.x / 24.0)), int(floor(p.y / 24.0)))
		for i in range(c.x - 1, c.x + 2):
			for j in range(c.y - 1, c.y + 2):
				var arr = cells.get(Vector2i(i, j))
				if arr == null:
					continue
				for b in arr:
					var d := Vector2(p.x - float(b[0]), p.y - float(b[1]))
					var yaw := float(b[2])
					var s := sin(yaw)
					var co := cos(yaw)
					var lx := d.x * co - d.y * s
					var lz := d.x * s + d.y * co
					if absf(lx) < float(b[3]) * 0.5 + margin and absf(lz) < float(b[4]) * 0.5 + margin:
						return true
		return false

# ------------------------------------------------------------------ walls, hedges, plot detail
static func build(world: Node3D, polylines: Array, rng: RandomNumberGenerator, col_body: StaticBody3D, high: bool, skip: Callable, buildings: Array) -> void:
	var bi := BldIndex.new(buildings)
	var walls := []     # [Transform3D, Color]
	var caps := []
	var hedges := []
	var blobs := []     # [pos Vector3, size, Color]
	var bushes := []    # Transform3D
	var shapes := []    # [pos, yaw, size]
	var pi := 0
	for rp in polylines:
		pi += 1
		var c: String = rp["c"]
		if c == "track" or c == "service":
			continue
		var pts: PackedVector2Array = rp["pts"]
		var hw: float = float(rp["w"]) * 0.5
		var off := hw + (3.0 if c == "secondary" else 2.4)
		for side in [-1.0, 1.0]:
			var run_left := 0
			var style := 0   # 0 open, 1 wall, 2 hedge
			var h := 1.4
			var col := Color.WHITE
			var carry := 0.0
			for i in pts.size() - 1:
				var a := pts[i]
				var b := pts[i + 1]
				var L := a.distance_to(b)
				if L < 0.5:
					continue
				var d := (b - a) / L
				var n := Vector2(-d.y, d.x) * float(side)
				var t := carry
				while t < L:
					t += 4.0
					if t > L:
						break
					run_left -= 1
					if run_left <= 0:
						var r := rng.randf()
						style = 1 if r < 0.55 else (2 if r < 0.7 else 0)
						run_left = rng.randi_range(5, 16)
						h = rng.randf_range(1.0, 1.9)
						col = Color(WALL_COLS[rng.randi() % WALL_COLS.size()])
						if rng.randf() < 0.3:
							col = col.darkened(0.12)
					var p := a + d * (t - 2.0) + n * off
					var okp: bool = skip.is_null() or not skip.call(p)
					okp = okp and float(world.nearest_road(p, 2)["edge"]) > 1.8 and not bi.near(p, 5.0)
					okp = okp and float(world.nearest_road(p + d * 2.2, 2)["edge"]) > 1.8 and float(world.nearest_road(p - d * 2.2, 2)["edge"]) > 1.8
					# gate gap near the end of a run
					if run_left <= 2 and run_left >= 0 and style != 0:
						okp = false
					if style == 0 or not okp:
						if okp and rng.randf() < 0.12:
							var q := p + n * rng.randf_range(3.0, 12.0)
							if float(world.nearest_road(q, 2)["edge"]) > 2.0 and not bi.near(q, 2.0):
								_blob(blobs, bushes, rng, q, high)
						continue
					var yaw := atan2(-d.y, d.x)
					if style == 1:
						walls.append([Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(4.1, h, 0.22)), Vector3(p.x, h * 0.5, p.y)), col])
						caps.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(4.15, 0.1, 0.38)), Vector3(p.x, h + 0.05, p.y)))
						shapes.append([Vector3(p.x, h * 0.5, p.y), yaw, Vector3(4.1, h, 0.22)])
					else:
						hedges.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(4.2, 1.0, 1.0)), Vector3(p.x, 0.55, p.y)))
						shapes.append([Vector3(p.x, 0.55, p.y), yaw, Vector3(4.2, 1.1, 0.6)])
					if rng.randf() < 0.5:
						var q2 := p + n * rng.randf_range(3.0, 14.0) + d * rng.randf_range(-3.0, 3.0)
						if float(world.nearest_road(q2, 2)["edge"]) > 2.0 and not bi.near(q2, 2.0):
							_blob(blobs, bushes, rng, q2, high)
				carry = t - L
	_emit_walls(world, walls, caps, hedges, shapes, col_body)
	_emit_blobs(world, blobs, bushes)

static func _blob(blobs: Array, bushes: Array, rng: RandomNumberGenerator, q: Vector2, high: bool) -> void:
	var kinds := [Color("6f5a3c"), Color("8a7a52"), Color("a39463"), Color("5d6b3a"), Color("b8a883"), Color("4d4234")]
	blobs.append([Vector3(q.x, 0.05, q.y), rng.randf_range(4.0, 11.0), kinds[rng.randi() % kinds.size()]])
	if rng.randf() < (0.8 if high else 0.45):
		var s := rng.randf_range(0.6, 1.5)
		bushes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s * 1.3, s * 0.8, s * 1.3)), Vector3(q.x + rng.randf_range(-2, 2), 0.3 * s, q.y + rng.randf_range(-2, 2))))

static func _emit_walls(world: Node3D, walls: Array, caps: Array, hedges: Array, shapes: Array, col_body: StaticBody3D) -> void:
	if not walls.is_empty():
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(TEX + "plaster002_color.jpg")
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		m.uv1_scale = Vector3(0.5, 0.5, 0.5)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		_multimesh(world, BoxMesh.new(), walls.map(func(w): return w[0]), m, 380.0, walls.map(func(w): return w[1]))
		_multimesh(world, BoxMesh.new(), caps, _mat(Color("8c8a84"), 0.9), 300.0)
	if not hedges.is_empty():
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color("55663a")
		hm.roughness = 1.0
		_multimesh(world, BoxMesh.new(), hedges, hm, 300.0)
	var space := world.get_world_3d().space
	var chunks := {}
	for s in shapes:
		var k := Vector2i(int(floor(s[0].x / 220.0)), int(floor(s[0].z / 220.0)))
		if not chunks.has(k):
			chunks[k] = []
		chunks[k].append(s)
	for k in chunks:
		for s in chunks[k]:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = s[2]
			cs.shape = bs
			cs.transform = Transform3D(Basis(Vector3.UP, s[1]), s[0])
			col_body.add_child(cs)

static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array, mat: Material, vis_end: float, colors: Array = []) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = vis_end
	mmi.custom_aabb = AABB(Vector3(-3000, -2, -3000), Vector3(6000, 30, 6000))
	parent.add_child(mmi)

static func _emit_blobs(world: Node3D, blobs: Array, bushes: Array) -> void:
	if not blobs.is_empty():
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.85))
		g.set_color(1, Color(1, 1, 1, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		var m := StandardMaterial3D.new()
		m.albedo_texture = gt
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q := PlaneMesh.new()
		q.size = Vector2.ONE
		_multimesh(world, q, blobs.map(func(b): return Transform3D(Basis.from_scale(Vector3(b[1], 1.0, b[1] * 0.8)).rotated(Vector3.UP, fmod(b[0].x * 5.7, TAU)), b[0])), m, 240.0, blobs.map(func(b): return b[2]))
	if not bushes.is_empty():
		var s := SphereMesh.new()
		s.radius = 0.6
		s.height = 1.0
		s.radial_segments = 7
		s.rings = 4
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color("6b6a3a")
		bm.roughness = 1.0
		_multimesh(world, s, bushes, bm, 200.0)

# ------------------------------------------------------------------ neem trees
static func tree_meshes() -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	var greens := [Color("56693a"), Color("667a3f"), Color("4b5e34"), Color("7a8446"), Color("5a6b2e")]
	for v in 3:
		rng.seed = 900 + v * 17
		var am := ArrayMesh.new()
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.18
		trunk.bottom_radius = 0.34
		trunk.height = 3.2
		trunk.radial_segments = 7
		var st := SurfaceTool.new()
		st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)))
		st.set_material(_mat(Color("5a4636"), 0.95))
		st.commit(am)
		for k in 3:
			var cst := SurfaceTool.new()
			for j in 3:
				var sp := SphereMesh.new()
				sp.radius = 1.0
				sp.height = 2.0
				sp.radial_segments = 8
				sp.rings = 5
				var r := rng.randf_range(1.5, 2.5)
				var ang := rng.randf() * TAU
				var rad := rng.randf_range(0.2, 2.0)
				var pos := Vector3(cos(ang) * rad, rng.randf_range(3.3, 5.4), sin(ang) * rad)
				cst.append_from(sp, 0, Transform3D(Basis.from_scale(Vector3(r, r * 0.62, r)), pos))
			cst.set_material(_mat(greens[(v + k * 2) % greens.size()], 1.0))
			cst.commit(am)
		out.append(am)
	return out

# ------------------------------------------------------------------ cloud dome
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_front, fog_disabled, shadows_disabled;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform vec3 tint = vec3(1.0, 0.96, 0.9);
uniform float cover = 0.5;
uniform float speed = 0.004;
varying vec3 dir;
void vertex() { dir = normalize(VERTEX); }
void fragment() {
	vec3 d = normalize(dir);
	float h = max(d.y, 0.0);
	vec2 uv = d.xz / (h + 0.28) * 0.55 + vec2(TIME * speed, TIME * speed * 0.4);
	float n = texture(noise, uv).r * 0.62 + texture(noise, uv * 2.7 + 3.1).r * 0.38;
	float c = smoothstep(1.0 - cover, 1.0 - cover + 0.32, n);
	float edge = smoothstep(0.0, 0.14, h) * smoothstep(1.0, 0.82, h) ;
	float shade = mix(0.78, 1.05, texture(noise, uv * 1.3 + 7.0).r);
	ALBEDO = tint * shade;
	ALPHA = c * edge * 0.92;
}
"""

static func add_clouds(parent: Node3D, tod: int) -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = CLOUD_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012
	fn.fractal_octaves = 5
	fn.seed = 11
	nt.noise = fn
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	sm.set_shader_parameter("noise", nt)
	var tints := [Color(1.0, 0.9, 0.78), Color(1.0, 0.97, 0.92), Color(1.0, 0.7, 0.5), Color(0.75, 0.55, 0.6)]
	var t: Color = tints[clampi(tod, 0, 3)]
	sm.set_shader_parameter("tint", Vector3(t.r, t.g, t.b))
	sm.set_shader_parameter("cover", 0.55)
	var sp := SphereMesh.new()
	sp.radius = 700.0
	sp.height = 1400.0
	sp.radial_segments = 32
	sp.rings = 16
	var mi := MeshInstance3D.new()
	mi.mesh = sp
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-800, -800, -800), Vector3(1600, 1600, 1600))
	mi.set_script(preload("res://scripts/follow_camera.gd"))
	parent.add_child(mi)
	return mi
