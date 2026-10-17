class_name TrafficCar
extends Node3D
## Ambient traffic vehicle: constant-speed lane follower (primitive models).

const KINDS := {
	"car": {"len": 4.3, "wid": 1.8, "spd": [20.0, 30.0], "w": 40},
	"suv": {"len": 4.7, "wid": 2.0, "spd": [19.0, 28.0], "w": 20},
	"van": {"len": 5.3, "wid": 2.0, "spd": [17.0, 25.0], "w": 14},
	"truck": {"len": 10.0, "wid": 2.5, "spd": [14.0, 21.0], "w": 12},
	"bus": {"len": 11.5, "wid": 2.6, "spd": [15.0, 22.0], "w": 6},
	"auto": {"len": 2.6, "wid": 1.4, "spd": [12.0, 18.0], "w": 10},
	"bike": {"len": 2.0, "wid": 0.8, "spd": [26.0, 36.0], "w": 8},
}
const PALETTE := [Color(0.8, 0.15, 0.15), Color(0.15, 0.35, 0.75), Color(0.85, 0.85, 0.85), Color(0.2, 0.2, 0.22), Color(0.85, 0.7, 0.15),
	Color(0.2, 0.55, 0.3), Color(0.6, 0.6, 0.65), Color(0.9, 0.5, 0.15)]

var kind := "car"
static var night := false
var _brakes: Array[StandardMaterial3D] = []
var _glows: Array[MeshInstance3D] = []
var _braking := false
var s := 0.0
var x := 0.0
var lane_x := 0.0
var v := 20.0
var base_v := 20.0
var half_len := 2.0
var half_wid := 0.9
var weave_ph := 0.0
var prev_ds := 0.0
var passed_flag := false

static func pick_kind(rng: RandomNumberGenerator) -> String:
	var total := 0
	for k in KINDS:
		total += int(KINDS[k]["w"])
	var r := rng.randi_range(0, total - 1)
	for k in KINDS:
		r -= int(KINDS[k]["w"])
		if r < 0:
			return k
	return "car"

