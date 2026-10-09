shader_type spatial;
// Procedural Indian-town building facade on a unit box. Per-instance data (INSTANCE_CUSTOM):
// r = palette index/15, g = 1 shop on front face / 0.4 party-wall (blank sides), b = floors/15, a = random seed.
varying vec3 lpos;
varying vec3 lnrm;
varying vec3 dims;
varying vec4 cd;

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

void fragment() {
	int idx = int(floor(cd.r * 15.0 + 0.5));
	float floors = floor(cd.b * 15.0 + 0.5);
	float seed = cd.a;
	vec3 base = palette(idx);
	float h = (lpos.y + 0.5) * dims.y;
	vec3 col = base;
	float rough = 0.92;
	float metal = 0.0;
	if (lnrm.y > 0.5) {
		// flat roof
		col = vec3(0.50, 0.47, 0.43) * (0.85 + 0.3 * hash(floor(lpos.xz * dims.xz * 0.5)));
		float edge = min(min(0.5 - abs(lpos.x), 0.5 - abs(lpos.z)) * min(dims.x, dims.z), 1.0);
		col = mix(base * 0.7, col, smoothstep(0.0, 0.5, edge));
	} else if (lnrm.y > -0.5) {
		float u = abs(lnrm.z) > 0.5 ? lpos.x * dims.x : lpos.z * dims.z;
		float fl = 3.2;
		float row = floor(h / fl);
		float fy = fract(h / fl);
		float colx = floor(u / 3.0 + 50.0);
		float fx = fract(u / 3.0 + 50.0);
		bool front = lnrm.z > 0.5;
		bool in_body = row < floors;
		// slab line + parapet + grime
		float slab = smoothstep(0.0, 0.06, fy) * (1.0 - smoothstep(0.94, 1.0, fy));
		col = base * mix(0.82, 1.0, slab);
		col *= 0.9 + 0.2 * hash(vec2(floor(u * 1.7), floor(h * 1.7)) + seed * 40.0);
		col *= mix(0.72, 1.0, smoothstep(0.0, 3.0, h));
		if (h > floors * fl + 0.05) {
			col = base * 0.78; // parapet
		} else if (in_body) {
			bool shop = front && row < 1.0 && cd.g > 0.9;
			bool blank_side = cd.g > 0.2 && abs(lnrm.x) > 0.5;
			if (shop) {
				// roll-up shutter bays with a signboard strip
				float bay = fract(u / 3.0 + 50.0);
				if (fy > 0.74) {
					vec3 sign = palette(int(mod(floor(u / 3.0 + 50.0) * 3.0 + seed * 16.0, 16.0)));
					col = sign * vec3(0.9, 0.9, 1.0);
				} else if (bay > 0.1 && bay < 0.9 && fy > 0.04) {
					col = vec3(0.45, 0.50, 0.52) * (0.85 + 0.15 * sin(h * 38.0));
					metal = 0.4; rough = 0.55;
				}
			} else if (blank_side) {
				col = base * 0.95;
			} else if (fx > 0.27 && fx < 0.73 && fy > 0.32 && fy < 0.82) {
				float r = hash(vec2(colx, row) + seed * 91.0);
				vec3 glass = vec3(0.16, 0.24, 0.30);
				if (r > 0.82) glass = vec3(0.55, 0.40, 0.26);      // curtain
				else if (r > 0.70) glass = vec3(0.34, 0.38, 0.30);  // shutters closed
				float frame = step(fx, 0.31) + step(0.69, fx) + step(fy, 0.36) + step(0.78, fy);
				col = mix(glass, vec3(0.88), clamp(frame, 0.0, 1.0));
				rough = frame > 0.5 ? 0.8 : 0.12;
				metal = frame > 0.5 ? 0.0 : 0.3;
			} else if (fx > 0.2 && fx < 0.8 && fy > 0.28 && fy < 0.32) {
				col = base * 0.78; // sill
			}
		}
	} else {
		col = base * 0.5;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.4;
}
