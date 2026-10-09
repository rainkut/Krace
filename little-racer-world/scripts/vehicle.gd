class_name Vehicle
extends RigidBody3D
## Arcade car: a box-shaped rigid body (so walls/other cars push back realistically) whose
## planar velocity is shaped every physics step - forward accel/brake, lateral grip, and a
## speed-dependent steering yaw rate. Inputs are plain fields so a player or an AI can drive it.

signal bumped(strength: float)

var def: Dictionary = {}
var throttle := 0.0      # 0..1
var brake := 0.0         # 0..1 (reverses when stopped)
var steer := 0.0         # -1 left .. +1 right
var handbrake := false
var reverse_now := false   # AI/explicit reverse; players get it after holding brake while stopped
var frozen_control := false
var max_speed := 30.0
var accel := 14.0
var handling := 1.0
var grip := 9.0
var drift_grip := 1.6
var steer_rate := 2.3
var on_road := true
var speed := 0.0         # signed forward speed (m/s)
var road_query := Callable()
var visual: Node3D
var half_height := 0.6

var _stopped_brake_t := 0.0
var _teleport_pending := false
var _teleport_xf := Transform3D.IDENTITY
var _last_set_speed := 0.0
var _vis_roll := 0.0
var _vis_pitch := 0.0

static func create(vehicle_def: Dictionary, paint_index: int) -> Vehicle:
	var v := Vehicle.new()
	v.def = vehicle_def
	v.max_speed = float(vehicle_def.get("max_speed", 30))
	v.accel = float(vehicle_def.get("accel", 14))
	v.handling = float(vehicle_def.get("handling", 1.0))
	v.grip = float(vehicle_def.get("grip", 9))
	var s := float(vehicle_def.get("model_scale", 1.75))
	v.mass = 1200.0
	v.gravity_scale = 1.0
	v.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.linear_damp = 0.0
	v.angular_damp = 0.0
	v.axis_lock_angular_x = true
	v.axis_lock_angular_z = true
	v.can_sleep = false
	v.collision_layer = 2
	v.collision_mask = 1 | 2
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	mat.bounce = 0.05
	v.physics_material_override = mat
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5 * s * 0.88, v.half_height * 2.0, 2.55 * s * 0.95)
	shape.shape = box
	v.add_child(shape)
	v.visual = CarVisual.build(vehicle_def, paint_index, v.half_height)
	v.add_child(v.visual)
	return v

func _ready() -> void:
	add_to_group("vehicle")

func teleport_to(xf: Transform3D) -> void:
	_teleport_xf = xf
	_teleport_pending = true

func _physics_process(_dt: float) -> void:
	if road_query.is_valid():
		on_road = road_query.call(global_position)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _teleport_pending:
		_teleport_pending = false
		state.transform = _teleport_xf
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_last_set_speed = 0.0
		return
	var dt := state.step
	var basis := state.transform.basis
	var fwd := -basis.z
	var right := basis.x
	var v := state.linear_velocity
	var vy := v.y
	var horiz := Vector3(v.x, 0.0, v.z)
	var drop := _last_set_speed - horiz.length()
	if drop > 6.0:
		bumped.emit(clampf(drop / 22.0, 0.0, 1.0))
	var vf := horiz.dot(fwd)
	var vl := horiz.dot(right)
	var th := 0.0 if frozen_control else throttle
	var br := 1.0 if frozen_control else brake
	var lim := max_speed * (1.0 if on_road else 0.62)
	if th > 0.0:
		if vf < lim:
			vf += accel * th * (1.0 - clampf(vf / lim, 0.0, 1.0) * 0.72) * dt
		else:
			vf = move_toward(vf, lim, 18.0 * dt)
	if br > 0.0:
		if vf > 0.5:
			vf = maxf(0.0, vf - 34.0 * br * dt)
			_stopped_brake_t = 0.0
		else:
			_stopped_brake_t += dt
			if not frozen_control and (reverse_now or _stopped_brake_t > 0.7):
				vf = maxf(-max_speed * 0.3, vf - accel * 0.55 * br * dt)
			else:
				vf = move_toward(vf, 0.0, 20.0 * dt)
	else:
		_stopped_brake_t = 0.0
	if th == 0.0 and br == 0.0:
		vf = move_toward(vf, 0.0, 5.0 * dt)
	vf -= vf * (0.03 if on_road else 0.28) * dt
	if handbrake and not frozen_control:
		vf = move_toward(vf, 0.0, 9.0 * dt)
	var g := drift_grip if (handbrake and not frozen_control) else grip
	vl = lerpf(vl, 0.0, 1.0 - exp(-g * dt))
	var spd_factor := clampf(absf(vf) / 6.0, 0.0, 1.0)
	var rate := steer_rate * handling / (1.0 + absf(vf) / max_speed * 1.1)
	if handbrake:
		rate *= 1.5
	var yaw := -steer * rate * spd_factor * signf(vf)
	state.angular_velocity = Vector3(0.0, yaw, 0.0)
	var nv := fwd * vf + right * vl
	_last_set_speed = nv.length()
	speed = vf
	state.linear_velocity = Vector3(nv.x, vy, nv.z)

func _process(dt: float) -> void:
	if visual == null:
		return
	var target_roll := clampf(-steer * absf(speed) * 0.0035, -0.07, 0.07)
	var target_pitch := clampf((throttle - brake) * 0.025, -0.04, 0.04)
	_vis_roll = lerpf(_vis_roll, target_roll, 1.0 - exp(-8.0 * dt))
	_vis_pitch = lerpf(_vis_pitch, target_pitch, 1.0 - exp(-6.0 * dt))
	visual.rotation = Vector3(_vis_pitch, 0.0, _vis_roll)

func heading() -> float:
	var f := -global_transform.basis.z
	return atan2(-f.x, -f.z)
