shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;
// Merged buildings, cartoon look (build 3). Vertex colour = sRGB albedo,
// COLOR.a < 1 => emissive (flames, beacons, lit crowns).
// Walls carry UV = (distance along wall, height above ground) and
// UV2 = (wall length, wall height) -> a bold window grid. The grid fades to a flat
// tint once a storey covers only a few pixels, so far / grazing walls never shimmer.

uniform float floor_h = 0.0028;    // toy storey (Toon.STOREY)
uniform float col_pitch = 0.0030;  // window bays
uniform vec3 glass : source_color = vec3(0.24, 0.36, 0.52);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float band(float f, float a, float b, float w) {
	return smoothstep(a - w, a + w, f) * (1.0 - smoothstep(b - w, b + w, f));
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	vec3 col = base;
	if (UV.y > -0.5 && UV2.x > 0.0) {
		float wl = UV2.x;
		float hh = UV2.y;
		float yy = UV.y;
		float rows = floor((hh + 0.0003) / floor_h);
		float ry = yy / floor_h;
		float ncols = max(1.0, floor((wl - 0.0008) / col_pitch));
		float off = (wl - ncols * col_pitch) * 0.5;
		float cx = (UV.x - off) / col_pitch;
		// pixels per storey / bay: 0 when the grid is too fine to draw cleanly
		float fy = fwidth(ry);
		float fx = fwidth(cx);
		float w = max(max(fy, fx) * 0.75, 0.02);
		float in_row = band(ry - floor(ry), 0.28, 0.74, w) * step(0.0, yy) * step(floor(ry), rows - 1.0);
		float in_col = band(cx - floor(cx), 0.22, 0.78, w) * step(0.0, cx) * step(floor(cx), ncols - 1.0);
		float win = in_row * in_col;
		float h = hash(vec2(floor(cx), floor(ry)) + floor(wl * 1000.0));
		vec3 g = mix(glass, glass * 1.6 + vec3(0.05), step(0.82, h));   // a few lit panes
		float fade = 1.0 - smoothstep(0.22, 0.45, max(fy, fx));
		vec3 avg = mix(base, glass, 0.22 * step(0.0, yy));
		col = mix(avg, mix(base, g, win), fade);
	}
	ALBEDO = col;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	EMISSION = base * (1.0 - COLOR.a) * 4.0;
}
