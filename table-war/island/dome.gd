class_name GlassDome
extends MeshInstance3D
## Glass dome over the whole island (the same build as Mafateeh's diorama dome): one
## smooth lathe standing on the slab's rim, clear where you look straight through it,
## catching the light towards its edges. Only drawn: shots, the pointer and the
## physics pass through it.

const K := 0.86            # a little lower than a half sphere
## The web's open ocean (build 20): no glass dome, nothing is held in (smoke, debris,
## arcs and jets fly free).
static var enabled := true
const R := IslandTerrain.RADIUS - 0.004


func build() -> void:
	name = "GlassDome"
	var outline: Array[Vector2] = []   # (radius, height above the sea)
	for k in 25:
		var t := PI / 2 * k / 24.0
		outline.append(Vector2(R * cos(t), K * R * sin(t)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 96
	for k in outline.size() - 1:
		var p0: Vector2 = outline[k]
		var p1: Vector2 = outline[k + 1]
		var tan := (p1 - p0).normalized()
		var n2 := Vector2(tan.y, -tan.x)   # outward in the (radius, height) plane
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var q := [Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x), Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x),
				Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x), Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)]
			var na := [Vector3(cos(a0) * n2.x, n2.y, sin(a0) * n2.x), Vector3(cos(a1) * n2.x, n2.y, sin(a1) * n2.x)]
			for j in [0, 2, 1, 0, 3, 2]:
				st.set_normal((na[0] if j in [0, 3] else na[1]).normalized())
				st.add_vertex(q[j])
	mesh = st.commit()
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
uniform vec3 tint : source_color = vec3(0.86, 0.93, 1.0);
void fragment() {
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = tint * 0.25;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	EMISSION = tint * f * 0.12;
	ALPHA = 0.035 + 0.4 * f;
}
"""
	m.shader = sh
	m.render_priority = -1   # under the trajectory dots, marker and smoke
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = IslandTerrain.SEA
