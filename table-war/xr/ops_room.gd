class_name OpsRoom
extends Node3D
## The battleship's operations room (VR, build 14): where the player stands. Procedural
## stylized low-poly, all in code: an octagonal steel room with a hologram table in the
## middle (the island stands on it), crew consoles with glowing screens round the walls,
## light strips in the ceiling, and a wide window band on the far side looking out over
## the sea, the archipelago on the horizon and the fleet sailing with us.
##
## World-locked (XR origin space, metres): the table centre is `table` on the floor, the
## player starts on the near side facing it. Flat shading everywhere (MeshBuilder faces),
## Lambert light (no toon bands, so the room reads as solid low-poly), emissive parts
## unshaded. Cheap: a handful of meshes, ~6k triangles, no textures, no shadows.

const R := 3.4                   # room radius (octagon)
const H := 2.9                   # ceiling
const SIDES := 8
const TABLE_H := 0.6             # the hologram table top (the diorama base stands on it): low, to look down on the city
const SEA_Y := -1.6              # the sea, below the ops room (we are high in the ship)
## The world outside the windows is built small and close (a stylized backdrop): all of
## it within OUT_MAX metres, inside the headset camera's far plane (60 m) and its depth
## precision. Built at real scale (hundreds of metres) it flickered at the far plane.
const OUT_K := 0.1
const OUT_MAX := 55.0
const HULL := Color(0.20, 0.23, 0.27)
const HULL_DARK := Color(0.13, 0.15, 0.18)
const PANEL := Color(0.27, 0.31, 0.36)
const FLOOR := Color(0.16, 0.18, 0.21)
const TRIM := Color(0.40, 0.45, 0.50)
const GLOW_CYAN := Color(0.30, 0.85, 1.0)
const GLOW_AMBER := Color(1.0, 0.72, 0.30)
const GLOW_GREEN := Color(0.45, 1.0, 0.55)
const SKY_TOP := Color(0.32, 0.52, 0.80)
const SKY_HORIZON := Color(0.86, 0.80, 0.70)
const SEA_DEEP := Color(0.10, 0.27, 0.42)
const SEA_NEAR := Color(0.15, 0.38, 0.55)

var table := Vector3(0, 0, -0.95)
var _rng := RandomNumberGenerator.new()


## Build round `table_centre` (a floor point under the hologram table).
func build(table_centre: Vector3) -> void:
	table = table_centre
	_rng.seed = 314
	var solid := MeshBuilder.new()
	var glow := MeshBuilder.new()
	_shell(solid, glow)
	_consoles(solid, glow)
	_pedestal(solid, glow)
	_add("Room", solid.commit(null, lambert(0.85)))
	_add("RoomGlow", glow.commit(null, emissive()))
	var outside := MeshBuilder.new()
	_sea(outside)
	_fleet(outside)
	_islands(outside)
	_add("Outside", outside.commit(null, lambert(0.95)))
	_add("Sky", _sky_dome())


