class_name Race
extends Node3D
## One race session: world, riders, traffic, combat, objectives, camera.

signal toast(text: String, kind: int)   # kind 0 info, 1 good, 2 bad, 3 big
signal ended(result: Dictionary)

enum RState { COUNTDOWN, RACING, FINISHED, GAME_OVER }

const VIEW := 950.0
const ATTACK_COST := 0.0

var def: Dictionary = {}
var diff: Dictionary = {}
var mode := "race"
var track: Track
var state: int = RState.COUNTDOWN
var player: Racer
var racers: Array[Racer] = []
var ais: Dictionary = {}          # Racer -> AIDriver
var traffic: Array[TrafficCar] = []
var pool: Dictionary = {}         # kind -> Array[TrafficCar]
var pickups: Array = []           # {s,x,kind,node,alive}
var cam: Camera3D
var rvp: SubViewport
var rcam: Camera3D
var low_q := false
var fps_acc := 0.0
var fps_n := 0
var fps_t := 0.0
var rng := RandomNumberGenerator.new()

var time := 0.0
var cd := 3.4
var cd_shown := 4
var done := false
var autopilot := false
var autopilot_ai: AIDriver
var god := false
var debug_on := false

var time_left := 0.0
var elim_t := 25.0
var cp_next := 0
var score := 0.0
var combo := 1
var combo_t := 0.0
var shake := 0.0
var cam_pos := Vector3.ZERO
var cam_init := false
var vis_t := 0.0
var traffic_target := 12
var rel_prev: Dictionary = {}
var target_rival: Racer = null
var shortcut_taken := false
var was_in_shortcut := false

var st := {"overtakes": 0, "near": 0, "takedowns": 0, "crashes": 0, "top": 0.0, "cash": 0, "hits": 0, "wrecked": 0, "cops": 0, "rams": 0, "combo": 1}

var kicktest := false
var kt_done := false
var slow_until := 0
var slow_scale := 1.0
var boss: Racer = null
var boss_outran := false
var cops: Array[TrafficCar] = []
var cop_t := 3.0
var heat := 1
var siren_t := 0.0
var ghost_id := ""
var ghost_pts: Array = []
var ghost_time := 0.0
var ghost_node: Node3D
var ghost_gap := 0.0
var rec_pts: Array = []
var rec_t := 0.0

var touch_steer := 0.0

func setup(race_def: Dictionary) -> void:
	def = race_def
	mode = def["mode"]
	diff = Data.DIFFICULTY[int(Save.setting("diff"))]
	rng.seed = int(def["seed"]) * 31 + 7
	track = Track.new()
	track.build(def)
	_build_world()
	Racer.SPRAY = "rain" if weather == "rain" else ("dust" if weather == "dust" else "")
	_build_riders()
	_build_pickups()
	traffic_target = int(round(float(def.get("traffic", 0.5)) * 14.0))
	_seed_traffic()
	match mode:
		"time":
			time_left = float(def["target"])
		"highway":
			time_left = float(def["limit"])
		"survival", "chase":
			time_left = float(def["survive"])
	_setup_ghost()
	cam = Camera3D.new()
	cam.far = 1400.0
	cam.fov = 70.0
	cam.current = true
	add_child(cam)
	_update_camera(0.1, true)
	_build_weather()
	_build_fx()
	Sfx.music(true, "music_cruise" if def.has("cruise") else ("music_night" if tod == "night" else "music"))
	Sfx.rain(weather == "rain")

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	get_viewport().scaling_3d_scale = 1.0
	Sfx.engine(false)
	Sfx.rain(false)
	Sfx.tunnel(false)

# ---------------------------------------------------------------- world
const TOD := {"r2": "night", "r5": "night", "r8": "night", "r6": "dusk", "r9": "dusk", "r12": "night", "r16": "dusk"}
const WEATHER := {"r2": "rain", "r5": "rain", "r4": "fog", "r7": "fog", "r3": "dust", "r9": "rain", "r10": "fog", "r11": "dust", "r12": "rain"}
var tod := "day"
var weather := "clear"
var env_ref: Environment
var amb_base := 0.75
var flash := 0.0
var flash_t := 4.0
var blur_mat: ShaderMaterial
var blur_amt := 0.0
var streaks: CPUParticles3D
var headlight: SpotLight3D

func _build_world() -> void:
	var theme := int(def.get("theme", 0))
	tod = str(def.get("tod", TOD.get(str(def.get("id", "")), "day")))
	weather = str(def.get("weather", WEATHER.get(str(def.get("id", "")), "clear")))
	var top := [Color(0.25, 0.48, 0.85), Color(0.12, 0.08, 0.28), Color(0.30, 0.42, 0.70)][theme] as Color
	var hor := [Color(0.72, 0.84, 0.96), Color(0.62, 0.36, 0.52), Color(0.98, 0.76, 0.50)][theme] as Color
	var amb := [Color(0.62, 0.66, 0.72), Color(0.55, 0.48, 0.62), Color(0.78, 0.68, 0.58)][theme] as Color
	var sun_e := [1.15, 0.8, 1.3][theme] as float
	var sun_c := [Color(1, 0.97, 0.9), Color(1.0, 0.7, 0.55), Color(1, 0.9, 0.75)][theme] as Color
	var fogd := 0.0018
	if tod == "dusk":
		top = Color(0.20, 0.16, 0.42); hor = Color(1.0, 0.52, 0.30); amb = Color(0.62, 0.48, 0.50); sun_e = 0.7; sun_c = Color(1.0, 0.55, 0.35)
	elif tod == "night":
		top = Color(0.02, 0.03, 0.09); hor = Color(0.10, 0.12, 0.26); amb = Color(0.20, 0.24, 0.42); sun_e = 0.25; sun_c = Color(0.55, 0.65, 1.0); fogd = 0.0026
	if weather == "rain":
		top = top.lerp(Color(0.25, 0.27, 0.32), 0.55); hor = hor.lerp(Color(0.38, 0.40, 0.46), 0.6); sun_e *= 0.55; fogd = 0.0042
	elif weather == "fog":
		top = top.lerp(Color(0.66, 0.68, 0.72), 0.7); hor = hor.lerp(Color(0.72, 0.74, 0.78), 0.85); sun_e *= 0.6; fogd = 0.0085
	elif weather == "dust":
		hor = hor.lerp(Color(0.86, 0.66, 0.42), 0.5); fogd = 0.0034
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = top
	psm.sky_horizon_color = hor
	psm.ground_horizon_color = hor
	psm.ground_bottom_color = hor.darkened(0.3)
	psm.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = psm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb
	amb_base = 0.75 if tod != "night" else 0.9
	env.ambient_light_energy = amb_base
	env.fog_enabled = true
	env.fog_light_color = hor
	env.fog_density = fogd
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env_ref = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0) if tod != "dusk" else Vector3(-14, -35, 0)
	sun.light_energy = sun_e
	sun.light_color = sun_c
	sun.shadow_enabled = tod != "night" and weather != "fog"
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_blur = 1.5
	add_child(sun)
	track.wet = weather == "rain"
	low_q = int(Save.setting("quality")) == 0
	if low_q:
		sun.shadow_enabled = false
		get_viewport().scaling_3d_scale = 0.75
	elif track.wet:
		_build_reflection()
	track.night = tod == "night"
	TrafficCar.night = tod == "night"
	track.build_visuals(self)
	if tod != "day" or weather == "rain" or weather == "fog":
		_build_lamps()

func _build_reflection() -> void:
	rvp = SubViewport.new()
	rvp.size = Vector2i(800, 450)
	rvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	rvp.msaa_3d = Viewport.MSAA_DISABLED
	rvp.world_3d = get_viewport().world_3d
	add_child(rvp)
	rcam = Camera3D.new()
	rcam.far = 400.0
	rcam.cull_mask = 0xFFFFD
	rvp.add_child(rcam)
	track.refl = rvp.get_texture()

