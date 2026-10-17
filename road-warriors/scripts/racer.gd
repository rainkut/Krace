class_name Racer
extends Node3D
## One motorcycle + rider (player or AI): road-relative physics, damage, melee animation.

signal event(kind: String, data: Dictionary)

enum St { IDLE, RACING, OVERTAKING, DEFENDING, ATTACKING, AVOIDING_TRAFFIC, RECOVERING, CRASHED, FINISHING }
const ST_NAMES := ["IDLE", "RACING", "OVERTAKING", "DEFENDING", "ATTACKING", "AVOIDING_TRAFFIC", "RECOVERING", "CRASHED", "FINISHING"]

static var _mats: Dictionary = {}

var rname := "Rider"
var is_player := false
var arch := "balanced"
var color := Color.ORANGE
var body_style := 0
var stats: Dictionary = {}
var spd_mult := 1.0
var speed_cap := 0.0
var acc_mult := 1.0
var dmg_mult_out := 1.0
var aggr := 0.3
var mass := 1.0

var s := 0.0
var x := 0.0
var vx := 0.0
var v := 0.0
var steer_i := 0.0
var roll := 0.0
var state: int = St.IDLE
var health := 100.0
var max_health := 100.0
var cond := 100.0
var nitro := 50.0
var nitro_on := false
var atk_cd := 0.0
var invuln := 0.0
var crash_t := 0.0
var recover_t := 0.0
var weapon := "punch"
var weapon_dur := 0
var finished := false
var finish_time := 0.0
var eliminated := false
var place := 1
var grudge: Racer = null
var on_dirt := false
var scrape := false
static var SPRAY := ""
var sparks: CPUParticles3D
var spray: CPUParticles3D
var inp := {"steer": 0.0, "throttle": 1.0, "brake": 0.0, "nitro": false, "atk": 0, "kick": false, "flip": false, "spin": 0.0}
var anim_t := 1.0
var anim_side := 1
var anim_kick := false
var hit_flash := 0.0
var bump_t := 0.0
var score := 0.0
var drift_t := 0.0
var air_y := 0.0
var air_vy := 0.0
var airborne := false
var ramp_y := 0.0
var air_time := 0.0
var flip_rot := 0.0
var spin_rot := 0.0
var land_evt := {}

var model: Node3D
var bike3: Node3D
var rider_mesh: Node3D
var wheel_f: Node3D
var wheel_r: Node3D
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var _flashing := false
var glow_tail: MeshInstance3D
var flames: Array[MeshInstance3D] = []
var body_parts: Array[Node3D] = []
var _bob := 0.0
const BIKE_IDS := ["thunderbolt", "nightbreaker", "scrambler", "commuter", "streak"]
const BWR := [0.33, 0.30, 0.38, 0.27, 0.30]
# per-bike: shoulder height, shoulder z, tail light (y,z), exhaust x list + (y,z)
const BSH := [1.50, 1.33, 1.61, 1.41, 1.33]
const BSZ := [0.15, 0.28, 0.09, 0.16, 0.12]
const BTAIL := [Vector3(0, 0.50, 1.06), Vector3(0, 0.44, 1.12), Vector3(0, 0.66, 1.10), Vector3(0, 0.46, 0.88), Vector3(0, 0.72, 1.22)]
const BEXH := [[Vector3(0.20, 0.36, 1.05)], [Vector3(-0.21, 0.40, 0.99), Vector3(0.21, 0.40, 0.99)], [Vector3(0.23, 0.845, 1.0)], [Vector3(0.17, 0.36, 0.86)], [Vector3(0, 0.625, 1.0)]]
static var _tex := {}
static var _glow_tex: GradientTexture2D

static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]

static func glow_tex() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 64
		_glow_tex.height = 64
	return _glow_tex

