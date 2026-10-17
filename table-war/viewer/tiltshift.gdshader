shader_type canvas_item;
// Fake tilt-shift: sharp horizontal focus band, blur growing above/below,
// plus a touch of saturation and vignette. Screen-space only (Compatibility-safe).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float focus_y = 0.55;
uniform float band = 0.12;
uniform float max_blur = 9.0;
uniform float saturation = 1.12;
uniform float vignette = 0.28;

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = abs(uv.y - focus_y);
	float b = smoothstep(band, band + 0.35, d) * max_blur;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	// 3 rings golden-angle disc
	for (int i = 0; i < 24; i++) {
		float fi = float(i);
		float r = sqrt((fi + 0.5) / 24.0) * b;
		float a = fi * 2.39996;
		vec2 o = vec2(cos(a), sin(a)) * r * px;
		acc += textureLod(screen_tex, uv + o, 0.0).rgb;
		wsum += 1.0;
	}
	vec3 c = acc / wsum;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	vec2 v = uv - 0.5;
	c *= 1.0 - vignette * dot(v, v) * 1.6;
	COLOR = vec4(c, 1.0);
}
