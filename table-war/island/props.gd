class_name IslandProps
extends Node3D
## Everything that sits on the terrain: vegetation (MultiMesh), the town, harbour,
## air base and lighthouse (merged "structures" mesh, rebuilt when something is
## destroyed), draped roads/runway/aprons (rebuilt after craters), boats, radar,
## the interactive launcher.

var terrain: IslandTerrain
var layout: IslandLayout
var rng := RandomNumberGenerator.new()

# --- vegetation ------------------------------------------------------------------------
var species := {}          # name -> {mm: MultiMesh, xf: Array[Transform3D], alive: PackedByteArray}
var veg_mat: StandardMaterial3D

# --- structures -------------------------------------------------------------------------
## each: {kind, pos: Vector3, rot: float, size: Vector3, col: Color, seed: int,
##        alive: bool, fragile: bool, sink: float}
var structures: Array[Dictionary] = []
var struct_mi: MeshInstance3D
var struct_mat: ShaderMaterial
var struct_tris := 0

# --- draped surfaces ---------------------------------------------------------------------
var drape_mi: Array[MeshInstance3D] = []
var drape_defs: Array[Dictionary] = []

# --- dynamic bits -------------------------------------------------------------------------
var boats: Array[Dictionary] = []
var radar_head: Node3D
var launcher: Node3D
var launcher_rack: Node3D
var placed: Array[Dictionary] = []   # for tests: {kind, pos, water_ok}

const C_WHITE := Color(0.93, 0.91, 0.86)
const C_SANDSTONE := Color(0.86, 0.78, 0.63)
const C_OCHRE := Color(0.82, 0.68, 0.50)
const C_MUD := Color(0.76, 0.65, 0.50)
const C_CONCRETE := Color(0.70, 0.69, 0.66)
const C_OLIVE := Color(0.50, 0.53, 0.44)
const C_MIL := Color(0.62, 0.62, 0.55)
const C_GLASS := Color(0.30, 0.42, 0.50)


func build(t: IslandTerrain, lay: IslandLayout) -> void:
	terrain = t
	layout = lay
	rng.seed = 4242
	veg_mat = MeshBuilder.vc_material(0.9)
	struct_mat = ShaderMaterial.new()
	struct_mat.shader = load("res://island/structure.gdshader")
	_place_air_base()
	_place_harbour()
	_place_town()
	_place_lighthouse()
	_rebuild_structures()
	_build_drapes()
	_place_vegetation()
	_place_boats()


# ======================================================================================
# helpers
# ======================================================================================

func _hs(x: float, z: float) -> float:
	return terrain.height_at(x, z) - IslandTerrain.SEA


## min/max ground under an oriented footprint
func _ground(c: Vector2, rot: float, half: Vector2) -> Vector2:
	var b := Basis(Vector3.UP, rot)
	var lo := 1e9
	var hi := -1e9
	for fx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for fz in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var o: Vector3 = b * Vector3(half.x * fx, 0, half.y * fz)
			var h := terrain.height_at(c.x + o.x, c.y + o.z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


func _footprint_clear(c: Vector2, r: float) -> bool:
	for s in structures:
		var p: Vector3 = s.pos
		var sz: Vector3 = s.size
		var sr := Vector2(sz.x, sz.z).length() * 0.5
		if Vector2(p.x, p.z).distance_to(c) < sr + r:
			return false
	return true


func add_structure(kind: String, c: Vector2, rot: float, size: Vector3, col: Color, fragile := true, water_ok := false) -> Dictionary:
	var g := _ground(c, rot, Vector2(size.x, size.z) * 0.5)
	var s := {
		"kind": kind, "pos": Vector3(c.x, g.y, c.y), "rot": rot, "size": size, "col": col,
		"seed": rng.randi(), "alive": true, "fragile": fragile, "sink": g.y - g.x + 0.0015,
		"ruin": false,
	}
	structures.append(s)
	placed.append({"kind": kind, "pos": Vector3(c.x, g.y, c.y), "water_ok": water_ok, "sink": s.sink, "ground_min": g.x})
	terrain.stamp_ao(c, Vector2(size.x, size.z).length() * 0.62, 0.45)
	return s


# ======================================================================================
# air base
# ======================================================================================

func _place_air_base() -> void:
	var L := layout
	var rd := L.runway_dir()
	var rot := L.runway_angle
	var north := Vector2(rd.y, -rd.x)
	var apron := L.apron_center
	# hangars along the north edge of the apron, doors facing the apron
	for k in 4:
		var c := apron + rd * (-0.054 + k * 0.034) + north * (L.apron_size.y * 0.5 + 0.0095)
		add_structure("hangar", c, rot, Vector3(0.026, 0.0085, 0.018), C_OLIVE.lerp(C_MIL, rng.randf() * 0.6))
	# control tower + HQ + barracks east of the apron
	add_structure("ctower", apron + rd * 0.087 + north * 0.006, rot, Vector3(0.0055, 0.016, 0.0055), Color(0.86, 0.84, 0.78))
	add_structure("house", apron + rd * 0.095 + north * 0.03, rot, Vector3(0.016, 0.0065, 0.010), Color(0.80, 0.76, 0.64))
	for k in 3:
		add_structure("barracks", apron + rd * (0.035 + k * 0.022) + north * 0.045, rot, Vector3(0.018, 0.0045, 0.0065), Color(0.78, 0.73, 0.60))
	# fuel tanks
	for k in 3:
		var c2 := L.silo_center + rd * (0.065 + k * 0.009) + north * 0.003
		add_structure("tank", c2, 0.0, Vector3(0.0072, 0.0045, 0.0072), Color(0.88, 0.88, 0.86))
	# silos on the silo pad
	for k in 3:
		var c3 := L.silo_center + rd * (-0.02 + k * 0.016) + north * 0.006
		add_structure("silo_open" if k == 1 else "silo", c3, rot, Vector3(0.008, 0.0012, 0.008), C_CONCRETE)
	# parked jets on the apron
	for k in 4:
		var c4 := apron + rd * (-0.05 + k * 0.022) + north * -0.004
		add_structure("jet", c4, rot + PI * 0.5, Vector3(0.0062, 0.0016, 0.0072), Color(0.60, 0.63, 0.65))
	# radar station on the knoll
	var rp := L.radar_pos
	add_structure("radar_base", rp + Vector2(0.006, 0.004), 0.3, Vector3(0.008, 0.004, 0.006), Color(0.84, 0.82, 0.76))
	var rg := terrain.height_at(rp.x, rp.y)
	add_structure("mast", rp, 0.0, Vector3(0.002, 0.007, 0.002), Color(0.75, 0.74, 0.70))
	radar_head = Node3D.new()
	radar_head.name = "RadarHead"
	radar_head.position = Vector3(rp.x, rg + 0.0075, rp.y)
	add_child(radar_head)
	var dm := MeshBuilder.new()
	_dish(dm, 0.0052, Color(0.92, 0.92, 0.90))
	var dmi := MeshInstance3D.new()
	dmi.mesh = dm.commit(null, MeshBuilder.vc_material(0.5, false))
	radar_head.add_child(dmi)
	# static launcher + the interactive one (on the silo pad)
	var lc := L.silo_center + rd * 0.03 + north * -0.013
	add_structure("launcher_truck", L.silo_center + rd * -0.01 + north * -0.013, rot, Vector3(0.0075, 0.0028, 0.0032), Color(0.48, 0.50, 0.40))
	_build_launcher(lc, rot)


func _dish(mb: MeshBuilder, r: float, col: Color) -> void:
	# shallow paraboloid facing +z, tilted up, on a small yoke
	var rings := 4
	var sides := 14
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-25))
	for ri in rings:
		var r0 := r * float(ri) / rings
		var r1 := r * float(ri + 1) / rings
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var p00 := tilt * Vector3(cos(a0) * r0, sin(a0) * r0, -r0 * r0 / r * 0.45)
			var p01 := tilt * Vector3(cos(a1) * r0, sin(a1) * r0, -r0 * r0 / r * 0.45)
			var p10 := tilt * Vector3(cos(a0) * r1, sin(a0) * r1, -r1 * r1 / r * 0.45)
			var p11 := tilt * Vector3(cos(a1) * r1, sin(a1) * r1, -r1 * r1 / r * 0.45)
			var fwd := tilt * Vector3(0, 0, 1)
			mb.tri_out(p00, p10, p11, col, fwd)
			mb.tri_out(p00, p11, p01, col, fwd)
	mb.box(Vector3(0, -0.001, -0.0012), Vector3(0.0008, 0.002, 0.0008), Color(0.6, 0.6, 0.58))
	mb.box(tilt * Vector3(0, 0, 0.0028), Vector3(0.0004, 0.0004, 0.0004), Color(0.3, 0.3, 0.3))


