class_name AIDriver
extends RefCounted
## Rival rider brain: state machine over lane choice, overtaking, defending, fighting and mistakes.

var r: Racer
var base_spd := 1.0
var diff: Dictionary = {}
var aggr_eff := 0.3
var target_x := 0.0
var lane_pref := 0.0
var retarget_t := 0.0
var mistake_t := 0.0
var mistake_kind := 0
var mistake_dir := 0.0
var next_mistake := 6.0
var target: Racer = null
var must_hunt := false
var atk_roll_t := 0.0

func setup(racer: Racer, d: Dictionary, rng: RandomNumberGenerator) -> void:
	r = racer
	diff = d
	base_spd = r.spd_mult
	aggr_eff = clampf(r.aggr * float(d["aggr"]), 0.0, 1.0)
	lane_pref = Track.LANES[rng.randi() % 4]
	next_mistake = rng.randf_range(4.0, 12.0) / float(d["mistake"])

func think(dt: float, race: Node) -> void:
	var track: Track = race.track
	var inp := r.inp
	inp["atk"] = 0
	inp["kick"] = false
	inp["brake"] = 0.0
	inp["nitro"] = false
	inp["throttle"] = 1.0
	if r.crash_t > 0.0:
		inp["throttle"] = 0.0
		inp["steer"] = 0.0
		return
	if r.finished:
		r.state = Racer.St.FINISHING
		inp["throttle"] = 0.0
		inp["steer"] = clampf((0.0 - r.x) * 0.5 - r.vx * 0.3, -1.0, 1.0)
		inp["brake"] = 0.35
		return
	if race.state != race.RState.RACING:
		r.state = Racer.St.IDLE
		inp["throttle"] = 0.0
		inp["steer"] = 0.0
		return
	if r.state == Racer.St.IDLE:
		r.state = Racer.St.RACING
	var st: int = Racer.St.RECOVERING if r.recover_t > 0.0 and r.state == Racer.St.RECOVERING else Racer.St.RACING
	# rubber band toward the player (gentle)
	var player: Racer = race.player
	var rb := 0.0
	if player != null:
		rb = clampf((player.s - r.s) / 450.0, -1.0, 1.0)
	r.spd_mult = base_spd * (1.0 + float(diff["rubber"]) * rb)
	# --- sense
	var look: float = 14.0 + r.v * 0.85
	var hazard_ds := 9999.0
	var hazard_v := 0.0
	for c in race.traffic:
		var ds: float = c.s - r.s
		if ds > 0.0 and ds < look and absf(c.x - r.x) < c.half_wid + 1.3 and ds < hazard_ds:
			hazard_ds = ds
			hazard_v = c.v
	var ahead: Racer = null
	var ahead_ds := 9999.0
	var behind: Racer = null
	var behind_ds := 9999.0
	var adj: Racer = null
	var adj_score := 9999.0
	for o in race.racers:
		if o == r or o.eliminated or o.crash_t > 0.0:
			continue
		var ds2: float = o.s - r.s
		var dx: float = o.x - r.x
		if ds2 > 0.0 and ds2 < 30.0 and absf(dx) < 2.4 and ds2 < ahead_ds:
			ahead = o; ahead_ds = ds2
		if ds2 < 0.0 and ds2 > -22.0 and absf(dx) < 3.6 and -ds2 < behind_ds:
			behind = o; behind_ds = -ds2
		if absf(ds2) < 32.0:
			var sc := absf(ds2) * 0.5 + absf(dx) + (-6.0 if (o == r.grudge or (o.is_player and must_hunt)) else 0.0)
			if sc < adj_score:
				adj = o; adj_score = sc
	retarget_t -= dt
	var desired := target_x
	if retarget_t <= 0.0:
		retarget_t = 0.3
		desired = _best_lane(race, look, ahead)
		target_x = desired
	# --- state selection
	var fight := false
	if adj != null and aggr_eff > 0.05 and not (adj.is_player and race.state != race.RState.RACING):
		var want := aggr_eff * (1.0 if (adj == r.grudge or (adj.is_player and must_hunt)) else 0.6)
		if adj_score < 22.0 and want > 0.25:
			fight = true
	if hazard_ds < look:
		st = Racer.St.AVOIDING_TRAFFIC
		if hazard_ds < 12.0 and r.v > hazard_v + 4.0:
			inp["brake"] = clampf((r.v - hazard_v) / 18.0, 0.2, 0.8)
			inp["throttle"] = 0.0
	elif fight and adj != null:
		st = Racer.St.ATTACKING
		target = adj
		var side := signf(r.x - adj.x)
		if side == 0.0:
			side = 1.0
		var want_x := adj.x + side * 1.55
		if absf(want_x) > Track.ROAD_HALF - 0.8:
			want_x = adj.x - side * 1.55
		target_x = clampf(want_x, -7.4, 7.4)
		var dsa: float = adj.s - r.s
		inp["throttle"] = 1.0 if dsa > 1.0 or r.v < adj.v + 6.0 else 0.5
		if dsa < -2.5:
			inp["brake"] = 0.25
		var dxs: float = (adj.x - r.x)
		atk_roll_t -= dt
		if r.can_attack() and absf(dsa) < 2.0 and absf(dxs) < 2.8 and absf(dxs) > 0.3 and atk_roll_t <= 0.0 and race.time > 6.0:
			atk_roll_t = randf_range(0.5, 1.6) / maxf(0.3, aggr_eff)
			inp["atk"] = int(signf(dxs))
			inp["kick"] = randf() < 0.3
	elif behind != null and r.arch == "defensive":
		st = Racer.St.DEFENDING
		target_x = clampf(lerpf(behind.x, target_x, 0.2), -7.0, 7.0)
	elif ahead != null and ahead.v < r.v + 3.0:
		st = Racer.St.OVERTAKING
		if ahead_ds < 14.0 and absf(ahead.x - r.x) < 2.0:
			# pick the free side
			var left_free := _lane_free(race, ahead.x - 4.0, ahead)
			var right_free := _lane_free(race, ahead.x + 4.0, ahead)
			if left_free and (not right_free or ahead.x > 0.0):
				target_x = clampf(ahead.x - 4.0, -6.2, 6.2)
			elif right_free:
				target_x = clampf(ahead.x + 4.0, -6.2, 6.2)
			else:
				inp["throttle"] = 0.7
	if r.state != Racer.St.RECOVERING or r.recover_t <= 0.0:
		r.state = st
	elif r.recover_t > 0.0:
		inp["throttle"] = 0.6
	# --- mistakes
	next_mistake -= dt
	if mistake_t > 0.0:
		mistake_t -= dt
	elif next_mistake <= 0.0 and r.v > 25.0:
		next_mistake = randf_range(7.0, 16.0) / float(diff["mistake"])
		mistake_t = randf_range(0.5, 1.0)
		mistake_kind = randi() % 2 + 1
		mistake_dir = 1.0 if randf() < 0.5 else -1.0
	# --- steering
	var drift := track.curve_at(r.s) * r.v * r.v * 0.30
	var grip: float = r.stats["grip"] * (1.0 - 0.35 * clampf(r.v / 70.0, 0.0, 1.0))
	var steer := clampf((target_x - r.x) * 0.55 - r.vx * 0.30, -1.0, 1.0)
	steer += clampf(-drift / maxf(grip, 1.0), -0.9, 0.9)
	if mistake_t > 0.0:
		if mistake_kind == 1:
			steer += mistake_dir * 0.45
		else:
			inp["brake"] = maxf(inp["brake"], 0.55)
			inp["throttle"] = 0.0
	inp["steer"] = clampf(steer, -1.0, 1.0)
	# --- nitro on clear straights
	if r.nitro > 35.0 and st in [Racer.St.RACING, Racer.St.OVERTAKING] and absf(track.curve_at(r.s)) < 0.0012 and hazard_ds > look:
		inp["nitro"] = true
	elif r.nitro_on and r.nitro > 8.0 and hazard_ds > look and st != Racer.St.AVOIDING_TRAFFIC:
		inp["nitro"] = true

func _lane_free(race: Node, lx: float, except: Racer) -> bool:
	if absf(lx) > 6.4:
		return false
	for o in race.racers:
		if o == r or o == except or o.eliminated:
			continue
		if absf(o.x - lx) < 2.2 and o.s - r.s > -8.0 and o.s - r.s < 30.0:
			return false
	for c in race.traffic:
		if absf(c.x - lx) < c.half_wid + 1.4 and c.s - r.s > -6.0 and c.s - r.s < 14.0 + r.v * 0.9:
			return false
	return true

func _best_lane(race: Node, look: float, ahead: Racer) -> float:
	var best := target_x
	var best_cost := 1e9
	for lx in Track.LANES:
		var cost := absf(lx - r.x) * 0.5 + absf(lx - lane_pref) * 0.12
		for c in race.traffic:
			var ds: float = c.s - r.s
			if ds > -5.0 and ds < look * 1.6 and absf(c.x - lx) < c.half_wid + 1.5:
				cost += 40.0 * (1.0 - ds / (look * 1.6)) + 6.0
		if ahead != null and absf(ahead.x - lx) < 2.0 and ahead.s - r.s < 28.0:
			cost += 5.0
		if cost < best_cost:
			best_cost = cost
			best = lx
	return best
