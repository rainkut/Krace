class_name Look
extends RefCounted
## Shared lighting / sky / colour grading so the town reads as a warm, hazy Rajasthan afternoon.

static func add_to(parent: Node, shadows: bool, shadow_dist := 140.0) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var tex = load("res://assets/sky/sky.hdr") if ResourceLoader.exists("res://assets/sky/sky.hdr") else null
	if tex is Texture2D:
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = tex
		pm.energy_multiplier = 1.05
		sky.sky_material = pm
	else:
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color("2f78d8")
		sm.sky_horizon_color = Color("cfe0ee")
		sm.ground_horizon_color = Color("cfe0ee")
		sm.ground_bottom_color = Color("a99e86")
		sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.fog_enabled = true
	env.fog_light_color = Color("d9d2c0")
	env.fog_density = 0.0021
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -52, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("ffe9c8")
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = shadow_dist
	sun.shadow_bias = 0.15
	sun.shadow_normal_bias = 2.0
	parent.add_child(sun)
