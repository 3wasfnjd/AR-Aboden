shader_type spatial;
render_mode cull_back;
// Merged buildings. Vertex colour = sRGB albedo, COLOR.a < 1 => emissive.
// Walls carry UV = (distance along wall, height above ground) and
// UV2 = (wall length, wall height) -> procedural window grid, anti-aliased.

uniform float floor_h = 0.0028;
uniform float col_pitch = 0.0024;
uniform vec3 glass : source_color = vec3(0.13, 0.17, 0.21);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float band(float f, float a, float b) {
	float w = max(fwidth(f) * 0.8, 1e-4);
	return smoothstep(a - w, a + w, f) * (1.0 - smoothstep(b - w, b + w, f));
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	vec3 col = base;
	float rough = 0.82;
	float spec = 0.35;
	if (UV.y > -0.5 && UV2.x > 0.0) {
		float wl = UV2.x;
		float hh = UV2.y;
		float yy = UV.y - 0.0010;
		float rows = floor((hh - 0.0012) / floor_h);
		float ry = yy / floor_h;
		float in_row = band(ry - floor(ry), 0.22, 0.72) * step(0.0, yy) * step(floor(ry), rows - 1.0);
		float ncols = max(1.0, floor((wl - 0.0006) / col_pitch));
		float off = (wl - ncols * col_pitch) * 0.5;
		float cx = (UV.x - off) / col_pitch;
		float in_col = band(cx - floor(cx), 0.2, 0.8) * step(0.0, cx) * step(floor(cx), ncols - 1.0);
		float win = in_row * in_col;
		float h = hash(vec2(floor(cx), floor(ry)) + floor(wl * 1000.0));
		vec3 g = glass * (0.75 + 0.5 * h);
		// shutters / closed windows on some cells
		g = mix(g, base * 0.75, step(0.86, h));
		col = mix(col, g, win);
		rough = mix(rough, 0.22, win);
		spec = mix(spec, 0.6, win);
		// soft grime at the foot of walls
		col *= mix(0.82, 1.0, smoothstep(-0.0005, 0.0015, UV.y));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = base * (1.0 - COLOR.a) * 5.0;
}
