shader_type spatial;
// Procedural Indian-town building facade on a unit box. Per-instance data (INSTANCE_CUSTOM):
// r = palette index/15, g = 1 shop on front face / 0.4 party-wall (blank sides), b = floors/15, a = random seed.
varying vec3 lpos;
varying vec3 lnrm;
varying vec3 dims;
varying vec4 cd;
uniform sampler2D plaster_a : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D plaster_b : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_t : source_color, repeat_enable, filter_linear_mipmap;
uniform float fade = 0.30;

vec3 palette(int i) {
	vec3 p[16] = vec3[16](
		vec3(0.93,0.86,0.70), vec3(0.90,0.74,0.58), vec3(0.86,0.60,0.46), vec3(0.78,0.82,0.74),
		vec3(0.70,0.80,0.84), vec3(0.94,0.80,0.80), vec3(0.96,0.92,0.78), vec3(0.82,0.70,0.60),
		vec3(0.92,0.92,0.90), vec3(0.74,0.55,0.42), vec3(0.88,0.68,0.34), vec3(0.62,0.72,0.58),
		vec3(0.80,0.58,0.62), vec3(0.66,0.66,0.72), vec3(0.95,0.85,0.60), vec3(0.76,0.50,0.38));
	return p[clamp(i, 0, 15)];
}
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	dims = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cd = INSTANCE_CUSTOM;
}

float aastripe(float x) {
	float w = fwidth(x);
	float v = smoothstep(0.5 - w, 0.5 + w, fract(x));
	return mix(v, 0.5, smoothstep(0.35, 0.8, w));
}

float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x), mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}

