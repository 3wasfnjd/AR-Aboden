shader_type spatial;
render_mode cull_back;
// Procedural wood (plinth and table): long grain streaks along world x,
// optional planks along z, subtle figure. Colours are source_color (linear).

uniform vec3 col_light : source_color = vec3(0.55, 0.36, 0.22);
uniform vec3 col_dark : source_color = vec3(0.30, 0.18, 0.10);
uniform float scale = 1.0;
uniform float plank = 0.0;        // >0: plank width (m) for a table top
uniform float gloss = 0.35;
// Island-local position: the diorama can be moved / turned / scaled in the room (XR),
// tw_island_inv (world -> diorama) keeps every pattern glued to the model.
global uniform mat4 tw_island_inv;
varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; } return s; }

uniform bool island_local = true;  // false: the room's own table / floor (world space)
void vertex() {
	vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0);
	wp = island_local ? (tw_island_inv * w).xyz : w.xyz;
}

void fragment() {
	vec3 p = wp / scale;
	float pid = 0.0;
	float seam = 0.0;
	float across = p.z + p.y * 0.7;
	if (plank > 0.0) {
		pid = floor(p.z / plank);
		float f = fract(p.z / plank);
		float w = fwidth(p.z / plank) * 1.5;
		seam = 1.0 - smoothstep(0.0, 0.004 + w, min(f, 1.0 - f));
		p.x += hash(vec2(pid, 3.0)) * 10.0;
	}
	// grain: thin dark late-wood lines, gently wandering along the length
	float wander = fbm(vec2(p.x * 0.7 + pid * 3.1, across * 2.0)) * 3.0;
	float g = across * 140.0 + wander * 6.0 + pid * 11.0;
	float lines = pow(0.5 + 0.5 * sin(g), 6.0);
	float fine = fbm(vec2(p.x * 3.0, across * 420.0 + pid * 5.0));
	float broad = fbm(vec2(p.x * 0.9 + pid, across * 9.0));
	vec3 c = mix(col_light, col_dark, clamp(lines * 0.35 + (fine - 0.5) * 0.3 + (broad - 0.5) * 0.5, 0.0, 1.0));
	c *= 0.92 + 0.16 * hash(vec2(pid, 1.0));
	c *= 1.0 - seam * 0.55;
	ALBEDO = c;
	ROUGHNESS = mix(0.72, 0.38, gloss) + fine * 0.08;
	SPECULAR = 0.4;
}