static func glow_mat(c: Color, tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = tex
	m.albedo_color = c
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m

func _glow(c: Color, size: float, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = glow_tex()
	m.albedo_color = c
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(mi)
	return mi

var torso: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var rider: Node3D
var head_mat: StandardMaterial3D
var wpn_nodes: Array[Node3D] = []
var rider_vel := Vector3.ZERO
var tumble := 0.0
var _spin := 0.0

static func mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [c.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]

func setup(info: Dictionary) -> void:
	rname = info["name"]
	is_player = info.get("player", false)
	arch = info.get("arch", "balanced")
	color = info["color"]
	body_style = info.get("body", 0)
	stats = info["stats"]
	spd_mult = info.get("spd", 1.0)
	acc_mult = info.get("acc", 1.0)
	dmg_mult_out = info.get("dmg", 1.0)
	aggr = info.get("aggr", 0.3)
	mass = stats["mass"] * info.get("mass", 1.0)
	max_health = info.get("hp", stats["health"])
	health = max_health
	nitro = stats["nitro_cap"] * 0.4
	_build()

func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rough := 0.6, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(c, rough, metal)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func flame_skull() -> void:
	head_mat.albedo_color = Color(0.9, 0.88, 0.8)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.35, 0.05)
	head_mat.emission_energy_multiplier = 1.6
	var parent: Node3D = torso if torso != null else self
	var base := Vector3(0, 0.78, -0.02)
	for ex in [-0.07, 0.07]:
		var eye := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.08, 0.05)
		eye.mesh = bm
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0.02, 0.0, 0.0)
		eye.material_override = em
		eye.position = base + Vector3(ex, 0.02, -0.18)
		parent.add_child(eye)
	var jaw := MeshInstance3D.new()
	var jb := BoxMesh.new()
	jb.size = Vector3(0.14, 0.04, 0.05)
	jaw.mesh = jb
	var jm := StandardMaterial3D.new()
	jm.albedo_color = Color(0.02, 0.0, 0.0)
	jaw.material_override = jm
	jaw.position = base + Vector3(0, -0.09, -0.18)
	parent.add_child(jaw)
	var hg := _glow(Color(1.0, 0.45, 0.05, 0.9), 1.3, base + Vector3(0, 0.12, 0))
	hg.reparent(parent, false)
	hg.position = base + Vector3(0, 0.12, 0)
	var f := _mk_particles(30, 0.3, Color(1.0, 0.5, 0.05, 0.8), 0.05, Vector2(0.5, 1.2), Vector3(0, 2.0, 0))
	f.direction = Vector3(0, 1, 0)
	f.spread = 22.0
	f.reparent(parent, false)
	f.position = base + Vector3(0, 0.15, 0)
	f.emitting = true
	for w in [wheel_f, wheel_r]:
		if w != null:
			var wp: Node3D = w
			var wg := _glow(Color(1.0, 0.4, 0.05, 0.55), 0.9, Vector3.ZERO)
			wg.reparent(wp, false)
			wg.position = Vector3.ZERO

