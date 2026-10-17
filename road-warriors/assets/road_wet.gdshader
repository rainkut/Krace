shader_type spatial;
render_mode cull_disabled;
uniform sampler2D refl : source_color, filter_linear;
uniform float strength = 1.7;
uniform float rough = 0.45;
uniform bool puddle = false;
varying vec3 wpos;
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x), mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x), f.y); }
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment(){
	vec2 uv = wpos.xz;
	float k = puddle ? 0.5 : 1.0;
	vec2 d = (vec2(vn(uv * 18.0 + TIME * 0.6), vn(uv * 18.0 + 5.0 - TIME * 0.5)) - 0.5) * 0.012 * k;
	vec3 r = texture(refl, vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + d).rgb;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0) * 0.7 + 0.25;
	float patch = puddle ? 1.0 : mix(0.35, 0.8, vn(uv * 0.3));
	ALBEDO = COLOR.rgb;
	ROUGHNESS = puddle ? 0.05 : rough;
	SPECULAR = 0.6;
	EMISSION = r * fres * patch * strength * (puddle ? 1.2 : 0.55);
	if (puddle) ALPHA = COLOR.a;
}