func _build_launcher(c: Vector2, rot: float) -> void:
	var g := _ground(c, rot, Vector2(0.004, 0.002))
	launcher = Node3D.new()
	launcher.name = "Launcher"
	launcher.position = Vector3(c.x, g.y, c.y)
	launcher.rotation.y = rot
	add_child(launcher)
	var mb := MeshBuilder.new()
	var green := Color(0.47, 0.50, 0.38)
	var dark := Color(0.16, 0.16, 0.15)
	# chassis with wheels
	mb.box(Vector3(0, 0.0012 - (g.y - g.x) * 0.5, 0), Vector3(0.0085, 0.0011 + (g.y - g.x), 0.0032), green)
	mb.box(Vector3(0.0032, 0.0024, 0), Vector3(0.0019, 0.0016, 0.0030), green.lightened(0.08))
	mb.box(Vector3(0.0041, 0.0025, 0), Vector3(0.0002, 0.0009, 0.0026), Color(0.2, 0.25, 0.3))
	for wx in [-0.003, -0.001, 0.001, 0.003]:
		for wz in [-1.0, 1.0]:
			mb.cylinder(Vector3(wx, 0.0006, wz * 0.0016), 0.0006, 0.0006, 0.0004, 8, dark)
	var body := MeshInstance3D.new()
	body.mesh = mb.commit(null, MeshBuilder.vc_material(0.8))
	launcher.add_child(body)
	launcher_rack = Node3D.new()
	launcher_rack.name = "Rack"
	launcher_rack.position = Vector3(-0.0025, 0.0022, 0)
	launcher.add_child(launcher_rack)
	var rb := MeshBuilder.new()
	# 2x3 tubes pointing along the rack's +x
	for ty in 2:
		for tz in 3:
			rb.xform = Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0, ty * 0.001, (tz - 1) * 0.001))
			rb.cylinder(Vector3.ZERO, 0.00045, 0.00045, 0.0058, 6, green.darkened(0.1), true, dark)
	rb.xform = Transform3D.IDENTITY
	rb.box(Vector3(0.0028, -0.0006, 0), Vector3(0.0056, 0.0006, 0.0034), green.darkened(0.2))
	var rmi := MeshInstance3D.new()
	rmi.mesh = rb.commit(null, MeshBuilder.vc_material(0.8))
	launcher_rack.add_child(rmi)
	placed.append({"kind": "launcher", "pos": launcher.position, "water_ok": false, "sink": g.y - g.x + 0.001, "ground_min": g.x})
	terrain.stamp_ao(c, 0.006, 0.4)


## Point the launcher at a launch velocity (world).
func aim_launcher(v: Vector3) -> void:
	if launcher == null:
		return
	var flat := Vector2(v.x, v.z)
	# local +x of the launcher -> horizontal launch direction
	launcher.rotation.y = atan2(-flat.y, flat.x)
	launcher_rack.rotation = Vector3(0, 0, atan2(v.y, flat.length()))


func launcher_muzzle() -> Vector3:
	if launcher == null:
		return Vector3.ZERO
	return launcher_rack.global_transform * Vector3(0.006, 0.0005, 0.0)


# ======================================================================================
# harbour
# ======================================================================================

func _place_harbour() -> void:
	var L := layout
	var x0 := L.harbour_x0
	var x1 := L.harbour_x1
	var sea := IslandTerrain.SEA
	# quay wall: concrete block whose front face drops into the basin
	var qd := L.quay_z - (L.quay_land_z + 0.002)
	var qc := Vector2((x0 + x1) * 0.5, L.quay_z - qd * 0.5)
	var s := {
		"kind": "quay", "pos": Vector3(qc.x, sea + L.quay_height + 0.0003, qc.y), "rot": 0.0,
		"size": Vector3(x1 - x0, 0.016, qd), "col": Color(0.74, 0.72, 0.67), "seed": 1,
		"alive": true, "fragile": false, "sink": 0.016, "ruin": false,
	}
	structures.append(s)
	# pier on posts
	var pz0 := L.quay_z
	var pz1 := L.quay_z + L.pier_len
	structures.append({
		"kind": "pier", "pos": Vector3(L.pier_x, sea + 0.0021, (pz0 + pz1) * 0.5), "rot": 0.0,
		"size": Vector3(0.0048, 0.0006, pz1 - pz0), "col": Color(0.55, 0.42, 0.30), "seed": 2,
		"alive": true, "fragile": false, "sink": 0.0, "ruin": false,
	})
	placed.append({"kind": "pier", "pos": Vector3(L.pier_x, sea, pz1), "water_ok": true, "sink": 0.0, "ground_min": 0.0})
	# warehouses behind the quay
	add_structure("warehouse", Vector2(x0 + 0.022, L.quay_land_z - 0.011), 0.0, Vector3(0.032, 0.0058, 0.012), Color(0.72, 0.74, 0.74))
	add_structure("warehouse", Vector2(x0 + 0.06, L.quay_land_z - 0.012), 0.0, Vector3(0.026, 0.0052, 0.011), Color(0.80, 0.70, 0.56))
	# container stacks + gantry cranes on the apron
	var cc := [Color(0.72, 0.25, 0.20), Color(0.20, 0.38, 0.58), Color(0.85, 0.62, 0.22), Color(0.30, 0.52, 0.40), Color(0.85, 0.85, 0.82)]
	for k in 4:
		var c := Vector2(x0 + 0.012 + k * 0.009, L.quay_land_z + 0.012)
		var st := add_structure("containers", c, 0.0, Vector3(0.0072, 0.0026, 0.0068), cc[k % cc.size()])
		st["seed"] = k * 31 + 7
	for k in 2:
		add_structure("crane", Vector2(x0 + 0.056 + k * 0.022, L.quay_z - 0.006), 0.0, Vector3(0.006, 0.014, 0.0065), Color(0.88, 0.70, 0.18), true, true)
	# breakwater (rock MultiMesh is placed in vegetation pass)


func breakwater_points() -> PackedVector2Array:
	var L := layout
	var pts := PackedVector2Array([Vector2(L.harbour_x1 + 0.004, L.quay_z - 0.004), Vector2(L.harbour_x1 + 0.012, L.quay_z + 0.025), Vector2(L.harbour_x1 + 0.0, L.basin_z + 0.01), Vector2(L.harbour_x1 - 0.022, L.basin_z + 0.016)])
	return IslandLayout.catmull(pts, 0.0035)


# ======================================================================================
# town
# ======================================================================================

func _place_town() -> void:
	var L := layout
	var tc := L.town_center
	# landmarks first
	add_structure("fort", L.fort_pos, deg_to_rad(8.0), Vector3(0.026, 0.0048, 0.026), C_MUD)
	var mosque_c := tc + Vector2(-0.025, -0.022)
	add_structure("mosque", mosque_c, 0.0, Vector3(0.016, 0.0055, 0.016), Color(0.95, 0.94, 0.90))
	var pitch := 0.0128
	var nxz := 9
	for gz in range(-nxz, nxz + 1):
		for gx in range(-nxz, nxz + 1):
			# street every third lot
			var sx: float = gx * pitch + floor(gx / 3.0) * 0.0045
			var sz: float = gz * pitch + floor(gz / 2.0) * 0.0045
			var c := tc + Vector2(sx, sz) + Vector2(rng.randf_range(-0.0012, 0.0012), rng.randf_range(-0.0012, 0.0012))
			var dn := c.distance_to(tc) / L.town_radius
			if dn > 1.0 + rng.randf_range(-0.2, 0.05):
				continue
			if rng.randf() < 0.06:
				continue   # open lots / squares
			var size := Vector3(rng.randf_range(0.0075, 0.0118), 0.0, rng.randf_range(0.0075, 0.0118))
			var half_diag := Vector2(size.x, size.z).length() * 0.5
			if L.road_distance(c) < half_diag * 0.8 + IslandLayout.ROAD_W * 0.5 + 0.0008:
				continue
			if L.infrastructure_distance(c) < half_diag:
				continue
			if not _footprint_clear(c, half_diag * 0.6):
				continue
			var g := _ground(c, 0.0, Vector2(size.x, size.z) * 0.5)
			if g.x - IslandTerrain.SEA < 0.0018 or g.y - g.x > 0.006:
				continue
			# downtown towers near the harbour road
			var downtown := 1.0 - smoothstep(0.0, 0.045, c.distance_to(Vector2(0.116, 0.123)))
			var kind := "house"
			var hgt := 0.0045 if rng.randf() < 0.55 else 0.0073
			if rng.randf() < 0.12:
				hgt = 0.0101
			var col: Color = [C_WHITE, C_SANDSTONE, C_OCHRE, Color(0.90, 0.86, 0.78), Color(0.84, 0.80, 0.74), Color(0.88, 0.80, 0.70)][rng.randi() % 6]
			if rng.randf() < downtown * 0.85:
				kind = "tower"
				hgt = rng.randf_range(0.013, 0.026)
				size.x = minf(size.x, 0.011)
				size.z = minf(size.z, 0.011)
				col = [Color(0.80, 0.84, 0.86), Color(0.92, 0.91, 0.88), Color(0.70, 0.78, 0.82)][rng.randi() % 3]
			size.y = hgt
			add_structure(kind, c, 0.0, size, col)


# ======================================================================================
# lighthouse
# ======================================================================================

func _place_lighthouse() -> void:
	var p := layout.lighthouse_pos
	add_structure("lighthouse", p, 0.0, Vector3(0.0075, 0.026, 0.0075), Color(0.95, 0.94, 0.92))
	add_structure("house", p + Vector2(-0.010, 0.006), 0.2, Vector3(0.008, 0.0042, 0.006), Color(0.93, 0.92, 0.88))


# ======================================================================================
# structure mesh generation
# ======================================================================================

func _rebuild_structures() -> void:
	var mb := MeshBuilder.new()
	for s in structures:
		_gen_structure(mb, s)
	if struct_mi == null:
		struct_mi = MeshInstance3D.new()
		struct_mi.name = "Structures"
		add_child(struct_mi)
	struct_mi.mesh = mb.commit(null, struct_mat)
	struct_tris = mb.tri_count()


func structure_xform(s: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, s.rot), s.pos)


