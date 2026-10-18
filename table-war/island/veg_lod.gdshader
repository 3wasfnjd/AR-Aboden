shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Quest profile: ONE MultiMesh per species and LOD level for the whole island
// (instead of 2x2 tiles x 2 levels with visibility ranges). Each instance picks its
// level in the vertex shader from its own distance to the head: instances outside
// [lod_begin, lod_end) collapse to a point (degenerate triangles, nothing rasterised).
// Same look as MeshBuilder.vc_material(): vertex colour albedo.

global uniform vec3 tw_eye;          // head (XR camera) world position, set every frame
global uniform float tw_lod_scale;   // diorama scale in the room: a smaller model swaps nearer
uniform float lod_begin = 0.0;       // m (at diorama scale 1)
uniform float lod_end = 1.0e6;
uniform float roughness_v = 0.9;

void vertex() {
	float d = distance(MODEL_MATRIX[3].xyz, tw_eye);
	float k = max(tw_lod_scale, 0.05);
	if (d < lod_begin * k || d >= lod_end * k) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	// COLOR as is: matches the tiled vc_material() look in the Compatibility renderer
	// (checked side by side on the desktop hero shot; an extra sRGB decode darkens it).
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_v;
	SPECULAR = 0.35;
	METALLIC = 0.0;
}