func _add(nm: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Flat-shaded vertex-colour material, plain Lambert (the low-poly look).
static func lambert(rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic_specular = 0.2
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	return m


static func emissive() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	return m


## Corner k of the octagon at radius r (corner 0 on the far side, -Z from the table).
func _corner(k: int, r: float) -> Vector3:
	var a := TAU * (float(k) + 0.5) / SIDES + PI * 0.5
	return table + Vector3(cos(a) * r, 0.0, -sin(a) * r)


## Wall segment k faces the table; segments 7, 0, 1 (the far side) carry the window band.
func _is_window(k: int) -> bool:
	return k == 0 or k == 1 or k == SIDES - 1


func _shell(mb: MeshBuilder, glow: MeshBuilder) -> void:
	var up := Vector3.UP
	# floor: steel plates in rings, a darker walkway round the table
	for k in SIDES:
		var a0 := _corner(k, R)
		var a1 := _corner(k + 1, R)
		var m0 := _corner(k, 1.1)
		var m1 := _corner(k + 1, 1.1)
		var c := table
		mb.tri_out(c, m0, m1, FLOOR.darkened(0.15), up)
		mb.tri_out(m0, a0, a1, FLOOR if k % 2 == 0 else FLOOR.lightened(0.04), up)
		mb.tri_out(m0, a1, m1, FLOOR if k % 2 == 0 else FLOOR.lightened(0.04), up)
		# glowing ring on the floor round the table
		var g0 := _corner(k, 1.12) + up * 0.008
		var g1 := _corner(k + 1, 1.12) + up * 0.008
		var h0 := _corner(k, 1.16) + up * 0.008
		var h1 := _corner(k + 1, 1.16) + up * 0.008
		glow.tri_out(g0, h0, h1, GLOW_CYAN.darkened(0.35), up)
		glow.tri_out(g0, h1, g1, GLOW_CYAN.darkened(0.35), up)
	# walls
	for k in SIDES:
		var a0 := _corner(k, R)
		var a1 := _corner(k + 1, R)
		var inward := (table - (a0 + a1) * 0.5) * Vector3(1, 0, 1)
		var y := func(p: Vector3, h: float) -> Vector3: return p + Vector3(0, h, 0)
		if _is_window(k):
			# lower wall, a sill, the window opening (nothing), a header
			_quad(mb, a0, a1, 0.0, 0.95, PANEL, inward)
			_quad(mb, a0, a1, 0.95, 1.02, TRIM, inward)
			_quad(mb, a0, a1, 2.25, H, PANEL, inward)
			# mullions
			for f in [0.0, 0.5, 1.0]:
				var p: Vector3 = a0.lerp(a1, f)
				var side := (a1 - a0).normalized() * 0.05
				_quad(mb, p - side, p + side, 1.02, 2.25, HULL_DARK, inward)
		else:
			_quad(mb, a0, a1, 0.0, 0.9, HULL_DARK, inward)
			_quad(mb, a0, a1, 0.9, 2.2, PANEL, inward)
			_quad(mb, a0, a1, 2.2, H, HULL, inward)
			# a glowing status strip along the wall
			var g0: Vector3 = a0.lerp(a1, 0.08) + inward.normalized() * 0.01
			var g1: Vector3 = a0.lerp(a1, 0.92) + inward.normalized() * 0.01
			_quad(glow, g0, g1, 2.12, 2.15, GLOW_CYAN.darkened(0.2), inward)
		# vertical ribs at the corners
		var rib := inward.normalized() * 0.02
		var t0 := a0 + (a1 - a0).normalized() * 0.07 + rib
		_quad(mb, a0 + rib, t0, 0.0, H, TRIM.darkened(0.2), inward)
	# ceiling with light strips
	for k in SIDES:
		var a0 := _corner(k, R) + Vector3(0, H, 0)
		var a1 := _corner(k + 1, R) + Vector3(0, H, 0)
		var c := table + Vector3(0, H, 0)
		mb.tri_out(c, a0, a1, HULL_DARK, Vector3.DOWN)
		var l0 := _corner(k, 1.8) + Vector3(0, H - 0.01, 0)
		var l1 := _corner(k + 1, 1.8) + Vector3(0, H - 0.01, 0)
		var l2 := _corner(k, 2.0) + Vector3(0, H - 0.01, 0)
		var l3 := _corner(k + 1, 2.0) + Vector3(0, H - 0.01, 0)
		glow.tri_out(l0, l2, l3, Color(0.85, 0.92, 1.0), Vector3.DOWN)
		glow.tri_out(l0, l3, l1, Color(0.85, 0.92, 1.0), Vector3.DOWN)


## A wall quad between floor points a, b from height h0 to h1, facing `inward`.
func _quad(mb: MeshBuilder, a: Vector3, b: Vector3, h0: float, h1: float, c: Color, inward: Vector3) -> void:
	var p0 := a + Vector3(0, h0, 0)
	var p1 := b + Vector3(0, h0, 0)
	var p2 := b + Vector3(0, h1, 0)
	var p3 := a + Vector3(0, h1, 0)
	mb.tri_out(p0, p1, p2, c, inward)
	mb.tri_out(p0, p2, p3, c, inward)


## Crew consoles on the side walls: angled desks with glowing screens and a seat.
func _consoles(mb: MeshBuilder, glow: MeshBuilder) -> void:
	var screens := [GLOW_CYAN, GLOW_GREEN, GLOW_AMBER]
	for k in [2, 3, 5, 6]:
		var a0 := _corner(k, R - 0.05)
		var a1 := _corner(k + 1, R - 0.05)
		var mid := (a0 + a1) * 0.5
		var along := (a1 - a0).normalized()
		var inward := ((table - mid) * Vector3(1, 0, 1)).normalized()
		for s in [-0.6, 0.6]:
			var c: Vector3 = mid + along * s + inward * 0.35
			var basis := Basis(along, Vector3.UP, -inward)
			var saved := mb.xform
			mb.xform = Transform3D(basis, c)
			mb.box(Vector3(0, 0.38, 0), Vector3(0.9, 0.76, 0.55), HULL)
			mb.box(Vector3(0, 0.8, 0.12), Vector3(0.9, 0.08, 0.3), TRIM.darkened(0.1))
			mb.box(Vector3(0, 1.08, 0.2), Vector3(0.85, 0.5, 0.06), HULL_DARK)
			mb.xform = saved
			var gsaved := glow.xform
			glow.xform = Transform3D(basis, c)
			var col: Color = screens[(k * 2 + int(s > 0.0)) % screens.size()]
			# screen face (toward the room) with a few "data" bars
			glow.box(Vector3(0, 1.08, -0.012), Vector3(0.74, 0.40, 0.004), Color(0.03, 0.08, 0.12).lerp(col, 0.12))
			for b in 4:
				var w := _rng.randf_range(0.15, 0.55)
				glow.box(Vector3(-0.3 + w * 0.5, 0.96 + b * 0.07, -0.022), Vector3(w, 0.022, 0.003), col)
			glow.box(Vector3(0.22, 1.18, -0.022), Vector3(0.18, 0.12, 0.003), col.lightened(0.2))
			glow.xform = gsaved
			# seat
			var seat: Vector3 = c + inward * 0.7
			var ss := mb.xform
			mb.xform = Transform3D(basis, seat)
			mb.cylinder(Vector3(0, 0, 0), 0.05, 0.05, 0.42, 8, HULL_DARK)
			mb.box(Vector3(0, 0.46, 0), Vector3(0.42, 0.08, 0.42), Color(0.18, 0.22, 0.30))
			mb.box(Vector3(0, 0.75, -0.19), Vector3(0.42, 0.55, 0.07), Color(0.18, 0.22, 0.30))
			# a crew member at most consoles, facing the screen
			if not (k == 6 and s > 0.0):
				_crew(mb, (k + int(s > 0.0)) % 3)
			mb.xform = ss


## A seated crew member (low-poly: torso, head, cap, arms on the desk), in the current
## xform (seat space: +z toward the console... the seat faces -inward = -z).
func _crew(mb: MeshBuilder, v: int) -> void:
	var uniform: Color = [Color(0.20, 0.27, 0.40), Color(0.26, 0.30, 0.24), Color(0.22, 0.24, 0.30)][v]
	var skin: Color = [Color(0.78, 0.60, 0.45), Color(0.62, 0.45, 0.33), Color(0.86, 0.70, 0.56)][v]
	mb.box(Vector3(0, 0.53, 0.05), Vector3(0.30, 0.14, 0.34), uniform.darkened(0.2))          # thighs
	mb.box(Vector3(0, 0.30, 0.20), Vector3(0.26, 0.40, 0.10), uniform.darkened(0.3))          # shins
	mb.box(Vector3(0, 0.82, -0.08), Vector3(0.34, 0.44, 0.20), uniform)                       # torso
	mb.sphere(Vector3(0, 1.13, -0.08), Vector3(0.10, 0.12, 0.10), 4, 6, skin)                 # head
	mb.box(Vector3(0, 1.22, -0.08), Vector3(0.21, 0.05, 0.21), uniform.darkened(0.25))        # cap
	mb.box(Vector3(0, 1.20, 0.03), Vector3(0.18, 0.015, 0.08), uniform.darkened(0.35))        # peak
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(sx * 0.2, 0.86, 0.06), Vector3(0.08, 0.08, 0.34), uniform.lightened(0.05))   # arms on the desk


## The hologram table: a round steel pedestal; its top (TABLE_H) carries the diorama base.
func _pedestal(mb: MeshBuilder, glow: MeshBuilder) -> void:
	mb.cylinder(table, 0.42, 0.36, 0.08, 16, HULL_DARK)
	mb.cylinder(table + Vector3(0, 0.08, 0), 0.30, 0.30, TABLE_H - 0.16, 16, HULL)
	mb.cylinder(table + Vector3(0, TABLE_H - 0.083, 0), 0.36, 0.585, 0.08, 24, PANEL, true, TRIM)
	glow.cylinder(table + Vector3(0, TABLE_H - 0.091, 0), 0.37, 0.37, 0.006, 24, GLOW_CYAN, false)
	glow.cylinder(table + Vector3(0, 0.08, 0), 0.305, 0.305, 0.012, 16, GLOW_CYAN.darkened(0.3), false)


# --- outside ---------------------------------------------------------------------------

func _sea(mb: MeshBuilder) -> void:
	# low-poly swell: a fan of facets out to the horizon, darker far away
	var rings := [4.0, 7.0, 12.0, 20.0, 30.0, 42.0, 52.0]
	var seg := 28
	var c := Vector3(table.x, SEA_Y, table.z)
	for i in rings.size() - 1:
		var r0: float = rings[i]
		var r1: float = rings[i + 1]
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var j0 := _rng.randf_range(-0.03, 0.03) * (1.0 + i)
			var p := [c + Vector3(cos(a0) * r0, j0 * 0.2, sin(a0) * r0), c + Vector3(cos(a1) * r0, 0.0, sin(a1) * r0),
				c + Vector3(cos(a0) * r1, 0.0, sin(a0) * r1), c + Vector3(cos(a1) * r1, j0 * 0.3, sin(a1) * r1)]
			var col := SEA_NEAR.lerp(SEA_DEEP, float(i) / (rings.size() - 2)).lightened(_rng.randf_range(-0.04, 0.04))
			mb.tri_out(p[0], p[2], p[3], col, Vector3.UP)
			mb.tri_out(p[0], p[3], p[1], col.darkened(0.05), Vector3.UP)


## Escort ships of the fleet, out beyond the windows.
func _fleet(mb: MeshBuilder) -> void:
	var ships := [[Vector3(-35, 0, -70), 22.0, 0.3], [Vector3(40, 0, -95), 28.0, -0.2], [Vector3(-90, 0, -150), 34.0, 0.1], [Vector3(110, 0, -180), 40.0, 0.5]]
	for s in ships:
		var p: Vector3 = table + (s[0] as Vector3) * OUT_K * 1.6 + Vector3(0, SEA_Y, 0)
		var L: float = float(s[1]) * OUT_K * 1.6
		var saved := mb.xform
		mb.xform = Transform3D(Basis(Vector3.UP, float(s[2])), p)
		var hull := Color(0.42, 0.46, 0.52)
		# hull (a prism), superstructure blocks, a mast
		var pts := [Vector3(-L * 0.5, 0, -L * 0.07), Vector3(L * 0.3, 0, -L * 0.08), Vector3(L * 0.5, 0, 0), Vector3(L * 0.3, 0, L * 0.08), Vector3(-L * 0.5, 0, L * 0.07)]
		for k in pts.size():
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[(k + 1) % pts.size()]
			var o := (a + b) * 0.5
			mb.tri_out(a, b, b + Vector3(0, L * 0.06, 0), hull, o)
			mb.tri_out(a, b + Vector3(0, L * 0.06, 0), a + Vector3(0, L * 0.06, 0), hull, o)
		for k in range(1, pts.size() - 1):
			mb.tri_out(pts[0] + Vector3(0, L * 0.06, 0), pts[k] + Vector3(0, L * 0.06, 0), pts[k + 1] + Vector3(0, L * 0.06, 0), hull.darkened(0.1), Vector3.UP)
		mb.box(Vector3(-L * 0.05, L * 0.1, 0), Vector3(L * 0.22, L * 0.08, L * 0.1), Color(0.55, 0.59, 0.64))
		mb.box(Vector3(-L * 0.02, L * 0.17, 0), Vector3(L * 0.1, L * 0.06, L * 0.07), Color(0.60, 0.64, 0.70))
		mb.cylinder(Vector3(-L * 0.02, L * 0.2, 0), L * 0.008, L * 0.004, L * 0.14, 5, Color(0.25, 0.27, 0.30))
		mb.xform = saved


## Low hills of the archipelago on the horizon.
func _islands(mb: MeshBuilder) -> void:
	var isl := [[Vector3(-160, 0, -380), 60.0, 14.0], [Vector3(90, 0, -420), 90.0, 22.0], [Vector3(260, 0, -330), 50.0, 10.0], [Vector3(-320, 0, -260), 70.0, 12.0]]
	for s in isl:
		var c: Vector3 = table + (s[0] as Vector3).normalized() * 47.0 + Vector3(0, SEA_Y, 0)
		var r: float = float(s[1]) * OUT_K * 1.2
		var h: float = float(s[2]) * OUT_K * 1.2
		var seg := 9
		var top := c + Vector3(_rng.randf_range(-r * 0.2, r * 0.2), h, 0)
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var r0 := r * _rng.randf_range(0.8, 1.1)
			var p0 := c + Vector3(cos(a0) * r0, 0, sin(a0) * r0 * 0.5)
			var p1 := c + Vector3(cos(a1) * r * 0.95, 0, sin(a1) * r * 0.95 * 0.5)
			var mid := c.lerp(top, 0.55) + Vector3(cos((a0 + a1) * 0.5) * r * 0.5, 0, sin((a0 + a1) * 0.5) * r * 0.25)
			var col := Color(0.62, 0.56, 0.42).lerp(Color(0.45, 0.50, 0.36), _rng.randf())
			mb.tri_out(p0, p1, mid, col, mid - c)
			mb.tri_out(mid, p1, top, col.darkened(0.1), mid - c)
			mb.tri_out(mid, top, p0, col.lightened(0.05), mid - c)


## The sky: a low-poly dome, vertex-coloured gradient, unshaded (no sky shader pass).
func _sky_dome() -> Mesh:
	var mb := MeshBuilder.new()
	var c := Vector3(table.x, SEA_Y - 0.5, table.z)
	var R2 := OUT_MAX
	var rows := 6
	var seg := 24
	for j in rows:
		var e0 := PI * 0.5 * float(j) / rows
		var e1 := PI * 0.5 * float(j + 1) / rows
		var c0 := SKY_HORIZON.lerp(SKY_TOP, pow(float(j) / rows, 0.7))
		var c1 := SKY_HORIZON.lerp(SKY_TOP, pow(float(j + 1) / rows, 0.7))
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var p00 := c + Vector3(cos(a0) * cos(e0), sin(e0), sin(a0) * cos(e0)) * R2
			var p01 := c + Vector3(cos(a1) * cos(e0), sin(e0), sin(a1) * cos(e0)) * R2
			var p10 := c + Vector3(cos(a0) * cos(e1), sin(e1), sin(a0) * cos(e1)) * R2
			var p11 := c + Vector3(cos(a1) * cos(e1), sin(e1), sin(a1) * cos(e1)) * R2
			mb.tri_out(p00, p10, p11, c0.lerp(c1, 0.5), c - (p00 + p11) * 0.5)
			mb.tri_out(p00, p11, p01, c0, c - (p00 + p11) * 0.5)
	var m := emissive()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mb.commit(null, m)
