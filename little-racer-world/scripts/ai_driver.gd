class_name AIDriver
extends Node
## Waypoint follower. Plain pure-pursuit steering plus corner-aware target speed; no
## rubber-banding or cheating - it drives the same car physics as the player.

var car: Vehicle
var route: PackedVector3Array
var racer: Dictionary          # shared with the race manager; racer.count = waypoints passed
var skill := 0.88
var lane := 0.0
var ambient := false           # traffic: advances its own waypoints and keeps distance
var _stuck_t := 0.0
var _reverse_t := 0.0
var _chk_pos := Vector3.ZERO
var _chk_t := 0.0

func _physics_process(dt: float) -> void:
	if car == null or route.is_empty():
		return
	car.handbrake = false
	if car.frozen_control:
		car.throttle = 0.0
		return
	var n := route.size()
	var idx: int = int(racer["count"]) % n
	var prev := route[(idx - 1 + n) % n]
	var p := route[idx]
	var nxt := route[(idx + 1) % n]
	var nn := route[(idx + 2) % n]
	var d_in := (p - prev).normalized()
	var d_out := (nxt - p).normalized()
	var side_in := Vector3(-d_in.z, 0.0, d_in.x) * lane      # lane offset to the car's left of travel
	var side_out := Vector3(-d_out.z, 0.0, d_out.x) * lane
	var here := car.global_position
	var dist := Vector2(p.x - here.x, p.z - here.z).length()
	if ambient and dist < 9.0 and int(racer["count"]) < n - 1:
		racer["count"] = int(racer["count"]) + 1
	var blend := clampf(1.0 - dist / 20.0, 0.0, 1.0) * 0.55
	var aim := (p + side_in).lerp(nxt + side_out, blend)
	var local := car.global_transform.affine_inverse() * aim
	var angle := atan2(local.x, -local.z)
	var turn := absf(d_in.signed_angle_to(d_out, Vector3.UP))
	var turn2 := absf(d_out.signed_angle_to((nn - nxt).normalized(), Vector3.UP))
	var corner_speed := 15.0 * (0.9 + skill * 0.15)
	var limit := car.max_speed * skill * Settings.ai_scale()
	if turn > 0.6 and dist < 42.0:
		limit = minf(limit, lerpf(car.max_speed, corner_speed, clampf(1.0 - dist / 42.0, 0.25, 1.0)))
	elif turn2 > 0.6 and dist < 14.0:
		limit = minf(limit, corner_speed * 1.2)
	limit *= clampf(1.0 - absf(angle) * 0.5, 0.45, 1.0)
	if ambient:
		limit = minf(limit, _traffic_limit())
	if _reverse_t > 0.0:
		_reverse_t -= dt
		car.throttle = 0.0
		car.brake = 1.0
		car.reverse_now = true
		car.steer = clampf(-angle * 2.0, -1.0, 1.0)
		return
	car.reverse_now = false
	car.steer = clampf(angle * 1.9, -1.0, 1.0)
	var spd := car.speed
	if spd > limit + 1.5:
		car.throttle = 0.0
		car.brake = clampf((spd - limit) / 8.0, 0.2, 1.0)
	else:
		car.throttle = 1.0 if spd < limit else 0.35
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

func _traffic_limit() -> float:
	var fwd := -car.global_transform.basis.z
	var best := 999.0
	for o in get_tree().get_nodes_in_group("vehicle"):
		if o == car:
			continue
		var d: Vector3 = o.global_position - car.global_position
		var ahead := d.dot(fwd)
		if ahead < 0.5 or ahead > 22.0 or absf(d.dot(car.global_transform.basis.x)) > 2.3:
			continue
		best = minf(best, ahead)
	if best > 20.0:
		return 999.0
	return maxf(0.0, (best - 6.0) * 1.2)