func _update_reflection() -> void:
	var plane := player.position.y
	var cp := cam.global_position
	var fw := -cam.global_transform.basis.z
	rcam.fov = cam.fov
	rcam.global_position = Vector3(cp.x, 2.0 * plane - cp.y, cp.z)
	rcam.look_at(Vector3(cp.x + fw.x, 2.0 * plane - (cp.y + fw.y), cp.z + fw.z), Vector3.DOWN)

func _watch_fps(dt: float) -> void:
	if low_q or time < 4.0:
		return
	fps_t += dt
	fps_acc += 1.0 / maxf(dt, 0.001)
	fps_n += 1
	if fps_t >= 3.0:
		var avg := fps_acc / float(fps_n)
		fps_t = 0.0
		fps_acc = 0.0
		fps_n = 0
		if avg < float(Save.setting("fps")) * 0.7:
			low_q = true
			get_viewport().scaling_3d_scale = 0.8
			if rvp != null:
				rvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
				for m in track.road_mats:
					m.set_shader_parameter("strength", 0.0)

func _build_lamps() -> void:
	var step := 36.0
	var n := int(float(def["len"]) / step)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07; pole.bottom_radius = 0.09; pole.height = 6.0
	var head := BoxMesh.new()
	head.size = Vector3(0.9, 0.18, 0.35)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.16, 0.17, 0.20)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(1.0, 0.82, 0.5) * 2.2 if tod == "night" else Color(1.0, 0.82, 0.5)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.75, 0.4)
	hm.emission_energy_multiplier = 3.0
	var mp := MultiMesh.new(); mp.transform_format = MultiMesh.TRANSFORM_3D; mp.mesh = pole; mp.instance_count = n * 2
	var mh := MultiMesh.new(); mh.transform_format = MultiMesh.TRANSFORM_3D; mh.mesh = head; mh.instance_count = n * 2
	for i in n:
		for sd in 2:
			var x := (Track.ROAD_HALF + 1.4) * (1.0 if sd == 0 else -1.0)
			var s := 20.0 + i * step + sd * 18.0
			var base := track.pos_at(s, x, 0.0)
			mp.set_instance_transform(i * 2 + sd, Transform3D(Basis(), base + Vector3(0, 3.0, 0)))
			mh.set_instance_transform(i * 2 + sd, Transform3D(Basis(), base + Vector3(-x * 0.03, 6.0, 0)))
	var a := MultiMeshInstance3D.new(); a.multimesh = mp; a.material_override = pm; add_child(a)
	var b := MultiMeshInstance3D.new(); b.multimesh = mh; b.material_override = hm; b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(b)

func _build_weather() -> void:
	if tod != "day" or weather == "rain":
		headlight = SpotLight3D.new()
		headlight.spot_range = 70.0
		headlight.spot_angle = 32.0
		headlight.light_energy = 6.0 if tod == "night" else 2.5
		headlight.light_color = Color(1.0, 0.95, 0.82)
		headlight.position = Vector3(0, -0.2, -0.5)
		cam.add_child(headlight)
	if weather == "rain":
		var pr := CPUParticles3D.new()
		pr.amount = 700
		pr.lifetime = 0.9
		pr.local_coords = false
		pr.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		pr.emission_box_extents = Vector3(14, 0.5, 22)
		pr.position = Vector3(0, 11, -14)
		pr.direction = Vector3(0, -1, 0.25)
		pr.spread = 3.0
		pr.initial_velocity_min = 34.0
		pr.initial_velocity_max = 40.0
		pr.gravity = Vector3.ZERO
		var q := BoxMesh.new()
		q.size = Vector3(0.012, 0.9, 0.012)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.75, 0.82, 0.95, 0.5)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		q.material = m
		pr.mesh = q
		cam.add_child(pr)
	elif weather == "dust":
		var pr2 := CPUParticles3D.new()
		pr2.amount = 120
		pr2.lifetime = 2.0
		pr2.local_coords = false
		pr2.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		pr2.emission_box_extents = Vector3(14, 3, 20)
		pr2.position = Vector3(0, 1, -14)
		pr2.direction = Vector3(-1, 0.1, 0)
		pr2.initial_velocity_min = 8.0
		pr2.initial_velocity_max = 14.0
		pr2.gravity = Vector3.ZERO
		var d := SphereMesh.new()
		d.radius = 0.05; d.height = 0.1
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.albedo_color = Color(0.9, 0.75, 0.5, 0.5)
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		d.material = dm
		pr2.mesh = d
		cam.add_child(pr2)

