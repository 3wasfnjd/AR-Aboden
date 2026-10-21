shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;
#include "res://fx/puff.gdshaderinc"

void fragment() {
	float a = puff_alpha(UV);
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * 2.5 * a * COLOR.a;
	ALPHA = 1.0;
}