func _gen_structure(mb: MeshBuilder, s: Dictionary) -> void:
	mb.xform = structure_xform(s)
	var r := RandomNumberGenerator.new()
	r.seed = s.seed
	var sz: Vector3 = s.size
	var col: Color = s.col
	var sink: float = s.sink
	var kind: String = s.kind
	if not s.alive:
		_gen_ruin(mb, s, r)
		return
	match kind:
		"house", "barracks":
			_box_walls(mb, Vector3(0, 0, 0), sz, sink, col, true)
			_parapet(mb, sz, col)
			if kind == "house":
				var nd := r.randi_range(0, 2)
				for k in nd:
					var dx := r.randf_range(-sz.x * 0.3, sz.x * 0.3)
					var dz := r.randf_range(-sz.z * 0.3, sz.z * 0.3)
					if r.randf() < 0.5:
						mb.box(Vector3(dx, sz.y + 0.0004, dz), Vector3(0.0014, 0.0008, 0.0011), col.darkened(0.12))
					else:
						mb.cylinder(Vector3(dx, sz.y, dz), 0.0006, 0.0006, 0.0011, 6, Color(0.85, 0.85, 0.85))
				if r.randf() < 0.45:
					mb.box(Vector3(sz.x * 0.25, sz.y + 0.0012, -sz.z * 0.2), Vector3(0.0028, 0.0024, 0.0028), col, true)
		"tower":
			_box_walls(mb, Vector3.ZERO, sz, sink, col, true)
			var crown := Vector3(sz.x * 0.72, 0.0024, sz.z * 0.72)
			mb.box(Vector3(0, sz.y + crown.y * 0.5, 0), crown, col.darkened(0.05), true)
			mb.box(Vector3(0, sz.y + crown.y + 0.0003, 0), Vector3(sz.x * 0.8, 0.0006, sz.z * 0.8), col.lightened(0.1))
			if r.randf() < 0.5:
				mb.cylinder(Vector3(0, sz.y + crown.y + 0.0006, 0), 0.00012, 0.00008, 0.004, 4, Color(0.8, 0.8, 0.8))
		"mosque":
			_box_walls(mb, Vector3.ZERO, sz, sink, col, false)
			_parapet(mb, sz, col)
			mb.cylinder(Vector3(0, sz.y, 0), 0.0045, 0.0045, 0.0012, 12, col)
			mb.sphere(Vector3(0, sz.y + 0.0012, 0), Vector3(0.0048, 0.0055, 0.0048), 8, 12, Color(0.86, 0.80, 0.62), true)
			mb.cylinder(Vector3(0, sz.y + 0.0067, 0), 0.0003, 0.0, 0.0018, 4, Color(0.85, 0.72, 0.35))
			var mp := Vector3(sz.x * 0.5 - 0.0014, 0, sz.z * 0.5 - 0.0014)
			mb.cylinder(mp + Vector3(0, -sink, 0), 0.0013, 0.0011, 0.019 + sink, 8, col)
			mb.cylinder(mp + Vector3(0, 0.0145, 0), 0.0017, 0.0017, 0.0007, 8, col.darkened(0.05))
			mb.cylinder(mp + Vector3(0, 0.0190, 0), 0.0009, 0.0, 0.0032, 8, Color(0.86, 0.80, 0.62))
		"fort":
			var t := 0.0018
			var h := sz.y
			var hx := sz.x * 0.5
			var hz := sz.z * 0.5
			mb.box(Vector3(0, (h - sink) * 0.5, -hz + t * 0.5), Vector3(sz.x, h + sink, t), col)
			mb.box(Vector3(0, (h - sink) * 0.5, hz - t * 0.5), Vector3(sz.x, h + sink, t), col)
			mb.box(Vector3(-hx + t * 0.5, (h - sink) * 0.5, 0), Vector3(t, h + sink, sz.z), col)
			mb.box(Vector3(hx - t * 0.5, (h - sink) * 0.5, 0), Vector3(t, h + sink, sz.z), col)
			# crenellations
			var n := 9
			for k in n:
				var f := (k + 0.5) / n * 2.0 - 1.0
				for side in [Vector3(f * hx, 0, -hz + t * 0.5), Vector3(f * hx, 0, hz - t * 0.5), Vector3(-hx + t * 0.5, 0, f * hz), Vector3(hx - t * 0.5, 0, f * hz)]:
					mb.box(side + Vector3(0, h + 0.0004, 0), Vector3(0.0011, 0.0008, 0.0011), col)
			for cx in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					var tp := Vector3(cx * hx, -sink, cz * hz)
					mb.cylinder(tp, 0.0036, 0.0032, h + sink + 0.002, 10, col.darkened(0.04), true, col.darkened(0.12))
					mb.cylinder(tp + Vector3(0, h + sink + 0.002, 0), 0.0037, 0.0037, 0.0008, 10, col)
			# inner keep + courtyard floor
			mb.box(Vector3(-hx * 0.35, (h * 1.25 - sink) * 0.5, -hz * 0.35), Vector3(0.008, h * 1.25 + sink, 0.008), col.lightened(0.05))
			mb.box(Vector3(0, 0.0003 - sink * 0.5, 0), Vector3(sz.x - t, sink + 0.0006, sz.z - t), Color(0.80, 0.70, 0.52))
			mb.box(Vector3(0, h * 0.25, hz), Vector3(0.0036, h * 0.55, 0.0008), Color(0.30, 0.22, 0.16))
		"warehouse":
			_box_walls(mb, Vector3.ZERO, sz, sink, col, false)
			# low gable roof
			var ry := 0.0014
			var hx2 := sz.x * 0.5 + 0.0003
			var hz2 := sz.z * 0.5 + 0.0003
			var rc := col.darkened(0.1)
			mb.quad(Vector3(-hx2, sz.y, -hz2), Vector3(-hx2, sz.y + ry, 0), Vector3(hx2, sz.y + ry, 0), Vector3(hx2, sz.y, -hz2), rc)
			mb.quad(Vector3(-hx2, sz.y + ry, 0), Vector3(-hx2, sz.y, hz2), Vector3(hx2, sz.y, hz2), Vector3(hx2, sz.y + ry, 0), rc.lightened(0.05))
			mb.tri_out(Vector3(-hx2, sz.y, -hz2), Vector3(-hx2, sz.y, hz2), Vector3(-hx2, sz.y + ry, 0), col, Vector3.LEFT)
			mb.tri_out(Vector3(hx2, sz.y, -hz2), Vector3(hx2, sz.y, hz2), Vector3(hx2, sz.y + ry, 0), col, Vector3.RIGHT)
			for k in 3:
				mb.box(Vector3(-sz.x * 0.3 + k * sz.x * 0.3, 0.0016, sz.z * 0.5 + 0.0001), Vector3(sz.x * 0.18, 0.0032, 0.0002), Color(0.35, 0.37, 0.38))
		"containers":
			var palette := [Color(0.72, 0.25, 0.20), Color(0.20, 0.38, 0.58), Color(0.85, 0.62, 0.22), Color(0.30, 0.52, 0.40), Color(0.85, 0.85, 0.82), Color(0.55, 0.30, 0.45)]
			var cl := 0.0034
			var cw := 0.0012
			var ch := 0.0012
			for rx in 2:
				for rz in 5:
					var stack := r.randi_range(1, 3)
					for ry2 in stack:
						var cpos := Vector3(-sz.x * 0.5 + cl * 0.5 + rx * (cl + 0.0003), ch * 0.5 + ry2 * ch, -sz.z * 0.5 + cw * 0.5 + rz * (cw + 0.0002))
						mb.box(cpos, Vector3(cl, ch * 0.96, cw * 0.96), palette[r.randi() % palette.size()])
		"crane":
			var leg := 0.0005
			var hy := sz.y
			for lx in [-1.0, 1.0]:
				for lz in [-1.0, 1.0]:
					mb.box(Vector3(lx * sz.x * 0.4, hy * 0.35, lz * sz.z * 0.4), Vector3(leg, hy * 0.7, leg), col)
			mb.box(Vector3(0, hy * 0.7, 0), Vector3(sz.x * 0.9, 0.0012, sz.z), col)
			mb.box(Vector3(0, hy * 0.7 + 0.0006, 0.006), Vector3(0.0012, 0.0008, 0.022), col.darkened(0.05))
			mb.box(Vector3(0, hy * 0.7 + 0.0016, -0.002), Vector3(0.002, 0.0016, 0.0024), Color(0.85, 0.85, 0.82))
		"hangar":
			_hangar(mb, sz, sink, col)
		"ctower":
			_box_walls(mb, Vector3.ZERO, Vector3(sz.x * 0.65, sz.y - 0.003, sz.z * 0.65), sink, col, false)
			mb.cylinder(Vector3(0, sz.y - 0.003, 0), sz.x * 0.62, sz.x * 0.75, 0.0024, 8, Color(0.22, 0.32, 0.38), false)
			mb.cylinder(Vector3(0, sz.y - 0.0006, 0), sz.x * 0.8, sz.x * 0.7, 0.0006, 8, col)
			mb.cylinder(Vector3(0, sz.y, 0), 0.0001, 0.0001, 0.003, 4, Color(0.8, 0.2, 0.2))
			mb.box(Vector3(0.006, (0.0045 - sink) * 0.5, 0), Vector3(0.008, 0.0045 + sink, 0.0065), col, true)
		"tank":
			mb.cylinder(Vector3(0, -sink, 0), sz.x * 0.5, sz.x * 0.5, sz.y + sink, 14, col, true, col.darkened(0.06))
			mb.cylinder(Vector3(0, sz.y, 0), sz.x * 0.5, sz.x * 0.2, 0.0007, 14, col.darkened(0.03))
		"silo", "silo_open":
			mb.cylinder(Vector3(0, -sink, 0), sz.x * 0.5, sz.x * 0.47, sz.y + sink, 14, C_CONCRETE, true, Color(0.62, 0.61, 0.58))
			if kind == "silo":
				mb.cylinder(Vector3(0, sz.y, 0), sz.x * 0.33, sz.x * 0.31, 0.0003, 12, Color(0.36, 0.38, 0.34))
			else:
				mb.cylinder(Vector3(0, sz.y, 0), sz.x * 0.33, sz.x * 0.33, 0.00005, 12, Color(0.05, 0.05, 0.05))
				mb.box(Vector3(sz.x * 0.62, sz.y + 0.00025, 0), Vector3(sz.x * 0.62, 0.0003, sz.x * 0.62), Color(0.36, 0.38, 0.34))
				mb.cylinder(Vector3(0, sz.y - 0.0005, 0), 0.0011, 0.0011, 0.0012, 10, Color(0.92, 0.92, 0.9))
				mb.cylinder(Vector3(0, sz.y + 0.0007, 0), 0.0011, 0.0, 0.0022, 10, Color(0.80, 0.22, 0.18))
		"jet":
			_jet(mb, col)
		"radar_base":
			_box_walls(mb, Vector3.ZERO, sz, sink, col, true)
			_parapet(mb, sz, col)
		"mast":
			mb.cylinder(Vector3(0, -sink, 0), 0.0011, 0.0006, sz.y + sink, 6, col)
		"launcher_truck":
			mb.box(Vector3(0, (0.0016 - sink) * 0.5, 0), Vector3(sz.x, 0.0016 + sink, sz.z), col)
			mb.box(Vector3(sz.x * 0.38, 0.0021, 0), Vector3(0.0018, 0.0012, sz.z * 0.92), col.lightened(0.06))
			for k in 2:
				mb.box(Vector3(-0.0008, 0.0022 + k * 0.0009, 0), Vector3(0.0056, 0.0008, sz.z * 0.85), col.darkened(0.12))
		"lighthouse":
			_lighthouse(mb, sz, sink)
		"quay":
			mb.box(Vector3(0, -sz.y * 0.5, 0), sz, col, false)
		"pier":
			mb.box(Vector3.ZERO, sz, col, false)
			var n2 := int(sz.z / 0.006) + 1
			for k in n2:
				var pz := -sz.z * 0.5 + k * sz.z / maxf(n2 - 1, 1)
				for px in [-1.0, 1.0]:
					var wp: Vector3 = mb.xform * Vector3(px * sz.x * 0.42, 0, pz)
					var gy := terrain.height_at(wp.x, wp.z)
					var py: float = s.pos.y
					mb.cylinder(Vector3(px * sz.x * 0.42, gy - py - 0.001, pz), 0.00028, 0.00028, py - gy + 0.0012, 5, col.darkened(0.3))
			# plank lines
			for k in int(sz.z / 0.0012):
				var pz2 := -sz.z * 0.5 + (k + 0.5) * 0.0012
				mb.box(Vector3(0, sz.y * 0.5 + 0.00003, pz2), Vector3(sz.x * 0.98, 0.00004, 0.00022), col.darkened(0.18))
		_:
			_box_walls(mb, Vector3.ZERO, sz, sink, col, false)
	mb.xform = Transform3D.IDENTITY