func _mk_particles(amount: int, life: float, col: Color, size: float, vel: Vector2, grav: Vector3, unshaded := true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.direction = Vector3(0, 0.6, 1)
	p.spread = 30.0
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = grav
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if col.r > 0.9 and col.g < 0.8:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.material = m
	p.mesh = sm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _build() -> void:
	model = Node3D.new()
	add_child(model)
	sparks = _mk_particles(36, 0.4, Color(1.0, 0.7, 0.2, 1.0), 0.03, Vector2(3.0, 8.0), Vector3(0, -9, 0))
	sparks.position = Vector3(0, 0.15, 0.3)
	if SPRAY == "rain":
		spray = _mk_particles(30, 0.6, Color(0.8, 0.85, 0.95, 0.35), 0.14, Vector2(1.5, 4.0), Vector3(0, -1.5, 0))
	elif SPRAY == "dust":
		spray = _mk_particles(30, 0.9, Color(0.78, 0.64, 0.44, 0.4), 0.22, Vector2(1.0, 3.0), Vector3(0, 0.3, 0))
	if spray != null:
		spray.position = Vector3(0, 0.12, 0.7)
	var id: String = BIKE_IDS[clampi(body_style, 0, 4)]
	var ps: PackedScene = load("res://assets/bikes/%s.glb" % id)
	bike3 = ps.instantiate()
	model.add_child(bike3)
	rider_mesh = bike3.find_child("rider", true, false)
	wheel_f = bike3.find_child("wheel_f", true, false)
	wheel_r = bike3.find_child("wheel_r", true, false)
	for n in bike3.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(n)
	glow_tail = _glow(Color(1.0, 0.1, 0.05, 0.7), 0.3, BTAIL[body_style] + Vector3(0, 0, 0.05))
	for ep in BEXH[body_style]:
		flames.append(_glow(Color(1.0, 0.55, 0.15, 0.0), 1.1, ep + Vector3(0, 0, 0.15)))
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rider = Node3D.new()
	model.add_child(rider)
	var lean_fwd := -0.5 if body_style in [1, 2] else -0.3
	torso = Node3D.new()
	torso.position = Vector3(0, BSH[body_style] - 0.52, BSZ[body_style])
	torso.rotation.x = lean_fwd
	rider.add_child(torso)
	body_parts.append(_box(torso, Vector3(0.38, 0.56, 0.26), Vector3(0, 0.3, 0), Color(0.12, 0.12, 0.14).lerp(color, 0.25), 0.8))
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2; sm.height = 0.4; sm.radial_segments = 10; sm.rings = 6
	head.mesh = sm
	head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = color
	head_mat.roughness = 0.3
	head.material_override = head_mat
	head.position = Vector3(0, 0.76, -0.02)
	torso.add_child(head)
	body_parts.append(head)
	body_parts.append(_box(torso, Vector3(0.28, 0.1, 0.1), Vector3(0, 0.76, -0.17), Color(0.05, 0.05, 0.08), 0.1))
	arm_l = _arm(-1)
	arm_r = _arm(1)
	leg_l = _leg(-1)
	leg_r = _leg(1)
	body_parts.append(leg_l)
	body_parts.append(leg_r)
	var shadow := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.3, 2.6)
	shadow.mesh = qm
	var sm2 := StandardMaterial3D.new()
	sm2.albedo_color = Color(0, 0, 0, 0.26)
	sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sm2
	shadow.rotation.x = -PI / 2
	shadow.position = Vector3(0, 0.03, 0.0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	for p in body_parts:
		p.visible = false
	arm_l.visible = false
	arm_r.visible = false
	set_weapon("punch", 0)

func _arm(side: int) -> Node3D:
	var p := Node3D.new()
	p.position = Vector3(0.24 * side, 0.52, 0)
	p.rotation.x = -1.15
	torso.add_child(p)
	_box(p, Vector3(0.11, 0.48, 0.11), Vector3(0, -0.24, 0), Color(0.15, 0.15, 0.17).lerp(color, 0.3), 0.8)
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.5, 0)
	p.add_child(hand)
	wpn_nodes.append(hand)
	return p

func _leg(side: int) -> Node3D:
	var p := Node3D.new()
	p.position = Vector3(0.17 * side, 0.82, 0.38)
	p.rotation.x = -0.55
	rider.add_child(p)
	_box(p, Vector3(0.15, 0.52, 0.15), Vector3(0, -0.26, 0), Color(0.1, 0.12, 0.2), 0.8)
	_box(p, Vector3(0.2, 0.14, 0.34), Vector3(0, -0.55, -0.06), Color(0.95, 0.5, 0.1), 0.6)
	return p

func apply_paint(c: Color, decal: String) -> void:
	for mi in _meshes:
		var n := String(mi.name)
		if not (n.begins_with("body_paint") or n.begins_with("body_accent")):
			continue
		var m0 := mi.get_active_material(0)
		if c.a > 0.0 and m0 is StandardMaterial3D:
			var m := (m0 as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.albedo_color = c if n.begins_with("body_paint") else c.darkened(0.45)
			mi.set_surface_override_material(0, m)
		if decal != "" and n.begins_with("body_paint"):
			var bb := mi.get_aabb()
			for sd in [-1, 1]:
				var lb := Label3D.new()
				lb.text = decal
				lb.font_size = 96
				lb.pixel_size = 0.0035
				lb.modulate = Color(1, 1, 1)
				lb.outline_size = 12
				lb.outline_modulate = Color(0, 0, 0)
				lb.double_sided = false
				lb.position = bb.get_center() + Vector3(sd * (bb.size.x * 0.5 + 0.02), 0.0, 0.0)
				lb.rotation.y = sd * PI * 0.5
				mi.add_child(lb)
			break

func make_ghost() -> void:
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.4, 0.9, 1.0, 0.35)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in _meshes:
		mi.material_override = gm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow_tail.visible = false

func set_weapon(id: String, dur: int) -> void:
	weapon = id
	weapon_dur = dur
	for h in wpn_nodes:
		for c in h.get_children():
			c.queue_free()
		match id:
			"bat": _box(h, Vector3(0.09, 0.85, 0.09), Vector3(0, -0.3, 0), Color(0.55, 0.36, 0.18), 0.8)
			"chain": _box(h, Vector3(0.05, 0.95, 0.05), Vector3(0, -0.4, 0), Color(0.6, 0.6, 0.65), 0.3, 0.9)
			"pipe": _box(h, Vector3(0.08, 0.75, 0.08), Vector3(0, -0.28, 0), Color(0.45, 0.5, 0.55), 0.35, 0.9)