void fragment() {
	int idx = int(floor(cd.r * 15.0 + 0.5));
	float floors = floor(cd.b * 15.0 + 0.5);
	float seed = cd.a;
	vec3 base = palette(idx);
	// sun-faded, dusty wash: pull toward a warm grey
	float lum = dot(base, vec3(0.3, 0.59, 0.11));
	base = mix(base, vec3(lum) * vec3(1.03, 0.97, 0.88), fade + 0.25 * hash(vec2(seed * 7.0, 3.0)));
	float h = (lpos.y + 0.5) * dims.y;
	vec3 col = base;
	float rough = 0.95;
	float metal = 0.0;
	bool construction = seed > 0.9 && floors >= 2.0;
	if (lnrm.y > 0.5) {
		vec2 ruv = lpos.xz * dims.xz;
		vec3 t = texture(stone_t, ruv * 0.12).rgb;
		col = vec3(0.52, 0.49, 0.45) * (0.7 + 0.6 * dot(t, vec3(0.33)));
		col *= 0.85 + 0.25 * vnoise(ruv * 0.8);
		float edge = min(min(0.5 - abs(lpos.x), 0.5 - abs(lpos.z)) * min(dims.x, dims.z), 1.0);
		col = mix(base * 0.62, col, smoothstep(0.0, 0.45, edge));
		if (construction) col = mix(col, vec3(0.42, 0.40, 0.38), 0.6);
	} else if (lnrm.y > -0.5) {
		float u = abs(lnrm.z) > 0.5 ? lpos.x * dims.x : lpos.z * dims.z;
		vec2 wuv = vec2(u, h);
		float fl = 3.2;
		float row = floor(h / fl);
		float fy = fract(h / fl);
		float colx = floor(u / 3.0 + 50.0);
		float fx = fract(u / 3.0 + 50.0);
		bool front = lnrm.z > 0.5;
		bool in_body = row < floors;
		float pl = dot(texture(plaster_b, wuv * 0.18 + seed * 3.0).rgb, vec3(0.333));
		float pa = dot(texture(plaster_a, wuv * 0.37).rgb, vec3(0.333));
		col = base * (0.62 + 0.55 * pl) * (0.85 + 0.3 * pa);
		// patchy re-painting: some wall patches are a different (fresher/darker) wash
		float patch = vnoise(wuv * 0.22 + seed * 20.0);
		col = mix(col, col * vec3(0.78, 0.74, 0.70), smoothstep(0.55, 0.75, patch) * 0.7);
		// slab bands
		float slab = smoothstep(0.0, 0.05, fy) * (1.0 - smoothstep(0.93, 1.0, fy));
		col *= mix(0.80, 1.0, slab);
		// damp / dust darkening at the base, soot-and-rain streaks from the parapet and window sills
		col *= mix(0.55, 1.0, smoothstep(0.0, 1.6, h));
		float streak = vnoise(vec2(u * 3.1 + seed * 40.0, h * 0.18));
		col *= 1.0 - 0.22 * smoothstep(0.55, 0.9, streak) * (1.0 - fy * 0.5);
		if (h > floors * fl + 0.05) {
			float rel = h - floors * fl;
			col = base * (0.7 + 0.3 * pl);
			if (rel > 0.55) col *= 0.9; // parapet band: coping line
			if (rel < 0.5) col *= 0.82;
		} else if (in_body) {
			bool shop = front && row < 1.0 && cd.g > 0.9;
			bool blank_side = cd.g > 0.2 && abs(lnrm.x) > 0.5;
			if (construction && row >= floors - 1.0) {
				// top floor still raw: bare brick/concrete with open columns
				vec3 br = texture(stone_t, wuv * 0.2).rgb;
				col = br * vec3(0.95, 0.72, 0.58);
				if (fx > 0.35 && fx < 0.65 && fy > 0.1 && fy < 0.9) col = vec3(0.05, 0.05, 0.06);
			} else if (shop) {
				if (fy > 0.74) {
					// hand-painted signboard strip, each shop a different faded colour
					vec3 sg = palette(int(mod(floor(u / 3.0 + 50.0) * 5.0 + seed * 16.0, 16.0)));
					sg = mix(sg, vec3(0.8, 0.12, 0.1), step(0.85, hash(vec2(colx, seed))) * 0.8);
					col = sg * (0.8 + 0.2 * pl);
					float letters = step(0.55, vnoise(vec2(u * 6.0, h * 14.0) + colx));
					col = mix(col, vec3(0.97, 0.95, 0.88), letters * step(0.12, fx) * step(fx, 0.88) * step(0.78, fy) * step(fy, 0.95) * 0.85);
				} else if (fx > 0.06 && fx < 0.94 && fy > 0.03) {
					float open = step(0.8, hash(vec2(colx, seed * 13.0)));
					if (open > 0.5) {
						col = vec3(0.18, 0.13, 0.10) + 0.18 * hash(floor(vec2(u * 2.0, h * 3.0)));
					} else {
						vec3 sh = mix(vec3(0.46, 0.50, 0.52), vec3(0.55, 0.30, 0.22), step(0.6, hash(vec2(colx, seed * 5.0))));
						col = sh * (0.78 + 0.22 * mix(sin(h * 40.0), 0.0, smoothstep(0.3, 0.9, fwidth(h * 40.0)))) * (0.75 + 0.25 * pl);
						metal = 0.35; rough = 0.55;
					}
				}
			} else if (blank_side) {
				// party wall: stained, with the odd patched hole
				col *= 0.92;
			} else {
				bool above_shop = front && row >= 1.0;
				// balcony every other bay on upper floors: dark recess + slab + railing
				bool balcony = front && row >= 1.0 && hash(vec2(colx, row + seed * 9.0)) > 0.55;
				if (balcony && fx > 0.15 && fx < 0.85 && fy > 0.05 && fy < 0.85) {
					col = vec3(0.14, 0.12, 0.11);
					if (fy < 0.12) col = base * 0.8;
					if (fy > 0.12 && fy < 0.40) col = mix(vec3(0.1, 0.09, 0.08), base * 0.7, aastripe(u * 5.0));
					rough = 0.9;
				} else if (fx > 0.27 && fx < 0.73 && fy > 0.32 && fy < 0.82) {
					float r = hash(vec2(colx, row) + seed * 91.0);
					vec3 glass = vec3(0.15, 0.21, 0.26);
					if (r > 0.85) glass = vec3(0.55, 0.40, 0.26);
					else if (r > 0.62) glass = vec3(0.30, 0.36, 0.30);
					float frame = step(fx, 0.31) + step(0.69, fx) + step(fy, 0.36) + step(0.78, fy);
					// jaali / grille on half of the windows
					if (hash(vec2(colx + 3.0, row + seed * 4.0)) > 0.5 && frame < 0.5) {
						glass = mix(glass, vec3(0.2), aastripe(u * 9.0) * 0.8);
					}
					col = mix(glass, vec3(0.80, 0.78, 0.72), clamp(frame, 0.0, 1.0));
					rough = frame > 0.5 ? 0.85 : 0.14;
					metal = frame > 0.5 ? 0.0 : 0.25;
					// AC unit hanging below some windows
				} else if (fx > 0.32 && fx < 0.68 && fy > 0.06 && fy < 0.28 && hash(vec2(colx + 7.0, row + seed * 31.0)) > 0.8) {
					col = vec3(0.82, 0.83, 0.82);
					if (distance(vec2(fx, fy), vec2(0.5, 0.17)) < 0.075) col = vec3(0.25);
					rough = 0.5;
				} else if (fx > 0.2 && fx < 0.8 && fy > 0.28 && fy < 0.32) {
					col *= 0.75;
				}
			}
		}
	} else {
		col = base * 0.5;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.3;
}
