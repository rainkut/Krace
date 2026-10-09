class_name CarVisual
extends RefCounted
## Builds a car's 3D model from a vehicle definition and recolours the body ("paint").
## The Kenney models share one palette texture, so a small shader swaps every saturated
## texel (the body) for the chosen paint while windows, tyres and lights stay as modelled.

const SHADER_CODE := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 paint : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float sat_thresh = 0.42;
void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float mx = max(t.r, max(t.g, t.b));
	float mn = min(t.r, min(t.g, t.b));
	float sat = (mx - mn) / max(mx, 0.001);
	float body = step(sat_thresh, sat) * step(0.3, mx);
	vec3 painted = paint.rgb * clamp(mx / 0.8, 0.55, 1.1);
	ALBEDO = mix(t.rgb, painted, body);
	ROUGHNESS = mix(0.8, 0.35, body);
	METALLIC = mix(0.0, 0.25, body);
}
"""
static var _shader: Shader

## Returns a Node3D whose origin is the body centre; wheels touch y = -half_height.
static func build(def: Dictionary, paint_index: int, half_height: float = 0.6, parts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	if str(def.get("procedural", "")) == "open_wheel":
		_open_wheel(root, Content.paint_color(paint_index), half_height)
		return root
	var model := Content.load_model(Content.resolve_path(def["model"], def.get("_root", "res://")))
	if model.find_children("*", "MeshInstance3D", true, false).is_empty():
		model = Content.load_model("res://assets/kenney/cars/hatchback-sports.glb")
	var s := float(def.get("model_scale", 1.75))
	model.scale = Vector3.ONE * s
	model.rotation.y = deg_to_rad(float(def.get("model_yaw", 180)))
	model.position.y = -half_height + 0.3 * s
	root.add_child(model)
	paint(model, Content.paint_color(paint_index))
	if not parts.is_empty():
		_decorate(root, model, parts, Content.paint_color(paint_index))
	return root

## Bounds of the model in the parent's space.
static func _bounds(model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != model:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var bb: AABB = xf * m.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return model.transform * out

## Decorative extras (wheel caps, spoiler, stripe/flag/decal) sized from the model's bounds.
## Purely cosmetic: no effect on handling or collision.
static func _decorate(root: Node3D, model: Node3D, parts: Dictionary, paint: Color) -> void:
	var b := _bounds(model)
	var hx := b.size.x * 0.5
	var len := b.size.z
	var top := b.end.y
	var ground := b.position.y
	var cx := b.get_center().x
	var cz := b.get_center().z
	var wheel_def := Content.get_part("wheels", str(parts.get("wheels", "stock")))
	if str(wheel_def.get("color", "")) != "":
		var wr := b.size.y * 0.2
		var cap := _mat(Color(wheel_def["color"]), 0.25, 0.7)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var c := CylinderMesh.new()
				c.top_radius = wr * 0.62
				c.bottom_radius = wr * 0.62
				c.height = 0.06
				c.radial_segments = 16
				_part(root, c, cap, Vector3(cx + sx * (hx + 0.005), ground + wr, cz + sz * len * 0.31), Vector3(0, 0, PI * 0.5))
	var sp := str(parts.get("spoilers", "none"))
	if sp != "none" and Content.get_part("spoilers", sp).size() > 0:
		var dark := _mat(Color("202226"), 0.6)
		var col := _mat(paint, 0.4, 0.2)
		var zb := cz + len * 0.5 - 0.12
		var h: float = {"lip": 0.0, "wing": 0.22, "tall": 0.42}.get(sp, 0.2)
		var yb := top - b.size.y * 0.18
		_bx(root, Vector3(b.size.x * 0.92, 0.05, 0.3), col, Vector3(cx, yb + h, zb))
		if h > 0.0:
			for sx in [-1.0, 1.0]:
				_bx(root, Vector3(0.05, h, 0.06), dark, Vector3(cx + sx * hx * 0.55, yb + h * 0.5, zb))
	var ex := str(parts.get("extras", "none"))
	if ex == "stripe":
		var wh := _mat(Color("f4f4f0"), 0.5)
		for sx in [-1.0, 1.0]:
			_bx(root, Vector3(0.1, 0.012, len * 0.9), wh, Vector3(cx + sx * 0.14, top + 0.004, cz))
	elif ex == "flag":
		var pole := _mat(Color("c9ccd2"), 0.4, 0.6)
		_bx(root, Vector3(0.025, 0.4, 0.025), pole, Vector3(cx + hx * 0.55, top + 0.2, cz))
		_bx(root, Vector3(0.3, 0.18, 0.012), _mat(Color("ff8a1f"), 0.6), Vector3(cx + hx * 0.55 + 0.16, top + 0.32, cz))
	elif ex == "star":
		var st := CylinderMesh.new()
		st.top_radius = 0.26
		st.bottom_radius = 0.26
		st.height = 0.012
		st.radial_segments = 5
		_part(root, st, _mat(Color("ffd21f"), 0.4), Vector3(cx, top + 0.006, cz))

static func paint(model: Node, color: Color) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var base := m.get_active_material(i)
			if base is BaseMaterial3D and base.albedo_texture != null:
				var sm := ShaderMaterial.new()
				sm.shader = _shader
				sm.set_shader_parameter("albedo_tex", base.albedo_texture)
				sm.set_shader_parameter("paint", color)
				m.set_surface_override_material(i, sm)


static func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

static func _part(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)

static func _bx(root: Node3D, size: Vector3, mat: Material, pos: Vector3) -> void:
	var b := BoxMesh.new()
	b.size = size
	_part(root, b, mat, pos)

## Original open-wheel racer (no real team/brand styling). Forward is -Z, ground is y = -half_height.
static func _open_wheel(root: Node3D, color: Color, hh: float) -> void:
	var body := _mat(color, 0.35, 0.25)
	var dark := _mat(Color("202226"), 0.7)
	var white := _mat(Color("f4f4f0"), 0.5)
	var accent := _mat(color.lightened(0.45), 0.4)
	var g := -hh
	_bx(root, Vector3(1.1, 0.06, 3.9), dark, Vector3(0, g + 0.1, 0.0))
	_bx(root, Vector3(0.66, 0.4, 2.1), body, Vector3(0, g + 0.4, 0.35))
	var nose := CylinderMesh.new()
	nose.top_radius = 0.07
	nose.bottom_radius = 0.27
	nose.height = 1.9
	nose.radial_segments = 14
	_part(root, nose, body, Vector3(0, g + 0.32, -1.2), Vector3(-PI * 0.5, 0, 0))
	_bx(root, Vector3(0.36, 0.06, 0.9), accent, Vector3(0, g + 0.62, -0.95))
	for sg in [-1.0, 1.0]:
		_bx(root, Vector3(0.36, 0.34, 1.2), body, Vector3(sg * 0.52, g + 0.38, 0.55))
		_bx(root, Vector3(0.38, 0.05, 1.0), accent, Vector3(sg * 0.52, g + 0.57, 0.55))
	_bx(root, Vector3(0.3, 0.42, 0.7), body, Vector3(0, g + 0.82, 0.85))
	var helmet := SphereMesh.new()
	helmet.radius = 0.17
	helmet.height = 0.34
	_part(root, helmet, white, Vector3(0, g + 0.78, 0.25))
	var visor := SphereMesh.new()
	visor.radius = 0.12
	visor.height = 0.24
	_part(root, visor, _mat(Color("1a2a40"), 0.2, 0.4), Vector3(0, g + 0.79, 0.1))
	# wings
	_bx(root, Vector3(1.95, 0.05, 0.42), body, Vector3(0, g + 0.16, -1.95))
	_bx(root, Vector3(1.9, 0.04, 0.2), accent, Vector3(0, g + 0.24, -2.0))
	for sg in [-1.0, 1.0]:
		_bx(root, Vector3(0.05, 0.22, 0.55), white, Vector3(sg * 0.98, g + 0.24, -1.95))
		_bx(root, Vector3(0.05, 0.42, 0.55), white, Vector3(sg * 0.62, g + 1.0, 1.9))
	_bx(root, Vector3(1.25, 0.05, 0.5), body, Vector3(0, g + 1.2, 1.9))
	_bx(root, Vector3(1.25, 0.04, 0.22), accent, Vector3(0, g + 1.0, 1.95))
	for sg in [-1.0, 1.0]:
		_bx(root, Vector3(0.06, 0.5, 0.06), dark, Vector3(sg * 0.2, g + 0.9, 1.75))
	# wheels + suspension
	var tyre := _mat(Color("151517"), 0.9)
	var hub := _mat(Color("c9ccd2"), 0.35, 0.6)
	for wz in [[-1.2, 0.36, 0.34], [1.25, 0.42, 0.46]]:
		for sg in [-1.0, 1.0]:
			var r: float = wz[1]
			var cyl := CylinderMesh.new()
			cyl.top_radius = r
			cyl.bottom_radius = r
			cyl.height = wz[2]
			cyl.radial_segments = 20
			var x: float = sg * (0.9 + (wz[2] - 0.34) * 0.5)
			_part(root, cyl, tyre, Vector3(x, g + r, wz[0]), Vector3(0, 0, PI * 0.5))
			var hb := CylinderMesh.new()
			hb.top_radius = r * 0.5
			hb.bottom_radius = r * 0.5
			hb.height = wz[2] + 0.02
			hb.radial_segments = 12
			_part(root, hb, hub, Vector3(x, g + r, wz[0]), Vector3(0, 0, PI * 0.5))
			_bx(root, Vector3(absf(x) - 0.3, 0.05, 0.08), dark, Vector3(sg * (absf(x) + 0.3) * 0.5, g + r, wz[0]))