# ---------------------------------------------------------------- actions
func can_attack() -> bool:
	return state != St.CRASHED and atk_cd <= 0.0 and not finished and crash_t <= 0.0

func begin_attack(side: int, kick: bool) -> void:
	var w: Dictionary = Data.WEAPONS["kick" if kick else weapon]
	atk_cd = float(w["cd"])
	anim_t = 0.0
	anim_side = side
	anim_kick = kick
	Sfx.play("swing", 0.6, randf_range(0.9, 1.15))

func use_weapon_dur() -> void:
	if weapon != "punch" and weapon_dur > 0:
		weapon_dur -= 1
		if weapon_dur <= 0:
			set_weapon("punch", 0)
			event.emit("weapon_broke", {})

func damage(amount: float, dmg_taken_mult := 1.0) -> void:
	if invuln > 0.0 or health <= 0.0:
		return
	var d: float = amount * stats["dmg_mult"] * dmg_taken_mult
	health = maxf(0.0, health - d)
	cond = maxf(0.0, cond - d * 0.5)
	hit_flash = 0.25

func crash(sev: int, side := 1) -> void:
	if crash_t > 0.0:
		return
	crash_t = 1.4 + 0.5 * sev
	state = St.CRASHED
	rider_vel = Vector3(side * randf_range(2.0, 4.0), randf_range(4.0, 6.5), randf_range(-6.0, -3.0)) * (0.6 + 0.2 * sev)
	_spin = side * randf_range(5.0, 9.0)
	tumble = 0.0
	atk_cd = 0.0
	event.emit("crash", {"sev": sev})

func respawn() -> void:
	crash_t = 0.0
	state = St.RECOVERING
	recover_t = 1.4
	invuln = 2.2
	v = 9.0
	vx = 0.0
	x = clampf(x, -6.0, 6.0)
	rider.position = Vector3.ZERO
	rider.rotation = Vector3.ZERO
	model.rotation = Vector3.ZERO
	cond = maxf(cond, 35.0)

# ---------------------------------------------------------------- physics
func step(dt: float, track: Track, active: bool) -> void:
	atk_cd = maxf(0.0, atk_cd - dt)
	invuln = maxf(0.0, invuln - dt)
	hit_flash = maxf(0.0, hit_flash - dt)
	bump_t = maxf(0.0, bump_t - dt)
	if anim_t < 1.0:
		anim_t = minf(1.0, anim_t + dt / (0.38 if not anim_kick else 0.5))
	if crash_t > 0.0:
		crash_t -= dt
		v = maxf(0.0, v - 28.0 * dt)
		vx *= exp(-2.0 * dt)
		s += v * dt
		x = clampf(x + vx * dt, -Track.BARRIER + 0.5, Track.BARRIER - 0.5)
		rider_vel.y -= 16.0 * dt
		rider.position += rider_vel * dt
		if rider.position.y < 0.0:
			rider.position.y = 0.0
			rider_vel.x *= 0.6
			rider_vel.y = absf(rider_vel.y) * 0.25 if rider_vel.y < -2.0 else 0.0
			rider_vel.z *= 0.8
		rider.rotation.z += _spin * dt * 0.6
		model.rotation.z += _spin * dt * 0.4 * minf(1.0, crash_t)
		tumble += dt
		if crash_t <= 0.0 and not (is_player and health <= 0.0):
			respawn()
		return
	if state == St.RECOVERING:
		recover_t -= dt
		if recover_t <= 0.0:
			state = St.RACING
	var cond_f := 0.75 + 0.25 * cond / 100.0
	var dirt_zone := track.in_shortcut(s) and x > Track.BARRIER - 1.2
	on_dirt = dirt_zone
	var off_road := absf(x) > Track.ROAD_HALF + 0.2 and not dirt_zone
	var terrain := 1.0
	if dirt_zone:
		terrain = float(stats["dirt"])
	elif off_road:
		terrain = 0.72
	var vmax: float = stats["vmax"] * spd_mult * cond_f * terrain
	var acc: float = stats["acc"] * acc_mult
	nitro_on = false
	if active and inp["nitro"] and nitro > 1.0 and speed_cap <= 0.0 and state != St.FINISHING and state != St.IDLE:
		nitro_on = true
		nitro = maxf(0.0, nitro - 20.0 * dt)
		vmax *= 1.32
		acc *= 2.8
	elif active:
		nitro = minf(stats["nitro_cap"], nitro + stats["nitro_regen"] * 0.8 * dt)
	if speed_cap > 0.0:
		vmax = minf(vmax, speed_cap)
	var throttle: float = inp["throttle"] if active else 0.0
	if state == St.FINISHING:
		throttle = 0.0
	var a := 0.0
	if throttle > 0.0:
		if v < vmax:
			a = acc * (1.0 - pow(v / vmax, 1.7)) * throttle
		else:
			a = -(v - vmax) * 1.4
	else:
		a = -3.5 if state != St.FINISHING else -9.0
	if inp["brake"] > 0.0:
		a = -stats["brake"] * float(inp["brake"])
	v = maxf(0.0, v + a * dt)
	# lateral
	steer_i = move_toward(steer_i, float(inp["steer"]) if active else 0.0, dt * 7.0)
	var hnd: float = stats["grip"] * (0.8 + 0.2 * cond_f)
	var grip := hnd * (1.0 - 0.35 * clampf(v / 70.0, 0.0, 1.0)) * (terrain if terrain < 1.0 else 1.0)
	var drift := track.curve_at(s) * v * v * 0.30
	vx += (steer_i * grip + drift) * dt
	vx *= exp(-3.2 * dt)
	vx = clampf(vx, -15.0, 15.0)
	x += vx * dt
	var drifting := active and not airborne and v > 32.0 and absf(vx) > 2.0 and absf(steer_i) > 0.5 and signf(steer_i) == signf(vx)
	drift_t = drift_t + dt if drifting else maxf(0.0, drift_t - dt * 3.0)
	_ramp_air(dt, track)
	var gain := track.shortcut_gain if dirt_zone else 1.0
	s += v * dt * gain
	# shortcut exit: nudge back to the road
	if track.shortcut.y > 0.0 and s > track.shortcut.y - 45.0 and s < track.shortcut.y + 20.0 and x > Track.ROAD_HALF - 1.0:
		vx -= 11.0 * dt
	scrape = false
	_barrier(track)

