shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;
#include "res://fx/puff.gdshaderinc"

void fragment() {
	float a = puff_alpha(UV);
	// fake lighting: brighter top, darker belly
	float shade = mix(0.72, 1.08, 1.0 - UV.y);
	// hot puffs (bright colours) are pushed into HDR so glow picks them up
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float hot = smoothstep(0.75, 0.95, COLOR.r) * smoothstep(0.35, 0.7, COLOR.g);
	ALBEDO = c * shade * (1.0 + hot * 2.5);
	ALPHA = a * COLOR.a;
}
