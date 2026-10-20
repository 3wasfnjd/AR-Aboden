class_name DioramaBase
extends Node3D
## The physical model, round: a walnut plinth disc with a raised, bevelled rim
## (brass inlay + engraved name plate on the rim), the cylindrical cut side of
## the slab showing strata, and the cast-resin sea where the cut passes water.

const RIM_W := 0.036          # width of the wooden rim around the slab
const RIM_UP := 0.006         # rim stands proud of the plinth top
const CHAMFER := 0.006
const FOOT := 0.003
const SEG := 160

var terrain: IslandTerrain
var tri_total := 0
var strata_mi: MeshInstance3D
var resin_mi: MeshInstance3D


func build(t: IslandTerrain) -> void:
	terrain = t
	for c in get_children():
		c.queue_free()
	_build_plinth()
	_build_walls()
	_build_plate()


static func _ring_pt(a: float, r: float, y: float) -> Vector3:
	return Vector3(cos(a) * r, y, sin(a) * r)


## Revolve a 2D profile (r, y) list around +y: quads between consecutive points.
func _lathe(mb: MeshBuilder, prof: Array, col: Color) -> void:
	for s in SEG:
		var a0 := TAU * s / SEG
		var a1 := TAU * (s + 1) / SEG
		var am := (a0 + a1) * 0.5
		for k in prof.size() - 1:
			var p0: Vector2 = prof[k]
			var p1: Vector2 = prof[k + 1]
			var A := _ring_pt(a0, p0.x, p0.y)
			var B := _ring_pt(a1, p0.x, p0.y)
			var C := _ring_pt(a1, p1.x, p1.y)
			var D := _ring_pt(a0, p1.x, p1.y)
			# outward = profile normal rotated into 3D
			var e := p1 - p0
			var n2 := Vector2(e.y, -e.x)   # right-hand normal of the profile segment
			var outd := Vector3(cos(am) * n2.x, n2.y, sin(am) * n2.x)
			mb.tri_out(A, B, C, col, outd)
			mb.tri_out(A, C, D, col, outd)


func _build_plinth() -> void:
	var R := IslandTerrain.RADIUS
	var top := IslandTerrain.PLINTH_H
	var ro := R + RIM_W
	var w := Color.WHITE
	# profile from the slab foot outwards and down (counter-clockwise in r,y):
	# inner rim wall -> bevelled rim top -> outer side -> bottom
	var prof := [
		Vector2(R + 0.0005, top),                       # meets the slab
		Vector2(R + 0.0005, top + RIM_UP - 0.0015),     # inner lip
		Vector2(R + 0.0025, top + RIM_UP),              # small inner bevel
		Vector2(ro - CHAMFER, top + RIM_UP),            # rim top
		Vector2(ro, top + RIM_UP - CHAMFER),            # outer chamfer
		Vector2(ro, FOOT),                              # outer side
		Vector2(ro - 0.008, FOOT),                      # under-cut
	]
	# make the profile wind so its right-hand normal points outward
	prof.reverse()
	var mb := MeshBuilder.new()
	_lathe(mb, prof, w)
	var wood := ShaderMaterial.new()
	wood.shader = load("res://island/wood.gdshader")
	wood.set_shader_parameter("col_light", Color(0.40, 0.25, 0.15))
	wood.set_shader_parameter("col_dark", Color(0.19, 0.11, 0.06))
	wood.set_shader_parameter("scale", 0.6)
	wood.set_shader_parameter("gloss", 0.75)
	var mi := MeshInstance3D.new()
	mi.name = "Plinth"
	mi.mesh = mb.commit(null, wood)
	add_child(mi)
	tri_total += mb.tri_count()
	# recessed dark foot (floating shadow-gap of a museum base)
	var fb := MeshBuilder.new()
	fb.cylinder(Vector3.ZERO, ro - 0.008, ro - 0.008, FOOT, 64, Color(0.08, 0.06, 0.05))
	var fm := MeshInstance3D.new()
	fm.name = "Foot"
	fm.mesh = fb.commit(null, MeshBuilder.vc_material(0.8))
	add_child(fm)
	# brass inlay ring on the rim top + a thin brass band where slab meets rim
	var bb := MeshBuilder.new()
	var gold := Color(0.85, 0.66, 0.36)
	var ring := [Vector2(R + 0.0105, top + RIM_UP + 0.0002), Vector2(R + 0.0125, top + RIM_UP + 0.0002)]
	_lathe(bb, [Vector2(R + 0.0125, top + RIM_UP + 0.00002), ring[1], ring[0], Vector2(R + 0.0105, top + RIM_UP + 0.00002)], gold)
	var bm := MeshInstance3D.new()
	bm.name = "BrassInlay"
	bm.mesh = bb.commit(null, _brass())
	add_child(bm)
	tri_total += bb.tri_count() + fb.tri_count()


