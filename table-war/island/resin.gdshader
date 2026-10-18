shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Polished cast-resin "sea" seen at the cut edge of the slab.

uniform float sea_y = 0.078;
uniform float depth_range = 0.04;
uniform vec3 col_top : source_color = vec3(0.34, 0.82, 0.80);
uniform vec3 col_deep : source_color = vec3(0.03, 0.22, 0.40);
varying vec3 wp;

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float d = clamp((sea_y - wp.y) / depth_range, 0.0, 1.0);
	vec3 c = mix(col_top, col_deep, smoothstep(0.0, 0.75, d));
	// faint suspended "depth haze" streaks typical of layered resin pours
	float streak = 0.5 + 0.5 * sin(wp.y * 2200.0 + sin((wp.x + wp.z) * 40.0) * 2.0);
	c *= 0.96 + streak * 0.05;
	// bright meniscus right under the surface
	float men = smoothstep(0.0012, 0.0, sea_y - wp.y);
	c = mix(c, vec3(0.75, 0.95, 0.93), men * 0.6);
	ALBEDO = c;
	// light scattered inside the cast resin (cheap subsurface impression)
	EMISSION = c * (0.10 + 0.25 * (1.0 - smoothstep(0.0, 0.5, d)));
	ALPHA = mix(0.62, 0.9, d);
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
}
