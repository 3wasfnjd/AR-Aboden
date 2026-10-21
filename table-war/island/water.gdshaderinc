// Shared body of water.gdshader (blended) and water_opaque.gdshader (Quest).

// Sea surface inside the diorama slab. Depth comes from a terrain-baked
// texture (no depth-buffer read: cheap and works in GL Compatibility / Quest).

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform vec4 rect;                 // origin.x, origin.z, size.x, size.z (m)
uniform float depth_range = 0.04;
uniform vec3 col_shallow : source_color = vec3(0.32, 0.90, 0.84);
uniform vec3 col_mid : source_color = vec3(0.10, 0.64, 0.88);
uniform vec3 col_deep : source_color = vec3(0.05, 0.34, 0.74);
uniform vec3 col_foam : source_color = vec3(0.97, 0.98, 0.96);
uniform float wave_amp = 0.00022;
uniform float ripple = 0.0;
uniform float radius = 0.5;
uniform vec3 seabed : source_color = vec3(0.74, 0.70, 0.56);   // opaque variant only

// Island-local position: the diorama can be moved / turned / scaled in the room (XR),
// tw_island_inv (world -> diorama) keeps every pattern glued to the model.
global uniform mat4 tw_island_inv;
global uniform float tw_night;
varying vec3 wp;
varying float edge_fade;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// cheap caustic web: abs of two warped value-noise fields, sharpened
float caustic(vec2 p, float t) {
	vec2 q = p * 520.0;
	float a = vnoise(q + vec2(t * 0.35, t * 0.22));
	float b = vnoise(q * 1.37 - vec2(t * 0.28, -t * 0.31) + 4.1);
	float c = 1.0 - abs(a - b) * 3.2;
	return pow(clamp(c, 0.0, 1.0), 6.0);
}

float swell(vec2 p, float t) {
	return sin(p.x * 48.0 + p.y * 12.0 + t * 1.1) * 0.55 + sin(p.y * 63.0 - p.x * 21.0 - t * 0.9) * 0.35 + sin((p.x + p.y) * 110.0 + t * 1.9) * 0.10;
}

// analytic gradient of a sum of directional sines (small ripples)
vec2 ripple_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	vec2 d; float w; float a; float ph;
	d = normalize(vec2(1.0, 0.35));  w = 260.0; a = 0.9; ph = dot(d, p) * w + t * 2.2; g += d * cos(ph) * a;
	d = normalize(vec2(-0.4, 1.0));  w = 330.0; a = 0.7; ph = dot(d, p) * w + t * 2.6; g += d * cos(ph) * a;
	d = normalize(vec2(0.8, -0.9));  w = 520.0; a = 0.45; ph = dot(d, p) * w + t * 3.1; g += d * cos(ph) * a;
	d = normalize(vec2(-1.0, -0.2)); w = 760.0; a = 0.3; ph = dot(d, p) * w + t * 3.7; g += d * cos(ph) * a;
	d = normalize(vec2(0.2, -1.0));  w = 150.0; a = 0.8; ph = dot(d, p) * w + t * 1.4; g += d * cos(ph) * a;
	return g;
}

void vertex() {
	wp = (tw_island_inv * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
	vec2 uv = (wp.xz - rect.xy) / rect.zw;
	edge_fade = smoothstep(0.0, 0.035, radius - length(wp.xz));
	VERTEX.y += swell(wp.xz, TIME) * wave_amp * edge_fade;
}

void fragment() {
	vec2 uv = (wp.xz - rect.xy) / rect.zw;
	float v = texture(depth_tex, uv).r;
	float d = (v - 0.2) / 0.8 * depth_range;   // water depth in metres (<0 = land)
	float dd = max(d, 0.0);
	float t = TIME;
	vec2 p = wp.xz;

	// normal: ripples + broken noise, calmer in very shallow water
	vec2 g = ripple_grad(p, t) * ripple;
	g *= mix(0.4, 1.0, smoothstep(0.0, 0.006, dd));
	// fade sub-pixel ripples (grazing views / far away) to avoid shimmering stripes
	float foot = fwidth(p.x) + fwidth(p.y);
	g *= 1.0 - smoothstep(0.0005, 0.0022, foot);
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
	n = normalize(mat3(MODEL_MATRIX) * n);   // diorama-local -> world (the model may be turned)
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// cartoon depth bands: shallow turquoise | mid blue | deep blue, soft-edged steps
	float patchy = vnoise(p * 9.0 + t * 0.02);
	float dv = dd * (0.9 + 0.2 * patchy);
	vec3 col = mix(col_shallow, col_mid, smoothstep(0.0028, 0.0042, dv));
	col = mix(col, col_deep, smoothstep(0.013, 0.017, dv));
	col *= 0.97 + 0.06 * patchy;
	float alpha = mix(0.5, 0.97, smoothstep(0.0, 0.016, dd));


	// foam: a crisp lapping line at the waterline + a broken outer surf line
	float fn = vnoise(p * 120.0 + vec2(t * 0.25, -t * 0.18));
	float lap = 0.0007 + 0.0003 * sin(t * 1.3 + fn * 4.0);
	float line1 = (1.0 - smoothstep(lap, lap + 0.0008, d)) * step(-0.0004, d);
	float surf_d = 0.0016 + 0.0004 * sin(t * 0.9 + p.x * 90.0);
	float line2 = (1.0 - smoothstep(0.0, 0.0006, abs(d - surf_d))) * smoothstep(0.35, 0.7, fn);
	float foam = clamp(max(line1 * smoothstep(0.15, 0.45, fn) * 1.2, line2 * 0.8), 0.0, 1.0);
	col = mix(col, col_foam, foam);
	alpha = max(alpha, foam * 0.95);

	// night (web): the sea darkens with the sky (the open ocean around matches it)
	col *= mix(1.0, 0.62, tw_night);
#ifdef WATER_OPAQUE
	// Quest: no blending (no overdraw, no sorting): the seabed seen through shallow
	// water is approximated by the baked shallow-sand colour.
	col = mix(seabed, col, clamp(alpha, 0.0, 1.0));
	ALBEDO = clamp(col, 0.0, 1.0);
#else
	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = clamp(alpha, 0.0, 1.0);
#endif
	ROUGHNESS = mix(0.45, 0.8, foam);   // no glints on the toy sea (they sparkled)
	SPECULAR = 0.12;
	METALLIC = 0.0;
}