func _box_walls(mb: MeshBuilder, off: Vector3, sz: Vector3, sink: float, col: Color, windows: bool) -> void:
	# windows: UV measured from ground level (y=0) so ground floors line up
	var x0 := off.x - sz.x * 0.5
	var x1 := off.x + sz.x * 0.5
	var z0 := off.z - sz.z * 0.5
	var z1 := off.z + sz.z * 0.5
	var y0 := off.y - sink
	var y1 := off.y + sz.y
	var tc := col.darkened(0.06)
	mb.quad(Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), tc)
	var hy := sz.y
	var ua := Vector2(0, -sink) if windows else MeshBuilder.NO_UV
	var faces := [
		[Vector3(x0, 0, z1), Vector3(x1, 0, z1), sz.x],
		[Vector3(x1, 0, z0), Vector3(x0, 0, z0), sz.x],
		[Vector3(x1, 0, z1), Vector3(x1, 0, z0), sz.z],
		[Vector3(x0, 0, z0), Vector3(x0, 0, z1), sz.z],
	]
	for f in faces:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var l: float = f[2]
		var u2 := Vector2(l, hy) if windows else Vector2.ZERO
		var A := Vector3(a.x, y0, a.z)
		var B := Vector3(b.x, y0, b.z)
		var C := Vector3(b.x, y1, b.z)
		var D := Vector3(a.x, y1, a.z)
		if windows:
			mb.quad(A, B, C, D, col, Vector2(0, -sink), Vector2(l, -sink), Vector2(l, hy), Vector2(0, hy), u2)
		else:
			mb.quad(A, B, C, D, col)


func _parapet(mb: MeshBuilder, sz: Vector3, col: Color) -> void:
	var t := 0.00045
	var h := 0.0006
	var y := sz.y + h * 0.5
	var c := col.lightened(0.03)
	mb.box(Vector3(0, y, -sz.z * 0.5 + t * 0.5), Vector3(sz.x, h, t), c)
	mb.box(Vector3(0, y, sz.z * 0.5 - t * 0.5), Vector3(sz.x, h, t), c)
	mb.box(Vector3(-sz.x * 0.5 + t * 0.5, y, 0), Vector3(t, h, sz.z - 2 * t), c)
	mb.box(Vector3(sz.x * 0.5 - t * 0.5, y, 0), Vector3(t, h, sz.z - 2 * t), c)


func _hangar(mb: MeshBuilder, sz: Vector3, sink: float, col: Color) -> void:
	# barrel vault along local x? no: along local z (depth), door faces -z... we
	# want the door facing the apron (+z of the hangar's frame after rotation).
	var L := sz.z
	var R := sz.x * 0.5
	var H := sz.y
	var seg := 10
	for k in seg:
		var a0 := PI * k / seg
		var a1 := PI * (k + 1) / seg
		var p0 := Vector3(cos(a0) * R, sin(a0) * H, 0)
		var p1 := Vector3(cos(a1) * R, sin(a1) * H, 0)
		var shade := col * (0.92 + 0.08 * sin(a0))
		shade.a = 1.0
		mb.tri_out(p0 + Vector3(0, 0, -L * 0.5), p1 + Vector3(0, 0, -L * 0.5), p1 + Vector3(0, 0, L * 0.5), shade, (p0 + p1) * 0.5)
		mb.tri_out(p0 + Vector3(0, 0, -L * 0.5), p1 + Vector3(0, 0, L * 0.5), p0 + Vector3(0, 0, L * 0.5), shade, (p0 + p1) * 0.5)
		# end walls
		for e in [-1.0, 1.0]:
			var zc: float = e * L * 0.5
			mb.tri_out(Vector3(0, 0, zc), p0 + Vector3(0, 0, zc), p1 + Vector3(0, 0, zc), col.darkened(0.08), Vector3(0, 0, e))
	# skirt down to the ground on slopes
	mb.box(Vector3(0, -sink * 0.5, 0), Vector3(sz.x, sink, L), col.darkened(0.1))
	# dark door on +z end
	mb.quad(Vector3(-R * 0.7, 0, L * 0.5 + 0.0001), Vector3(R * 0.7, 0, L * 0.5 + 0.0001), Vector3(R * 0.7, H * 0.72, L * 0.5 + 0.0001), Vector3(-R * 0.7, H * 0.72, L * 0.5 + 0.0001), Color(0.16, 0.17, 0.16))
	# rib lines
	for k in 4:
		var zr := -L * 0.5 + L * (k + 1) / 5.0
		for j in seg:
			var a0 := PI * j / seg
			var a1 := PI * (j + 1) / seg
			var p0 := Vector3(cos(a0) * (R + 0.00008), sin(a0) * (H + 0.00008), zr)
			var p1 := Vector3(cos(a1) * (R + 0.00008), sin(a1) * (H + 0.00008), zr)
			mb.tri_out(p0 + Vector3(0, 0, -0.00015), p1 + Vector3(0, 0, -0.00015), p1 + Vector3(0, 0, 0.00015), col.darkened(0.15), (p0 + p1) * 0.5)
			mb.tri_out(p0 + Vector3(0, 0, -0.00015), p1 + Vector3(0, 0, 0.00015), p0 + Vector3(0, 0, 0.00015), col.darkened(0.15), (p0 + p1) * 0.5)


func _jet(mb: MeshBuilder, col: Color) -> void:
	# nose along +x (structure rot adds the heading); size ~7 mm
	var y := 0.0007
	var dark := col.darkened(0.25)
	mb.box(Vector3(0, y, 0), Vector3(0.0062, 0.0006, 0.0007), col)
	mb.tri_out(Vector3(0.0031, y + 0.0003, 0), Vector3(0.0045, y, 0), Vector3(0.0031, y - 0.0003, 0.0003), col, Vector3(1, 0, 1))
	mb.tri_out(Vector3(0.0031, y + 0.0003, 0), Vector3(0.0045, y, 0), Vector3(0.0031, y - 0.0003, -0.0003), col, Vector3(1, 0, -1))
	mb.tri_out(Vector3(0.0031, y + 0.0003, 0.0003), Vector3(0.0031, y + 0.0003, -0.0003), Vector3(0.0045, y, 0), col, Vector3.UP)
	for sd in [-1.0, 1.0]:
		mb.tri_out(Vector3(0.0012, y + 0.0001, 0), Vector3(-0.0018, y + 0.0001, 0), Vector3(-0.0016, y + 0.0001, sd * 0.0036), col, Vector3.UP)
		mb.tri_out(Vector3(0.0012, y + 0.00005, 0), Vector3(-0.0018, y + 0.00005, 0), Vector3(-0.0016, y + 0.00005, sd * 0.0036), dark, Vector3.DOWN)
		mb.tri_out(Vector3(-0.0022, y + 0.0001, 0), Vector3(-0.0031, y + 0.0001, 0), Vector3(-0.0030, y + 0.0001, sd * 0.0014), col, Vector3.UP)
	mb.tri_out(Vector3(-0.0016, y + 0.0003, 0), Vector3(-0.0031, y + 0.0003, 0), Vector3(-0.0030, y + 0.0019, 0), col, Vector3.FORWARD)
	mb.tri_out(Vector3(-0.0016, y + 0.0003, 0), Vector3(-0.0031, y + 0.0003, 0), Vector3(-0.0030, y + 0.0019, 0), col, Vector3.BACK)
	mb.box(Vector3(0.0018, y + 0.0004, 0), Vector3(0.0012, 0.0003, 0.0004), Color(0.2, 0.3, 0.38))
	# wheel stubs
	mb.box(Vector3(0, y * 0.5, 0), Vector3(0.002, y, 0.0004), dark)


