class_name Ocean
extends MeshInstance3D
## The web's open ocean (build 20): the island stands in the middle of a sea that runs to
## the horizon instead of on a slab on a table. A low-poly ring of facets round the
## island's own water disc, the deep colour of the island sea near it, darker and bluer
## towards the horizon, with a gentle swell of flat facets. Island-local; one draw call.

const SEA_COL := Color(0.05, 0.34, 0.74)       # the island sea's deep band (water.gdshaderinc)
const FAR_COL := Color(0.10, 0.30, 0.55)
const RINGS := [0.492, 0.56, 0.68, 0.86, 1.15, 1.6, 2.4, 3.6, 5.5, 8.5, 13.0, 20.0, 30.0]


func build() -> void:
	name = "Ocean"
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var seg := 120
	var y := IslandTerrain.SEA - 0.0003
	for i in RINGS.size() - 1:
		var r0: float = RINGS[i]
		var r1: float = RINGS[i + 1]
		var k := float(i) / (RINGS.size() - 2)
		var amp := 0.0 if i == 0 else 0.0006 * r0
		for sgi in seg:
			var a0 := TAU * sgi / seg
			var a1 := TAU * (sgi + 1) / seg
			var p00 := Vector3(cos(a0) * r0, y, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y + rng.randf_range(-amp, amp), sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y + rng.randf_range(-amp, amp), sin(a1) * r1)
			var c := SEA_COL.lerp(FAR_COL, pow(k, 0.7)).lightened(rng.randf_range(-0.03, 0.03))
			mb.tri_out(p00, p10, p11, c, Vector3.UP)
			mb.tri_out(p00, p11, p01, c.darkened(0.03), Vector3.UP)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.35
	m.metallic_specular = 0.25
	mesh = mb.commit(null, m)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
