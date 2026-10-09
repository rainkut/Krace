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
static func build(def: Dictionary, paint_index: int, half_height: float = 0.6) -> Node3D:
	var root := Node3D.new()
	var model := Content.load_model(Content.resolve_path(def["model"], def.get("_root", "res://")))
	var s := float(def.get("model_scale", 1.75))
	model.scale = Vector3.ONE * s
	model.rotation.y = deg_to_rad(float(def.get("model_yaw", 180)))
	model.position.y = -half_height + 0.3 * s
	root.add_child(model)
	paint(model, Content.paint_color(paint_index))
	return root

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