func _lighthouse(mb: MeshBuilder, sz: Vector3, sink: float) -> void:
	var h := sz.y
	var r0 := sz.x * 0.5
	var r1 := r0 * 0.62
	var bands := 6
	mb.cylinder(Vector3(0, -sink, 0), r0 * 1.25, r0 * 1.2, sink + 0.0018, 12, Color(0.75, 0.72, 0.68))
	for k in bands:
		var t0 := float(k) / bands
		var t1 := float(k + 1) / bands
		var c := Color(0.95, 0.94, 0.92) if k % 2 == 0 else Color(0.80, 0.18, 0.15)
		mb.cylinder(Vector3(0, 0.0018 + t0 * (h - 0.0018), 0), lerpf(r0, r1, t0), lerpf(r0, r1, t1), (t1 - t0) * (h - 0.0018), 12, c, false)
	mb.cylinder(Vector3(0, h, 0), r1 * 1.55, r1 * 1.55, 0.0006, 12, Color(0.2, 0.2, 0.2))
	var glow := Color(1.0, 0.92, 0.6, 0.45)   # alpha < 1 => emissive in structure shader
	mb.cylinder(Vector3(0, h + 0.0006, 0), r1 * 0.85, r1 * 0.85, 0.0024, 10, glow, false)
	mb.cylinder(Vector3(0, h + 0.003, 0), r1 * 1.05, 0.0, 0.0022, 10, Color(0.75, 0.16, 0.14))
	mb.cylinder(Vector3(0, h + 0.0052, 0), 0.0001, 0.0001, 0.0012, 4, Color(0.2, 0.2, 0.2))


func _gen_ruin(mb: MeshBuilder, s: Dictionary, r: RandomNumberGenerator) -> void:
	var sz: Vector3 = s.size
	var col: Color = (s.col as Color).darkened(0.45)
	var stub := minf(sz.y * 0.28, 0.0028)
	if s.kind in ["tank", "silo", "silo_open", "mast", "lighthouse"]:
		mb.cylinder(Vector3(0, -s.sink, 0), sz.x * 0.5, sz.x * 0.45, s.sink + stub, 10, col)
	elif s.kind in ["jet", "containers", "launcher_truck", "crane"]:
		mb.box(Vector3(0, 0.0003, 0), Vector3(sz.x * 0.7, 0.0006, sz.z * 0.7), Color(0.12, 0.11, 0.10))
	else:
		# jagged broken walls
		var hx := sz.x * 0.5
		var hz := sz.z * 0.5
		var t := 0.0006
		for k in 6:
			var f0 := k / 6.0
			var hh := stub * r.randf_range(0.3, 1.0)
			mb.box(Vector3(-hx + sz.x * (f0 + 1.0 / 12.0), (hh - s.sink) * 0.5, -hz + t * 0.5), Vector3(sz.x / 6.0, hh + s.sink, t), col)
			hh = stub * r.randf_range(0.3, 1.0)
			mb.box(Vector3(-hx + sz.x * (f0 + 1.0 / 12.0), (hh - s.sink) * 0.5, hz - t * 0.5), Vector3(sz.x / 6.0, hh + s.sink, t), col)
			hh = stub * r.randf_range(0.3, 1.0)
			mb.box(Vector3(-hx + t * 0.5, (hh - s.sink) * 0.5, -hz + sz.z * (f0 + 1.0 / 12.0)), Vector3(t, hh + s.sink, sz.z / 6.0), col)
			hh = stub * r.randf_range(0.3, 1.0)
			mb.box(Vector3(hx - t * 0.5, (hh - s.sink) * 0.5, -hz + sz.z * (f0 + 1.0 / 12.0)), Vector3(t, hh + s.sink, sz.z / 6.0), col)
		mb.box(Vector3(0, 0.0002 - s.sink * 0.5, 0), Vector3(sz.x * 0.95, 0.0004 + s.sink, sz.z * 0.95), Color(0.16, 0.14, 0.12))


# ======================================================================================
# destruction
# ======================================================================================

func _footprint_dist(s: Dictionary, p: Vector3) -> float:
	var inv := structure_xform(s).affine_inverse()
	var lp: Vector3 = inv * p
	var sz: Vector3 = s.size
	var dx := maxf(absf(lp.x) - sz.x * 0.5, 0.0)
	var dz := maxf(absf(lp.z) - sz.z * 0.5, 0.0)
	var dy := maxf(lp.y - sz.y, 0.0)
	return Vector3(dx, dy, dz).length()


## Destroy fragile structures within `radius` of `center`; returns pre-fractured
## chunks: [{pos, basis, half, col, vel, ang}] ready for the debris system.
func blast(center: Vector3, radius: float) -> Array[Dictionary]:
	var frags: Array[Dictionary] = []
	var changed := false
	for s in structures:
		if not s.alive or not s.fragile:
			continue
		var d := _footprint_dist(s, center)
		if d > radius:
			continue
		s.alive = false
		changed = true
		frags.append_array(_fracture(s, center))
	if changed:
		_rebuild_structures()
	return frags


func _fracture(s: Dictionary, center: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sz: Vector3 = s.size
	var r := RandomNumberGenerator.new()
	r.seed = s.seed + 99
	var full_h: float = sz.y
	if s.kind == "lighthouse":
		full_h = sz.y + 0.005
	var nx := clampi(int(round(sz.x / 0.0028)), 1, 5)
	var nz := clampi(int(round(sz.z / 0.0028)), 1, 5)
	var ny := clampi(int(round(full_h / 0.0028)), 1, 8)
	while nx * ny * nz > 64:
		ny = maxi(1, ny - 1)
		if nx * ny * nz > 40:
			nx = maxi(1, nx - 1)
			nz = maxi(1, nz - 1)
	var xs := _splits(nx, sz.x, r)
	var zs := _splits(nz, sz.z, r)
	var ys := _splits(ny, full_h, r)
	var xf := structure_xform(s)
	var col: Color = s.col
	for iy in ny:
		for ix in nx:
			for iz in nz:
				var lo := Vector3(xs[ix], ys[iy], zs[iz]) - Vector3(sz.x * 0.5, 0, sz.z * 0.5)
				var hi := Vector3(xs[ix + 1], ys[iy + 1], zs[iz + 1]) - Vector3(sz.x * 0.5, 0, sz.z * 0.5)
				var half := (hi - lo) * 0.5 * Vector3(r.randf_range(0.6, 0.95), r.randf_range(0.5, 0.95), r.randf_range(0.6, 0.95))
				var lc := (lo + hi) * 0.5
				var wp := xf * lc
				var away := wp - center
				var dist := maxf(away.length(), 0.004)
				var dirv := away / dist
				var power := clampf(0.010 / dist, 0.25, 1.3)
				var vel := (dirv * Vector3(1, 0, 1)).normalized() * r.randf_range(0.03, 0.09) * power
				vel.y = r.randf_range(0.04, 0.16) * power * (0.5 + float(iy + 1) / ny)
				var c := col.darkened(r.randf_range(0.15, 0.45)) if r.randf() < 0.65 else Color(0.22, 0.20, 0.18).lerp(col, r.randf_range(0.0, 0.3))
				out.append({
					"pos": wp, "basis": xf.basis, "half": half, "col": c, "vel": vel,
					"ang": Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)) * r.randf_range(4.0, 14.0),
				})
	return out


func _splits(n: int, total: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var a := PackedFloat32Array([0.0])
	for k in range(1, n):
		a.append(total * (float(k) + r.randf_range(-0.25, 0.25)) / n)
	a.append(total)
	return a


## Called after a crater: remove vegetation inside, re-snap the rest, re-drape roads.
func on_crater(center: Vector3, radius: float) -> Array[Dictionary]:
	var burnt: Array[Dictionary] = []
	for name in species:
		var sp: Dictionary = species[name]
		var mm: MultiMesh = sp.mm
		var xfs: Array = sp.xf
		for k in xfs.size():
			if sp.alive[k] == 0:
				continue
			var xf: Transform3D = xfs[k]
			var d := Vector2(xf.origin.x - center.x, xf.origin.z - center.z).length()
			if d < radius * 1.15:
				sp.alive[k] = 0
				mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * 1e-5), xf.origin))
				if name == "palm" or name == "acacia":
					burnt.append({"pos": xf.origin + Vector3(0, 0.002, 0), "half": Vector3(0.0003, 0.0022, 0.0003), "col": Color(0.18, 0.14, 0.11)})
			elif d < radius * 2.0:
				var ny := terrain.height_at(xf.origin.x, xf.origin.z) - 0.0004
				xf.origin.y = ny
				xfs[k] = xf
				mm.set_instance_transform(k, xf)
	_build_drapes()
	return burnt


# ======================================================================================
# draped surfaces (roads, runway, aprons) — follow the faceted terrain exactly
# ======================================================================================

