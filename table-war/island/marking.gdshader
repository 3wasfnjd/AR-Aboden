shader_type spatial;
render_mode cull_back;
// Draped infrastructure: 0 = road, 1 = runway, 2 = concrete apron.
// UV.x = distance along (m), UV.y = -1..1 across.

uniform int kind = 0;
uniform float run_len = 0.0;
// Island-local position: the diorama can be moved / turned / scaled in the room (XR),
// tw_island_inv (world -> diorama) keeps every pattern glued to the model.
global uniform mat4 tw_island_inv;
varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float aa(float d) { float w = max(fwidth(d), 1e-5); return 1.0 - smoothstep(-w, w, d); }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void vertex() { wp = (tw_island_inv * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz; }

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
		// runway 600 x 25 m, all distances in model metres (1:2000)
		c = vec3(0.40, 0.40, 0.41) * (0.9 + 0.2 * n);
		float ends = 1.0 - smoothstep(0.0, 0.06, min(u, run_len - u));
		c *= 1.0 - 0.35 * ends * smoothstep(0.55, 0.0, av) * n;          // tyre rubber
		vec3 W = vec3(0.92);
		c = mix(c, W, aa(abs(av - 0.955) - 0.035));                         // edge lines 0.9 m
		float e = min(u, run_len - u);                                     // distance from nearest end
		float dash = step(fract((u - 0.020) / 0.025), 0.6);                // 30 m dash / 20 m gap
		c = mix(c, W, aa(av - 0.036) * dash * step(0.040, e));             // centreline 0.9 m
		float key = step(0.5, fract(av * 4.0 + 0.25)) * step(av, 0.85);   // threshold piano keys
		c = mix(c, W, key * step(0.003, e) * step(e, 0.018));
		float aim = step(0.075, e) * step(e, 0.0975) * step(0.28, av) * step(av, 0.52);  // aiming point
		c = mix(c, W, aim);
		float tdz = step(0.11, e) * step(e, 0.122) * step(0.28, av) * step(av, 0.42);    // touchdown pair
		c = mix(c, W, tdz);
	} else if (kind == 4) {
		// taxiway: asphalt, yellow centreline, yellow edge lines
		c = vec3(0.42, 0.41, 0.40) * (0.9 + 0.2 * n);
		vec3 Y = vec3(0.86, 0.68, 0.18);
		c = mix(c, Y, aa(av - 0.07));
		c = mix(c, Y, aa(abs(av - 0.93) - 0.04) * 0.85);
	} else if (kind == 5) {
		// patrol road: compacted gravel/asphalt, no markings
		c = vec3(0.58, 0.54, 0.47) * (0.9 + 0.2 * n);
		c = mix(c, vec3(0.70, 0.63, 0.52), smoothstep(0.5, 1.0, av) * 0.6);
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
