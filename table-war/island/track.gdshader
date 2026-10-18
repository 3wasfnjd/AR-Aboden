shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_back, shadows_disabled;
// Tyre ruts: multiply-darken whatever sand is underneath (no colour mismatch).
// Island-local position: the diorama can be moved / turned / scaled in the room (XR),
// tw_island_inv (world -> diorama) keeps every pattern glued to the model.
global uniform mat4 tw_island_inv;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() { wp = (tw_island_inv * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz; }
void fragment() {
	float edge = 1.0 - smoothstep(0.3, 1.0, abs(UV.y));
	float fade = smoothstep(0.25, 0.65, vnoise(wp.xz * 120.0));
	ALBEDO = mix(vec3(1.0), vec3(0.86, 0.82, 0.76), edge * fade);
}
