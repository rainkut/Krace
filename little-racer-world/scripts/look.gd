class_name Look
extends RefCounted
## Shared lighting / sky / colour grading so the town reads as a warm, hazy Rajasthan afternoon.

## [sun pitch, sun yaw, sun energy, sun colour, fog colour, fog density, ambient energy, sky energy]
const TOD := [
	[-22.0, -95.0, 1.0, "ffd9b0", "e6cfa8", 0.0034, 0.70, 0.90],
	[-38.0, -52.0, 1.25, "ffe9c8", "dccfb0", 0.0026, 0.80, 1.0],
	[-14.0, -70.0, 1.1, "ff9a4d", "e8b88a", 0.0026, 0.60, 0.78],
	[-5.0, -60.0, 0.45, "ff6a3a", "9a86a0", 0.0030, 0.45, 0.50],
]

const SKY_NAMES := ["morning", "noon", "evening", "dusk"]

static func add_to(parent: Node, shadows: bool, shadow_dist := 140.0) -> void:
	var high := Settings.quality_level() == 2
	var tod: Array = TOD[clampi(Settings.time_of_day, 0, 3)]
	var vp := parent.get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(4096 if high else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var hdr := "res://assets/sky/%s_%s.hdr" % [SKY_NAMES[clampi(Settings.time_of_day, 0, 3)], "2k" if high else "1k"]
	if not ResourceLoader.exists(hdr):
		hdr = hdr.replace("_2k", "_1k")
	var tex = load(hdr) if ResourceLoader.exists(hdr) else null
	if tex is Texture2D:
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = tex
		pm.energy_multiplier = 1.05
		sky.sky_material = pm
		sky.radiance_size = Sky.RADIANCE_SIZE_256 if high else Sky.RADIANCE_SIZE_128
	else:
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color("2f78d8")
		sm.sky_horizon_color = Color("cfe0ee")
		sm.ground_horizon_color = Color("cfe0ee")
		sm.ground_bottom_color = Color("a99e86")
		sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(tod[6])
	env.background_energy_multiplier = float(tod[7])
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.fog_enabled = true
	env.fog_light_color = Color(str(tod[4]))
	env.fog_density = float(tod[5])
	if high:
		env.fog_aerial_perspective = 0.35
		env.fog_sun_scatter = 0.25
	env.fog_sky_affect = 0.42
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	env.glow_enabled = true
	env.glow_intensity = 0.8 if high else 0.55
	env.glow_bloom = 0.1 if high else 0.06
	env.glow_hdr_threshold = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	Compounds.add_clouds(parent, Settings.time_of_day)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(float(tod[0]), float(tod[1]), 0)
	sun.light_energy = float(tod[2])
	sun.light_color = Color(str(tod[3]))
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = shadow_dist * (1.9 if high else 1.0)
	sun.shadow_bias = 0.15
	sun.shadow_normal_bias = 2.0
	parent.add_child(sun)
