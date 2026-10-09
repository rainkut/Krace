class_name ClutterCrush
extends Node3D
## Light street props (drums, stalls, carts, bikes) get knocked over when the player's car hits them
## at speed: they tumble away, puff some dust, vanish after a moment, and the car only slows a little.

const CELL := 8.0
const MIN_SPEED := 2.5
const MAX_DEBRIS := 10

var _items: Array = []
var _grid := {}
var _debris := 0

func setup(items: Array) -> void:
	_items = items
	for i in items.size():
		var o: Vector3 = items[i]["xf"].origin
		var key := Vector2i(int(floor(o.x / CELL)), int(floor(o.z / CELL)))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)

func _physics_process(_dt: float) -> void:
	for n in get_tree().get_nodes_in_group("crush_cars"):
		var car := n as RigidBody3D
		if car == null:
			continue
		var v := car.linear_velocity
		v.y = 0.0
		var speed := v.length()
		if speed < MIN_SPEED:
			continue
		var p := car.global_position
		var cx := int(floor(p.x / CELL))
		var cz := int(floor(p.z / CELL))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var key := Vector2i(cx + dx, cz + dz)
				if not _grid.has(key):
					continue
				for idx in _grid[key]:
					var it: Dictionary = _items[idx]
					if not it["alive"]:
						continue
					var o: Vector3 = it["xf"].origin
					var rel := Vector2(o.x - p.x, o.z - p.z)
					if rel.length() < float(StreetClutter.CRUSH_RADIUS[it["kind"]]) + 1.0:
						_smash(it, v, speed, car)

func _smash(it: Dictionary, vel: Vector3, speed: float, car: RigidBody3D) -> void:
	it["alive"] = false
	var xf: Transform3D = it["xf"]
	var mm: MultiMesh = it["mm"]
	mm.set_instance_transform(int(it["i"]), Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))
	car.linear_velocity = Vector3(car.linear_velocity.x * 0.94, car.linear_velocity.y, car.linear_velocity.z * 0.94)
	Sfx.play("crunch", clampf(0.35 + speed / 25.0, 0.35, 0.9))
	if _debris >= MAX_DEBRIS:
		return
	_debris += 1
	var mi := MeshInstance3D.new()
	mi.mesh = it["mesh"]
	mi.transform = xf
	add_child(mi)
	var dir := vel.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x) * randf_range(-1.5, 1.5)
	var fling := minf(speed, 25.0)
	var end_pos := xf.origin + dir * fling * 0.35 + side
	var tw := mi.create_tween()
	if Settings.reduced_motion:
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.6)
	else:
		var peak := xf.origin + (end_pos - xf.origin) * 0.5 + Vector3(0, 1.2 + fling * 0.08, 0)
		tw.tween_property(mi, "position", peak, 0.25).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "rotation", Vector3(randf_range(-4, 4), randf_range(-3, 3), randf_range(-4, 4)), 0.9)
		tw.tween_property(mi, "position", Vector3(end_pos.x, 0.12, end_pos.z), 0.3).set_ease(Tween.EASE_IN)
		tw.tween_interval(1.4)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.4)
		_puff(xf.origin)
	tw.tween_callback(func():
		_debris -= 1
		mi.queue_free())

func _puff(at: Vector3) -> void:
	var pt := CPUParticles3D.new()
	pt.one_shot = true
	pt.amount = 10
	pt.lifetime = 0.7
	pt.explosiveness = 1.0
	pt.direction = Vector3.UP
	pt.spread = 60.0
	pt.initial_velocity_min = 1.0
	pt.initial_velocity_max = 2.6
	pt.gravity = Vector3(0, -1.5, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.74, 0.6, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat
	pt.mesh = sm
	pt.position = at + Vector3(0, 0.4, 0)
	add_child(pt)
	pt.emitting = true
	get_tree().create_timer(1.2).timeout.connect(pt.queue_free)