func _build_drapes() -> void:
	for m in drape_mi:
		m.queue_free()
	drape_mi.clear()
	var L := layout
	var rd := L.runway_dir()
	var shader := load("res://island/marking.gdshader")
	# roads
	var rb := MeshBuilder.new()
	for r in L.road_samples():
		_ribbon(rb, r, IslandLayout.ROAD_W, 0.00032)
	_add_drape(rb, shader, 0, 0.0)
	# runway
	var rwb := MeshBuilder.new()
	_rect_grid(rwb, L.runway_center, rd, Vector2(L.runway_len, L.runway_w), 0.0005)
	_add_drape(rwb, shader, 1, L.runway_len)
	# apron, silo pad, quay apron (concrete)
	var cb := MeshBuilder.new()
	_rect_grid(cb, L.apron_center, rd, L.apron_size, 0.0004)
	_rect_grid(cb, L.silo_center, rd, Vector2(0.07, 0.044), 0.0004)
	# taxiways from the apron's south edge to the runway's north edge
	var south := Vector2(-rd.y, rd.x)
	var d := L.apron_center - L.runway_center
	var along := d.dot(rd)
	var lat_apron := d.dot(south) + L.apron_size.y * 0.5
	var lat_rw := -L.runway_w * 0.5
	for off in [-0.05, 0.05]:
		var mid_lat := (lat_apron + lat_rw) * 0.5
		var c: Vector2 = L.runway_center + rd * (along + off) + south * mid_lat
		_rect_grid(cb, c, south, Vector2(absf(lat_rw - lat_apron) + 0.002, 0.007), 0.00035)
	# harbour apron: flat, on top of the quay slab
	_rect_grid(cb, Vector2((L.harbour_x0 + L.harbour_x1) * 0.5, (L.quay_land_z + 0.002 + L.quay_z) * 0.5), Vector2.RIGHT, Vector2(L.harbour_x1 - L.harbour_x0, L.quay_z - L.quay_land_z - 0.002), 0.0, IslandTerrain.SEA + L.quay_height + 0.00035)
	_add_drape(cb, shader, 2, 0.0)


