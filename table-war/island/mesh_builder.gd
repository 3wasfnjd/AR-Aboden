class_name MeshBuilder
extends RefCounted
## Tiny flat-shaded mesh builder used by every procedural piece.
## Convention: tri(a, b, c) takes the corners counter-clockwise as seen from the
## front face (normal = (b-a)x(c-a)); it is emitted in Godot's clockwise order.
## UV  : free per-material use (walls: x = distance along wall, y = height).
## UV2 : walls: (wall length, wall height) so shaders can centre window grids.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var xform := Transform3D.IDENTITY

const NO_UV := Vector2(0.0, -1.0)


func clear() -> void:
	verts.clear(); norms.clear(); cols.clear(); uvs.clear(); uv2s.clear()


func tri_count() -> int:
	return verts.size() / 3


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, ua := NO_UV, ub := NO_UV, uc := NO_UV, u2 := Vector2.ZERO) -> void:
	a = xform * a
	b = xform * b
	c = xform * c
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-26:
		return
	n = n.normalized()
	verts.append(a); verts.append(c); verts.append(b)
	norms.append(n); norms.append(n); norms.append(n)
	cols.append(col); cols.append(col); cols.append(col)
	uvs.append(ua); uvs.append(uc); uvs.append(ub)
	uv2s.append(u2); uv2s.append(u2); uv2s.append(u2)


## Triangle that is re-ordered so that its normal points along `out_dir`.
func tri_out(a: Vector3, b: Vector3, c: Vector3, col: Color, out_dir: Vector3, ua := NO_UV, ub := NO_UV, uc := NO_UV, u2 := Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(out_dir) < 0.0:
		tri(a, c, b, col, ua, uc, ub, u2)
	else:
		tri(a, b, c, col, ua, ub, uc, u2)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, ua := NO_UV, ub := NO_UV, uc := NO_UV, ud := NO_UV, u2 := Vector2.ZERO) -> void:
	tri(a, b, c, col, ua, ub, uc, u2)
	tri(a, c, d, col, ua, uc, ud, u2)


## Axis-aligned (in local xform space) box. `windows` writes wall UVs for the
## structure shader; otherwise all faces get NO_UV.
func box(center: Vector3, size: Vector3, col: Color, windows := false, top_col := Color(-1, 0, 0), bottom := false) -> void:
	var h := size * 0.5
	var x0 := center.x - h.x; var x1 := center.x + h.x
	var y0 := center.y - h.y; var y1 := center.y + h.y
	var z0 := center.z - h.z; var z1 := center.z + h.z
	var tc := col if top_col.r < 0.0 else top_col
	# top
	quad(Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), tc)
	if bottom:
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), col)
	var hy := size.y
	var u2x := Vector2(size.x, hy)
	var u2z := Vector2(size.z, hy)
	if windows:
		# +z face
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), col,
			Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, hy), Vector2(0, hy), u2x)
		# -z face
		quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), col,
			Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, hy), Vector2(0, hy), u2x)
		# +x face
		quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), col,
			Vector2(0, 0), Vector2(size.z, 0), Vector2(size.z, hy), Vector2(0, hy), u2z)
		# -x face
		quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), col,
			Vector2(0, 0), Vector2(size.z, 0), Vector2(size.z, hy), Vector2(0, hy), u2z)
	else:
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), col)
		quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), col)
		quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), col)
		quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), col)


## Frustum / cylinder along +y starting at `base`.
func cylinder(base: Vector3, r0: float, r1: float, height: float, sides: int, col: Color, cap_top := true, cap_col := Color(-1, 0, 0), phase := 0.0) -> void:
	var cc := col if cap_col.r < 0.0 else cap_col
	var top := base + Vector3(0, height, 0)
	for s in sides:
		var a0 := TAU * float(s) / sides + phase
		var a1 := TAU * float(s + 1) / sides + phase
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := base + d0 * r0
		var b1 := base + d1 * r0
		var t0 := top + d0 * r1
		var t1 := top + d1 * r1
		var outd := d0 + d1 + Vector3(0, (r0 - r1) / maxf(height, 1e-6), 0)
		tri_out(b0, b1, t1, col, outd)
		tri_out(b0, t1, t0, col, outd)
		if cap_top and r1 > 0.0:
			tri_out(top, t0, t1, cc, Vector3.UP)


## Low-poly UV sphere (or upper hemisphere when `hemi`).
func sphere(center: Vector3, radius: Vector3, rings: int, sides: int, col: Color, hemi := false) -> void:
	var r_end := rings if not hemi else rings / 2
	for r in r_end:
		var p0 := PI * float(r) / rings
		var p1 := PI * float(r + 1) / rings
		for s in sides:
			var a0 := TAU * float(s) / sides
			var a1 := TAU * float(s + 1) / sides
			var v00 := center + Vector3(sin(p0) * cos(a0), cos(p0), sin(p0) * sin(a0)) * radius
			var v01 := center + Vector3(sin(p0) * cos(a1), cos(p0), sin(p0) * sin(a1)) * radius
			var v10 := center + Vector3(sin(p1) * cos(a0), cos(p1), sin(p1) * sin(a0)) * radius
			var v11 := center + Vector3(sin(p1) * cos(a1), cos(p1), sin(p1) * sin(a1)) * radius
			tri_out(v00, v10, v11, col, (v00 + v11) * 0.5 - center)
			tri_out(v00, v11, v01, col, (v00 + v11) * 0.5 - center)


## Displaced icosahedron rock, unit radius around origin.
func rock(center: Vector3, radius: Vector3, col: Color, rng: RandomNumberGenerator, rough := 0.28) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var pts: Array[Vector3] = []
	for p: Vector3 in v:
		var q := p.normalized() * (1.0 + rng.randf_range(-rough, rough))
		pts.append(center + q * radius)
	for face: Array in f:
		var a: Vector3 = pts[face[0]]
		var b: Vector3 = pts[face[1]]
		var c: Vector3 = pts[face[2]]
		var shade := 1.0 + rng.randf_range(-0.06, 0.06)
		tri_out(a, b, c, Color(col.r * shade, col.g * shade, col.b * shade, col.a), (a + b + c) / 3.0 - center)


func to_arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	return arr


func commit(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.size() == 0:
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, to_arrays())
	if material:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


static func vc_material(rough := 0.85, cull := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic_specular = 0.35
	# build 3 cartoon look: banded light everywhere (terrain, vegetation, props)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	if not cull:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
