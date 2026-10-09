# Dev tool: lays out road pieces in a grid with labels and saves a top-down screenshot,
# so we can see which way each Kenney piece faces.  Run: godot --path . -s tools/probe_roads.gd
extends SceneTree

const NAMES := ["road-straight","road-bend","road-crossroad","road-intersection","road-end","road-bend-square","road-split","road-side","road-curve","road-curve-intersection","road-roundabout","road-slant","road-slant-high","road-slant-flat","road-bridge","road-crossing","road-driveway-single","road-intersection-line","road-square","road-straight-half"]

func _init() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.3,0.4,0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1,1,1); e.ambient_light_energy = 0.8
	env.environment = e; root3d.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-60, 30, 0); root3d.add_child(sun)
	var cols := 5
	for i in NAMES.size():
		var p: PackedScene = load("res://assets/kenney/roads/%s.glb" % NAMES[i])
		var n := p.instantiate() as Node3D
		n.position = Vector3((i % cols) * 4.0, 0, (i / cols) * 4.0)
		root3d.add_child(n)
		var l := Label3D.new(); l.text = NAMES[i]; l.position = n.position + Vector3(0, 0.1, 1.6); l.rotation_degrees = Vector3(-90,0,0); l.pixel_size = 0.01; l.modulate = Color.YELLOW
		root3d.add_child(l)
		# arrow marker on +X side and +Z side to read orientation
		var mx := MeshInstance3D.new(); mx.mesh = SphereMesh.new(); mx.scale = Vector3(0.1,0.1,0.1); mx.position = n.position + Vector3(0.6,0.3,0); root3d.add_child(mx)
	var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 18
	cam.position = Vector3(8, 20, 8); cam.rotation_degrees = Vector3(-90, 0, 0); root3d.add_child(cam)
	await create_timer(0.5).timeout
	await process_frame; await process_frame
	get_root().get_viewport().get_texture().get_image().save_png("/tmp/probe_roads.png")
	print("saved")
	quit()