func _add_drape(mb: MeshBuilder, shader: Shader, kind: int, length: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("kind", kind)
	mat.set_shader_parameter("run_len", length)
	var mi := MeshInstance3D.new()
	mi.name = "Drape%d" % kind
	mi.mesh = mb.commit(null, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	drape_mi.append(mi)


func _ribbon(mb: MeshBuilder, pts: PackedVector2Array, width: float, lift: float) -> void:
	var dist := 0.0
	var prev_l := Vector3.ZERO
	var prev_c := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_u := 0.0
	for s in pts.size():
		var tng: Vector2
		if s == 0:
			tng = pts[1] - pts[0]
		elif s == pts.size() - 1:
			tng = pts[s] - pts[s - 1]
		else:
			tng = pts[s + 1] - pts[s - 1]
		tng = tng.normalized()
		var nrm := Vector2(-tng.y, tng.x) * width * 0.5
		var c := pts[s]
		if s > 0:
			dist += c.distance_to(pts[s - 1])
		var pl := c + nrm
		var pr := c - nrm
		var L := Vector3(pl.x, terrain.height_at(pl.x, pl.y) + lift, pl.y)
		var C := Vector3(c.x, terrain.height_at(c.x, c.y) + lift, c.y)
		var R := Vector3(pr.x, terrain.height_at(pr.x, pr.y) + lift, pr.y)
		var tint := _scorch_tint(c)
		if s > 0:
			mb.tri_out(prev_l, L, C, tint, Vector3.UP, Vector2(prev_u, 1), Vector2(dist, 1), Vector2(dist, 0))
			mb.tri_out(prev_l, C, prev_c, tint, Vector3.UP, Vector2(prev_u, 1), Vector2(dist, 0), Vector2(prev_u, 0))
			mb.tri_out(prev_c, C, R, tint, Vector3.UP, Vector2(prev_u, 0), Vector2(dist, 0), Vector2(dist, -1))
			mb.tri_out(prev_c, R, prev_r, tint, Vector3.UP, Vector2(prev_u, 0), Vector2(dist, -1), Vector2(prev_u, -1))
		prev_l = L; prev_c = C; prev_r = R; prev_u = dist


func _scorch_tint(p: Vector2) -> Color:
	var sc := terrain.scorch_at(p.x, p.y)
	if sc <= 0.0:
		return Color.WHITE
	return Color.WHITE.lerp(Color(0.28, 0.24, 0.21), clampf(sc * 1.2, 0.0, 0.92))


func _rect_grid(mb: MeshBuilder, c: Vector2, dir: Vector2, size: Vector2, lift: float, fixed_y := -1.0) -> void:
	var nu := maxi(2, int(ceil(size.x / 0.003)))
	var nv := maxi(2, int(ceil(size.y / 0.003)))
	var perp := Vector2(-dir.y, dir.x)
	var grid: Array[Vector3] = []
	var uvg: Array[Vector2] = []
	for j in nv + 1:
		for i in nu + 1:
			var u := float(i) / nu
			var v := float(j) / nv
			var p := c + dir * (u - 0.5) * size.x + perp * (v - 0.5) * size.y
			var gy := fixed_y if fixed_y > 0.0 else terrain.height_at(p.x, p.y) + lift
			grid.append(Vector3(p.x, gy, p.y))
			uvg.append(Vector2(u * size.x, v * 2.0 - 1.0))
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			var b := a + 1
			var cc := a + nu + 1
			var d := cc + 1
			var tint := _scorch_tint(Vector2(grid[a].x, grid[a].z))
			mb.tri_out(grid[a], grid[b], grid[d], tint, Vector3.UP, uvg[a], uvg[b], uvg[d])
			mb.tri_out(grid[a], grid[d], grid[cc], tint, Vector3.UP, uvg[a], uvg[d], uvg[cc])


# ======================================================================================
# vegetation & rocks (MultiMesh)
# ======================================================================================

func _palm_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var trunk := Color(0.55, 0.45, 0.34)
	var segs := 5
	var H := 1.0
	var bend := 0.10
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var b0 := Vector3(bend * t0 * t0, H * 0.8 * t0, 0)
		var b1 := Vector3(bend * t1 * t1, H * 0.8 * t1, 0)
		var r0 := lerpf(0.042, 0.026, t0)
		var r1 := lerpf(0.042, 0.026, t1)
		for s in 5:
			var a0 := TAU * s / 5.0
			var a1 := TAU * (s + 1) / 5.0
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var c := trunk * (0.9 + 0.1 * (k % 2))
			c.a = 1.0
			mb.tri_out(b0 + d0 * r0, b0 + d1 * r0, b1 + d1 * r1, c, d0 + d1)
			mb.tri_out(b0 + d0 * r0, b1 + d1 * r1, b1 + d0 * r1, c, d0 + d1)
	var crown := Vector3(bend, H * 0.8, 0)
	var leaves := 8
	for l in leaves:
		var ang := TAU * l / leaves + 0.3 * (l % 2)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := 0.42 if l % 2 == 0 else 0.36
		var lift := 0.10 if l % 2 == 0 else 0.16
		var green := Color(0.33, 0.48, 0.22) if l % 3 != 0 else Color(0.40, 0.52, 0.25)
		var pts: Array[Vector3] = []
		var n := 4
		for k in n + 1:
			var t := float(k) / n
			var r := length * t
			var y := lift * t - 0.55 * pow(t, 2.2) * length
			pts.append(crown + dir * r + Vector3(0, y, 0))
		for k in n:
			var t := (k + 0.5) / n
			var w := 0.085 * sin(PI * minf(t * 1.15, 1.0)) + 0.01
			var p0 := pts[k]
			var p1 := pts[k + 1]
			var m := (p0 + p1) * 0.5
			var droop := Vector3(0, -w * 0.45, 0)
			var lft := m + side * w + droop
			var rgt := m - side * w + droop
			# both sides visible (double-sided by duplicating with flipped winding)
			for tri in [[p0, lft, p1], [p0, p1, rgt]]:
				var a: Vector3 = tri[0]
				var b: Vector3 = tri[1]
				var c2: Vector3 = tri[2]
				var shade := green * (0.92 + 0.08 * k / n)
				shade.a = 1.0
				mb.tri_out(a, b, c2, shade, Vector3.UP)
				mb.tri_out(a, b, c2, shade.darkened(0.25), Vector3.DOWN)
	# a few dates
	mb.sphere(crown + Vector3(0, -0.03, 0), Vector3(0.045, 0.035, 0.045), 3, 5, Color(0.55, 0.38, 0.18))
	return mb.commit()


func _acacia_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var bark := Color(0.40, 0.33, 0.26)
	mb.cylinder(Vector3.ZERO, 0.05, 0.035, 0.45, 5, bark)
	# two forks
	for f in [Vector3(0.18, 0.62, 0.05), Vector3(-0.15, 0.6, -0.08), Vector3(0.02, 0.64, 0.17)]:
		var a := Vector3(0, 0.42, 0)
		var b: Vector3 = f
		var dirv := (b - a).normalized()
		var side := dirv.cross(Vector3.FORWARD).normalized() * 0.022
		var side2 := dirv.cross(side).normalized() * 0.022
		mb.tri_out(a + side, b + side * 0.5, b - side * 0.5, bark, side2)
		mb.tri_out(a + side, b - side * 0.5, a - side, bark, side2)
		mb.tri_out(a + side, b + side * 0.5, b - side * 0.5, bark, -side2)
		mb.tri_out(a + side, b - side * 0.5, a - side, bark, -side2)
	# flat umbrella canopy: two irregular layers
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for layer in 2:
		var cy := 0.66 + layer * 0.08
		var rad := 0.52 - layer * 0.16
		var sides := 9
		var top := Vector3(0.02 * layer, cy + 0.08, 0)
		var ring_t: Array[Vector3] = []
		var ring_b: Array[Vector3] = []
		for s in sides:
			var a := TAU * s / sides
			var rr := rad * r.randf_range(0.8, 1.1)
			ring_t.append(Vector3(cos(a) * rr, cy + 0.03 + r.randf_range(-0.02, 0.03), sin(a) * rr))
			ring_b.append(Vector3(cos(a) * rr * 0.75, cy - 0.06, sin(a) * rr * 0.75))
		var g := Color(0.46, 0.52, 0.29) if layer == 0 else Color(0.52, 0.58, 0.32)
		for s in sides:
			var n := (s + 1) % sides
			mb.tri_out(top, ring_t[s], ring_t[n], g, Vector3.UP)
			mb.tri_out(ring_t[s], ring_b[s], ring_b[n], g.darkened(0.12), ring_t[s] - Vector3(0, cy, 0))
			mb.tri_out(ring_t[s], ring_b[n], ring_t[n], g.darkened(0.12), ring_t[s] - Vector3(0, cy, 0))
			mb.tri_out(Vector3(0, cy - 0.07, 0), ring_b[n], ring_b[s], g.darkened(0.3), Vector3.DOWN)
	return mb.commit()


func _shrub_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 9
	mb.rock(Vector3(0, 0.35, 0), Vector3(1.0, 0.7, 1.0), Color(0.55, 0.56, 0.36), r, 0.22)
	return mb.commit()


func _tuft_mesh() -> ArrayMesh:
	# dry grass tuft: a few thin double-sided blades (unit height)
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 21
	for k in 5:
		var a := TAU * k / 5.0 + r.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x) * 0.12
		var tip := d * r.randf_range(0.35, 0.6) + Vector3(0, r.randf_range(0.7, 1.0), 0)
		var c := Color(0.80, 0.72, 0.46).lerp(Color(0.62, 0.62, 0.38), r.randf())
		mb.tri_out(-side, side, tip, c, d)
		mb.tri_out(-side, side, tip, c.darkened(0.15), -d)
	return mb.commit()


func _rock_mesh(seed: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = seed
	mb.rock(Vector3(0, 0.3, 0), Vector3(1.0, 0.75, 0.9), Color(0.70, 0.62, 0.54), r, 0.3)
	return mb.commit()


func _make_species(name: String, mesh: Mesh, xfs: Array[Transform3D], cols: Array[Color]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		mm.set_instance_color(k, cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + name
	mmi.multimesh = mm
	mmi.material_override = veg_mat
	add_child(mmi)
	var alive := PackedByteArray()
	alive.resize(xfs.size())
	alive.fill(1)
	species[name] = {"mm": mm, "xf": xfs, "alive": alive, "mmi": mmi}


func _veg_ok(p: Vector2, min_hs: float, min_ny: float, clear_r: float) -> bool:
	if not terrain.is_inside(p.x, p.y, 0.02):
		return false
	var hs := _hs(p.x, p.y)
	if hs < min_hs:
		return false
	if terrain.smooth_normal_at(p.x, p.y, 0.003).y < min_ny:
		return false
	if layout.infrastructure_distance(p) < clear_r:
		return false
	if not _footprint_clear(p, clear_r * 0.6):
		return false
	return true


func _place_vegetation() -> void:
	var L := layout
	var palms: Array[Transform3D] = []
	var palm_c: Array[Color] = []
	var add_palm := func(p: Vector2) -> void:
		var s := rng.randf_range(0.0085, 0.0125)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		b = b.rotated(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.12))
		var y := terrain.height_at(p.x, p.y) - 0.0004
		palms.append(Transform3D(b.scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)))
		var tint := rng.randf_range(0.88, 1.1)
		palm_c.append(Color(tint, tint * rng.randf_range(0.96, 1.04), tint * 0.95))
		placed.append({"kind": "palm", "pos": Vector3(p.x, y, p.y), "water_ok": false, "sink": 0.0004, "ground_min": y + 0.0004})
		terrain.stamp_ao(p, 0.0045, 0.35)
	# groves
	for g in L.groves:
		var n := int(g.z * g.z * 26000.0)
		for k in n * 3:
			if n <= 0:
				break
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * g.z
			var p := Vector2(g.x, g.y) + Vector2(cos(a), sin(a)) * r
			if _veg_ok(p, 0.0022, 0.9, 0.003) and _spacing_ok(palms, p, 0.0042):
				add_palm.call(p)
				n -= 1
	# lagoon oasis ring
	for k in 140:
		var a := rng.randf() * TAU
		var f := rng.randf_range(1.12, 1.6)
		var p := Vector2(L.lagoon.x + cos(a) * L.lagoon.z * f, L.lagoon.y + sin(a) * L.lagoon.w * f)
		if _veg_ok(p, 0.0016, 0.9, 0.003) and _spacing_ok(palms, p, 0.0045):
			add_palm.call(p)
	# boulevard palms along the town main road
	var main_road: PackedVector2Array = L.road_samples()[0]
	var acc := 0.0
	for s in range(1, main_road.size()):
		acc += main_road[s].distance_to(main_road[s - 1])
		if acc < 0.011:
			continue
		acc = 0.0
		var p := main_road[s]
		if p.distance_to(L.town_center) > L.town_radius * 1.6:
			continue
		var tng := (main_road[mini(s + 1, main_road.size() - 1)] - main_road[s - 1]).normalized()
		for sd in [-1.0, 1.0]:
			var q: Vector2 = p + Vector2(-tng.y, tng.x) * sd * 0.0046
			if _veg_ok(q, 0.002, 0.88, 0.0015) and _spacing_ok(palms, q, 0.004):
				add_palm.call(q)
	# a few scattered coastal palms
	for k in 120:
		var p := Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.34, 0.34))
		var hs := _hs(p.x, p.y)
		if hs > 0.0022 and hs < 0.006 and _veg_ok(p, 0.0022, 0.92, 0.004) and _spacing_ok(palms, p, 0.006):
			if p.distance_to(L.sabkha_center) > L.sabkha_radius:
				add_palm.call(p)
	_make_species("palm", _palm_mesh(), palms, palm_c)

	# acacias on the dry inland plains
	var aca: Array[Transform3D] = []
	var aca_c: Array[Color] = []
	for k in 900:
		var p := Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.34, 0.34))
		var hs := _hs(p.x, p.y)
		if hs < 0.004 or hs > 0.03:
			continue
		if p.distance_to(L.town_center) < L.town_radius * 1.1:
			continue
		if L.lush_at(p.x, p.y) > 0.5:
			continue
		if not _veg_ok(p, 0.004, 0.86, 0.005) or not _spacing_ok(aca, p, 0.009) or not _spacing_ok(palms, p, 0.006):
			continue
		var s := rng.randf_range(0.0065, 0.0095)
		var y := terrain.height_at(p.x, p.y) - 0.0004
		aca.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.1), s)), Vector3(p.x, y, p.y)))
		var t := rng.randf_range(0.85, 1.1)
		aca_c.append(Color(t, t, t * 0.95))
		placed.append({"kind": "acacia", "pos": Vector3(p.x, y, p.y), "water_ok": false, "sink": 0.0004, "ground_min": y + 0.0004})
		terrain.stamp_ao(p, 0.005, 0.3)
		if aca.size() >= 140:
			break
	_make_species("acacia", _acacia_mesh(), aca, aca_c)

	# low shrubs: break up the big flat colour fields
	var sh: Array[Transform3D] = []
	var sh_c: Array[Color] = []
	for k in 6000:
		var p := Vector2(rng.randf_range(-0.44, 0.44), rng.randf_range(-0.36, 0.36))
		var hs := _hs(p.x, p.y)
		if hs < 0.003 or hs > 0.04:
			continue
		if p.distance_to(L.sabkha_center) < L.sabkha_radius * 0.8:
			continue
		if p.distance_to(L.town_center) < L.town_radius * 0.9:
			continue
		var ny := terrain.smooth_normal_at(p.x, p.y, 0.003).y
		if ny < 0.75:
			continue
		if L.infrastructure_distance(p) < 0.0025 or not _footprint_clear(p, 0.001):
			continue
		var s := rng.randf_range(0.0011, 0.0024)
		var y := terrain.height_at(p.x, p.y) - 0.0003
		sh.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s)), Vector3(p.x, y, p.y)))
		var t := rng.randf_range(0.8, 1.15)
		var lu := L.lush_at(p.x, p.y)
		sh_c.append(Color(t * (1.0 - lu * 0.15), t * (1.0 + lu * 0.05), t * 0.9 * (1.0 - lu * 0.1)))
		placed.append({"kind": "shrub", "pos": Vector3(p.x, y, p.y), "water_ok": false, "sink": 0.0003, "ground_min": y + 0.0003})
		if sh.size() >= 900:
			break
	_make_species("shrub", _shrub_mesh(), sh, sh_c)

	# dry grass tufts: fine texture over the plains and dune flanks
	var tf: Array[Transform3D] = []
	var tf_c: Array[Color] = []
	for k in 9000:
		var p := Vector2(rng.randf_range(-0.44, 0.44), rng.randf_range(-0.36, 0.36))
		if not terrain.is_inside(p.x, p.y, 0.03):
			continue
		var hs := _hs(p.x, p.y)
		if hs < 0.0025 or hs > 0.03:
			continue
		if p.distance_to(L.town_center) < L.town_radius * 0.8:
			continue
		if L.infrastructure_distance(p) < 0.002 or not _footprint_clear(p, 0.0008):
			continue
		var s := rng.randf_range(0.0012, 0.0022)
		var y := terrain.height_at(p.x, p.y) - 0.0002
		tf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(p.x, y, p.y)))
		var t := rng.randf_range(0.85, 1.12)
		tf_c.append(Color(t, t, t * 0.95))
		placed.append({"kind": "tuft", "pos": Vector3(p.x, y, p.y), "water_ok": false, "sink": 0.0002, "ground_min": y + 0.0002})
		if tf.size() >= 1400:
			break
	_make_species("tuft", _tuft_mesh(), tf, tf_c)

	# rocks: ridge flanks, cliffs, breakwater
	var rk: Array[Transform3D] = []
	var rk_c: Array[Color] = []
	for k in 5000:
		var p := Vector2(rng.randf_range(-0.44, 0.44), rng.randf_range(-0.38, 0.38))
		var hs := _hs(p.x, p.y)
		if hs < 0.0005:
			continue
		var ny := terrain.smooth_normal_at(p.x, p.y, 0.003).y
		var rocky := hs > 0.016 or ny < 0.9
		if not rocky or rng.randf() < 0.3:
			continue
		if L.infrastructure_distance(p) < 0.004 or not _footprint_clear(p, 0.002):
			continue
		var s := rng.randf_range(0.0012, 0.0042) * (1.6 if rng.randf() < 0.08 else 1.0)
		var y := terrain.height_at(p.x, p.y) - s * 0.25
		rk.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s * rng.randf_range(0.8, 1.2))), Vector3(p.x, y, p.y)))
		var t := rng.randf_range(0.8, 1.08)
		rk_c.append(Color(t, t * 0.97, t * 0.93))
		placed.append({"kind": "rock", "pos": Vector3(p.x, y, p.y), "water_ok": false, "sink": s * 0.25, "ground_min": y + s * 0.25})
		if rk.size() >= 420:
			break
	# breakwater rocks (in water on purpose)
	for p in breakwater_points():
		for j in 2:
			var q: Vector2 = p + Vector2(rng.randf_range(-0.002, 0.002), rng.randf_range(-0.002, 0.002))
			var g := terrain.height_at(q.x, q.y)
			var top := IslandTerrain.SEA + rng.randf_range(0.0012, 0.0026)
			var hy := (top - g) / 1.05
			var s := rng.randf_range(0.0026, 0.0038)
			rk.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, hy, s)), Vector3(q.x, g - hy * 0.0, q.y)))
			rk_c.append(Color(0.82, 0.8, 0.76))
			placed.append({"kind": "breakwater", "pos": Vector3(q.x, g, q.y), "water_ok": true, "sink": 0.0, "ground_min": g})
	_make_species("rock", _rock_mesh(17), rk, rk_c)


