class_name ChaseCamera
extends Camera3D
## Smooth third-person follow camera with wall avoidance and a speed-based field of view.

var target: Vehicle
var yaw := 0.0
var distance := 9.5
var height := 4.2
var _first := true

func snap_to_target() -> void:
	_first = true
	_update(1.0, true)

func _physics_process(dt: float) -> void:
	_update(dt, false)

func _update(dt: float, snap: bool) -> void:
	if target == null:
		return
	var heading := target.heading()
	if _first or snap:
		yaw = heading
	yaw = lerp_angle(yaw, heading, 1.0 - exp(-3.5 * Settings.cam_sensitivity * dt))
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var spd := target.linear_velocity.length()
	var tp := target.global_position + Vector3(0, 0.8, 0)
	var desired := tp - dir * (distance + (0.0 if Settings.reduced_motion else spd * 0.04)) + Vector3(0, height, 0)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(tp, desired, 1)
	var hit := space.intersect_ray(q)
	if hit:
		desired = hit["position"] + (tp - desired).normalized() * 0.8
	if _first or snap:
		global_position = desired
		_first = false
	else:
		global_position = global_position.lerp(desired, 1.0 - exp(-9.0 * Settings.cam_sensitivity * dt))
	look_at(tp + dir * 5.0 + Vector3(0, 0.6, 0), Vector3.UP)
	fov = lerpf(fov, 66.0 + (0.0 if Settings.reduced_motion else minf(spd, 40.0) * 0.45), 1.0 - exp(-3.0 * dt))
