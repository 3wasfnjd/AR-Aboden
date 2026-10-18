shader_type spatial;
render_mode cull_back;
// Cut side of the slab: stratified sediment layers, slightly wavy, with a thin
// top-soil band under the surface. UV.y = depth below the terrain surface (m).

uniform float base_y = 0.018;
// Island-local position: the diorama can be moved / turned / scaled in the room (XR),
// tw_island_inv (world -> diorama) keeps every pattern glued to the model.
global uniform mat4 tw_island_inv;
varying vec3 wp;
varying float below;

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(hash(i), hash(i + 1.0), f); }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void vertex() {
	wp = (tw_island_inv * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
	below = UV.y;
}

void fragment() {
	float along = wp.x + wp.z * 1.37;
	float y = wp.y - base_y;
	// warp layers: long gentle folds + small wobble
	float yw = y + 0.004 * sin(along * 5.0 + 1.0) + 0.0016 * sin(along * 23.0) + 0.0007 * (vn(along * 160.0) - 0.5);
	float layer = yw * 260.0;           // ~3.8 mm average layer
	float li = floor(layer + vn(along * 9.0) * 0.6);
	float r = hash(li + 3.0);
	vec3 c;
	if (r < 0.22) c = vec3(0.84, 0.78, 0.66);        // pale sandstone
	else if (r < 0.40) c = vec3(0.74, 0.65, 0.52);   // buff
	else if (r < 0.52) c = vec3(0.66, 0.53, 0.42);   // ochre
	else if (r < 0.66) c = vec3(0.58, 0.55, 0.51);   // grey shale
	else if (r < 0.80) c = vec3(0.79, 0.71, 0.58);   // sand
	else if (r < 0.90) c = vec3(0.60, 0.48, 0.40);   // red-brown
	else c = vec3(0.88, 0.85, 0.78);                 // chalky limestone
	// thin dark seams between some layers
	float fl = fract(layer);
	float seam = smoothstep(0.06, 0.0, fl) * step(0.55, hash(li + 17.0));
	c *= 1.0 - seam * 0.35;
	// grain / pebbles
	float g = hash2(floor(vec2(along, wp.y) * 2600.0));
	c *= 0.94 + g * 0.1;
	float peb = step(0.985, hash2(floor(vec2(along, wp.y) * 900.0)));
	c = mix(c, c * 0.72, peb * step(0.5, hash(li)));
	// darker towards the plinth, top soil under the surface
	c *= mix(0.78, 1.0, smoothstep(0.0, 0.03, y));
	float soil = 1.0 - smoothstep(0.0015, 0.0035, below);
	c = mix(c, vec3(0.55, 0.43, 0.31), soil * 0.8);
	ALBEDO = lin(c);
	ROUGHNESS = 0.93;
	SPECULAR = 0.2;
}
