extends Node3D
## 3D feasibility test: one real 3D bike on a wet night road with planar reflections.

var bike: Node3D
var cam: Camera3D
var rcam: Camera3D
var rvp: SubViewport
var road_mat: ShaderMaterial
var scroll := 0.0
var speed := 40.0
var lamps: Node3D
var fps_label: Label
var orbit := 0.0
var orbit_target := 0.0
var q_high := true
var rain: GPUParticles3D

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.5)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.12, 0.2)
	env.fog_density = 0.006
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-35, 150, 0)
	moon.light_color = Color(0.5, 0.6, 1.0)
	moon.light_energy = 0.5
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 25.0
	add_child(moon)
	rvp = SubViewport.new()
	rvp.size = Vector2i(960, 540)
	rvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	rvp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(rvp)
	rvp.world_3d = get_viewport().world_3d
	rcam = Camera3D.new()
	rcam.far = 200.0
	rvp.add_child(rcam)
	cam = Camera3D.new()
	cam.far = 300.0
	cam.fov = 60.0
	add_child(cam)
	_road()
	_bike()
	_lamps()
	_rain()
	var cl := CanvasLayer.new()
	add_child(cl)
	fps_label = Label.new()
	fps_label.position = Vector2(20, 14)
	fps_label.add_theme_font_size_override("font_size", 28)
	cl.add_child(fps_label)
	var hint := Label.new()
	hint.text = "drag: orbit   tap top-right: quality (high/low)"
	hint.position = Vector2(20, 60)
	hint.add_theme_font_size_override("font_size", 20)
	cl.add_child(hint)

func _road() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 260)
	mi.mesh = pm
	mi.position = Vector3(0, 0, -100)
	road_mat = ShaderMaterial.new()
	road_mat.shader = load("res://road.gdshader")
	road_mat.set_shader_parameter("refl", rvp.get_texture())
	mi.material_override = road_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for sx in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.9, 260)
		w.mesh = bm
		w.position = Vector3(sx * 7.3, 0.45, -100)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.26, 0.3)
		m.roughness = 0.8
		w.material_override = m
		add_child(w)
		for i in 14:
			var b := MeshInstance3D.new()
			var bb := BoxMesh.new()
			var h := randf_range(18, 60)
			bb.size = Vector3(10, h, randf_range(10, 16))
			b.mesh = bb
			b.position = Vector3(sx * randf_range(15, 22), h * 0.5, -i * 18.0 + 10)
			var bm2 := StandardMaterial3D.new()
			bm2.albedo_color = Color(0.06, 0.07, 0.11)
			bm2.emission_enabled = true
			bm2.emission = Color(1.0, 0.8, 0.5)
			bm2.emission_energy_multiplier = 0.06
			bm2.roughness = 0.6
			b.material_override = bm2
			add_child(b)

func _bike() -> void:
	var ps: PackedScene = load("res://models/streak.glb")
	bike = ps.instantiate()
	add_child(bike)
	bike.position = Vector3(0, 0, 0)
	bike.scale = Vector3.ONE * 1.1
	var hl := SpotLight3D.new()
	hl.position = Vector3(0, 1.0, -1.0)
	hl.spot_range = 45.0
	hl.spot_angle = 28.0
	hl.light_energy = 6.0
	hl.light_color = Color(1, 0.95, 0.82)
	hl.rotation_degrees.x = -4
	bike.add_child(hl)
	var tl := OmniLight3D.new()
	tl.position = Vector3(0, 0.9, 0.9)
	tl.light_color = Color(1, 0.1, 0.05)
	tl.light_energy = 1.2
	tl.omni_range = 5.0
	bike.add_child(tl)

func _lamps() -> void:
	lamps = Node3D.new()
	add_child(lamps)
	for i in 8:
		for sx in [-1.0, 1.0]:
			var n := Node3D.new()
			n.position = Vector3(sx * 6.6, 0, -i * 30.0)
			var pole := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.07
			cm.height = 8.0
			pole.mesh = cm
			pole.position.y = 4.0
			n.add_child(pole)
			var head := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.3
			sm.height = 0.5
			head.mesh = sm
			head.position = Vector3(-sx * 0.8, 8.0, 0)
			var m := StandardMaterial3D.new()
			m.emission_enabled = true
			m.emission = Color(1.0, 0.8, 0.45)
			m.emission_energy_multiplier = 6.0
			m.albedo_color = Color(1, 0.9, 0.7)
			head.material_override = m
			n.add_child(head)
			if i % 2 == 0:
				var ol := OmniLight3D.new()
				ol.position = head.position
				ol.light_color = Color(1.0, 0.8, 0.5)
				ol.light_energy = 6.0
				ol.omni_range = 22.0
				n.add_child(ol)
			lamps.add_child(n)

func _rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 2500
	rain.lifetime = 0.8
	rain.position = Vector3(0, 12, -10)
	rain.visibility_aabb = AABB(Vector3(-20, -20, -40), Vector3(40, 40, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12, 0.5, 25)
	pm.direction = Vector3(0, -1, 0.3)
	pm.spread = 2.0
	pm.initial_velocity_min = 35.0
	pm.initial_velocity_max = 40.0
	pm.gravity = Vector3.ZERO
	rain.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.8, 0.012)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.7, 0.8, 1.0, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = m
	rain.draw_pass_1 = bm
	add_child(rain)

func _input(e: InputEvent) -> void:
	if e is InputEventScreenDrag:
		orbit_target += e.relative.x * 0.006
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		orbit_target += e.relative.x * 0.006
	elif (e is InputEventScreenTouch and e.pressed and e.position.x > get_viewport().get_visible_rect().size.x - 160 and e.position.y < 160) \
			or (e is InputEventKey and e.pressed and e.keycode == KEY_Q):
		q_high = not q_high
		rvp.size = Vector2i(960, 540) if q_high else Vector2i(480, 270)
		rvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_viewport().scaling_3d_scale = 1.0 if q_high else 0.7

func _process(dt: float) -> void:
	scroll += speed * dt
	road_mat.set_shader_parameter("scroll", -scroll)
	for n in lamps.get_children():
		n.position.z += speed * dt
		if n.position.z > 20.0:
			n.position.z -= 240.0
	orbit = lerpf(orbit, orbit_target, dt * 5.0)
	var t := Time.get_ticks_msec() / 1000.0
	bike.rotation.z = sin(t * 0.7) * 0.18
	var a := orbit + sin(t * 0.25) * 0.15
	var d := Vector3(sin(a) * 4.2, 1.5, cos(a) * 4.2)
	cam.position = d
	cam.look_at(Vector3(0, 0.8, -3.0), Vector3.UP)
	rcam.fov = cam.fov
	var cp := cam.global_position
	var fw := -cam.global_transform.basis.z
	rcam.global_position = Vector3(cp.x, -cp.y, cp.z)
	rcam.look_at(Vector3(cp.x + fw.x, -(cp.y + fw.y), cp.z + fw.z), Vector3.DOWN)
	rain.global_position = Vector3(0, 12, cam.global_position.z - 12)
	fps_label.text = "%d fps  %s" % [Engine.get_frames_per_second(), "HIGH" if q_high else "LOW"]