func _ramp_air(dt: float, track: Track) -> void:
	if airborne:
		air_time += dt
		air_y += air_vy * dt
		air_vy -= 24.0 * dt
		if inp["flip"]:
			flip_rot += 7.0 * dt
		if absf(float(inp["spin"])) > 0.1:
			spin_rot += signf(float(inp["spin"])) * 8.0 * dt
		if air_y <= 0.0:
			airborne = false
			air_y = 0.0
			var tr := floori((absf(flip_rot) + 0.8) / TAU) + floori((absf(spin_rot) + 0.8) / TAU)
			var fa := fposmod(absf(flip_rot), TAU)
			var sa := fposmod(absf(spin_rot), TAU)
			var clean := (fa < 0.8 or fa > TAU - 0.8) and (sa < 0.8 or sa > TAU - 0.8)
			land_evt = {"tricks": tr, "clean": clean, "air": air_time, "attempt": absf(flip_rot) + absf(spin_rot) > 0.5}
			flip_rot = 0.0
			spin_rot = 0.0
		return
	var ry := track.ramp_h(s) if absf(x) < Track.ROAD_HALF else 0.0
	if ramp_y > 0.4 and ry <= 0.0:
		airborne = true
		air_y = ramp_y
		air_vy = v * 0.16 + 4.0
		air_time = 0.0
		flip_rot = 0.0
		spin_rot = 0.0
	ramp_y = ry

func _barrier(track: Track) -> void:
	var lim := Track.BARRIER - 0.4
	var in_sc := track.in_shortcut(s)
	var right_lim := Track.DIRT_OUT - 0.5 if in_sc else lim
	if x > right_lim or x < -lim:
		var sg := 1.0 if x > 0.0 else -1.0
		x = right_lim if sg > 0.0 else -lim
		var closing := vx * sg
		if closing > 0.0:
			vx = -closing * 0.35 * sg
			if invuln <= 0.0 and not (in_sc and sg > 0.0):
				var sev := 0
				if closing > 9.0 or (closing > 6.0 and v > 45.0):
					sev = 2
				elif closing > 4.5:
					sev = 1
				v *= [0.9, 0.78, 0.55][sev]
				damage([2.0, 6.0, 14.0][sev])
				invuln = 0.5
				event.emit("wall", {"sev": sev, "side": sg})
				if sev == 2:
					crash(2, int(-sg))
			elif in_sc and sg > 0.0:
				v *= 0.9
		else:
			scrape = v > 20.0
			v = maxf(0.0, v - 14.0 * get_physics_process_delta_time())
			cond = maxf(0.0, cond - 0.8 * get_physics_process_delta_time())

