shader_type spatial;
render_mode cull_disabled;
uniform sampler2D refl : source_color, filter_linear;
uniform float scroll = 0.0;
uniform float wet = 1.0;
varying vec3 wpos;
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x), mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x), f.y); }
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment(){
	vec2 uv = vec2(wpos.x, wpos.z + scroll);
	float n = vn(uv * 1.3) * 0.6 + vn(uv * 6.0) * 0.4;
	vec3 asph = vec3(0.045) + n * 0.03;
	float lane = 0.0;
	float ax = abs(wpos.x);
	lane += step(abs(ax - 3.6), 0.07);
	lane += step(abs(wpos.x - 1.8), 0.05) * step(fract((wpos.z + scroll) / 6.0), 0.5);
	lane += step(abs(wpos.x + 1.8), 0.05) * step(fract((wpos.z + scroll) / 6.0), 0.5);
	lane += step(abs(wpos.x), 0.05) * step(fract((wpos.z + scroll) / 6.0), 0.5);
	float puddle = smoothstep(0.45, 0.62, vn(uv * 0.35 + 7.0));
	float rough_map = mix(0.55, 0.06, clamp(wet * (0.5 + 0.5 * puddle), 0.0, 1.0));
	vec3 base = asph + vec3(0.7) * lane * 0.7;
	vec2 suv = SCREEN_UV;
	vec2 distort = (vec2(vn(uv * 20.0), vn(uv * 20.0 + 5.0)) - 0.5) * 0.012 * (1.0 - puddle * 0.7);
	vec3 r = texture(refl, vec2(suv.x, 1.0 - suv.y) + distort).rgb;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0) * 0.8 + 0.2;
	ALBEDO = base;
	ROUGHNESS = rough_map;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = r * fres * wet * mix(0.5, 1.0, puddle);
}
