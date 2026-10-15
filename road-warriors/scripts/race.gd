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

var st := {"overtakes": 0, "near": 0, "takedowns": 0, "crashes": 0, "top": 0.0, "cash": 0, "hits": 0, "wrecked": 0}

var touch_steer := 0.0

func setup(race_def: Dictionary) -> void:
	def = race_def
	mode = def["mode"]
	diff = Data.DIFFICULTY[int(Save.setting("diff"))]
	rng.seed = int(def["seed"]) * 31 + 7
	track = Track.new()
	track.build(def)
	_build_world()
	_build_riders()
	_build_pickups()
	traffic_target = int(round(float(def.get("traffic", 0.5)) * 14.0))
	_seed_traffic()
	match mode:
		"time":
			time_left = float(def["target"])
		"highway":
			time_left = float(def["limit"])
		"survival":
			time_left = float(def["survive"])
	cam = Camera3D.new()
	cam.far = 1400.0
	cam.fov = 70.0
	cam.current = true
	add_child(cam)
	_update_camera(0.1, true)
	Sfx.music(true)

func _exit_tree() -> void:
	Sfx.engine(false)

# ---------------------------------------------------------------- world
func _build_world() -> void:
	var theme := int(def.get("theme", 0))
	var sky := [Color(0.62, 0.78, 0.95), Color(0.30, 0.22, 0.42), Color(0.96, 0.78, 0.55)][theme] as Color
	var amb := [Color(0.62, 0.66, 0.72), Color(0.55, 0.48, 0.62), Color(0.78, 0.68, 0.58)][theme] as Color
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_light_color = sky
	env.fog_density = 0.0018
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = [1.15, 0.8, 1.3][theme]
	sun.light_color = [Color(1, 0.97, 0.9), Color(1.0, 0.7, 0.55), Color(1, 0.9, 0.75)][theme]
	sun.shadow_enabled = false
	add_child(sun)
	track.build_visuals(self)

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
	player.setup({"name": "You", "player": true, "arch": "balanced", "color": b["color"], "body": b["body"],
		"stats": Data.stats(bid, Save.bike_upg(bid))})
	add_child(player)
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
		var rn: String = Data.RIVAL_NAMES[(i + int(def["seed"])) % Data.RIVAL_NAMES.size()]
		if mode == "rival":
			rn = "Mara Slate"
		elif mode == "revenge" and i == int(def.get("target_rival", 0)):
			rn = "Tank Orlo"
		var boost := 1.0
		if mode == "rival":
			boost = float(def.get("rival_boost", 1.0))
		r.setup({"name": rn, "arch": arch, "color": A["color"], "body": i % 5, "stats": Data.stats(bike_id, upg),
			"spd": float(A["spd"]) * float(diff["ai_speed"]) * boost, "acc": A["acc"], "dmg": A["dmg"],
			"aggr": A["aggr"], "mass": A["mass"], "hp": A["hp"]})
		add_child(r)
		r.s = slots[slot_i].x
		r.x = slots[slot_i].y
		slot_i += 1
		var ai := AIDriver.new()
		ai.setup(r, diff, rng)
		if mode == "survival" or (mode == "revenge" and i == int(def.get("target_rival", 0))):
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

func _build_pickups() -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = int(def["seed"]) * 13 + 5
	var kinds := ["nitro", "nitro", "repair", "bat", "chain", "pipe", "cash", "cash"]
	var colors := {"nitro": Color(0.2, 0.9, 1.0), "repair": Color(0.3, 1.0, 0.4), "bat": Color(1.0, 0.6, 0.15),
		"chain": Color(1.0, 0.6, 0.15), "pipe": Color(1.0, 0.6, 0.15), "cash": Color(1.0, 0.85, 0.2)}
	var s := 320.0
	while s < track.finish_s - 250.0:
		var k: String = kinds[prng.randi() % kinds.size()]
		var px: float = Track.LANES[prng.randi() % 4] + prng.randf_range(-0.8, 0.8)
		if mode == "highway" or mode == "time":
			k = ["nitro", "cash", "repair"][prng.randi() % 3]
		var node := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.9, 0.9)
		node.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[k]
		m.emission_enabled = true
		m.emission = colors[k]
		m.emission_energy_multiplier = 0.9
		node.material_override = m
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		pickups.append({"s": s, "x": px, "kind": k, "node": node, "alive": true})
		node.position = track.pos_at(s, px, 1.0)
		s += prng.randf_range(170.0, 300.0)
	if track.shortcut.y > 0.0:
		var ss := track.shortcut.x + 40.0
		while ss < track.shortcut.y - 30.0:
			var node2 := MeshInstance3D.new()
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.8, 0.8, 0.8)
			node2.mesh = bm2
			var m2 := StandardMaterial3D.new()
			m2.albedo_color = colors["cash"]
			m2.emission_enabled = true
			m2.emission = colors["cash"]
			node2.material_override = m2
			add_child(node2)
			pickups.append({"s": ss, "x": 12.0, "kind": "cash", "node": node2, "alive": true})
			node2.position = track.pos_at(ss, 12.0, 1.0)
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
			var n: MeshInstance3D = p["node"]
			n.visible = absf(float(p["s"]) - player.s) < 500.0
			if n.visible:
				n.rotation.y += dt * 2.5
	track.update_visibility(player.s, VIEW)
	_update_camera(dt, false)
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
	if state != RState.RACING:
		return
	if Input.is_action_just_pressed("atk_l"):
		_melee(player, -1, false)
	elif Input.is_action_just_pressed("atk_r"):
		_melee(player, 1, false)
	elif Input.is_action_just_pressed("attack"):
		_melee(player, 0, false)
	elif Input.is_action_just_pressed("kick"):
		_melee(player, 0, true)