func place_in_world(track: Track, dt: float) -> void:
	var pitch := atan(track.slope_at(s))
	var yw := track.yaw_at(s) - atan2(vx, maxf(v, 8.0)) * 0.9
	var gy := track.pos_at(s, x).y
	position = track.pos_at(s, x) + Vector3(0, air_y if airborne else ramp_y, 0)
	var up_tilt := 0.0
	if airborne:
		up_tilt = clampf(air_vy * 0.018, -0.35, 0.35)
	elif ramp_y > 0.0:
		up_tilt = 0.108
	rotation = Vector3(pitch + up_tilt, yw, 0.0)
	if crash_t <= 0.0:
		var target_roll := -vx * 0.045 + track.curve_at(s) * v * 1.4
		roll = lerpf(roll, clampf(target_roll, -0.7, 0.7), clampf(dt * 9.0, 0.0, 1.0))
		model.rotation = Vector3(flip_rot if airborne else 0.0, 0, roll + (spin_rot if airborne else 0.0))
	_bob += dt * (20.0 + v * 0.5)
	if sparks != null:
		sparks.emitting = (scrape or crash_t > 0.0) and v > 8.0
	if spray != null:
		spray.emitting = v > 18.0 and crash_t <= 0.0
	bike3.position.y = sin(_bob) * 0.006 * clampf(v / 40.0, 0.0, 1.0)
	bike3.rotation.x = lerpf(bike3.rotation.x, 0.06 if nitro_on else 0.0, clampf(dt * 6.0, 0.0, 1.0))
	var spin: float = v / float(BWR[body_style]) * dt
	wheel_f.rotation.x -= spin
	wheel_r.rotation.x -= spin
	var crashed := crash_t > 0.0
	rider_mesh.visible = not crashed
	for p in body_parts:
		p.visible = crashed
	for f in flames:
		var fm := f.material_override as StandardMaterial3D
		fm.albedo_color.a = lerpf(fm.albedo_color.a, 0.95 if nitro_on else 0.0, clampf(dt * 12.0, 0.0, 1.0))
		f.scale = Vector3.ONE * (1.0 + 0.35 * sin(_bob * 3.0))
	# melee animation
	var sw := sin(PI * clampf(anim_t, 0.0, 1.0)) if anim_t < 1.0 else 0.0
	var arms_on := crashed or sw > 0.0 or weapon != "punch"
	arm_l.visible = arms_on
	arm_r.visible = arms_on
	var ar := arm_r if anim_side > 0 else arm_l
	var al := arm_l if anim_side > 0 else arm_r
	for a in [arm_l, arm_r]:
		a.rotation = Vector3(-1.15, 0, 0)
	for l in [leg_l, leg_r]:
		l.rotation = Vector3(-0.55, 0, 0)
		l.scale = Vector3.ONE
	if sw > 0.0:
		if anim_kick:
			var lg := leg_r if anim_side > 0 else leg_l
			lg.visible = true
			lg.rotation = Vector3(-0.55 + sw * 0.35, 0, anim_side * sw * 1.75)
			lg.scale = Vector3(1.0 + sw * 0.5, 1.0 + sw * 1.0, 1.0 + sw * 0.5)
		else:
			ar.rotation = Vector3(-1.15 + sw * 1.0, 0, anim_side * sw * 1.55)
	var fl := hit_flash > 0.0
	if fl:
		_flash_mat.albedo_color = Color(1, 1, 1, clampf(hit_flash * 1.6, 0.0, 0.7))
	if fl != _flashing:
		_flashing = fl
		for mi in _meshes:
			mi.material_overlay = _flash_mat if fl else null
	if hit_flash > 0.0:
		head_mat.emission_enabled = true
		head_mat.emission = Color(1, 1, 1)
		head_mat.emission_energy_multiplier = hit_flash * 6.0
	elif head_mat.emission_enabled:
		head_mat.emission_enabled = false
	visible = invuln <= 0.0 or int(invuln * 12.0) % 2 == 0 or crash_t > 0.0
