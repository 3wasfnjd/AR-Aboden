shader_type spatial;
render_mode cull_back;
// Draped infrastructure: 0 = road, 1 = runway, 2 = concrete apron.
// UV.x = distance along (m), UV.y = -1..1 across.

uniform int kind = 0;
uniform float run_len = 0.0;
varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float aa(float d) { float w = max(fwidth(d), 1e-5); return 1.0 - smoothstep(-w, w, d); }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float av = abs(v);
	float n = vnoise(wp.xz * 900.0) * 0.5 + vnoise(wp.xz * 3000.0) * 0.5;
	vec3 c;
	if (kind == 0) {
		c = vec3(0.58, 0.56, 0.52) * (0.92 + 0.16 * n);
		// dusty shoulders
		c = mix(c, vec3(0.62, 0.56, 0.46), smoothstep(0.62, 1.0, av) * 0.75);
		float dash = step(fract(u / 0.0045), 0.5);
		c = mix(c, vec3(0.86, 0.83, 0.72), aa(av - 0.05) * dash * 0.45);
	} else if (kind == 1) {
		c = vec3(0.44, 0.44, 0.45) * (0.9 + 0.2 * n);
		// tyre-rubber near both ends
		float ends = 1.0 - smoothstep(0.0, 0.05, min(u, run_len - u));
		c *= 1.0 - 0.35 * ends * smoothstep(0.6, 0.0, av) * n;
		// edge lines
		c = mix(c, vec3(0.92), aa(abs(av - 0.88) - 0.03));
		// centre dashes
		float dash = step(fract(u / 0.008), 0.55);
		float inner = step(0.022, u) * step(u, run_len - 0.022);
		c = mix(c, vec3(0.92), aa(av - 0.022) * dash * inner);
		// threshold piano keys
		float key = step(0.5, fract(v * 4.0 + 0.5)) * step(av, 0.78);
		float thr = (step(0.003, u) * step(u, 0.011)) + (step(run_len - 0.011, u) * step(u, run_len - 0.003));
		c = mix(c, vec3(0.92), key * thr);
		// touchdown blocks
		float td = (step(0.026, u) * step(u, 0.034)) + (step(run_len - 0.034, u) * step(u, run_len - 0.026));
		c = mix(c, vec3(0.9), td * step(0.3, av) * step(av, 0.55));
	} else {
		c = vec3(0.70, 0.69, 0.66) * (0.94 + 0.1 * n);
		vec2 g = fract(wp.xz / 0.004);
		float joint = max(aa(g.x - 0.04), aa(g.y - 0.04));
		c *= 1.0 - joint * 0.18;
		// oil stains
		c *= 1.0 - 0.12 * smoothstep(0.7, 0.95, vnoise(wp.xz * 300.0));
	}
	ALBEDO = lin(c * COLOR.rgb);
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
