class_name CircuitDriver
extends Node
## AI rival on a racing line around a CircuitRace: pure pursuit on the offset line, corner-limited
## speed profile, polite overtaking, stuck recovery. Same car physics as the player (no cheating).

var car: Vehicle
var circuit: CircuitRace
var racer: Dictionary
var skill := 0.92
var lane := 0.0
var cool_down := false           # after finishing: cruise so the car doesn't block others
var _shift := 0.0
var _stuck_t := 0.0
var _reverse_t := 0.0
var _chk_pos := Vector3.ZERO
var _chk_t := 0.0

func _physics_process(dt: float) -> void:
	if car == null or circuit == null or circuit.n == 0:
		return
	car.handbrake = false
	if car.frozen_control:
		car.throttle = 0.0
		return
	var ci: int = racer["ci"]
	var spd := car.speed
	var ahead := 1 + int((6.0 + maxf(spd, 0.0) * 0.30) / 3.5)
	var near := _nearest_ahead()
	var want_shift := 0.0
	var limit := car.max_speed * skill * Settings.ai_scale()
	if cool_down:
		limit = minf(limit, car.max_speed * 0.5)
	if near.has("gap"):
		var gap: float = near["gap"]
		want_shift = -signf(near["lat"] if absf(near["lat"]) > 0.15 else 1.0) * 1.8
		if gap < 5.5:
			limit = minf(limit, maxf(near["speed"] - 1.0, 4.0))
	_shift = move_toward(_shift, want_shift, 3.0 * dt)
	var target := circuit.aim(ci, ahead, lane, _shift)
	var local := car.global_transform.affine_inverse() * target
	var angle := atan2(local.x, -local.z)
	var la := ci + int(maxf(spd, 0.0) * 0.12 / 3.5)
	limit = minf(limit, circuit.prof[circuit.widx(la)] * (0.9 + skill * 0.1))
	limit *= clampf(1.0 - absf(angle) * 0.45, 0.5, 1.0)
	if _reverse_t > 0.0:
		_reverse_t -= dt
		car.throttle = 0.0
		car.brake = 1.0
		car.reverse_now = true
		car.steer = clampf(-angle * 2.0, -1.0, 1.0)
		return
	car.reverse_now = false
	car.steer = clampf(angle * 2.2, -1.0, 1.0)
	if spd > limit + 1.2:
		car.throttle = 0.0
		car.brake = clampf((spd - limit) / 8.0, 0.2, 1.0)
	else:
		car.throttle = 1.0 if spd < limit else 0.4
		car.brake = 0.0
	_chk_t += dt
	if _chk_t > 1.5:
		_chk_t = 0.0
		if car.throttle > 0.3 and car.global_position.distance_to(_chk_pos) < 0.8 and _stuck_t < 0.1:
			_reverse_t = 1.0
		_chk_pos = car.global_position
	if car.throttle > 0.3 and absf(spd) < 1.2:
		_stuck_t += dt
		if _stuck_t > 1.4:
			_stuck_t = 0.0
			_reverse_t = 1.0
	else:
		_stuck_t = 0.0

func _nearest_ahead() -> Dictionary:
	var fwd := -car.global_transform.basis.z
	var rgt := car.global_transform.basis.x
	var best := {}
	var best_gap := 14.0
	for o in circuit.racers:
		var v: Vehicle = o["vehicle"]
		if v == car:
			continue
		var d := v.global_position - car.global_position
		var a := d.dot(fwd)
		if a < 0.5 or a > best_gap:
			continue
		var l := d.dot(rgt)
		if absf(l) > 1.9:
			continue
		best_gap = a
		best = {"gap": a, "lat": l, "speed": v.speed}
	return best
