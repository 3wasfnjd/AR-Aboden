// Camera-facing soft puff for MultiMesh particles (one draw call per kind).
// INSTANCE_CUSTOM: x = rotation, y = seed, z = softness
varying float v_seed;
varying float v_soft;

float p_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float p_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(p_hash(i), p_hash(i + vec2(1.0, 0.0)), f.x), mix(p_hash(i + vec2(0.0, 1.0)), p_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	float rot = INSTANCE_CUSTOM.x;
	vec2 q = vec2(VERTEX.x * cos(rot) - VERTEX.y * sin(rot), VERTEX.x * sin(rot) + VERTEX.y * cos(rot));
	vec3 wpos = MODEL_MATRIX[3].xyz + (INV_VIEW_MATRIX[0].xyz * q.x + INV_VIEW_MATRIX[1].xyz * q.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(wpos, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.y;
	v_soft = INSTANCE_CUSTOM.z;
}

float puff_alpha(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;
	float r = length(d);
	float n = p_noise(uv * 3.5 + v_seed * 17.0) * 0.6 + p_noise(uv * 8.0 + v_seed * 5.0) * 0.4;
	return smoothstep(1.0, mix(0.15, 0.5, v_soft), r + (n - 0.5) * 0.45);
}