func build(k: String, rng: RandomNumberGenerator) -> void:
	kind = k
	var d: Dictionary = KINDS[k]
	half_len = float(d["len"]) * 0.5
	half_wid = float(d["wid"]) * 0.5
	var col: Color = PALETTE[rng.randi() % PALETTE.size()]
	for c in get_children():
		c.queue_free()
	_glows.clear()
	var L: float = d["len"]
	var W: float = d["wid"]
	var glass := Color(0.08, 0.1, 0.14)
	var dark := Color(0.05, 0.05, 0.05)
	_brakes.clear()
	match k:
		"car", "suv":
			var h := 0.62 if k == "car" else 0.85
			_box(Vector3(W, h, L), Vector3(0, 0.38 + h * 0.5, 0), col)
			var cab_h := 0.55 if k == "car" else 0.62
			var cab_l := L * (0.5 if k == "car" else 0.62)
			_box(Vector3(W * 0.88, cab_h, cab_l), Vector3(0, 0.38 + h + cab_h * 0.5, 0.18 if k == "car" else 0.35), glass)
			_box(Vector3(W * 0.9, 0.06, cab_l * 0.9), Vector3(0, 0.38 + h + cab_h + 0.02, 0.18 if k == "car" else 0.35), col.darkened(0.1))
			_box(Vector3(W * 0.96, 0.18, 0.2), Vector3(0, 0.42, -L * 0.5), dark)
			_box(Vector3(W * 0.96, 0.18, 0.2), Vector3(0, 0.42, L * 0.5), dark)
		"van":
			_box(Vector3(W, 1.6, L), Vector3(0, 1.2, 0), col)
			_box(Vector3(W * 0.92, 0.5, 1.2), Vector3(0, 1.75, -L * 0.5 + 0.7), glass)
		"truck":
			_box(Vector3(W, 2.1, 2.4), Vector3(0, 1.45, -L * 0.5 + 1.3), col)
			_box(Vector3(W * 0.9, 0.7, 0.1), Vector3(0, 1.9, -L * 0.5 + 0.1), glass)
			_box(Vector3(W, 0.3, L - 3.0), Vector3(0, 0.7, 1.5), Color(0.25, 0.25, 0.27))
			_box(Vector3(W * 0.98, 2.6, L - 3.1), Vector3(0, 2.2, 1.55), col.lightened(0.35) if col.v < 0.5 else Color(0.82, 0.8, 0.74))
			for i in 5:
				_box(Vector3(W * 0.99, 2.6, 0.06), Vector3(0, 2.2, -0.3 + i * (L - 3.4) / 4.4), Color(0.4, 0.4, 0.4))
		"bus":
			_box(Vector3(W, 3.0, L), Vector3(0, 2.0, 0), Color(0.85, 0.65, 0.12))
			_box(Vector3(W + 0.04, 0.9, L * 0.92), Vector3(0, 2.4, 0), glass)
			_box(Vector3(W + 0.04, 0.12, L), Vector3(0, 1.2, 0), Color(0.7, 0.1, 0.1))
			_box(Vector3(W * 0.8, 0.35, 0.06), Vector3(0, 3.25, -L * 0.5 + 0.1), Color(1, 0.8, 0.3))
		"auto":
			_box(Vector3(W, 0.7, L * 0.9), Vector3(0, 0.75, 0.1), Color(0.95, 0.8, 0.1))
			_box(Vector3(W * 0.92, 0.7, L * 0.6), Vector3(0, 1.45, 0.4), Color(0.1, 0.1, 0.1))
			_box(Vector3(W * 0.96, 0.08, L * 0.65), Vector3(0, 1.84, 0.4), Color(0.1, 0.1, 0.12))
			_box(Vector3(0.12, 0.6, 0.12), Vector3(0, 0.55, -L * 0.5 + 0.15), dark)
		"bike":
			_box(Vector3(0.3, 0.55, L * 0.85), Vector3(0, 0.6, 0), col)
			_box(Vector3(0.12, 0.3, 0.9), Vector3(0, 0.88, -0.2), dark)
			_box(Vector3(0.32, 0.65, 0.3), Vector3(0, 1.28, 0.15), Color(0.15, 0.15, 0.18))
			_box(Vector3(0.22, 0.2, 0.22), Vector3(0, 1.75, 0.15), Color(0.9, 0.5, 0.1))
	if k == "bike":
		for sz in [-0.4, 0.4]:
			_box(Vector3(0.14, 0.62, 0.62), Vector3(0, 0.31, L * sz), dark)
	elif k == "auto":
		_box(Vector3(0.14, 0.5, 0.5), Vector3(0, 0.25, -L * 0.5 + 0.3), dark)
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.14, 0.5, 0.5), Vector3(sx * W * 0.5, 0.25, L * 0.3), dark)
	else:
		for sz in [-0.33, 0.33]:
			for sx in [-1.0, 1.0]:
				_box(Vector3(0.25, 0.7, 0.7), Vector3(sx * (W * 0.5), 0.35, L * sz), dark)
				if k == "truck":
					_box(Vector3(0.25, 0.7, 0.7), Vector3(sx * (W * 0.5), 0.35, L * (sz + 0.12)), dark)
	var tl_h := 0.9 if k in ["car", "suv"] else (0.8 if k == "auto" else (0.9 if k == "bike" else 1.0))
	if k == "bus" or k == "truck" or k == "van":
		tl_h = 0.95
	var tls: Array = [-0.38, 0.38]
	if k == "bike":
		tls = [0.0]
	for sx in tls:
		var tl := StandardMaterial3D.new()
		tl.albedo_color = Color(0.45, 0.02, 0.02)
		tl.emission_enabled = true
		tl.emission = Color(1, 0.05, 0.05)
		tl.emission_energy_multiplier = 0.5
		tl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if false else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		var wl := 0.5 if k == "bike" else W
		var m := _box(Vector3(0.4 if k != "bike" else 0.16, 0.2, 0.08), Vector3(wl * sx, tl_h, L * 0.5 + 0.02), Color.RED)
		m.material_override = tl
		_brakes.append(tl)
	if night:
		var gt := Racer.glow_tex()
		for sx in tls:
			var wl2 := 0.5 if k == "bike" else W
			var q := MeshInstance3D.new()
			var qq := QuadMesh.new()
			qq.size = Vector2(1.6, 1.6)
			q.mesh = qq
			q.material_override = Racer.glow_mat(Color(1, 0.1, 0.05, 0.8), gt)
			q.position = Vector3(wl2 * sx, tl_h, L * 0.5 + 0.2)
			q.rotation.y = PI
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(q)
			_glows.append(q)
		for sx in [-0.34, 0.34]:
			var hq := MeshInstance3D.new()
			var hqq := QuadMesh.new()
			hqq.size = Vector2(1.4, 1.4)
			hq.mesh = hqq
			hq.material_override = Racer.glow_mat(Color(1, 0.95, 0.75, 0.7), gt)
			hq.position = Vector3(W * sx if k != "bike" else 0.0, 0.8, -L * 0.5 - 0.2)
			hq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(hq)
	var sh := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(W * 1.1, L * 1.05)
	sh.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0, 0, 0, 0.3)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sh.material_override = sm
	sh.rotation.x = -PI / 2
	sh.position.y = 0.04
	add_child(sh)
	var sp: Array = d["spd"]
	base_v = rng.randf_range(sp[0], sp[1])
	v = base_v
	weave_ph = rng.randf() * 6.28

func _box(size: Vector3, p: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Racer.mat(c, 0.55, 0.2)
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func step(dt: float, others: Array) -> void:
	var tv := base_v
	for o in others:
		if o == self:
			continue
		var ds: float = o.s - s
		if ds > 0.0 and ds < 26.0 + v and absf(o.x - x) < 1.6:
			tv = minf(tv, o.v * 0.97)
	v = move_toward(v, tv, 7.0 * dt)
	var br := v < base_v - 1.0
	if br != _braking:
		_braking = br
		for m in _brakes:
			m.emission_energy_multiplier = 4.0 if br else 0.5
		for g in _glows:
			g.scale = Vector3.ONE * (1.8 if br else 1.0)
	s += v * dt
	if kind == "bike":
		weave_ph += dt * 0.9
		x = lane_x + sin(weave_ph) * 1.7
	else:
		x = lane_x

func place_in_world(track: Track) -> void:
	position = track.pos_at(s, x)
	rotation = Vector3(atan(track.slope_at(s)), track.yaw_at(s), 0.0)
