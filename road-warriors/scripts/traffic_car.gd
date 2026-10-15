class_name TrafficCar
extends Node3D
## Ambient traffic vehicle: constant-speed lane follower (primitive models).

const KINDS := {
	"car": {"len": 4.3, "wid": 1.8, "spd": [20.0, 30.0], "w": 40},
	"suv": {"len": 4.7, "wid": 2.0, "spd": [19.0, 28.0], "w": 20},
	"van": {"len": 5.3, "wid": 2.0, "spd": [17.0, 25.0], "w": 14},
	"truck": {"len": 10.0, "wid": 2.5, "spd": [14.0, 21.0], "w": 12},
	"bus": {"len": 11.5, "wid": 2.6, "spd": [15.0, 22.0], "w": 6},
	"bike": {"len": 2.0, "wid": 0.8, "spd": [26.0, 36.0], "w": 8},
}
const PALETTE := [Color(0.8, 0.15, 0.15), Color(0.15, 0.35, 0.75), Color(0.85, 0.85, 0.85), Color(0.2, 0.2, 0.22), Color(0.85, 0.7, 0.15),
	Color(0.2, 0.55, 0.3), Color(0.6, 0.6, 0.65), Color(0.9, 0.5, 0.15)]

var kind := "car"
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
	var L: float = d["len"]
	var W: float = d["wid"]
	match k:
		"car", "suv":
			var h := 0.8 if k == "car" else 1.05
			_box(Vector3(W, h, L), Vector3(0, 0.3 + h * 0.5, 0), col)
			_box(Vector3(W * 0.9, 0.6, L * 0.5), Vector3(0, 0.3 + h + 0.3, 0.1), col.darkened(0.25))
		"van":
			_box(Vector3(W, 1.9, L), Vector3(0, 1.25, 0), col)
		"truck":
			_box(Vector3(W, 2.0, 2.6), Vector3(0, 1.4, -L * 0.5 + 1.4), col)
			_box(Vector3(W, 2.9, L - 3.2), Vector3(0, 2.0, 1.6), Color(0.85, 0.85, 0.82))
		"bus":
			_box(Vector3(W, 2.9, L), Vector3(0, 2.0, 0), Color(0.85, 0.65, 0.12))
			_box(Vector3(W + 0.02, 0.7, L * 0.9), Vector3(0, 2.4, 0), Color(0.15, 0.2, 0.28))
		"bike":
			_box(Vector3(0.3, 0.8, L), Vector3(0, 0.6, 0), col)
			_box(Vector3(0.4, 0.7, 0.4), Vector3(0, 1.3, 0.2), Color(0.15, 0.15, 0.18))
	# wheels & tail lights
	if k != "bike":
		for sz in [-0.33, 0.33]:
			for sx in [-1.0, 1.0]:
				_box(Vector3(0.25, 0.7, 0.7), Vector3(sx * (W * 0.5), 0.35, L * sz), Color(0.05, 0.05, 0.05))
		var tl := StandardMaterial3D.new()
		tl.albedo_color = Color(1, 0.1, 0.1)
		tl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for sx in [-0.38, 0.38]:
			var m := _box(Vector3(0.4, 0.2, 0.08), Vector3(W * sx, 0.9 if k in ["car", "suv"] else 1.1, L * 0.5 + 0.02), Color.RED)
			m.material_override = tl
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
	s += v * dt
	if kind == "bike":
		weave_ph += dt * 0.9
		x = lane_x + sin(weave_ph) * 1.7
	else:
		x = lane_x

func place_in_world(track: Track) -> void:
	position = track.pos_at(s, x)
	rotation = Vector3(atan(track.slope_at(s)), track.yaw_at(s), 0.0)