func _build_fx() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 4
	add_child(cl)
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
uniform float amt = 0.0;
uniform float ca = 0.0;
void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5, 0.45);
	float r = length(d);
	vec3 c = vec3(0.0);
	float w = amt * smoothstep(0.12, 0.6, r);
	for (int i = 0; i < 6; i++) {
		float k = 1.0 - w * float(i) / 6.0 * 0.15;
		c += texture(scr, vec2(0.5, 0.45) + d * k).rgb;
	}
	c /= 6.0;
	c.r = mix(c.r, texture(scr, vec2(0.5, 0.45) + d * (1.0 + ca * r)).r, step(0.001, ca));
	c.b = mix(c.b, texture(scr, vec2(0.5, 0.45) + d * (1.0 - ca * r)).b, step(0.001, ca));
	c *= 1.0 - amt * 0.35 * smoothstep(0.35, 0.8, r);
	COLOR = vec4(c, 1.0);
}"""
	blur_mat = ShaderMaterial.new()
	blur_mat.shader = sh
	cr.material = blur_mat
	cl.add_child(cr)
	var st := CPUParticles3D.new()
	st.amount = 40
	st.lifetime = 0.35
	st.local_coords = false
	st.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	st.emission_box_extents = Vector3(5, 2.5, 1)
	st.position = Vector3(0, 0, -16)
	st.direction = Vector3(0, 0, 1)
	st.spread = 2.0
	st.initial_velocity_min = 45.0
	st.initial_velocity_max = 60.0
	st.gravity = Vector3.ZERO
	var bm := BoxMesh.new()
	bm.size = Vector3(0.015, 0.015, 2.4)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1, 1, 1, 0.22)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = mm
	st.mesh = bm
	st.emitting = false
	cam.add_child(st)
	streaks = st
	_build_streaks()

func _build_streaks() -> void:
	if not (tod != "day" or weather == "rain"):
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 30.0)
	mm.mesh = qm
	var pts: Array = []
	var i := 0.0
	while i < track.length:
		if int(i / 36.0) % 1 == 0:
			for sx in [-1.0, 1.0]:
				var t := Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)), track.pos_at(i, 4.5 * sx, 0.04))
				t.basis = Basis.from_euler(Vector3(0, track.yaw_at(i), 0)) * Basis.from_euler(Vector3(-PI / 2, 0, 0))
				pts.append(t)
		i += 36.0
	mm.instance_count = pts.size()
	for k in pts.size():
		mm.set_instance_transform(k, pts[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Racer.glow_tex()
	m.albedo_color = Color(1.0, 0.8, 0.45, 0.22 if weather == "rain" else 0.1)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _update_fx(dt: float) -> void:
	Sfx.tunnel((track.feat_at(player.s) & Track.F_TUNNEL) != 0)
	Sfx.scrape_snd(player.scrape)
	var v01 := clampf(player.v / 80.0, 0.0, 1.0)
	var a := clampf((v01 - 0.35) / 0.65, 0.0, 1.0)
	if player.nitro_on:
		a = minf(a + 0.5, 1.0)
	blur_amt = lerpf(blur_amt, a, dt * 4.0)
	if blur_mat != null:
		blur_mat.set_shader_parameter("amt", blur_amt * (0.5 if Save.setting("shake") == 0 else 1.0))
		blur_mat.set_shader_parameter("ca", 0.025 if player.nitro_on else 0.0)
	if streaks != null:
		streaks.emitting = v01 > 0.4

func _update_atmosphere(dt: float) -> void:
	_update_fx(dt)
	if headlight != null:
		var tun := (track.feat_at(player.s) & Track.F_TUNNEL) != 0
		headlight.light_energy = lerpf(headlight.light_energy, (6.0 if tod == "night" else 2.5) + (3.0 if tun else 0.0), dt * 3.0)
	if weather == "rain" and env_ref != null:
		flash_t -= dt
		if flash_t <= 0.0:
			flash = 1.0
			flash_t = randf_range(5.0, 12.0)
		flash = maxf(0.0, flash - dt * 3.5)
		env_ref.ambient_light_energy = amb_base + flash * 2.2 * (1.0 if sin(flash * 40.0) > -0.3 else 0.3)

func _bike_for_arch(a: String) -> String:
	return {"balanced": "dustrunner", "speed": "viper", "heavy": "boulder", "aggressive": "hornet", "defensive": "ironclad"}.get(a, "dustrunner")

func _build_riders() -> void:
	var slots: Array = []
	var rivals: Array = def["rivals"]
	var n := rivals.size() + 1
	for i in n:
		var row := i / 2
		var col := i % 2
		var sx := (-3.0 if col == 0 else 3.0) if n > 1 else 0.0
		slots.append(Vector2(12.0 - row * 8.0 - (3.0 if col == 1 else 0.0), sx))
	var player_slot := mini(3, n - 1)
	# player
	var bid: String = Save.d["bike"]
	var b := Data.bike(bid)
	player = Racer.new()
	player.speed_cap = float(def.get("cruise", 0.0))
	player.setup({"name": "You", "player": true, "arch": "balanced", "color": b["color"], "body": b["body"],
		"stats": Data.stats(bid, Save.bike_upg(bid))})
	add_child(player)
	var cu: Dictionary = Save.d["custom"].get(bid, {})
	if not cu.is_empty():
		var pi := int(cu.get("paint", -1))
		player.apply_paint(Data.PAINTS[pi] if pi >= 0 and pi < Data.PAINTS.size() else Color(0, 0, 0, 0), Data.DECALS[clampi(int(cu.get("decal", 0)), 0, Data.DECALS.size() - 1)])
	player.s = slots[player_slot].x
	player.x = slots[player_slot].y
	racers.append(player)
	player.event.connect(_on_racer_event.bind(player))
	# rivals
	var lvl := clampi(int(float(def.get("req", 0)) / 60.0), 0, 4)
	var slot_i := 0
	for i in rivals.size():
		if slot_i == player_slot:
			slot_i += 1
		var arch: String = rivals[i]
		var A: Dictionary = Data.ARCH[arch]
		var bike_id := _bike_for_arch(arch)
		var upg := {"engine": lvl, "tires": lvl, "handling": lvl, "armor": lvl, "nitro": lvl, "brakes": lvl}
		var r := Racer.new()
		var is_boss := mode == "boss" and i == int(def.get("boss", 0))
		var rn: String = Data.RIVAL_NAMES[(i + int(def["seed"])) % Data.RIVAL_NAMES.size()]
		if is_boss:
			rn = str(def["boss_name"])
		if mode == "rival":
			rn = "Mara Slate"
		elif mode == "revenge" and i == int(def.get("target_rival", 0)):
			rn = "Tank Orlo"
		var boost := 1.0
		if mode == "rival":
			boost = float(def.get("rival_boost", 1.0))
		r.setup({"name": rn, "arch": arch, "color": def["boss_color"] if is_boss else A["color"], "body": i % 5, "stats": Data.stats(bike_id, upg),
			"spd": float(A["spd"]) * float(diff["ai_speed"]) * boost * (1.04 if is_boss else 1.0), "acc": A["acc"],
			"dmg": float(A["dmg"]) * (1.3 if is_boss else 1.0),
			"aggr": 0.9 if is_boss else A["aggr"], "mass": float(A["mass"]) * (1.3 if is_boss else 1.0),
			"hp": float(def["boss_hp"]) if is_boss else A["hp"]})
		add_child(r)
		if is_boss:
			boss = r
			r.set_meta("boss", true)
			r.model.scale = Vector3.ONE * 1.2
			r.apply_paint(def["boss_color"], "B")
		r.s = slots[slot_i].x
		r.x = slots[slot_i].y
		slot_i += 1
		var ai := AIDriver.new()
		ai.setup(r, diff, rng)
		if mode == "survival" or is_boss or (mode == "revenge" and i == int(def.get("target_rival", 0))):
			ai.must_hunt = true
			r.grudge = player
		ais[r] = ai
		racers.append(r)
		r.event.connect(_on_racer_event.bind(r))
		if mode == "revenge" and i == int(def.get("target_rival", 0)):
			target_rival = r
	if autopilot:
		_enable_autopilot()
	for r in racers:
		r.place_in_world(track, 0.016)

func _enable_autopilot() -> void:
	autopilot_ai = AIDriver.new()
	player.aggr = 0.4
	autopilot_ai.setup(player, diff, rng)

const PICK_COL := {"nitro": Color(0.2, 0.9, 1.0), "repair": Color(0.3, 1.0, 0.4), "bat": Color(1.0, 0.6, 0.15),
	"chain": Color(1.0, 0.6, 0.15), "pipe": Color(1.0, 0.6, 0.15), "cash": Color(1.0, 0.85, 0.2)}

func _pickup_node(k: String) -> Node3D:
	var root := Node3D.new()
	var col: Color = PICK_COL[k]
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.9
	match k:
		"bat":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.1; cm.bottom_radius = 0.2; cm.height = 1.6
			mi.mesh = cm
			m.albedo_color = Color(0.6, 0.4, 0.2)
		"chain":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.3; tm.outer_radius = 0.55
			mi.mesh = tm
			m.albedo_color = Color(0.75, 0.75, 0.8)
		"pipe":
			var cm2 := CylinderMesh.new()
			cm2.top_radius = 0.16; cm2.bottom_radius = 0.16; cm2.height = 1.5
			mi.mesh = cm2
			m.albedo_color = Color(0.5, 0.55, 0.65)
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 0.9, 0.9)
			mi.mesh = bm
			m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if k == "bat" or k == "pipe":
		mi.rotation.z = 0.9
	root.add_child(mi)
	if k in ["bat", "chain", "pipe"]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(3.0, 3.0)
		q.mesh = qm
		q.material_override = Racer.glow_mat(Color(1.0, 0.55, 0.1, 0.55), Racer.glow_tex())
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(q)
	return root

func _add_pickup(ps: float, px: float, k: String) -> void:
	var node := _pickup_node(k)
	add_child(node)
	pickups.append({"s": ps, "x": px, "kind": k, "node": node, "alive": true})
	node.position = track.pos_at(ps, px, 1.0)

func _build_pickups() -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = int(def["seed"]) * 13 + 5
	var kinds := ["nitro", "nitro", "repair", "bat", "chain", "pipe", "cash", "cash"]
	if mode in ["boss", "chase", "rival", "revenge", "survival", "knockout"]:
		kinds = ["nitro", "repair", "bat", "chain", "pipe", "bat", "chain", "pipe", "cash"]
	var s := 320.0
	while s < track.finish_s - 250.0:
		var k: String = kinds[prng.randi() % kinds.size()]
		var px: float = Track.LANES[prng.randi() % 4] + prng.randf_range(-0.8, 0.8)
		if mode == "highway" or mode == "time":
			k = ["nitro", "cash", "repair"][prng.randi() % 3]
		_add_pickup(s, px, k)
		s += prng.randf_range(170.0, 300.0)
	if track.shortcut.y > 0.0:
		var ss := track.shortcut.x + 40.0
		while ss < track.shortcut.y - 30.0:
			_add_pickup(ss, 12.0, "cash")
			ss += 55.0

# ---------------------------------------------------------------- traffic
func _get_car(kind: String) -> TrafficCar:
	var lst: Array = pool.get(kind, [])
	var c: TrafficCar
	if lst.is_empty():
		c = TrafficCar.new()
		c.build(kind, rng)
		add_child(c)
	else:
		c = lst.pop_back()
		c.visible = true
		pool[kind] = lst
	return c

func _release_car(c: TrafficCar) -> void:
	c.visible = false
	var lst: Array = pool.get(c.kind, [])
	lst.append(c)
	pool[c.kind] = lst

func _try_spawn(s_lo: float, s_hi: float) -> bool:
	var kind := TrafficCar.pick_kind(rng)
	var lane: float = Track.LANES[rng.randi() % 4]
	var sp := rng.randf_range(s_lo, s_hi)
	if sp > track.finish_s + 150.0:
		return false
	if track.feat_at(sp) & Track.F_INTER:
		return false
	for c in traffic:
		if absf(c.lane_x - lane) < 1.0 and absf(c.s - sp) < 38.0:
			return false
	for r in racers:
		if absf(r.s - sp) < 30.0 and absf(r.x - lane) < 3.0:
			return false
	var car := _get_car(kind)
	var K: Dictionary = TrafficCar.KINDS[kind]
	car.s = sp
	car.lane_x = lane
	car.x = lane
	car.base_v = rng.randf_range(float(K["spd"][0]), float(K["spd"][1]))
	car.v = car.base_v
	car.passed_flag = false
	car.prev_ds = sp - player.s
	traffic.append(car)
	return true

func _seed_traffic() -> void:
	var tries := 0
	while traffic.size() < traffic_target and tries < 200:
		tries += 1
		_try_spawn(player.s + 60.0, player.s + 420.0)

func _update_traffic(dt: float) -> void:
	var lo := player.s - 90.0
	var hi := player.s + 430.0
	var i := traffic.size() - 1
	while i >= 0:
		var c := traffic[i]
		if c.s < lo or c.s > hi + 120.0:
			_release_car(c)
			traffic.remove_at(i)
		i -= 1
	var guard := 0
	while traffic.size() < traffic_target and guard < 3:
		guard += 1
		_try_spawn(hi - 90.0, hi)
	for c in traffic:
		c.step(dt, traffic)
		c.place_in_world(track)

# ---------------------------------------------------------------- loop
func _physics_process(dt: float) -> void:
	if state == RState.COUNTDOWN:
		cd -= dt
		var shown := int(ceil(cd - 0.4))
		if shown != cd_shown and shown >= 0 and shown <= 3:
			cd_shown = shown
			Sfx.play("beep" if shown > 0 else "go", 0.8)
		if cd <= 0.4 and cd_shown != 0:
			cd_shown = 0
			Sfx.play("go")
		if cd <= 0.0:
			state = RState.RACING
	if state == RState.RACING:
		time += dt
	var racing := state == RState.RACING or state == RState.FINISHED
	_player_input()
	for r in racers:
		if r.eliminated:
			continue
		if r != player and ais.has(r):
			(ais[r] as AIDriver).think(dt, self)
			var a: int = int(r.inp["atk"])
			if a != 0:
				_melee(r, a, bool(r.inp["kick"]))
				r.inp["atk"] = 0
		elif r == player and autopilot and autopilot_ai != null:
			autopilot_ai.think(dt, self)
			var a2: int = int(r.inp["atk"])
			if a2 != 0:
				_melee(r, a2, bool(r.inp["kick"]))
				r.inp["atk"] = 0
		r.step(dt, track, racing)
	_health_checks()
	_collide_riders()
	_collide_traffic()
	_pickups_step()
	_update_traffic(dt)
	_update_cops(dt)
	_ghost_step(dt)
	if kicktest and not kt_done and state == RState.RACING and time > 0.8:
		_kicktest()
	_rewards(dt)
	_finish_checks(dt)
	_rank()
	st["top"] = maxf(float(st["top"]), player.v)
	if track.shortcut.y > 0.0:
		var ins := track.in_shortcut(player.s) and player.x > Track.BARRIER - 1.0
		if ins and not was_in_shortcut:
			toast.emit("SHORTCUT!", 1)
			shortcut_taken = true
		was_in_shortcut = ins
	# presentation
	vis_t -= dt
	for r in racers:
		var near := absf(r.s - player.s) < VIEW
		r.visible = near and not (r.eliminated and r.crash_t <= 0.0)
		if near:
			r.place_in_world(track, dt)
	for p in pickups:
		if p["alive"]:
			var n: Node3D = p["node"]
			n.visible = absf(float(p["s"]) - player.s) < 500.0
			if n.visible:
				n.rotation.y += dt * 2.5
	track.update_visibility(player.s, VIEW)
	_update_camera(dt, false)
	_update_atmosphere(dt)
	var sp01 := clampf(player.v / maxf(1.0, float(player.stats["vmax"]) * 1.2), 0.0, 1.0)
	Sfx.engine(state != RState.GAME_OVER and player.crash_t <= 0.0, sp01, player.nitro_on)

func _player_input() -> void:
	if autopilot:
		return
	var inp := player.inp
	var steer := Input.get_axis("left", "right") + touch_steer
	inp["steer"] = clampf(steer, -1.0, 1.0)
	var brake := Input.get_action_strength("brake")
	inp["brake"] = brake
	if Save.auto_throttle():
		inp["throttle"] = 1.0 if brake < 0.1 else 0.0
	else:
		inp["throttle"] = Input.get_action_strength("accel")
	inp["nitro"] = Input.is_action_pressed("nitro")
	inp["flip"] = Input.is_action_pressed("kick")
	inp["spin"] = Input.get_action_strength("attack") + Input.get_action_strength("atk_r") - Input.get_action_strength("atk_l")
	if state != RState.RACING or player.airborne:
		return
	var dt := get_process_delta_time()
	buf_punch = maxf(0.0, buf_punch - dt)
	buf_kick = maxf(0.0, buf_kick - dt)
	if Input.is_action_just_pressed("attack"):
		buf_punch = 0.35
	if Input.is_action_just_pressed("kick"):
		buf_kick = 0.35
	if Input.is_action_just_pressed("atk_l"):
		_melee(player, -1, false)
	elif Input.is_action_just_pressed("atk_r"):
		_melee(player, 1, false)
	elif buf_kick > 0.0 and player.can_attack():
		buf_kick = 0.0
		_melee(player, 0, true)
	elif buf_punch > 0.0 and player.can_attack():
		buf_punch = 0.0
		_melee(player, 0, false)

# ---------------------------------------------------------------- combat
func _melee(a: Racer, side: int, kick: bool) -> void:
	if not a.can_attack() or a.eliminated:
		return
	var wid: String = "kick" if kick else a.weapon
	var w: Dictionary = Data.WEAPONS[wid]
	var reach := float(w["reach"])
	var win_s := 2.8
	if a.is_player:
		reach = maxf(reach, 4.6 if kick else 3.8)
		win_s = 4.5 if kick else 3.8
	var best: Racer = null
	var bd := 99.0
	for o in racers:
		if o == a or o.eliminated or o.crash_t > 0.0 or o.finished:
			continue
		var dsx := o.s - a.s
		var dx := o.x - a.x
		if absf(dsx) > win_s or absf(dx) > reach:
			continue
		if side != 0 and absf(dx) > 0.35 and signf(dx) != float(side):
			continue
		var d := absf(dx) + absf(dsx) * 0.5
		if d < bd:
			bd = d
			best = o
	var best_cop: TrafficCar = null
	if a.is_player:
		for c in cops:
			if c.wreck_t > 0.0:
				continue
			var cdx := c.x - a.x
			var cdsx := c.s - a.s
			if absf(cdsx) > win_s + 1.0 or absf(cdx) > reach + 1.0:
				continue
			if side != 0 and absf(cdx) > 0.35 and signf(cdx) != float(side):
				continue
			var cd2 := absf(cdx) + absf(cdsx) * 0.5
			if cd2 < bd:
				bd = cd2
				best_cop = c
				best = null
	var sd := side
	if sd == 0:
		var tx := 0.0
		if best != null:
			tx = best.x - a.x
		elif best_cop != null:
			tx = best_cop.x - a.x
		sd = int(signf(tx)) if (best != null or best_cop != null) else (int(signf(float(a.inp["steer"]))) if absf(float(a.inp["steer"])) > 0.2 else 1)
		if sd == 0:
			sd = 1
	a.begin_attack(sd, kick)
	if best == null and best_cop == null:
		if a.is_player and kick:
			Sfx.play("swing", 0.7, 0.8)
			toast.emit("MISS", 0)
		return
	if not kick:
		a.use_weapon_dur()
	var dmg := float(w["dmg"]) * a.dmg_mult_out
	var kn := float(w["knock"]) * (1.5 if kick else 1.0)
	if best_cop != null:
		_hit_cop(best_cop, dmg, sd, kn, wid)
		return
	var o2 := best
	var taken := float(diff["dmg_taken"]) if o2.is_player else 1.0
	if god and o2.is_player:
		dmg = 0.0
	o2.damage(dmg, taken)
	o2.vx += sd * kn / maxf(0.6, o2.mass)
	o2.v *= 1.0 - float(w["slow"])
	o2.hit_flash = 0.25
	o2.bump_t = 0.2
	a.v *= 1.0 - float(w["slow"]) * 0.3
	if not a.is_player:
		Sfx.play("hit", 0.9, randf_range(0.9, 1.1))
		st["ai_hits"] = int(st.get("ai_hits", 0)) + 1
	if a.is_player:
		st["hits"] += 1
		_hit_fx(o2.global_position, wid)
		_combo_add(1)
		st["cash"] += 8 * combo
		score += 40.0 * combo
		if o2.grudge == null:
			o2.grudge = a
	elif o2.is_player:
		shake = maxf(shake, 0.5)
		_slowmo(0.05, 0.2)
		toast.emit("%s hit you" % a.rname, 2)
		if a.grudge == null:
			a.grudge = player
	if not o2.is_player and o2.grudge == null:
		o2.grudge = a
	if o2.health <= 0.0 and o2.crash_t <= 0.0:
		_knock_out(o2, a, sd)
	elif dmg >= 22.0 and o2.v > 22.0 and o2.crash_t <= 0.0:
		o2.crash(1, sd)

func _hit_fx(pos: Vector3, wid: String) -> void:
	_spark(pos + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.3) if wid != "pipe" else Color(0.6, 0.9, 1.0), 2.6 if wid == "kick" else 2.0)
	Sfx.play("kick" if wid == "kick" else "hit", 1.0, randf_range(0.92, 1.08))
	if wid in ["pipe", "bat"]:
		Sfx.play("crunch", 0.6, 1.3)
	var nm: String = {"kick": "KICK!", "punch": "PUNCH!", "bat": "BAT!", "chain": "CHAIN!", "pipe": "PIPE!"}[wid]
	toast.emit(nm, 3)
	shake = maxf(shake, 0.45 if wid == "kick" else 0.3)
	_slowmo(0.07, 0.12)

func _spark(pos: Vector3, col: Color, size: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	q.mesh = qm
	var m := Racer.glow_mat(Color(col.r, col.g, col.b, 1.0), Racer.glow_tex())
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = pos
	add_child(q)
	var tw := q.create_tween()
	tw.set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * 2.2, 0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(q.queue_free)

func _slowmo(secs: float, sc: float) -> void:
	var now := Time.get_ticks_msec()
	var until := now + int(secs * 1000.0)
	if now >= slow_until:
		slow_scale = sc
	else:
		slow_scale = minf(slow_scale, sc)
	slow_until = maxi(slow_until, until)

func _process(_dt: float) -> void:
	if Time.get_ticks_msec() < slow_until:
		Engine.time_scale = slow_scale
	elif Engine.time_scale != 1.0:
		Engine.time_scale = 1.0

func _combo_add(n: int) -> void:
	combo = mini(combo + n, 9)
	combo_t = 4.0
	st["combo"] = maxi(int(st["combo"]), combo)

func _drop_weapon(at: Racer) -> void:
	var k: String = ["bat", "chain", "pipe"][rng.randi() % 3]
	_add_pickup(at.s + 12.0, clampf(at.x, -6.5, 6.5), k)

func _knock_out(o: Racer, by: Racer, side: int) -> void:
	o.crash(2, side)
	o.set_meta("ko", true)
	if by != null and by.is_player and not o.is_player:
		st["takedowns"] += 1
		player.nitro = minf(float(player.stats["nitro_cap"]), player.nitro + 25.0)
		_combo_add(2)
		score += 300.0 * combo
		toast.emit("TAKEDOWN  %s" % o.rname, 3)
		Sfx.play("pickup")
		Sfx.play("crunch", 1.0)
		shake = 1.0
		_spark(o.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.2), 5.0)
		if o == boss:
			_slowmo(1.3, 0.2)
		else:
			_slowmo(0.8, 0.3)
		_drop_weapon(o)

func _health_checks() -> void:
	for r in racers:
		if r.eliminated:
			continue
		if r.health <= 0.0:
			if r.is_player:
				if r.crash_t <= 0.0 and r.state != Racer.St.CRASHED:
					r.crash(2, 1)
					r.set_meta("ko", true)
			elif r.crash_t <= 0.0:
				if r.state == Racer.St.RECOVERING:
					r.health = r.max_health * 0.45
				elif r.state != Racer.St.CRASHED:
					_knock_out(r, null, 1)
		if god and r.is_player:
			r.health = r.max_health
			r.cond = 100.0
			r.nitro = float(r.stats["nitro_cap"])

func _on_racer_event(kind: String, data: Dictionary, r: Racer) -> void:
	match kind:
		"wall":
			if r == player:
				shake = maxf(shake, 0.2 + 0.25 * int(data["sev"]))
				Sfx.play("bump", 0.8)
		"crash":
			if r == player:
				st["crashes"] += 1
				shake = 1.0
				combo = 1
				Sfx.play("crash")
				Sfx.play("impact", 0.9)
				toast.emit("WIPEOUT", 2)
		"weapon_broke":
			if r == player:
				toast.emit("Weapon broke", 0)

func _collide_riders() -> void:
	for i in racers.size():
		var a := racers[i]
		if a.eliminated or a.crash_t > 0.0 or a.airborne:
			continue
		for j in range(i + 1, racers.size()):
			var b := racers[j]
			if b.eliminated or b.crash_t > 0.0:
				continue
			var ds := b.s - a.s
			var dx := b.x - a.x
			if absf(ds) < 1.9 and absf(dx) < 0.95:
				var sg := signf(dx) if absf(dx) > 0.05 else (1.0 if i % 2 == 0 else -1.0)
				var ma := a.mass
				var mb := b.mass
				a.vx -= sg * 3.0 * mb / (ma + mb) * 2.0
				b.vx += sg * 3.0 * ma / (ma + mb) * 2.0
				if absf(ds) > 0.6 and absf(dx) < 0.7:
					var back := a if ds > 0.0 else b
					var front := b if ds > 0.0 else a
					back.v = minf(back.v, front.v * 1.02)
					front.v += 0.5
				if a.bump_t <= 0.0 and b.bump_t <= 0.0:
					a.bump_t = 0.3
					b.bump_t = 0.3
					if not (god and (a.is_player or b.is_player)):
						a.damage(1.5)
						b.damage(1.5)
					if a.is_player or b.is_player:
						Sfx.play("bump", 0.6)
						shake = maxf(shake, 0.2)

func _collide_traffic() -> void:
	for r in racers:
		if r.eliminated or r.crash_t > 0.0 or (r.airborne and r.air_y > 0.8):
			continue
		for c in traffic:
			var ds := c.s - r.s
			if absf(ds) > c.half_len + 1.2:
				continue
			var dx := r.x - c.x
			var wlim := c.half_wid + 0.55
			if absf(dx) > wlim:
				continue
			c.passed_flag = true
			if r.invuln > 0.0:
				continue
			var rel := r.v - c.v
			var behind := ds > 0.0
			var sg := signf(dx) if absf(dx) > 0.05 else (1.0 if r.x >= 0.0 else -1.0)
			if behind and absf(dx) < wlim * 0.8:
				# rear-end
				r.s = minf(r.s, c.s - c.half_len - 0.9)
				if r.bump_t <= 0.0:
					var sev := 0
					if rel > 17.0:
						sev = 2
					elif rel > 8.0:
						sev = 1
					r.bump_t = 0.5
					var big := 1.3 if (c.kind == "truck" or c.kind == "bus") else 1.0
					if not (god and r.is_player):
						r.damage([3.0, 12.0, 30.0][sev] * big)
					r.v = minf(r.v, c.v * [0.95, 0.8, 0.5][sev])
					r.vx += sg * 3.0
					if r.is_player:
						shake = maxf(shake, 0.35 + 0.3 * sev)
						Sfx.play("crash" if sev > 0 else "bump", 0.8)
						combo = 1
						toast.emit(["BUMP", "COLLISION", "CRASH"][sev], 2)
					if sev == 2:
						r.crash(2, int(sg))
					elif sev == 1 and rel > 12.0:
						r.crash(1, int(sg))
			else:
				# sideswipe
				r.vx += sg * 14.0 * get_physics_process_delta_time() * 6.0
				if r.bump_t <= 0.0:
					r.bump_t = 0.4
					if not (god and r.is_player):
						r.damage(2.5)
					r.v *= 0.96
					if r.is_player:
						shake = maxf(shake, 0.3)
						Sfx.play("bump", 0.8)
						combo = 1

func _pickups_step() -> void:
	for p in pickups:
		if not p["alive"]:
			continue
		var ps: float = p["s"]
		if absf(ps - player.s) > 150.0:
			# AI pickups only while near the player
			continue
		for r in racers:
			if r.eliminated or r.crash_t > 0.0:
				continue
			if absf(r.s - ps) < 2.2 and absf(r.x - float(p["x"])) < 1.8:
				_collect(r, p)
				break

func _collect(r: Racer, p: Dictionary) -> void:
	var k: String = p["kind"]
	if not r.is_player and k == "cash":
		return
	p["alive"] = false
	(p["node"] as Node3D).visible = false
	match k:
		"nitro":
			r.nitro = minf(float(r.stats["nitro_cap"]), r.nitro + 35.0)
		"repair":
			r.health = minf(r.max_health, r.health + 30.0)
			r.cond = minf(100.0, r.cond + 30.0)
		"cash":
			st["cash"] += 60
		_:
			r.set_weapon(k, int(Data.WEAPONS[k]["dur"]))
	if r.is_player:
		Sfx.play("pickup")
		toast.emit({"nitro": "NITRO +", "repair": "REPAIR +", "cash": "CASH +60", "bat": "BAT - PUNCH TO SWING", "chain": "CHAIN - PUNCH TO SWING", "pipe": "PIPE - PUNCH TO SWING"}[k], 1)

# ---------------------------------------------------------------- rewards
var drift_acc := 0.0
var drift_cash := 0.0
var air_hint := false
var buf_punch := 0.0
var buf_kick := 0.0
var was_air := false

func _drift_air_rewards(dt: float) -> void:
	if player.drift_t > 0.5 and player.crash_t <= 0.0:
		if drift_acc <= 0.0:
			toast.emit("DRIFT!", 1)
			Sfx.play("screech", 0.7)
		elif fmod(drift_acc, 0.6) > 0.6 - dt:
			Sfx.play("screech", 0.5, randf_range(0.95, 1.1))
		drift_acc += dt
		var rate := 1.0 + minf(drift_acc, 5.0) * 0.4
		drift_cash += 14.0 * rate * dt
		score += 160.0 * rate * dt
		player.nitro = minf(float(player.stats["nitro_cap"]), player.nitro + 16.0 * dt)
	elif drift_acc > 0.0 and player.drift_t <= 0.0:
		if drift_acc > 1.2:
			toast.emit("DRIFT +$%d" % int(drift_cash), 1)
			_combo_add(1)
		st["cash"] += int(drift_cash)
		drift_acc = 0.0
		drift_cash = 0.0
	if player.airborne and not air_hint and not autopilot:
		air_hint = true
		toast.emit("AIR! KICK = FLIP   PUNCH = SPIN", 1)
	if player.airborne and not was_air:
		Sfx.play("whoosh", 0.9)
	was_air = player.airborne
	if not player.land_evt.is_empty():
		var le: Dictionary = player.land_evt
		player.land_evt = {}
		var tr := int(le["tricks"])
		Sfx.play("thud", 1.0)
		if bool(le["attempt"]) and not bool(le["clean"]):
			player.v *= 0.55
			player.hit_flash = 0.3
			shake = maxf(shake, 0.6)
			toast.emit("SKETCHY LANDING", 2)
		else:
			var cash := int(float(le["air"]) * 30.0) + tr * 150
			st["cash"] += cash
			score += float(cash) * 4.0
			player.nitro = minf(float(player.stats["nitro_cap"]), player.nitro + 10.0 + tr * 25.0)
			Sfx.play("stinger" if tr > 0 else "overtake", 0.9)
			if tr > 0:
				_combo_add(tr)
			toast.emit(("%dx TRICK  +$%d" % [tr, cash]) if tr > 0 else "AIR TIME  +$%d" % cash, 1)

func _rewards(dt: float) -> void:
	_drift_air_rewards(dt)
	combo_t = maxf(0.0, combo_t - dt)
	if combo_t <= 0.0 and combo > 1:
		combo = 1
	if player.crash_t > 0.0 or state != RState.RACING:
		for c in traffic:
			c.prev_ds = c.s - player.s
		return
	score += player.v * dt * 0.1
	for c in traffic:
		var ds := c.s - player.s
		if c.prev_ds > 0.0 and ds <= 0.0 and not c.passed_flag and player.v > c.v + 3.0:
			var gap := absf(c.x - player.x) - c.half_wid
			if gap < 1.35:
				st["near"] += 1
				_combo_add(1)
				var pts := 100.0 * combo * (1.5 if gap < 0.7 else 1.0)
				score += pts
				player.nitro = minf(float(player.stats["nitro_cap"]), player.nitro + 9.0)
				Sfx.play("nearmiss", 0.8)
				toast.emit("NEAR MISS x%d" % combo, 1)
			else:
				score += 20.0
		c.prev_ds = ds
	for r in racers:
		if r == player or r.eliminated:
			continue
		var ahead := r.s > player.s
		if rel_prev.has(r) and rel_prev[r] != ahead and not ahead and r.crash_t <= 0.0:
			st["overtakes"] += 1
			score += 200.0
			player.nitro = minf(float(player.stats["nitro_cap"]), player.nitro + 12.0)
			Sfx.play("overtake", 0.8)
			toast.emit("OVERTAKE", 1)
		rel_prev[r] = ahead

func _rank() -> void:
	var order := racers.duplicate()
	order.sort_custom(func(a: Racer, b: Racer) -> bool:
		if a.eliminated != b.eliminated:
			return not a.eliminated
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.finish_time < b.finish_time
		return a.s > b.s)
	for i in order.size():
		(order[i] as Racer).place = i + 1

func progress() -> float:
	return clampf(player.s / track.finish_s, 0.0, 1.0)

# ---------------------------------------------------------------- objectives
func _finish_checks(dt: float) -> void:
	for r in racers:
		if not r.finished and r.s >= track.finish_s and not r.eliminated:
			r.finished = true
			r.finish_time = time - (r.s - track.finish_s) / maxf(r.v, 1.0)
			r.state = Racer.St.FINISHING
			if r == player and not done:
				_on_player_finish()
	if done or state != RState.RACING:
		return
	# checkpoints
	if cp_next < track.checkpoints.size() and player.s >= float(track.checkpoints[cp_next]):
		cp_next += 1
		if mode == "time":
			time_left += 25.0
			toast.emit("CHECKPOINT +25s", 1)
		else:
			toast.emit("CHECKPOINT", 0)
		Sfx.play("pickup", 0.6)
	if player.health <= 0.0 and player.crash_t < 0.7:
		st["wrecked"] += 1
		_end(false, "WRECKED", true)
		return
	match mode:
		"boss":
			if boss != null and boss.has_meta("ko"):
				_end(true, "BOSS DOWN", false)
		"time", "highway", "survival", "chase":
			time_left -= dt
			if mode == "chase" and time_left <= 0.0:
				_end(true, "ESCAPED THE POLICE", false)
			elif mode == "survival" and time_left <= 0.0:
				_end(true, "SURVIVED", false)
			elif mode == "highway" and score >= float(def["score_goal"]):
				_end(true, "SCORE REACHED", false)
			elif mode != "survival" and mode != "chase" and time_left <= 0.0:
				_end(false, "TIME UP", true)
		"knockout":
			elim_t -= dt
			if elim_t <= 0.0:
				_eliminate_last()
		"revenge":
			if target_rival != null and target_rival.has_meta("ko") and not done:
				_end(true, "TARGET DOWN", false)

func _eliminate_last() -> void:
	elim_t = 25.0
	var worst: Racer = null
	for r in racers:
		if r.eliminated or r.finished:
			continue
		if worst == null or r.s < worst.s:
			worst = r
	if worst == null:
		return
	worst.eliminated = true
	worst.crash(1, 1)
	toast.emit("%s ELIMINATED" % ("YOU" if worst.is_player else worst.rname.to_upper()), 2 if worst.is_player else 3)
	if worst.is_player:
		_end(false, "ELIMINATED", true)
	else:
		var left := 0
		for r in racers:
			if not r.eliminated:
				left += 1
		if left <= 1:
			_end(true, "LAST RIDER STANDING", false)

func _on_player_finish() -> void:
	match mode:
		"race", "rival":
			var p := 1
			for r in racers:
				if r != player and r.finished and r.finish_time < player.finish_time:
					p += 1
			_end(p <= int(def["need_place"]), "FINISHED P%d" % p, false)
		"knockout":
			_end(true, "FINISHED", false)
		"time":
			_end(time_left > 0.0, "FINISHED", false)
		"survival":
			_end(true, "SURVIVED", false)
		"chase":
			_end(true, "ESCAPED THE POLICE", false)
		"boss":
			var ko2 := boss != null and boss.has_meta("ko")
			if ko2:
				_end(true, "BOSS DOWN", false)
			elif boss != null and not (boss.finished and boss.finish_time < player.finish_time):
				boss_outran = true
				_end(true, "OUTRAN THE BOSS", false)
			else:
				_end(false, "BOSS BEAT YOU", false)
		"highway":
			var ok := score >= float(def["score_goal"])
			_end(ok, "SCORE REACHED" if ok else "SCORE TOO LOW", false)
		"revenge":
			var ko := target_rival != null and target_rival.has_meta("ko")
			_end(ko, "TARGET DOWN" if ko else "TARGET GOT AWAY", false)

func final_place() -> int:
	var p := 1
	for r in racers:
		if r == player:
			continue
		if r.eliminated:
			continue
		if r.finished and (not player.finished or r.finish_time < player.finish_time):
			p += 1
		elif not r.finished and r.s > player.s and not player.finished:
			p += 1
	return p

func _end(win: bool, reason: String, game_over: bool) -> void:
	if done:
		return
	done = true
	state = RState.GAME_OVER if game_over else RState.FINISHED
	var place := final_place()
	var base := int(def["reward"])
	var mult := 0.25
	if win:
		match mode:
			"race", "rival":
				mult = [1.0, 0.65, 0.45][clampi(place - 1, 0, 2)]
			"boss":
				mult = 0.5 if boss_outran else 1.0
			_:
				mult = 1.0
	elif mode == "race" or mode == "rival":
		mult = 0.2 if place <= 4 else 0.1
	var daily_done: bool = bool(def.get("daily", false)) and int(Save.d["daily"].get("claimed", 0)) == int(def.get("date", 0))
	if daily_done:
		mult *= 0.15
	var bonus := int(st["cash"]) + int(st["takedowns"]) * 80 + int(st["near"]) * 15 + int(st["overtakes"]) * 40 + int(st["cops"]) * 60 + (int(st["combo"]) - 1) * 25
	var money := int(base * mult) + bonus
	var first_clear: bool = not Save.d["done"].has(def["id"])
	var rep := 0
	if win:
		rep = int(def["rep"]) if first_clear else int(def["rep"]) / 3
	var res := {"win": win, "reason": reason, "place": place, "time": time, "money": money, "rep": rep,
		"mode": mode, "id": def["id"], "name": def["name"], "stats": st.duplicate(), "score": int(score),
		"first_clear": first_clear, "game_over": game_over, "shortcut": shortcut_taken, "bonus": bonus, "base": int(base * mult),
		"daily": def.get("daily", false), "daily_repeat": daily_done, "date": int(def.get("date", 0)), "ghost_id": ghost_id,
		"ghost": rec_pts if (win and player.finished and not game_over and ghost_id != "") else [], "ftime": player.finish_time}
	ended.emit(res)

# ---------------------------------------------------------------- police chase
func _spawn_cop() -> void:
	var c := _get_car("cop")
	c.s = player.s - rng.randf_range(55.0, 90.0)
	c.x = Track.LANES[rng.randi() % 4]
	c.v = player.v + 6.0
	c.hp = 40.0 + 6.0 * heat
	c.vx = 0.0
	c.cool = 1.2
	c.wreck_t = 0.0
	c.wreck_ang = 0.0
	c.visible = true
	cops.append(c)

func _update_cops(dt: float) -> void:
	if mode != "chase" or state != RState.RACING:
		return
	heat = clampi(1 + int(time / 15.0), 1, 5)
	cop_t -= dt
	var live := 0
	for c in cops:
		if c.wreck_t <= 0.0:
			live += 1
	if cop_t <= 0.0 and live < 1 + heat:
		_spawn_cop()
		cop_t = maxf(2.5, 8.0 - heat * 1.2)
	var near_d := 999.0
	var i := cops.size() - 1
	while i >= 0:
		var c := cops[i]
		if _step_cop(c, dt):
			_release_car(c)
			cops.remove_at(i)
		else:
			near_d = minf(near_d, absf(c.s - player.s))
		i -= 1
	siren_t -= dt
	if siren_t <= 0.0 and near_d < 300.0:
		siren_t = 1.6
		Sfx.play("siren", clampf(1.0 - near_d / 300.0, 0.12, 0.5))

func _step_cop(c: TrafficCar, dt: float) -> bool:
	if c.wreck_t > 0.0:
		c.wreck_t -= dt
		c.v = move_toward(c.v, 0.0, 25.0 * dt)
		c.s += c.v * dt
		c.x += c.vx * dt
		c.vx *= 0.97
		c.wreck_ang += 9.0 * dt
		c.place_in_world(track)
		return c.wreck_t <= 0.0
	var ds := player.s - c.s
	var tv := player.v * 1.04
	if ds > 8.0:
		tv = player.v * 1.07 + 5.0
	elif ds < -8.0:
		tv = player.v * 0.7
	c.v = move_toward(c.v, tv, 22.0 * dt)
	c.s += c.v * dt
	c.x += c.vx * dt
	c.vx *= pow(0.05, dt)
	c.x = clampf(move_toward(c.x, player.x, (3.5 + heat * 0.5) * dt), -7.2, 7.2)
	c.cool -= dt
	if ds > 280.0:
		c.s = player.s - 80.0
		c.v = player.v
	if c.cool <= 0.0 and player.crash_t <= 0.0 and player.invuln <= 0.0 and absf(ds) < c.half_len + 1.3 and absf(player.x - c.x) < c.half_wid + 0.7:
		var sg := signf(player.x - c.x)
		if sg == 0.0:
			sg = 1.0
		if not god:
			player.damage(9.0 + heat * 1.5, float(diff["dmg_taken"]))
		player.vx += sg * 9.0
		player.v *= 0.92
		c.vx -= sg * 6.0
		c.cool = 1.4
		st["rams"] += 1
		combo = 1
		shake = maxf(shake, 0.6)
		Sfx.play("crash", 0.8)
		toast.emit("RAMMED!", 2)
	c.place_in_world(track)
	c.flash(time)
	return false

func _hit_cop(c: TrafficCar, dmg: float, sd: int, kn: float, wid: String) -> void:
	c.hp -= dmg
	c.vx += sd * kn * 0.6
	c.v *= 0.85
	st["hits"] += 1
	_hit_fx(player.global_position + Vector3(sd * 2.0, 0, -1.0), wid)
	_combo_add(1)
	if c.hp <= 0.0 and c.wreck_t <= 0.0:
		c.wreck_t = 1.4
		c.vx = sd * 8.0
		st["cops"] += 1
		st["cash"] += 150
		score += 500.0 * combo
		_combo_add(2)
		toast.emit("COP DOWN  +$150", 3)
		Sfx.play("crunch", 1.0)
		shake = 0.8
		_slowmo(0.5, 0.3)
		if rng.randf() < 0.4:
			var k: String = ["bat", "chain", "pipe"][rng.randi() % 3]
			_add_pickup(c.s + 10.0, clampf(c.x, -6.5, 6.5), k)

# ---------------------------------------------------------------- ghost
func _setup_ghost() -> void:
	if mode in ["chase", "survival"]:
		return
	ghost_id = str(def.get("ghost_id", def["id"]))
	var g: Dictionary = Save.d["ghost"].get(ghost_id, {})
	var pts: Array = g.get("pts", [])
	if pts.size() < 8:
		return
	ghost_pts = pts
	ghost_time = float(g.get("time", 0.0))
	print("[ghost] loaded ", ghost_id, " samples=", pts.size() / 2)
	ghost_node = Node3D.new()
	var ps: PackedScene = load("res://assets/bikes/%s.glb" % Racer.BIKE_IDS[clampi(player.body_style, 0, 4)])
	var bike := ps.instantiate()
	ghost_node.add_child(bike)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.4, 0.9, 1.0, 0.35)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in bike.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = gm
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost_node)
	ghost_node.visible = false

func _ghost_step(dt: float) -> void:
	if state == RState.RACING and not done:
		rec_t += dt
		if rec_t >= 0.1:
			rec_t -= 0.1
			rec_pts.append(int(player.s * 10.0))
			rec_pts.append(int(player.x * 100.0))
	if ghost_node == null:
		return
	var gi := time / 0.1
	var i := int(gi)
	var n := ghost_pts.size() / 2
	if state != RState.RACING or i + 1 >= n:
		ghost_node.visible = false
		return
	var f := gi - float(i)
	var gs := lerpf(float(ghost_pts[i * 2]), float(ghost_pts[i * 2 + 2]), f) / 10.0
	var gx := lerpf(float(ghost_pts[i * 2 + 1]), float(ghost_pts[i * 2 + 3]), f) / 100.0
	ghost_gap = gs - player.s
	ghost_node.visible = absf(ghost_gap) < VIEW
	ghost_node.position = track.pos_at(gs, gx)
	ghost_node.rotation = Vector3(atan(track.slope_at(gs)), track.yaw_at(gs), 0.0)

# ---------------------------------------------------------------- headless kick proof
func _kicktest() -> void:
	kt_done = true
	var r: Racer = null
	for o in racers:
		if o != player:
			r = o
			break
	if r == null:
		print("[kicktest] FAIL no rival")
		get_tree().quit(1)
		return
	var cases := [[1.5, 2.0, true], [-3.5, -3.0, true], [4.0, 4.2, true], [-4.0, 0.5, true], [7.0, 0.0, false], [0.0, 7.5, false]]
	var ok := true
	for cs in cases:
		for o in racers:
			o.atk_cd = 0.0
		r.s = player.s + float(cs[0])
		r.x = player.x + float(cs[1])
		r.crash_t = 0.0
		r.invuln = 0.0
		r.health = r.max_health
		r.finished = false
		var hp0 := r.health
		var vx0 := r.vx
		_melee(player, 0, true)
		var hit := r.health < hp0
		var pass_ok := hit == bool(cs[2])
		ok = ok and pass_ok
		print("[kicktest] dsx=%.1f dx=%.1f hit=%s hp %.1f->%.1f dvx=%.1f %s" % [cs[0], cs[1], hit, hp0, r.health, r.vx - vx0, "ok" if pass_ok else "BAD"])
	print("[kicktest] ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

# ---------------------------------------------------------------- camera
func _update_camera(dt: float, snap: bool) -> void:
	var p := player
	var back := 3.9 + p.v * 0.022
	var height := 1.75 + p.v * 0.006
	var cs := p.s - back
	var want := track.pos_at(cs, p.x * 0.8, height)
	if not cam_init or snap:
		cam_pos = want
		cam_init = true
	else:
		cam_pos = cam_pos.lerp(want, 1.0 - exp(-dt * 6.5))
	var look := track.pos_at(p.s + 13.0, p.x * 0.9, 1.5)
	var sk := float(Save.setting("shake"))
	shake = maxf(0.0, shake - dt * 2.2)
	var off := Vector3.ZERO
	var amp := (shake * 0.35 + (0.03 if p.nitro_on else 0.0) + p.v * 0.0004) * sk
	if amp > 0.0:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * amp
	cam.global_position = cam_pos + off
	cam.look_at(look + off * 0.5, Vector3.UP)
	var tilt := -p.vx * 0.012 - track.curve_at(p.s) * p.v * 0.35
	cam.rotate_object_local(Vector3(0, 0, 1), clampf(tilt, -0.2, 0.2))
	var tfov := 62.0 + p.v * 0.13 + (9.0 if p.nitro_on else 0.0)
	cam.fov = lerpf(cam.fov, tfov, clampf(dt * 4.0, 0.0, 1.0))
	if rcam != null and not low_q:
		_update_reflection()
	_watch_fps(dt)

# ---------------------------------------------------------------- debug helpers
func dbg_text() -> String:
	var t := "t %.1f  s %.0f  v %.1f  x %.1f  traffic %d  fps %d\n" % [time, player.s, player.v, player.x, traffic.size(), Engine.get_frames_per_second()]
	for r in racers:
		t += "%s %s s=%.0f v=%.0f hp=%.0f %s\n" % [r.rname, Racer.ST_NAMES[r.state], r.s, r.v, r.health, "FIN" if r.finished else ""]
	return t

func dbg_key(k: int) -> void:
	match k:
		KEY_F2:
			god = not god
			toast.emit("GOD " + ("ON" if god else "OFF"), 0)
		KEY_F3:
			player.s = maxf(player.s, track.finish_s - 350.0)
		KEY_F4:
			player.crash(2, 1)
		KEY_F5:
			player.nitro = float(player.stats["nitro_cap"])
		KEY_F6:
			score += 1000.0