func _spacing_ok(list: Array[Transform3D], p: Vector2, d: float) -> bool:
	for xf in list:
		if absf(xf.origin.x - p.x) < d and absf(xf.origin.z - p.y) < d:
			if Vector2(xf.origin.x, xf.origin.z).distance_to(p) < d:
				return false
	return true


# ======================================================================================
# boats
# ======================================================================================

func _boat_mesh(kind: int, col: Color) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var L := 0.010 if kind == 0 else (0.014 if kind == 1 else 0.009)
	var W := L * 0.30
	var deck := 0.0007
	var keel := -0.0008
	var hull := [Vector2(-L * 0.5, -W * 0.42), Vector2(L * 0.2, -W * 0.5), Vector2(L * 0.5, 0), Vector2(L * 0.2, W * 0.5), Vector2(-L * 0.5, W * 0.42)]
	var n := hull.size()
	var hc := col
	var stripe := Color(0.2, 0.3, 0.5) if kind != 2 else Color(0.35, 0.22, 0.12)
	for k in n:
		var a: Vector2 = hull[k]
		var b: Vector2 = hull[(k + 1) % n]
		var A := Vector3(a.x, deck, a.y)
		var B := Vector3(b.x, deck, b.y)
		var Ab := Vector3(a.x * 0.85, keel, a.y * 0.55)
		var Bb := Vector3(b.x * 0.85, keel, b.y * 0.55)
		var outd := Vector3((a.x + b.x) * 0.5, 0, (a.y + b.y) * 0.5)
		mb.tri_out(A, B, Bb, hc, outd)
		mb.tri_out(A, Bb, Ab, hc, outd)
		# stripe
		var As := Vector3(a.x * 1.003, deck - 0.00008, a.y * 1.003)
		var Bs := Vector3(b.x * 1.003, deck - 0.00008, b.y * 1.003)
		mb.tri_out(As, Bs, Bs + Vector3(0, -0.00022, 0), stripe, outd)
		mb.tri_out(As, Bs + Vector3(0, -0.00022, 0), As + Vector3(0, -0.00022, 0), stripe, outd)
	var deck_c := Color(0.85, 0.80, 0.70) if kind != 2 else Color(0.60, 0.45, 0.30)
	for k in range(1, n - 1):
		var a: Vector2 = hull[0]
		var b: Vector2 = hull[k]
		var c: Vector2 = hull[k + 1]
		mb.tri_out(Vector3(a.x, deck, a.y), Vector3(b.x, deck, b.y), Vector3(c.x, deck, c.y), deck_c, Vector3.UP)
	if kind == 0:
		mb.box(Vector3(-L * 0.12, deck + 0.0006, 0), Vector3(L * 0.32, 0.0012, W * 0.6), Color(0.95, 0.95, 0.93))
		mb.box(Vector3(-L * 0.02, deck + 0.0009, 0), Vector3(0.0002, 0.0005, W * 0.5), Color(0.2, 0.28, 0.35))
	elif kind == 1:
		mb.box(Vector3(-L * 0.25, deck + 0.0009, 0), Vector3(L * 0.25, 0.0018, W * 0.7), Color(0.95, 0.95, 0.93))
		mb.box(Vector3(-L * 0.22, deck + 0.0021, 0), Vector3(L * 0.15, 0.0007, W * 0.6), Color(0.2, 0.3, 0.38))
		mb.cylinder(Vector3(L * 0.1, deck, 0), 0.00012, 0.00012, 0.004, 4, Color(0.3, 0.3, 0.3))
	else:
		# dhow: mast + lateen sail
		mb.cylinder(Vector3(L * 0.08, deck, 0), 0.00014, 0.0001, 0.0075, 4, Color(0.35, 0.25, 0.15))
		var s0 := Vector3(L * 0.45, deck + 0.0012, 0)
		var s1 := Vector3(-L * 0.42, deck + 0.0085, 0)
		var s2 := Vector3(L * 0.05, deck + 0.0008, 0)
		var sail := Color(0.95, 0.92, 0.84)
		mb.tri_out(s0, s1, s2, sail, Vector3.BACK)
		mb.tri_out(s0, s1, s2, sail.darkened(0.08), Vector3.FORWARD)
	return mb.commit()


func _place_boats() -> void:
	var L := layout
	var defs := [
		[Vector2(L.pier_x - 0.0055, L.quay_z + 0.016), deg_to_rad(90), 0, Color(0.95, 0.95, 0.93)],
		[Vector2(L.pier_x + 0.0058, L.quay_z + 0.03), deg_to_rad(-90), 1, Color(0.92, 0.93, 0.95)],
		[Vector2(L.pier_x - 0.006, L.quay_z + 0.036), deg_to_rad(95), 2, Color(0.55, 0.40, 0.25)],
		[Vector2(L.harbour_x0 + 0.02, L.quay_z + 0.008), deg_to_rad(5), 1, Color(0.30, 0.42, 0.55)],
		[Vector2(0.06, 0.29), deg_to_rad(30), 2, Color(0.50, 0.36, 0.22)],
		[Vector2(-0.30, 0.25), deg_to_rad(-60), 0, Color(0.92, 0.92, 0.9)],
		[Vector2(0.40, -0.18), deg_to_rad(150), 1, Color(0.42, 0.45, 0.42)],
	]
	var mat := MeshBuilder.vc_material(0.6)
	for d in defs:
		var p: Vector2 = d[0]
		if _hs(p.x, p.y) > -0.0025:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _boat_mesh(d[2], d[3])
		mi.material_override = mat
		mi.position = Vector3(p.x, IslandTerrain.SEA, p.y)
		mi.rotation.y = d[1]
		add_child(mi)
		boats.append({"node": mi, "phase": rng.randf() * TAU, "rot": float(d[1])})
		placed.append({"kind": "boat", "pos": mi.position, "water_ok": true, "sink": 0.0, "ground_min": 0.0})


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for b in boats:
		var n: Node3D = b.node
		n.position.y = IslandTerrain.SEA - 0.0001 + sin(t * 1.4 + b.phase) * 0.00012
		n.rotation = Vector3(sin(t * 1.1 + b.phase) * 0.03, b.rot, sin(t * 1.3 + b.phase * 2.0) * 0.04)
	if radar_head:
		radar_head.rotation.y = t * 0.9


# ======================================================================================
# stats
# ======================================================================================

func triangle_stats() -> Dictionary:
	var out := {"structure_tris": struct_tris}
	var veg := 0
	for name in species:
		var sp: Dictionary = species[name]
		var mm: MultiMesh = sp.mm
		var per := (mm.mesh as ArrayMesh).surface_get_array_len(0) / 3
		out["mm_" + name] = per * mm.instance_count
		veg += per * mm.instance_count
	out["vegetation_total"] = veg
	var dr := 0
	for m in drape_mi:
		dr += (m.mesh as ArrayMesh).surface_get_array_len(0) / 3 if m.mesh and (m.mesh as ArrayMesh).get_surface_count() > 0 else 0
	out["drapes"] = dr
	return out


func structure_count() -> int:
	return structures.size()