# ---------------------------------------------------------------- combat
func _melee(a: Racer, side: int, kick: bool) -> void:
	if not a.can_attack() or a.eliminated:
		return
	var wid: String = "kick" if kick else a.weapon
	var w: Dictionary = Data.WEAPONS[wid]
	var best: Racer = null
	var bd := 99.0
	for o in racers:
		if o == a or o.eliminated or o.crash_t > 0.0 or o.finished:
			continue
		var dsx := o.s - a.s
		var dx := o.x - a.x
		if absf(dsx) > 2.8 or absf(dx) > float(w["reach"]):
			continue
		if side != 0 and absf(dx) > 0.35 and signf(dx) != float(side):
			continue
		var d := absf(dx) + absf(dsx) * 0.5
		if d < bd:
			bd = d
			best = o
	var sd := side
	if sd == 0:
		sd = int(signf(best.x - a.x)) if best != null else (int(signf(float(a.inp["steer"]))) if absf(float(a.inp["steer"])) > 0.2 else 1)
		if sd == 0:
			sd = 1
	a.begin_attack(sd, kick)
	if best == null:
		return
	if not kick:
		a.use_weapon_dur()
	var o2 := best
	var dmg := float(w["dmg"]) * a.dmg_mult_out
	var taken := float(diff["dmg_taken"]) if o2.is_player else 1.0
	if god and o2.is_player:
		dmg = 0.0
	o2.damage(dmg, taken)
	o2.vx += sd * float(w["knock"]) / maxf(0.6, o2.mass)
	o2.v *= 1.0 - float(w["slow"])
	o2.hit_flash = 0.25
	o2.bump_t = 0.2
	a.v *= 1.0 - float(w["slow"]) * 0.3
	Sfx.play("hit", 0.9, randf_range(0.9, 1.1))
	if not a.is_player:
		st["ai_hits"] = int(st.get("ai_hits", 0)) + 1
	if a.is_player:
		st["hits"] += 1
		shake = maxf(shake, 0.25)
		if o2.grudge == null:
			o2.grudge = a
	elif o2.is_player:
		shake = maxf(shake, 0.5)
		toast.emit("%s hit you" % a.rname, 2)
		if a.grudge == null:
			a.grudge = player
	if not o2.is_player and o2.grudge == null:
		o2.grudge = a
	if o2.health <= 0.0 and o2.crash_t <= 0.0:
		_knock_out(o2, a, sd)
	elif dmg >= 22.0 and o2.v > 22.0 and o2.crash_t <= 0.0:
		o2.crash(1, sd)

func _knock_out(o: Racer, by: Racer, side: int) -> void:
	o.crash(2, side)
	o.set_meta("ko", true)
	if by != null and by.is_player and not o.is_player:
		st["takedowns"] += 1
		player.nitro = minf(float(player.stats["nitro_cap"]), player.nitro + 25.0)
		score += 300.0 * combo
		toast.emit("TAKEDOWN  %s" % o.rname, 3)
		Sfx.play("pickup")

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
				toast.emit("WIPEOUT", 2)
		"weapon_broke":
			if r == player:
				toast.emit("Weapon broke", 0)

func _collide_riders() -> void:
	for i in racers.size():
		var a := racers[i]
		if a.eliminated or a.crash_t > 0.0:
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
		if r.eliminated or r.crash_t > 0.0:
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
		toast.emit({"nitro": "NITRO +", "repair": "REPAIR +", "cash": "CASH +60", "bat": "BAT", "chain": "CHAIN", "pipe": "PIPE"}[k], 1)

# ---------------------------------------------------------------- rewards
func _rewards(dt: float) -> void:
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
				combo = mini(combo + 1, 6)
				combo_t = 3.5
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
		"time", "highway", "survival":
			time_left -= dt
			if mode == "survival" and time_left <= 0.0:
				_end(true, "SURVIVED", false)
			elif mode == "highway" and score >= float(def["score_goal"]):
				_end(true, "SCORE REACHED", false)
			elif mode != "survival" and time_left <= 0.0:
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
			_:
				mult = 1.0
	elif mode == "race" or mode == "rival":
		mult = 0.2 if place <= 4 else 0.1
	var bonus := int(st["cash"]) + int(st["takedowns"]) * 80 + int(st["near"]) * 15 + int(st["overtakes"]) * 40
	var money := int(base * mult) + bonus
	var first_clear: bool = not Save.d["done"].has(def["id"])
	var rep := 0
	if win:
		rep = int(def["rep"]) if first_clear else int(def["rep"]) / 3
	var res := {"win": win, "reason": reason, "place": place, "time": time, "money": money, "rep": rep,
		"mode": mode, "id": def["id"], "name": def["name"], "stats": st.duplicate(), "score": int(score),
		"first_clear": first_clear, "game_over": game_over, "shortcut": shortcut_taken, "bonus": bonus, "base": int(base * mult)}
	ended.emit(res)

# ---------------------------------------------------------------- camera
func _update_camera(dt: float, snap: bool) -> void:
	var p := player
	var back := 5.4 + p.v * 0.035
	var height := 2.3 + p.v * 0.008
	var cs := p.s - back
	var want := track.pos_at(cs, p.x * 0.8, height)
	if not cam_init or snap:
		cam_pos = want
		cam_init = true
	else:
		cam_pos = cam_pos.lerp(want, 1.0 - exp(-dt * 9.0))
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
	var tfov := 68.0 + p.v * 0.22 + (9.0 if p.nitro_on else 0.0)
	cam.fov = lerpf(cam.fov, tfov, clampf(dt * 4.0, 0.0, 1.0))

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
