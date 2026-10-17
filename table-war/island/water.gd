class_name IslandWater
extends MeshInstance3D
## Sea surface plane covering the whole slab at IslandTerrain.SEA.

var terrain: IslandTerrain
var shader_mat: ShaderMaterial


func build(t: IslandTerrain) -> void:
	terrain = t
	var sz := t.size()
	# polar disc so the sea meets the round resin edge exactly
	var rings := 40
	var segs := 160
	var R := IslandTerrain.RADIUS - 0.00005
	var verts := PackedVector3Array([Vector3(0, IslandTerrain.SEA, 0)])
	var idxs := PackedInt32Array()
	for r in range(1, rings + 1):
		var rr := R * float(r) / rings
		for k in segs:
			var a := TAU * k / segs
			verts.append(Vector3(cos(a) * rr, IslandTerrain.SEA, sin(a) * rr))
	for k in segs:
		var k1 := (k + 1) % segs
		idxs.append_array([0, 1 + k, 1 + k1])
	for r in range(1, rings):
		var b0 := 1 + (r - 1) * segs
		var b1 := 1 + r * segs
		for k in segs:
			var k1 := (k + 1) % segs
			idxs.append_array([b0 + k, b1 + k, b0 + k1, b0 + k1, b1 + k, b1 + k1])
	_tris = idxs.size() / 3
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idxs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = load("res://island/water.gdshader")
	shader_mat.set_shader_parameter("depth_tex", t.depth_texture)
	shader_mat.set_shader_parameter("rect", Vector4(t.ox, t.oz, sz.x, sz.y))
	shader_mat.set_shader_parameter("depth_range", IslandTerrain.DEPTH_RANGE)
	shader_mat.set_shader_parameter("radius", IslandTerrain.RADIUS)
	m.surface_set_material(0, shader_mat)
	mesh = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# AABB margin for the vertex waves
	custom_aabb = AABB(Vector3(t.ox, IslandTerrain.SEA - 0.01, t.oz), Vector3(sz.x, 0.02, sz.y))


var _tris := 0


func triangle_count() -> int:
	return _tris