func _brass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.metallic = 1.0
	m.roughness = 0.32
	return m


func _build_walls() -> void:
	var t := terrain
	var sm := MeshBuilder.new()
	var rm := MeshBuilder.new()
	var w := Color.WHITE
	var by := IslandTerrain.PLINTH_H
	var sea := IslandTerrain.SEA
	for e in t.rim_edges():
		var a := t.vpos(e.x % (IslandTerrain.NX + 1), e.x / (IslandTerrain.NX + 1))
		var b := t.vpos(e.y % (IslandTerrain.NX + 1), e.y / (IslandTerrain.NX + 1))
		if Vector2(a.x - b.x, a.z - b.z).length() < 1e-6:
			continue
		var outd := Vector3((a.x + b.x) * 0.5, 0, (a.z + b.z) * 0.5)
		var ab := Vector3(a.x, by, a.z)
		var bb := Vector3(b.x, by, b.z)
		sm.tri_out(ab, bb, b, w, outd, Vector2(0, a.y - by), Vector2(0, b.y - by), Vector2(0, 0))
		sm.tri_out(ab, b, a, w, outd, Vector2(0, a.y - by), Vector2(0, 0), Vector2(0, 0))
		var ha := a.y
		var hb := b.y
		if ha >= sea and hb >= sea:
			continue
		var sa := Vector3(a.x, sea, a.z)
		var sb := Vector3(b.x, sea, b.z)
		if ha < sea and hb < sea:
			rm.tri_out(a, b, sb, w, outd)
			rm.tri_out(a, sb, sa, w, outd)
		else:
			var f := (sea - ha) / (hb - ha)
			var cpt := a.lerp(b, f)
			cpt.y = sea
			if ha < sea:
				rm.tri_out(a, cpt, sa, w, outd)
			else:
				rm.tri_out(cpt, b, sb, w, outd)
	var smat := ShaderMaterial.new()
	smat.shader = load("res://island/strata.gdshader")
	smat.set_shader_parameter("base_y", IslandTerrain.PLINTH_H)
	strata_mi = MeshInstance3D.new()
	strata_mi.name = "StrataWalls"
	strata_mi.mesh = sm.commit(null, smat)
	add_child(strata_mi)
	var rmat := ShaderMaterial.new()
	rmat.shader = load("res://island/resin.gdshader")
	rmat.set_shader_parameter("sea_y", IslandTerrain.SEA)
	rmat.set_shader_parameter("depth_range", 0.045)
	resin_mi = MeshInstance3D.new()
	resin_mi.name = "ResinEdge"
	resin_mi.mesh = rm.commit(null, rmat)
	resin_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(resin_mi)
	tri_total += sm.tri_count() + rm.tri_count()


func _build_plate() -> void:
	# plate sits on the front of the rim top, facing the player
	var R := IslandTerrain.RADIUS
	var top := IslandTerrain.PLINTH_H + RIM_UP
	var zc := R + 0.0245
	var pb := MeshBuilder.new()
	var gold := Color(0.80, 0.62, 0.34)
	pb.box(Vector3(0, top + 0.0005, zc), Vector3(0.13, 0.001, 0.0125), gold)
	pb.box(Vector3(0, top + 0.00105, zc), Vector3(0.124, 0.0001, 0.0095), Color(0.70, 0.53, 0.28))
	var mi := MeshInstance3D.new()
	mi.name = "NamePlate"
	mi.mesh = pb.commit(null, _brass())
	add_child(mi)
	tri_total += pb.tri_count()
	add_child(_engraving("حرب البارجة", 0.0042, Vector3(0, top + 0.00115, zc - 0.0016)))
	add_child(_engraving("عبودين قيمز  ·  ABODEN GAMES", 0.0019, Vector3(0, top + 0.00115, zc + 0.0031)))


func _engraving(text: String, height: float, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font = XRGame.ui_font()   # Cairo with the Arabic glyphs
	l.text = text
	l.font_size = 96
	l.outline_size = 0
	l.pixel_size = height / 96.0
	l.modulate = Color(0.22, 0.14, 0.06)
	l.shaded = true
	l.double_sided = false
	l.position = pos
	l.rotation = Vector3(-PI * 0.5, 0, 0)
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return l
