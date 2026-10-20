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
	_place_plant()
	_place_refinery()
	_place_desal()
	_place_army()
	_place_ships()
	_place_city()
	_place_lighthouse()
	_rebuild_structures()
	_build_drapes()
	_place_vegetation()
	_place_buoys()
	_snapshot()


## Undamaged state, for reset_damage() ("reset island" on the panel).
var _snap := {}


func _snapshot() -> void:
	_snap = {"structures": structures.duplicate(true), "veg": {}}
	for nm in species:
		_snap.veg[nm] = (species[nm].xf as Array).duplicate()


## Buildings, vegetation and roads back to the undamaged island (no rebuild of the
## generators: the snapshot taken at build time is restored).
func reset_damage() -> void:
	structures.clear()
	for st in (_snap.structures as Array):
		structures.append((st as Dictionary).duplicate(true))
	for nm in species:
		var sp: Dictionary = species[nm]
		var xfs: Array = sp.xf
		var orig: Array = _snap.veg[nm]
		for k in xfs.size():
			xfs[k] = orig[k]
			_set_veg_xf(sp, k, orig[k])
		(sp.alive as PackedByteArray).fill(1)
	craters.clear()
	_crater_grid.clear()
	_pending_drapes.clear()
	_rebuild_structures()
	_build_drapes()


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
	terrain.stamp_ao(c, Vector2(size.x, size.z).length() * 0.78 + 0.002, 0.6)
	return s


# ======================================================================================
# air base
# ======================================================================================

## Air-base buildings and aircraft are drawn this much bigger than 1:2000 (toy look).
const TOY := 1.5


func _place_air_base() -> void:
	var L := layout
	var rd := L.runway_dir()
	var rot := L.runway_angle
	var M := Scale.m(1.0)
	# hardened aircraft shelters dispersed north of the apron, doors to the apron
	var has_lat := L.taxi_offset + L.taxi_w * 0.5 + Scale.m(20.0) + L.apron_size.y + Scale.m(28.0)
	for k in 4:
		var along := -Scale.m(130.0) + k * Scale.m(100.0)
		var c := L.base_world(along, has_lat + (k % 2) * Scale.m(10.0))
		var st := add_structure("has", c, rot + PI, Vector3(Scale.m(30.0), Scale.m(11.0), Scale.m(36.0)) * TOY, Color(0.80, 0.76, 0.64))
		st["link"] = [L.base_world(along, has_lat - Scale.m(20.0)), L.base_world(along, L.taxi_offset + L.taxi_w * 0.5 + Scale.m(20.0) + L.apron_size.y - Scale.m(2.0))]
	# fighters on the apron (15 m long, 10 m span)
	for k in 5:
		var c4 := L.base_world(-Scale.m(90.0) + k * Scale.m(40.0), L.taxi_offset + L.taxi_w * 0.5 + Scale.m(20.0) + L.apron_size.y * 0.55)
		add_structure("jet", c4, rot - PI * 0.5, Vector3(Scale.m(10.0), Scale.m(5.0), Scale.m(15.0)) * TOY, Color(0.62, 0.70, 0.78))
	# tower, operations, barracks east end (inside the fence)
	var east := L.runway_len * 0.5 - Scale.m(40.0)
	add_structure("ctower", L.base_world(east, L.taxi_offset + Scale.m(40.0)), rot, Vector3(Scale.m(10.0), Scale.m(25.0), Scale.m(10.0)) * TOY, Color(0.96, 0.94, 0.88))
	add_structure("barracks", L.base_world(east - Scale.m(30.0), L.taxi_offset + Scale.m(48.0)), rot, Vector3(Scale.m(34.0), Toon.storeys(2.0), Scale.m(16.0)), Color(0.90, 0.86, 0.74))
	for k in 3:
		add_structure("barracks", L.base_world(east - Scale.m(20.0) - k * Scale.m(46.0), has_lat + Scale.m(62.0)), rot, Vector3(Scale.m(40.0), Toon.storeys(1.0), Scale.m(14.0)), Color(0.88, 0.84, 0.70))
	# fuel farm with bunds near the west end
	for k in 3:
		var c2 := L.base_world(Scale.m(0.0) + k * Scale.m(34.0), has_lat + Scale.m(70.0))
		add_structure("tank", c2, 0.0, Vector3(Scale.m(20.0), Scale.m(12.0), Scale.m(20.0)) * TOY, Color(0.96, 0.96, 0.94))
	# missile silos on the silo pad
	for k in 3:
		var c3 := L.silo_center + rd * (-Scale.m(36.0) + k * Scale.m(36.0)) + Vector2(rd.y, -rd.x) * Scale.m(10.0)
		add_structure("silo_open" if k == 1 else "silo", c3, rot, Vector3(Scale.m(14.0), Scale.m(2.0), Scale.m(14.0)), Arch.CONCRETE)
	# radar station on the knoll (outside the wire)
	var rp := L.radar_pos
	add_structure("radar_base", rp + Vector2(Scale.m(14.0), Scale.m(8.0)), 0.3, Vector3(Scale.m(16.0), Scale.storeys(1.0), Scale.m(12.0)), Color(0.84, 0.82, 0.76))
	var rg := terrain.height_at(rp.x, rp.y)
	add_structure("mast", rp, 0.0, Vector3(Scale.m(3.0), Scale.m(12.0), Scale.m(3.0)), Color(0.75, 0.74, 0.70))
	radar_head = Node3D.new()
	radar_head.name = "RadarHead"
	radar_head.position = Vector3(rp.x, rg + Scale.m(12.5), rp.y)
	add_child(radar_head)
	var dm := MeshBuilder.new()
	_dish(dm, Scale.m(5.0), Color(0.92, 0.92, 0.90))
	var dmi := MeshInstance3D.new()
	dmi.mesh = dm.commit(null, MeshBuilder.vc_material(0.5, false))
	radar_head.add_child(dmi)
	# static launcher + the interactive one (on the silo pad); 12 m TEL trucks
	var north := Vector2(rd.y, -rd.x)
	var lc := L.silo_center + rd * Scale.m(60.0) - north * Scale.m(18.0)
	add_structure("launcher_truck", L.silo_center - rd * Scale.m(60.0) - north * Scale.m(18.0), rot, Vector3(Scale.m(12.0), Scale.m(3.5), Scale.m(3.0)), Color(0.48, 0.50, 0.40))
	_build_launcher(lc, rot)
	if M < 0.0:
		pass


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
	launcher.scale = Vector3.ONE * 0.72     # 8.5 mm model -> ~12 m TEL at 1:2000
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
	# island-local (the diorama may be moved / scaled in the room): props sit at the
	# island origin, so its inverse maps the rack's world transform back.
	return global_transform.affine_inverse() * (launcher_rack.global_transform * Vector3(0.006, 0.0005, 0.0))


# ======================================================================================
# harbour
# ======================================================================================

func _place_harbour() -> void:
	var L := layout
	var x0 := L.harbour_x0
	var x1 := L.harbour_x1
	var sea := IslandTerrain.SEA
	# quay wall: concrete block whose front face drops into the dredged basin
	var qd := L.quay_z - (L.quay_land_z + 0.002)
	var qc := Vector2((x0 + x1) * 0.5, L.quay_z - qd * 0.5)
	structures.append({
		"kind": "quay", "pos": Vector3(qc.x, sea + L.quay_height + 0.0003, qc.y), "rot": 0.0,
		"size": Vector3(x1 - x0, 0.016, qd), "col": Color(0.74, 0.72, 0.67), "seed": 1,
		"alive": true, "fragile": false, "sink": 0.016, "ruin": false,
	})
	# fishing / dhow pier on piles (120 m)
	var pz0 := L.quay_z
	var pz1 := L.quay_z + L.pier_len
	structures.append({
		"kind": "pier", "pos": Vector3(L.pier_x, sea + Scale.m(4.2), (pz0 + pz1) * 0.5), "rot": 0.0,
		"size": Vector3(Scale.m(8.0), Scale.m(1.2), pz1 - pz0), "col": Color(0.55, 0.42, 0.30), "seed": 2,
		"alive": true, "fragile": true, "sink": 0.0, "ruin": false,
	})
	placed.append({"kind": "pier", "pos": Vector3(L.pier_x, sea, pz1), "water_ok": true, "sink": 0.0, "ground_min": 0.0})
	# ship-to-shore cranes on the quay edge, booms over the berth
	var crane_z := L.quay_z - Scale.m(17.0)
	for k in 2:
		add_structure("sts_crane", Vector2(x0 + Scale.m(70.0) + k * Scale.m(56.0), crane_z), 0.0, Vector3(Scale.m(20.0), Scale.m(58.0), Scale.m(32.0)), Color(0.88, 0.70, 0.18), true, true)
	# container yard: 2 rows x 3 blocks, RTG over one block
	var yard_z0 := L.quay_land_z + Scale.m(8.0)
	var block := Vector3(Scale.m(40.0), Scale.m(11.0), Scale.m(14.0))
	for row in 2:
		for k in 3:
			var c := Vector2(x0 + Scale.m(30.0) + k * Scale.m(46.0), yard_z0 + block.z * 0.5 + row * Scale.m(20.0))
			var st := add_structure("containers", c, 0.0, block, Color(0.6, 0.5, 0.4))
			st["seed"] = row * 31 + k * 7 + 3
	add_structure("rtg", Vector2(x0 + Scale.m(76.0), yard_z0 + block.z * 0.5), 0.0, Vector3(Scale.m(42.0), Scale.m(18.0), Scale.m(20.0)), Color(0.90, 0.72, 0.20))
	# transit sheds at the east end of the apron
	add_structure("warehouse", Vector2(x1 - Scale.m(32.0), yard_z0 + Scale.m(8.0)), 0.0, Vector3(Scale.m(56.0), Scale.m(9.0), Scale.m(18.0)), Color(0.72, 0.74, 0.74))
	add_structure("warehouse", Vector2(x1 - Scale.m(32.0), yard_z0 + Scale.m(30.0)), 0.0, Vector3(Scale.m(56.0), Scale.m(8.0), Scale.m(16.0)), Color(0.80, 0.70, 0.56))
	# navigation: beacon on the breakwater head
	var bw := breakwater_points()
	var head: Vector2 = bw[bw.size() - 1]
	var bsz := Vector3(Scale.m(2.4), Scale.m(9.0), Scale.m(2.4))
	structures.append({"kind": "beacon", "pos": Vector3(head.x, sea + Scale.m(4.0), head.y), "rot": 0.0, "size": bsz,
		"col": Color(0.2, 0.62, 0.3), "seed": 5, "alive": true, "fragile": true, "sink": Scale.m(4.0), "ruin": false})
	placed.append({"kind": "beacon", "pos": Vector3(head.x, sea, head.y), "water_ok": true, "sink": 0.0, "ground_min": 0.0})


func breakwater_points() -> PackedVector2Array:
	var L := layout
	var pts := PackedVector2Array([Vector2(L.harbour_x1 + 0.004, L.quay_z - 0.004), Vector2(L.harbour_x1 + 0.012, L.quay_z + 0.025), Vector2(L.harbour_x1 + 0.0, L.basin_z + 0.01), Vector2(L.harbour_x1 - 0.022, L.basin_z + 0.016)])
	return IslandLayout.catmull(pts, 0.0035)


# ======================================================================================
# town
# ======================================================================================

## Build 3 toy city on a street grid: skyscrapers downtown, mid-rise blocks, a mall,
## a stadium and a TV tower in the ring, houses and villas outside. One lot grid per
## block (2 x 2 downtown / ring, 3 x 3 houses outside).
func _place_city() -> void:
	var L := layout
	var C := L.town_center
	var P := IslandLayout.CITY_PITCH
	var inner := P - IslandLayout.ROAD_W - 0.002
	var specials := ["stadium", "mall", "mall"]
	# the TV tower (a mission target) always stands: the first free ring block gets it
	for gz in range(-5, 5):
		var done := false
		for gx in range(-5, 5):
			var tb := C + Vector2((gx + 0.5) * P, (gz + 0.5) * P)
			var td := tb.distance_to(C) / L.town_radius
			if td > 0.5 and td < 0.72 and _city_lot(tb, Vector3(0.006, 0.075, 0.006)):
				add_structure("tv_tower", tb, 0.0, Vector3(0.006, 0.075, 0.006), Toon.WHITE)
				done = true
				break
		if done:
			break
	add_structure("fort", L.fort_pos, deg_to_rad(8.0), Vector3(Scale.m(56.0), Scale.m(9.0), Scale.m(56.0)), Color(0.86, 0.70, 0.48))
	for gz in range(-5, 5):
		for gx in range(-5, 5):
			var bc := C + Vector2((gx + 0.5) * P, (gz + 0.5) * P)
			var dn := bc.distance_to(C) / L.town_radius
			if dn > 1.0:
				continue
			var zone := 0 if dn < 0.46 else (1 if dn < 0.72 else 2)
			if zone == 1 and not specials.is_empty() and rng.randf() < 0.22:
				var kind: String = specials.pop_front()
				var ssz := Vector3(inner, Toon.storeys(4.0), inner * 0.8) if kind != "tv_tower" else Vector3(0.006, 0.075, 0.006)
				if kind == "mall":
					ssz = Vector3(inner, Toon.storeys(3.0), inner * 0.7)
				if _city_lot(bc, ssz):
					add_structure(kind, bc, 0.0, ssz, Color(0.95, 0.55, 0.30) if kind == "stadium" else Toon.pastel(rng))
					continue
				specials.push_front(kind)
			var n := 3 if zone == 2 else 2
			var lot := inner / n
			for iz in n:
				for ix in n:
					var c := bc + Vector2((ix + 0.5) * lot - inner * 0.5, (iz + 0.5) * lot - inner * 0.5)
					var kind := "house"
					var size: Vector3
					var col: Color = Toon.pastel(rng)
					if zone == 0 and rng.randf() < 0.9:
						kind = "skyscraper"
						var f := lot * rng.randf_range(0.72, 0.86)
						# taller towards the centre
						var top := lerpf(28.0, 13.0, clampf(c.distance_to(C) / (L.town_radius * 0.46), 0.0, 1.0))
						size = Vector3(f, Toon.storeys(float(rng.randi_range(int(top * 0.6), int(top)))), f)
						col = Toon.GLASS[rng.randi() % Toon.GLASS.size()]
					elif zone <= 1:
						kind = "midrise"
						var f2 := lot * rng.randf_range(0.7, 0.84)
						size = Vector3(f2, Toon.storeys(float(rng.randi_range(4, 8))), f2 * rng.randf_range(0.8, 1.0))
					elif rng.randf() < 0.25:
						kind = "villa"
						size = Vector3(lot * 0.85, Toon.storeys(2.0), lot * 0.85)
					else:
						size = Vector3(lot * rng.randf_range(0.6, 0.78), Toon.storeys(1.0 if rng.randf() < 0.4 else 2.0), lot * rng.randf_range(0.6, 0.78))
					if rng.randf() < 0.06:
						continue
					if _city_lot(c, size):
						add_structure(kind, c, 0.0, size, col)


## A lot is buildable: dry, fairly flat, off roads and infrastructure, no overlap.
func _city_lot(c: Vector2, size: Vector3) -> bool:
	var half_diag := Vector2(size.x, size.z).length() * 0.5
	if layout.road_distance(c) < half_diag * 0.72 + IslandLayout.ROAD_W * 0.5 + 0.0004:
		return false
	if layout.infrastructure_distance(c) < half_diag:
		return false
	if not _footprint_clear(c, half_diag * 0.55):
		return false
	var g := _ground(c, 0.0, Vector2(size.x, size.z) * 0.5)
	return g.x - IslandTerrain.SEA >= 0.0018 and g.y - g.x <= 0.007


# ======================================================================================
# lighthouse
# ======================================================================================

func _place_lighthouse() -> void:
	var p := layout.lighthouse_pos
	add_structure("lighthouse", p, 0.0, Vector3(Scale.m(9.0), Scale.m(30.0), Scale.m(9.0)), Color(0.95, 0.94, 0.92))
	add_structure("house", p + Vector2(-Scale.m(20.0), Scale.m(12.0)), 0.2, Vector3(0.007, Toon.storeys(1.0), 0.005), Color(0.93, 0.92, 0.88))


## Coastal gas power station (south-east coast): halls, chimneys, cooling towers,
## transformer yard.
func _place_plant() -> void:
	var L := layout
	var c := L.plant_center
	add_structure("power_hall", c + Vector2(-0.012, 0.004), 0.0, Vector3(0.034, 0.011, 0.014), Color(0.88, 0.90, 0.92))
	for k in 3:
		add_structure("chimney", c + Vector2(-0.026 + k * 0.012, -0.012), 0.0, Vector3(0.0045, 0.05, 0.0045), Toon.WHITE)
	for k in 2:
		add_structure("cooling_tower", c + Vector2(0.022, -0.010 + k * 0.02), 0.0, Vector3(0.016, 0.026, 0.016), Toon.WHITE)
	add_structure("transformer", c + Vector2(-0.012, 0.018), 0.0, Vector3(0.022, 0.006, 0.008), Toon.STEEL)
	# intake jetty straight out to sea
	var jx := c.x - Scale.m(10.0)
	var jz0 := c.y + L.plant_size.y * 0.5
	var jz1 := jz0
	while jz1 < jz0 + 0.06 and _hs(jx, jz1) > -0.004:
		jz1 += 0.002
	jz1 += 0.006
	var sea := IslandTerrain.SEA
	structures.append({"kind": "jetty", "pos": Vector3(jx, sea + Scale.m(3.0), (jz0 + jz1) * 0.5), "rot": 0.0,
		"size": Vector3(Scale.m(6.0), Scale.m(1.0), jz1 - jz0), "col": Arch.CONCRETE, "seed": 9,
		"alive": true, "fragile": true, "sink": 0.0, "ruin": false})
	placed.append({"kind": "jetty", "pos": Vector3(jx, sea, jz1), "water_ok": true, "sink": 0.0, "ground_min": 0.0})


## Oil refinery on the east cape: crude tank farm, distillation columns, cracking
## units, LPG spheres, flare stacks, pipe racks, and a tanker jetty to the sea.
func _place_refinery() -> void:
	var L := layout
	var c := L.refinery_center
	var sz := L.refinery_size
	for i in 3:
		for j in 2:
			add_structure("crude_tank", c + Vector2(-sz.x * 0.32 + i * 0.019, -sz.y * 0.28 + j * 0.019), 0.0, Vector3(0.016, 0.0075, 0.016), Toon.WHITE)
	for k in 3:
		add_structure("column", c + Vector2(sz.x * 0.08 + k * 0.008, -sz.y * 0.30), 0.0, Vector3(0.003, 0.030 + k * 0.006, 0.003), Toon.STEEL)
	for k in 2:
		add_structure("cracker", c + Vector2(sz.x * 0.18 + k * 0.016, sz.y * 0.02), 0.0, Vector3(0.013, 0.013, 0.011), Toon.STEEL)
	for k in 3:
		add_structure("sphere_tank", c + Vector2(-sz.x * 0.30 + k * 0.012, sz.y * 0.33), 0.0, Vector3(0.009, 0.009, 0.009), Toon.WHITE)
	add_structure("flare", c + Vector2(sz.x * 0.42, sz.y * 0.36), 0.0, Vector3(0.002, 0.04, 0.002), Toon.WHITE)
	add_structure("flare", c + Vector2(sz.x * 0.30, sz.y * 0.40), 0.0, Vector3(0.002, 0.032, 0.002), Toon.WHITE)
	add_structure("pipe_rack", c + Vector2(sz.x * 0.05, sz.y * 0.20), 0.0, Vector3(sz.x * 0.8, 0.004, 0.004), Toon.STEEL)
	# tanker jetty: east from the refinery into deep water, the tanker alongside
	var jz := c.y - sz.y * 0.05
	var jx0 := c.x + sz.x * 0.5
	var jx1 := jx0
	while jx1 < jx0 + 0.09 and _hs(jx1, jz) > -0.006:
		jx1 += 0.002
	jx1 += 0.004
	var sea := IslandTerrain.SEA
	structures.append({"kind": "jetty", "pos": Vector3((jx0 + jx1) * 0.5, sea + 0.0018, jz), "rot": PI * 0.5,
		"size": Vector3(0.004, 0.0008, jx1 - jx0), "col": Arch.CONCRETE, "seed": 19,
		"alive": true, "fragile": true, "sink": 0.0, "ruin": false})
	placed.append({"kind": "jetty", "pos": Vector3(jx1, sea, jz), "water_ok": true, "sink": 0.0, "ground_min": 0.0})
	_add_ship("tanker", Vector2(jx1 + 0.022, jz - 0.012), PI * 0.5, Vector3(0.09, 0.006, 0.016))


## Desalination plant beside the power station: process trains + blue water tanks.
func _place_desal() -> void:
	var c := layout.desal_center
	for k in 2:
		add_structure("desal", c + Vector2(-0.006, -0.007 + k * 0.012), 0.0, Vector3(0.03, 0.005, 0.010), Toon.WHITE)
	for k in 2:
		add_structure("water_tank", c + Vector2(0.017, -0.006 + k * 0.012), 0.0, Vector3(0.009, 0.007, 0.009), Toon.WATER_BLUE)


## Army camp on the north plain: SAM batteries, bunkers, tanks, barracks.
func _place_army() -> void:
	var c := layout.army_center
	for k in 3:
		add_structure("barracks", c + Vector2(-0.018 + k * 0.016, -0.014), 0.0, Vector3(0.013, Toon.storeys(1.0), 0.006), Color(0.86, 0.82, 0.68))
	for k in 3:
		add_structure("sam", c + Vector2(-0.02 + k * 0.02, 0.006), deg_to_rad(-30.0 + k * 30.0), Vector3(0.008, 0.003, 0.004), Toon.OLIVE)
	for k in 4:
		add_structure("tank_vehicle", c + Vector2(-0.022 + k * 0.012, 0.018), deg_to_rad(90.0), Vector3(0.0068, 0.003, 0.0042), Toon.OLIVE)
	for k in 2:
		add_structure("bunker", c + Vector2(0.024, -0.012 + k * 0.016), 0.0, Vector3(0.010, 0.0035, 0.010), Color(0.70, 0.68, 0.62))
	add_structure("radar_sphere", c + Vector2(-0.026, 0.0), 0.0, Vector3(0.007, 0.009, 0.007), Toon.WHITE)


## Ships on the sea (static, destroyable): harbour cargo ships, warships offshore,
## fishing / patrol boats. Each is placed only where the sea is deep enough.
func _place_ships() -> void:
	var L := layout
	_add_ship("cargo", Vector2(L.harbour_x0 + Scale.m(95.0), L.quay_z + Scale.m(13.0)), 0.0, Vector3(0.085, 0.006, 0.015))
	_add_ship("cargo", Vector2(0.24, 0.33), deg_to_rad(-20.0), Vector3(0.09, 0.006, 0.016))
	_add_ship("frigate", Vector2(-0.06, 0.34), deg_to_rad(15.0), Vector3(0.06, 0.006, 0.010))
	_add_ship("frigate", Vector2(0.06, -0.33), deg_to_rad(170.0), Vector3(0.065, 0.006, 0.011))
	_add_ship("frigate", Vector2(-0.40, -0.18), deg_to_rad(120.0), Vector3(0.055, 0.006, 0.0095))
	var small := [[Vector2(L.pier_x - Scale.m(9.0), L.quay_z + Scale.m(30.0)), deg_to_rad(90), Color(0.95, 0.95, 0.93)],
		[Vector2(L.pier_x + Scale.m(11.0), L.quay_z + Scale.m(60.0)), deg_to_rad(-90), Color(0.92, 0.35, 0.25)],
		[Vector2(0.06, 0.29), deg_to_rad(30), Color(0.95, 0.75, 0.30)],
		[Vector2(-0.30, 0.25), deg_to_rad(-60), Color(0.30, 0.60, 0.95)],
		[Vector2(0.40, -0.18), deg_to_rad(150), Color(0.55, 0.62, 0.66)],
		[Vector2(-0.18, -0.30), deg_to_rad(40), Color(0.95, 0.95, 0.93)]]
	for b in small:
		_add_ship("boat", b[0], b[1], Vector3(0.016, 0.003, 0.005), b[2])


func _add_ship(kind: String, c: Vector2, rot: float, size: Vector3, col: Color = Toon.NAVY) -> void:
	var b := Basis(Vector3.UP, rot)
	for f in [Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5), Vector3.ZERO]:
		var q: Vector3 = b * (f * size)
		if not terrain.is_inside(c.x + q.x, c.y + q.z, 0.01) or _hs(c.x + q.x, c.y + q.z) > -0.003:
			return
	var st := {"kind": kind, "pos": Vector3(c.x, IslandTerrain.SEA, c.y), "rot": rot, "size": size, "col": col,
		"seed": rng.randi(), "alive": true, "fragile": true, "sink": 0.0, "ruin": false}
	structures.append(st)
	placed.append({"kind": kind, "pos": st.pos, "water_ok": true, "sink": 0.0, "ground_min": 0.0})


# ======================================================================================
# targets: everything that can be destroyed, by category, for the destruction meter
# ======================================================================================

## kind -> [category, value]. Category ids: city oil power water port military navy.
const TARGETS := {
	"house": ["city", 1], "villa": ["city", 1], "midrise": ["city", 2], "skyscraper": ["city", 5],
	"mall": ["city", 4], "stadium": ["city", 4], "tv_tower": ["city", 4], "fort": ["city", 3], "lighthouse": ["city", 2],
	"crude_tank": ["oil", 4], "column": ["oil", 4], "cracker": ["oil", 5], "sphere_tank": ["oil", 3], "flare": ["oil", 2], "pipe_rack": ["oil", 2],
	"power_hall": ["power", 6], "chimney": ["power", 3], "cooling_tower": ["power", 4], "transformer": ["power", 3],
	"desal": ["water", 5], "water_tank": ["water", 3],
	"sts_crane": ["port", 3], "rtg": ["port", 2], "containers": ["port", 1], "warehouse": ["port", 2], "pier": ["port", 1], "jetty": ["port", 1], "beacon": ["port", 1],
	"has": ["military", 4], "jet": ["military", 3], "ctower": ["military", 4], "barracks": ["military", 2], "tank": ["military", 3],
	"silo": ["military", 4], "silo_open": ["military", 4], "launcher_truck": ["military", 3], "radar_base": ["military", 2], "mast": ["military", 2],
	"sam": ["military", 4], "bunker": ["military", 3], "tank_vehicle": ["military", 2], "radar_sphere": ["military", 4], "house_mil": ["military", 1],
	"cargo": ["navy", 5], "tanker": ["navy", 6], "frigate": ["navy", 7], "boat": ["navy", 1],
}
const CATEGORIES := ["city", "oil", "power", "water", "port", "military", "navy"]
const SHIP_KINDS := ["cargo", "tanker", "frigate", "boat"]


## Destruction state: pct (0-100, by value), targets left, and per category
## {cat: [destroyed, total]}.
func destruction() -> Dictionary:
	var tot := 0
	var hit := 0
	var left := 0
	var cats := {}
	for c in CATEGORIES:
		cats[c] = [0, 0]
	for st in structures:
		if not TARGETS.has(st.kind):
			continue
		var t: Array = TARGETS[st.kind]
		var v: int = t[1]
		tot += v
		var cc: Array = cats[t[0]]
		cc[1] = int(cc[1]) + 1
		if not st.alive:
			hit += v
			cc[0] = int(cc[0]) + 1
		else:
			left += 1
	return {"pct": 100.0 * hit / maxf(tot, 1), "left": left, "cats": cats}


# ======================================================================================
# structure mesh generation
# ======================================================================================

# --- simple box colliders for debris (rebuilt with the structures mesh) ----------------
const COL_CELL := 0.02
var col_boxes: Array[Dictionary] = []
var col_hash := {}


func _rebuild_colliders() -> void:
	col_boxes.clear()
	col_hash.clear()
	for st in structures:
		if not st.alive or st.kind in ["quay", "pier", "jetty", "boat"]:
			continue
		var sz: Vector3 = st.size
		var xf := structure_xform(st)
		var top: float = sz.y
		if st.kind in SHIP_KINDS:
			top = 0.003
		var box := {"inv": xf.affine_inverse(), "basis": xf.basis, "hx": sz.x * 0.5, "hz": sz.z * 0.5, "top": top, "bottom": -float(st.sink) - 0.002, "st": st}
		var idx := col_boxes.size()
		col_boxes.append(box)
		var r := Vector2(sz.x, sz.z).length() * 0.5
		var p: Vector3 = st.pos
		for cx in range(int(floor((p.x - r) / COL_CELL)), int(floor((p.x + r) / COL_CELL)) + 1):
			for cz in range(int(floor((p.z - r) / COL_CELL)), int(floor((p.z + r) / COL_CELL)) + 1):
				var key := Vector2i(cx, cz)
				if not col_hash.has(key):
					col_hash[key] = []
				(col_hash[key] as Array).append(idx)


## Push a point (radius r) out of any standing building. Returns the world
## contact normal, or Vector3.ZERO when there was no contact.
func collide_point(p: Vector3, r: float) -> Array:
	var key := Vector2i(int(floor(p.x / COL_CELL)), int(floor(p.z / COL_CELL)))
	if not col_hash.has(key):
		return []
	for i in (col_hash[key] as Array):
		var b: Dictionary = col_boxes[i]
		if not (b.st as Dictionary).alive:
			continue    # destroyed since the last full rebuild
		var lp: Vector3 = (b.inv as Transform3D) * p
		var px: float = b.hx + r - absf(lp.x)
		var pz: float = b.hz + r - absf(lp.z)
		var py: float = b.top + r - lp.y
		if px <= 0.0 or pz <= 0.0 or py <= 0.0 or lp.y < b.bottom:
			continue
		var n := Vector3.UP
		var pen := py
		if px < pen:
			pen = px
			n = Vector3(signf(lp.x), 0, 0)
		if pz < pen:
			pen = pz
			n = Vector3(0, 0, signf(lp.z))
		return [((b.basis as Basis) * n).normalized(), pen]
	return []


## The merged structures mesh, split into STRUCT_TILES x STRUCT_TILES tiles so a blast
## rebuilds only the tile(s) it touched (the whole 31k-triangle mesh took ~20 ms).
const STRUCT_TILES := 8       # 8 x 8 tiles: a hit re-uploads ~1/64 of the buildings
var _struct_tile_mi := {}     # tile index -> MeshInstance3D
var _struct_tile_tris := {}
## Per-structure mesh arrays (index = structure id), built once: a tile rebuild only
## concatenates them (native array appends, no GDScript geometry), so a hit costs
## the new ruin of the hit building plus the upload of its tile.
var _arr_alive := {}
var _arr_ruin := {}


var _warm_next := 0


## Prepare the ruin meshes a few per frame after the build, so a hit only concatenates.
func _warm_ruins(n: int) -> void:
	while n > 0 and _warm_next < structures.size():
		var st: Dictionary = structures[_warm_next]
		_warm_next += 1
		if st.fragile and not _arr_ruin.has(st.id):
			var mb := MeshBuilder.new()
			var was: bool = st.alive
			st.alive = false
			_gen_structure(mb, st)
			st.alive = was
			_arr_ruin[st.id] = [mb.verts, mb.norms, mb.cols, mb.uvs, mb.uv2s]
			n -= 1


func _struct_tile(st: Dictionary) -> int:
	var p: Vector3 = st.pos
	var tx := clampi(int((p.x + 0.5) * STRUCT_TILES), 0, STRUCT_TILES - 1)
	var tz := clampi(int((p.z + 0.5) * STRUCT_TILES), 0, STRUCT_TILES - 1)
	return tz * STRUCT_TILES + tx


func _struct_arrays(st: Dictionary) -> Array:
	var cache := _arr_alive if st.alive else _arr_ruin
	var id: int = st.id
	if not cache.has(id):
		var mb := MeshBuilder.new()
		_gen_structure(mb, st)
		cache[id] = [mb.verts, mb.norms, mb.cols, mb.uvs, mb.uv2s]
	return cache[id]


func _rebuild_structures(tiles: Array = []) -> void:
	# a blast only kills boxes (collide_point skips dead structures): the collider grid
	# is rebuilt on the full rebuilds (build, reset)
	if tiles.is_empty():
		_rebuild_colliders()
		_warm_next = 0
	for i in structures.size():
		structures[i]["id"] = i
	var parts := {}
	for t in STRUCT_TILES * STRUCT_TILES:
		if tiles.is_empty() or t in tiles:
			parts[t] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array()]
	for st in structures:
		var t := _struct_tile(st)
		if parts.has(t):
			var a := _struct_arrays(st)
			var dst: Array = parts[t]
			for k in 5:
				dst[k].append_array(a[k])
	for t in parts:
		if not _struct_tile_mi.has(t):
			var mi := MeshInstance3D.new()
			mi.name = "Structures_%d" % t
			add_child(mi)
			_struct_tile_mi[t] = mi
			if struct_mi == null:
				struct_mi = mi
		var dst: Array = parts[t]
		var n: int = (dst[0] as PackedVector3Array).size()
		var mesh: ArrayMesh = null
		if n > 0:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = dst[0]
			arr[Mesh.ARRAY_NORMAL] = dst[1]
			arr[Mesh.ARRAY_COLOR] = dst[2]
			arr[Mesh.ARRAY_TEX_UV] = dst[3]
			arr[Mesh.ARRAY_TEX_UV2] = dst[4]
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(0, struct_mat)
		(_struct_tile_mi[t] as MeshInstance3D).mesh = mesh
		_struct_tile_tris[t] = n / 3
	struct_tris = 0
	for t in _struct_tile_tris:
		struct_tris += int(_struct_tile_tris[t])


func structure_xform(s: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, s.rot), s.pos)


## Build-3 kinds drawn by the cartoon kit (island/toon.gd): kind -> Toon function.
const TOON_GEN := {
	"house": "house", "villa": "villa", "midrise": "midrise", "skyscraper": "skyscraper", "mall": "mall",
	"stadium": "stadium", "tv_tower": "tv_tower", "crude_tank": "crude_tank", "column": "column",
	"cracker": "cracker", "flare": "flare", "sphere_tank": "sphere_tank", "pipe_rack": "pipe_rack",
	"power_hall": "power_hall", "chimney": "chimney", "cooling_tower": "cooling_tower",
	"transformer": "transformer", "desal": "desal", "water_tank": "water_tank", "sam": "sam",
	"bunker": "bunker", "tank_vehicle": "tank_vehicle", "barracks": "barracks", "radar_sphere": "radar_sphere",
	"tanker": "tanker", "cargo": "cargo", "frigate": "frigate", "boat": "boat",
}


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
	if TOON_GEN.has(kind):
		Callable(Toon, TOON_GEN[kind]).call(mb, sz, sink, col, r)
		mb.xform = Transform3D.IDENTITY
		return
	match kind:
		"radar_base":
			Arch.house(mb, sz, sink, col, r)
		"courtyard":
			Arch.courtyard(mb, sz, sink, col, r)
		"midrise":
			Arch.midrise(mb, sz, sink, col, r)
		"tower":
			Arch.tower(mb, sz, sink, col, r)
		"souq":
			Arch.souq(mb, sz, sink, col, r)
		"sts_crane":
			Arch.sts_crane(mb, col)
		"rtg":
			Arch.rtg(mb, sz, col)
		"ship":
			Arch.ship(mb, sz, r)
		"has":
			Arch.has(mb, sz, sink, col)
		"tank", "water_tank":
			Arch.tank(mb, sz, sink, col, kind == "tank")
		"stack":
			Arch.stack(mb, sz, sink)
		"turbine_hall":
			Arch.turbine_hall(mb, sz, sink, col)
		"desal":
			Arch.desal(mb, sz, sink, col)
		"jetty":
			Arch.jetty(mb, sz, terrain, mb.xform)
		"beacon":
			Arch.beacon(mb, sz, sink, col)
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
			Arch.warehouse(mb, sz, sink, col)
		"containers":
			Arch.container_block(mb, sz, r)
		"ctower":
			_box_walls(mb, Vector3.ZERO, Vector3(sz.x * 0.65, sz.y - 0.003, sz.z * 0.65), sink, col, false)
			mb.cylinder(Vector3(0, sz.y - 0.003, 0), sz.x * 0.62, sz.x * 0.75, 0.0024, 8, Color(0.22, 0.32, 0.38), false)
			mb.cylinder(Vector3(0, sz.y - 0.0006, 0), sz.x * 0.8, sz.x * 0.7, 0.0006, 8, col)
			mb.cylinder(Vector3(0, sz.y, 0), 0.0001, 0.0001, 0.003, 4, Color(0.8, 0.2, 0.2))
			mb.box(Vector3(0.006, (0.0045 - sink) * 0.5, 0), Vector3(0.008, 0.0045 + sink, 0.0065), col, true)
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
			# mesh authored nose +x, 6.2 mm long / 7.2 mm span -> 15 m x 10 m (x the toy factor)
			var jk := sz.z / Scale.m(15.0)
			mb.xform = mb.xform * Transform3D(Basis.from_scale(Vector3(1.21, 1.0, 0.69) * jk), Vector3.ZERO)
			_jet(mb, col)
		"mast":
			mb.cylinder(Vector3(0, -sink, 0), 0.0011, 0.0006, sz.y + sink, 6, col)
		"launcher_truck":
			mb.box(Vector3(0, (sz.y * 0.45 - sink) * 0.5, 0), Vector3(sz.x, sz.y * 0.45 + sink, sz.z), col)
			mb.box(Vector3(sz.x * 0.38, sz.y * 0.6, 0), Vector3(sz.x * 0.22, sz.y * 0.35, sz.z * 0.92), col.lightened(0.06))
			for k in 2:
				mb.box(Vector3(-sz.x * 0.1, sz.y * (0.62 + k * 0.22), 0), Vector3(sz.x * 0.66, sz.y * 0.2, sz.z * 0.85), col.darkened(0.12))
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
	if s.kind in ["tank", "water_tank", "silo", "silo_open", "mast", "lighthouse", "stack", "beacon", "crude_tank", "column", "flare",
			"chimney", "cooling_tower", "tv_tower", "sphere_tank", "bunker", "radar_sphere"]:
		mb.cylinder(Vector3(0, -s.sink, 0), sz.x * 0.5, sz.x * 0.45, s.sink + stub, 10, col)
	elif s.kind in ["jet", "containers", "launcher_truck", "crane", "sts_crane", "rtg", "sam", "tank_vehicle", "pipe_rack", "transformer", "cracker", "jetty", "pier"]:
		mb.box(Vector3(0, 0.0003, 0), Vector3(sz.x * 0.7, 0.0006, sz.z * 0.7), Color(0.12, 0.11, 0.10))
	elif s.kind in SHIP_KINDS:
		# burnt hull settled at the waterline, broken in two
		mb.box(Vector3(sz.x * 0.22, 0.0002, 0), Vector3(sz.x * 0.42, 0.0012, sz.z * 0.8), Color(0.12, 0.11, 0.10))
		mb.box(Vector3(-sz.x * 0.25, -0.0002, 0), Vector3(sz.x * 0.4, 0.0010, sz.z * 0.8), Color(0.16, 0.14, 0.12))
	else:
		# broken wall stubs (two per side, uneven) on a dark rubble floor
		var hx := sz.x * 0.5
		var hz := sz.z * 0.5
		var t := 0.0007
		for k in 2:
			var f0 := (k + 0.5) * 0.5
			var hh := stub * r.randf_range(0.35, 1.0)
			mb.box(Vector3(-hx + sz.x * f0 * 0.5 + sz.x * 0.25 * k, (hh - s.sink) * 0.5, -hz + t * 0.5), Vector3(sz.x * 0.45, hh + s.sink, t), col)
			hh = stub * r.randf_range(0.35, 1.0)
			mb.box(Vector3(-hx + sz.x * f0 * 0.5 + sz.x * 0.25 * k, (hh - s.sink) * 0.5, hz - t * 0.5), Vector3(sz.x * 0.45, hh + s.sink, t), col)
			hh = stub * r.randf_range(0.35, 1.0)
			mb.box(Vector3(-hx + t * 0.5, (hh - s.sink) * 0.5, -hz + sz.z * f0 * 0.5 + sz.z * 0.25 * k), Vector3(t, hh + s.sink, sz.z * 0.45), col)
			hh = stub * r.randf_range(0.35, 1.0)
			mb.box(Vector3(hx - t * 0.5, (hh - s.sink) * 0.5, -hz + sz.z * f0 * 0.5 + sz.z * 0.25 * k), Vector3(t, hh + s.sink, sz.z * 0.45), col)
		mb.box(Vector3(0, 0.0003 - s.sink * 0.5, 0), Vector3(sz.x * 0.95, 0.0006 + s.sink, sz.z * 0.95), Color(0.16, 0.14, 0.12))
		mb.box(Vector3(sz.x * 0.1, 0.0009, -sz.z * 0.1), Vector3(sz.x * 0.5, 0.0012, sz.z * 0.45), col.darkened(0.3))


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
	var hit_tiles := []
	for s in structures:
		if not s.alive or not s.fragile:
			continue
		var d := _footprint_dist(s, center)
		if d > radius:
			continue
		s.alive = false
		changed = true
		if not _struct_tile(s) in hit_tiles:
			hit_tiles.append(_struct_tile(s))
		frags.append_array(_fracture(s, center))
	if changed:
		_rebuild_structures(hit_tiles)
	return frags


## Pre-fractured pieces per destroyed building (the Quest profile lowers it).
static var max_chunks := 64


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
	while nx * ny * nz > max_chunks:
		ny = maxi(1, ny - 1)
		if nx * ny * nz > max_chunks * 0.6:
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
	_add_crater(Vector3(center.x, center.z, radius))
	for name in species:
		var sp: Dictionary = species[name]
		var xfs: Array = sp.xf
		for k in xfs.size():
			if sp.alive[k] == 0:
				continue
			var xf: Transform3D = xfs[k]
			var d := Vector2(xf.origin.x - center.x, xf.origin.z - center.z).length()
			if d < radius * 1.15:
				sp.alive[k] = 0
				_set_veg_xf(sp, k, Transform3D(Basis().scaled(Vector3.ONE * 1e-5), xf.origin))
				if name == "palm" or name == "acacia":
					burnt.append({"pos": xf.origin + Vector3(0, 0.002, 0), "half": Vector3(0.0003, 0.0022, 0.0003), "col": Color(0.18, 0.14, 0.11)})
			elif d < radius * 2.0:
				var ny := terrain.height_at(xf.origin.x, xf.origin.z) - 0.0004
				xf.origin.y = ny
				xfs[k] = xf
				_set_veg_xf(sp, k, xf)
	# re-drape the touched groups over the next frames (one per frame, see _process)
	for g in drapes_near(Vector2(center.x, center.z), radius * 1.3):
		if not g in _pending_drapes:
			_pending_drapes.append(g)
	return burnt


# ======================================================================================
# draped surfaces (roads, runway, aprons) — follow the faceted terrain exactly
# ======================================================================================

var craters: Array[Vector3] = []      # (x, z, radius): paving is broken inside
var designators: Array[Label3D] = []


## Craters in a 2.5 cm grid: _in_crater() is called for every draped vertex, so a
## linear scan over all craters made every re-drape slower as craters accumulated.
const CRATER_CELL := 0.025
var _crater_grid := {}


func _in_crater(p: Vector2, jag := 1.0) -> bool:
	var cx := int(floor(p.x / CRATER_CELL))
	var cz := int(floor(p.y / CRATER_CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not _crater_grid.has(key):
				continue
			for c in (_crater_grid[key] as Array):
				if Vector2(c.x, c.y).distance_to(p) < c.z * 0.82 * jag:
					return true
	return false


func _add_crater(c: Vector3) -> void:
	craters.append(c)
	var key := Vector2i(int(floor(c.x / CRATER_CELL)), int(floor(c.y / CRATER_CELL)))
	if not _crater_grid.has(key):
		_crater_grid[key] = []
	(_crater_grid[key] as Array).append(c)


func _index_group(nm: String) -> void:
	var cells := {}
	for n in (_group_nodes.get(nm, []) as Array):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or (mi.mesh as ArrayMesh).get_surface_count() == 0:
			continue
		var verts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in verts:
			cells[Vector2i(int(floor(v.x / 0.01)), int(floor(v.z / 0.01)))] = true
	_group_cells[nm] = cells


## The drape groups with geometry within r of c (1 cm cells).
func drapes_near(c: Vector2, r: float) -> Array:
	var out := []
	for nm in DRAPE_GROUPS:
		var cells: Dictionary = _group_cells.get(nm, {})
		var hit := false
		for cz in range(int(floor((c.y - r) / 0.01)), int(floor((c.y + r) / 0.01)) + 1):
			for cx in range(int(floor((c.x - r) / 0.01)), int(floor((c.x + r) / 0.01)) + 1):
				if cells.has(Vector2i(cx, cz)):
					hit = true
					break
			if hit:
				break
		if hit:
			out.append(nm)
	return out


func paving_at(p: Vector2, r: float) -> bool:
	var L := layout
	if L.road_distance(p) < IslandLayout.ROAD_W * 0.5 + r * 0.6:
		return true
	return L.inside_base(p, -0.01) and L.infrastructure_distance(p) < r * 0.6


## Draped surfaces in groups, so a crater re-drapes only the groups it touches
## (re-draping everything took ~90 ms per impact on desktop, ~3x on Quest).
const DRAPE_GROUPS := ["roads", "runway", "taxi", "concrete", "patrol", "tracks"]
var _group_nodes := {}      # group -> [nodes]
var _group_cells := {}      # group -> {Vector2i(1 cm cell): true}
var _cur_group: Array = []
var _pending_drapes: Array = []


func _build_drapes(only: Array = []) -> void:
	for nm in DRAPE_GROUPS:
		if not only.is_empty() and not nm in only:
			continue
		for n in (_group_nodes.get(nm, []) as Array):
			if is_instance_valid(n):
				(n as Node).queue_free()
		_cur_group = []
		call("_drape_" + nm)
		_group_nodes[nm] = _cur_group
		if not _group_cells.has(nm):
			_index_group(nm)
	drape_mi.clear()
	for nm in DRAPE_GROUPS:
		for n in (_group_nodes.get(nm, []) as Array):
			if n is MeshInstance3D and is_instance_valid(n):
				drape_mi.append(n)


func _drape_roads() -> void:
	var L := layout
	var rd := L.runway_dir()
	var north := Vector2(rd.y, -rd.x)
	var shader := load("res://island/marking.gdshader")
	# roads (8 m two-lane)
	var rb := MeshBuilder.new()
	for r in L.road_samples():
		_ribbon(rb, r, IslandLayout.ROAD_W, 0.00032)
	_add_drape(rb, shader, 0, 0.0)


func _drape_runway() -> void:
	var L := layout
	var rd := L.runway_dir()
	var north := Vector2(rd.y, -rd.x)
	var shader := load("res://island/marking.gdshader")
	# runway 600 x 25 m with ICAO-style markings
	var rwb := MeshBuilder.new()
	_rect_grid(rwb, L.runway_center, rd, Vector2(L.runway_len, L.runway_w), 0.0005)
	_add_drape(rwb, shader, 1, L.runway_len)
	_build_designators()


func _drape_taxi() -> void:
	var L := layout
	var rd := L.runway_dir()
	var north := Vector2(rd.y, -rd.x)
	var shader := load("res://island/marking.gdshader")
	# parallel taxiway + end/middle connectors (15 m, yellow centreline)
	var tb := MeshBuilder.new()
	_rect_grid(tb, L.runway_center + north * L.taxi_offset, rd, Vector2(L.runway_len - Scale.m(20.0), L.taxi_w), 0.00045)
	for along in [-L.runway_len * 0.5 + Scale.m(20.0), 0.0, L.runway_len * 0.5 - Scale.m(20.0)]:
		var c: Vector2 = L.runway_center + rd * along + north * L.taxi_offset * 0.5
		_rect_grid(tb, c, north, Vector2(L.taxi_offset - L.runway_w * 0.5 - L.taxi_w * 0.5 + Scale.m(4.0), L.taxi_w), 0.00042)
	_add_drape(tb, shader, 4, 0.0)


func _drape_concrete() -> void:
	var L := layout
	var rd := L.runway_dir()
	var north := Vector2(rd.y, -rd.x)
	var shader := load("res://island/marking.gdshader")
	# apron, silo pad, HAS links, plant yard (concrete)
	var cb := MeshBuilder.new()
	_rect_grid(cb, L.apron_center, rd, L.apron_size, 0.0004)
	_rect_grid(cb, L.apron_center - north * (L.apron_size.y * 0.5 + Scale.m(5.0)), north, Vector2(Scale.m(12.0), Scale.m(40.0)), 0.00041)
	_rect_grid(cb, L.silo_center, rd, Vector2(Scale.m(150.0), Scale.m(80.0)), 0.0004)
	for st in structures:
		if st.has("link"):
			var lk: Array = st.link
			var p0: Vector2 = lk[0]
			var p1: Vector2 = lk[1]
			_rect_grid(cb, (p0 + p1) * 0.5, (p1 - p0).normalized(), Vector2(p0.distance_to(p1), Scale.m(16.0)), 0.00041)
	_rect_grid(cb, L.plant_center, Vector2.RIGHT, L.plant_size, 0.0004)
	_rect_grid(cb, Vector2((L.harbour_x0 + L.harbour_x1) * 0.5, (L.quay_land_z + 0.002 + L.quay_z) * 0.5), Vector2.RIGHT, Vector2(L.harbour_x1 - L.harbour_x0, L.quay_z - L.quay_land_z - 0.002), 0.0, IslandTerrain.SEA + L.quay_height + 0.00035)
	_add_drape(cb, shader, 2, 0.0)


func _drape_patrol() -> void:
	var L := layout
	var rd := L.runway_dir()
	var north := Vector2(rd.y, -rd.x)
	var shader := load("res://island/marking.gdshader")
	# base perimeter: fence (with gates where roads cross) + inner patrol road
	var f := L.base_frame()
	var corners := [Vector2(f.along0, f.lat0), Vector2(f.along1, f.lat0), Vector2(f.along1, f.lat1), Vector2(f.along0, f.lat1)]
	var ring := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 5:
		var a2: Vector2 = corners[k % 4]
		var b2: Vector2 = corners[(k + 1) % 4]
		if k == 4:
			break
		var n := int(ceil(a2.distance_to(b2) / 0.003))
		for i in n:
			var q := a2.lerp(b2, float(i) / n)
			ring.append(L.base_world(q.x, q.y))
			var qi := Vector2(clampf(q.x, f.along0 + 0.005, f.along1 - 0.005), clampf(q.y, f.lat0 + 0.005, f.lat1 - 0.005))
			inner.append(L.base_world(qi.x, qi.y))
	ring.append(ring[0])
	inner.append(inner[0])
	var pr := MeshBuilder.new()
	var land_inner := PackedVector2Array()
	for q in inner:
		land_inner.append(q)
	_ribbon(pr, land_inner, Scale.m(6.0), 0.0003, true)
	_add_drape(pr, shader, 5, 0.0)
	_build_fence(ring)


func _drape_tracks() -> void:
	var L := layout
	var rd := L.runway_dir()
	var north := Vector2(rd.y, -rd.x)
	var shader := load("res://island/marking.gdshader")
	# desert tyre tracks (pairs of ruts, multiply-blended)
	var trk := MeshBuilder.new()
	for t in L.tracks:
		var pts := IslandLayout.catmull(t, 0.003)
		for side in [-1.0, 1.0]:
			var off := PackedVector2Array()
			for i in pts.size():
				var tng := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
				off.append(pts[i] + Vector2(-tng.y, tng.x) * side * Scale.m(1.0))
			_ribbon(trk, off, Scale.m(1.0), 0.00018, true)
	var tm := ShaderMaterial.new()
	tm.shader = load("res://island/track.gdshader")
	var tmi := MeshInstance3D.new()
	tmi.name = "Tracks"
	tmi.mesh = trk.commit(null, tm)
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tmi)
	_cur_group.append(tmi)


func _build_fence(ring: PackedVector2Array) -> void:
	var fb := MeshBuilder.new()
	var pb := MeshBuilder.new()
	var h := Scale.m(2.5)
	var wire := Color(0.30, 0.31, 0.32)
	var post_acc := 0.0
	for i in ring.size() - 1:
		var a := ring[i]
		var b := ring[i + 1]
		var m := (a + b) * 0.5
		if _hs(m.x, m.y) < 0.0015 or not terrain.is_inside(m.x, m.y, 0.01):
			continue
		if layout.road_distance(m) < IslandLayout.ROAD_W * 1.2 or _in_crater(m):
			continue
		if IslandLayout._rect_dist(m, layout.silo_center, layout.runway_dir(), Vector2(Scale.m(78.0), Scale.m(43.0))) < 0.0:
			continue
		var A := Vector3(a.x, terrain.height_at(a.x, a.y), a.y)
		var B := Vector3(b.x, terrain.height_at(b.x, b.y), b.y)
		var up := Vector3(0, h, 0)
		var n := (B - A).cross(Vector3.UP)
		fb.tri_out(A, B, B + up, wire, n)
		fb.tri_out(A, B + up, A + up, wire, n)
		fb.tri_out(A, B, B + up, wire, -n)
		fb.tri_out(A, B + up, A + up, wire, -n)
		post_acc += a.distance_to(b)
		if post_acc > Scale.m(10.0):
			post_acc = 0.0
			pb.box(A + Vector3(0, h * 0.55, 0), Vector3(Scale.m(0.5), h * 1.1, Scale.m(0.5)), Color(0.45, 0.46, 0.46))
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(1, 1, 1, 0.42)
	fm.roughness = 0.8
	var fmi := MeshInstance3D.new()
	fmi.name = "Fence"
	fmi.mesh = fb.commit(null, fm)
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmi)
	_cur_group.append(fmi)
	var pmi := MeshInstance3D.new()
	pmi.name = "FencePosts"
	pmi.mesh = pb.commit(null, MeshBuilder.vc_material(0.7))
	add_child(pmi)
	_cur_group.append(pmi)


## Runway designators (heading 099/279 -> "10" / "28"), painted flat.
func _build_designators() -> void:
	for d in designators:
		d.queue_free()
	designators.clear()
	var L := layout
	var rd := L.runway_dir()
	for e in [[-1.0, "10"], [1.0, "28"]]:
		var sgn: float = e[0]
		var c := L.runway_center + rd * sgn * (L.runway_len * 0.5 - Scale.m(48.0))
		if _in_crater(c):
			continue
		var lb := Label3D.new()
		lb.text = e[1]
		lb.font_size = 96
		lb.pixel_size = Scale.m(9.0) / 96.0
		lb.outline_size = 0
		lb.modulate = Color(0.93, 0.93, 0.92)
		lb.shaded = true
		lb.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		var upv := rd * -sgn
		var theta := atan2(-upv.x, -upv.y)
		lb.basis = Basis(Vector3.UP, theta) * Basis(Vector3.RIGHT, -PI * 0.5)
		lb.position = Vector3(c.x, terrain.height_at(c.x, c.y) + 0.0006, c.y)
		add_child(lb)
		designators.append(lb)


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
	_cur_group.append(mi)


func _ribbon(mb: MeshBuilder, pts: PackedVector2Array, width: float, lift: float, land_only := false) -> void:
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
		var mid := (c + pts[maxi(s - 1, 0)]) * 0.5
		var skip := _in_crater(mid, 0.85 + 0.3 * _hash01(s))
		if land_only and (_hs(mid.x, mid.y) < 0.0012 or not terrain.is_inside(mid.x, mid.y, 0.008)):
			skip = true
		if s > 0 and not skip:
			mb.tri_out(prev_l, L, C, tint, Vector3.UP, Vector2(prev_u, 1), Vector2(dist, 1), Vector2(dist, 0))
			mb.tri_out(prev_l, C, prev_c, tint, Vector3.UP, Vector2(prev_u, 1), Vector2(dist, 0), Vector2(prev_u, 0))
			mb.tri_out(prev_c, C, R, tint, Vector3.UP, Vector2(prev_u, 0), Vector2(dist, 0), Vector2(dist, -1))
			mb.tri_out(prev_c, R, prev_r, tint, Vector3.UP, Vector2(prev_u, 0), Vector2(dist, -1), Vector2(prev_u, -1))
		prev_l = L; prev_c = C; prev_r = R; prev_u = dist


static func _hash01(n: int) -> float:
	return float(((n * 2654435761) >> 7) & 1023) / 1023.0


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
			var ctr := Vector2((grid[a].x + grid[d].x) * 0.5, (grid[a].z + grid[d].z) * 0.5)
			if _in_crater(ctr, 0.85 + 0.3 * _hash01(i * 31 + j * 17)):
				continue
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


## ~26 triangles: 3-sided trunk + 5 crossed frond cards (both faces).
func _palm_lo_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var trunk := Color(0.55, 0.45, 0.34)
	var crown := Vector3(0.1, 0.8, 0)
	for s in 3:
		var a0 := TAU * s / 3.0
		var a1 := TAU * (s + 1) / 3.0
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		mb.tri_out(d0 * 0.04, d1 * 0.04, crown + d1 * 0.025, trunk, d0 + d1)
		mb.tri_out(d0 * 0.04, crown + d1 * 0.025, crown + d0 * 0.025, trunk, d0 + d1)
	for l in 5:
		var ang := TAU * l / 5.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x) * 0.08
		var tip := crown + dir * 0.4 + Vector3(0, -0.14, 0)
		var mid := crown + dir * 0.2 + Vector3(0, 0.04, 0)
		var g := Color(0.34, 0.48, 0.23)
		mb.tri_out(crown, mid + side, tip, g, Vector3.UP)
		mb.tri_out(crown, tip, mid - side, g, Vector3.UP)
		mb.tri_out(crown, mid + side, tip, g.darkened(0.25), Vector3.DOWN)
		mb.tri_out(crown, tip, mid - side, g.darkened(0.25), Vector3.DOWN)
	return mb.commit()


## ~16 triangles: crossed trunk card + hexagonal flat-top canopy.
func _acacia_lo_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var bark := Color(0.40, 0.33, 0.26)
	for a in [0.0, PI * 0.5]:
		var d := Vector3(cos(a), 0, sin(a)) * 0.04
		mb.tri_out(-d, d, Vector3(0, 0.66, 0), bark, Vector3(-d.z, 0, d.x))
		mb.tri_out(-d, d, Vector3(0, 0.66, 0), bark, Vector3(d.z, 0, -d.x))
	var top := Vector3(0, 0.80, 0)
	var g := Color(0.48, 0.54, 0.30)
	for s in 6:
		var a0 := TAU * s / 6.0
		var a1 := TAU * (s + 1) / 6.0
		var p0 := Vector3(cos(a0) * 0.46, 0.70, sin(a0) * 0.46)
		var p1 := Vector3(cos(a1) * 0.46, 0.70, sin(a1) * 0.46)
		mb.tri_out(top, p0, p1, g, Vector3.UP)
		mb.tri_out(Vector3(0, 0.64, 0), p0, p1, g.darkened(0.3), Vector3.DOWN)
	return mb.commit()


func _shrub_lo_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var c := Color(0.55, 0.56, 0.36)
	var top := Vector3(0, 0.75, 0)
	for s in 4:
		var a0 := TAU * s / 4.0
		var a1 := TAU * (s + 1) / 4.0
		mb.tri_out(top, Vector3(cos(a0), 0.05, sin(a0)), Vector3(cos(a1), 0.05, sin(a1)), c, Vector3.UP)
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


const VEG_TILES := 2          # 2 x 2 spatial tiles per species -> per-tile LOD switching
const LOD_DIST := 0.55        # m camera distance where trees swap to the low mesh
## Quest profile: one MultiMesh per species and level, per-instance LOD in the vertex
## shader (island/veg_lod.gdshader) -> 2 draw calls per species instead of 8.
static var merged_veg := false
## Quest profile: small props (shrubs, grass tufts, rocks) cast no shadows.
static var small_shadows := true
## Quest profile: no grass tufts at all (2200 tiny instances, barely visible at 1:2000).
static var tufts := true
var _veg_shader: Shader


## Build tiled MultiMeshes. `lo` (optional) is drawn beyond LOD_DIST; with
## `cull_far` the species simply disappears beyond `far` (grass tufts).
func _make_species(name: String, hi: Mesh, lo: Mesh, xfs: Array[Transform3D], cols: Array[Color], cull_far := false, far := LOD_DIST) -> void:
	var tiles := 1 if merged_veg else VEG_TILES
	var nt := tiles * tiles
	var buckets: Array = []
	for t in nt:
		buckets.append([])
	var tile_of := PackedInt32Array(); tile_of.resize(xfs.size())
	var local := PackedInt32Array(); local.resize(xfs.size())
	for k in xfs.size():
		var o := xfs[k].origin
		var tx := clampi(int((o.x + 0.5) * tiles), 0, tiles - 1)
		var tz := clampi(int((o.z + 0.5) * tiles), 0, tiles - 1)
		var t := tz * tiles + tx
		tile_of[k] = t
		local[k] = (buckets[t] as Array).size()
		(buckets[t] as Array).append(k)
	var mm_hi: Array[MultiMesh] = []
	var mm_lo: Array[MultiMesh] = []
	for t in nt:
		var ids: Array = buckets[t]
		for lod in 2:
			var mesh: Mesh = hi if lod == 0 else lo
			if mesh == null:
				if lod == 1:
					mm_lo.append(null)
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = ids.size()
			for i in ids.size():
				mm.set_instance_transform(i, xfs[ids[i]])
				mm.set_instance_color(i, cols[ids[i]])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "MM_%s_t%d_%s" % [name, t, "hi" if lod == 0 else "lo"]
			mmi.multimesh = mm
			mmi.material_override = veg_mat
			if merged_veg:
				if _veg_shader == null:
					_veg_shader = load("res://island/veg_lod.gdshader")
				var vm := ShaderMaterial.new()
				vm.shader = _veg_shader
				if lod == 0 and (lo != null or cull_far):
					vm.set_shader_parameter("lod_end", far)
				elif lod == 1:
					vm.set_shader_parameter("lod_begin", far)
				mmi.material_override = vm
				if lod == 1:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if name == "shrub" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			elif lod == 0 and (lo != null or cull_far):
				mmi.visibility_range_end = far
			elif lod == 1:
				mmi.visibility_range_begin = far
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if name == "shrub" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if name == "tuft" or (not small_shadows and name in ["shrub", "rock"]):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			if lod == 0:
				mm_hi.append(mm)
			else:
				mm_lo.append(mm)
	var alive := PackedByteArray()
	alive.resize(xfs.size())
	alive.fill(1)
	species[name] = {"xf": xfs, "alive": alive, "tile": tile_of, "local": local, "hi": mm_hi, "lo": mm_lo, "mesh_hi": hi, "mesh_lo": lo}


func _set_veg_xf(sp: Dictionary, k: int, xf: Transform3D) -> void:
	var t: int = sp.tile[k]
	var i: int = sp.local[k]
	(sp.hi[t] as MultiMesh).set_instance_transform(i, xf)
	var lo: MultiMesh = sp.lo[t] if (sp.lo as Array).size() > t else null
	if lo:
		lo.set_instance_transform(i, xf)


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
		var s := rng.randf_range(0.0058, 0.0082)       # date palm 11-16 m
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		b = b.rotated(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.12))
		var y := terrain.height_at(p.x, p.y) - 0.0004
		palms.append(Transform3D(b.scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)))
		var tint := rng.randf_range(0.88, 1.1)
		palm_c.append(Color(tint, tint * rng.randf_range(0.96, 1.04), tint * 0.95))
		placed.append({"kind": "palm", "pos": Vector3(p.x, y, p.y), "water_ok": false, "sink": 0.0004, "ground_min": y + 0.0004})
		terrain.stamp_ao(p, 0.0035, 0.45)
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
	_make_species("palm", _palm_mesh(), _palm_lo_mesh(), palms, palm_c)

	# acacias on the dry inland plains
	var aca: Array[Transform3D] = []
	var aca_c: Array[Color] = []
	for k in 4000:
		var p := Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.34, 0.34))
		if k % 2 == 0:
			# half the candidates are drawn along the wadis (trees follow the water)
			var w: PackedVector2Array = L.wadis[rng.randi() % L.wadis.size()]
			var seg := rng.randi() % (w.size() - 1)
			p = w[seg].lerp(w[seg + 1], rng.randf()) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * IslandLayout.WADI_W * 1.4
		var hs := _hs(p.x, p.y)
		if hs < 0.0025 or hs > 0.03:
			continue
		var wet := terrain.wadi_at(p.x, p.y)
		if rng.randf() > 0.12 + wet * 0.88:
			continue
		if L.inside_base(p, 0.005):
			continue
		if p.distance_to(L.town_center) < L.town_radius * 1.1:
			continue
		if L.lush_at(p.x, p.y) > 0.5:
			continue
		if not _veg_ok(p, 0.0025, 0.86, 0.004) or not _spacing_ok(aca, p, 0.0055) or not _spacing_ok(palms, p, 0.004):
			continue
		var s := rng.randf_range(0.0035, 0.005)        # acacia 6-8 m
		var y := terrain.height_at(p.x, p.y) - 0.0004
		aca.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.1), s)), Vector3(p.x, y, p.y)))
		var t := rng.randf_range(0.85, 1.1)
		aca_c.append(Color(t, t, t * 0.95))
		placed.append({"kind": "acacia", "pos": Vector3(p.x, y, p.y), "water_ok": false, "sink": 0.0004, "ground_min": y + 0.0004})
		terrain.stamp_ao(p, 0.003, 0.4)
		if aca.size() >= 220:
			break
	_make_species("acacia", _acacia_mesh(), _acacia_lo_mesh(), aca, aca_c)

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
		if L.infrastructure_distance(p) < 0.0025 or not _footprint_clear(p, 0.001) or L.inside_base(p, 0.0):
			continue
		var wet2 := maxf(terrain.wadi_at(p.x, p.y), L.lush_at(p.x, p.y))
		if rng.randf() > 0.35 + wet2 * 0.65:
			continue
		var s := rng.randf_range(0.0005, 0.0009)       # saltbush / calotropis 2-3.5 m
		var y := terrain.height_at(p.x, p.y) - 0.0003
		sh.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s)), Vector3(p.x, y, p.y)))
		var t := rng.randf_range(0.8, 1.15)
		var lu := L.lush_at(p.x, p.y)
		sh_c.append(Color(t * (1.0 - lu * 0.15), t * (1.0 + lu * 0.05), t * 0.9 * (1.0 - lu * 0.1)))
		placed.append({"kind": "shrub", "pos": Vector3(p.x, y, p.y), "water_ok": false, "sink": 0.0003, "ground_min": y + 0.0003})
		if sh.size() >= 1400:
			break
	_make_species("shrub", _shrub_mesh(), _shrub_lo_mesh(), sh, sh_c)

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
		var s := rng.randf_range(0.0006, 0.001)         # grass clumps ~1.5 m
		var y := terrain.height_at(p.x, p.y) - 0.0002
		tf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(p.x, y, p.y)))
		var t := rng.randf_range(0.85, 1.12)
		tf_c.append(Color(t, t, t * 0.95))
		placed.append({"kind": "tuft", "pos": Vector3(p.x, y, p.y), "water_ok": false, "sink": 0.0002, "ground_min": y + 0.0002})
		if tf.size() >= 2200:
			break
	if tufts:
		_make_species("tuft", _tuft_mesh(), null, tf, tf_c, true, 0.6)

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
		var s := rng.randf_range(0.0008, 0.003) * (1.6 if rng.randf() < 0.08 else 1.0)
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
	_make_species("rock", _rock_mesh(17), null, rk, rk_c)


func _spacing_ok(list: Array[Transform3D], p: Vector2, d: float) -> bool:
	for xf in list:
		if absf(xf.origin.x - p.x) < d and absf(xf.origin.z - p.y) < d:
			if Vector2(xf.origin.x, xf.origin.z).distance_to(p) < d:
				return false
	return true


# ======================================================================================
# boats
# ======================================================================================

func _place_buoys() -> void:
	# IALA region A: red to port, green to starboard when entering (heading north)
	var L := layout
	var gate_z := L.basin_z + Scale.m(30.0)
	var cx := (L.harbour_x0 + L.harbour_x1) * 0.5
	var red := Color(0.80, 0.18, 0.14)
	var green := Color(0.15, 0.55, 0.28)
	for e in [[cx - Scale.m(40.0), 0.0, red], [cx - Scale.m(46.0), Scale.m(45.0), red], [cx + Scale.m(30.0), 0.0, green], [cx + Scale.m(36.0), Scale.m(45.0), green]]:
		var bx: float = e[0]
		var bz: float = gate_z + float(e[1])
		if _hs(bx, bz) > -0.002:
			continue
		var mb := MeshBuilder.new()
		var col: Color = e[2]
		mb.cylinder(Vector3(0, -Scale.m(1.0), 0), Scale.m(1.2), Scale.m(1.0), Scale.m(3.0), 8, col)
		mb.cylinder(Vector3(0, Scale.m(2.0), 0), Scale.m(0.25), Scale.m(0.25), Scale.m(2.0), 4, Color(0.2, 0.2, 0.2))
		if col.r > 0.5:
			mb.cylinder(Vector3(0, Scale.m(4.0), 0), Scale.m(0.8), Scale.m(0.8), Scale.m(1.2), 6, col)
		else:
			mb.cylinder(Vector3(0, Scale.m(4.0), 0), Scale.m(0.8), 0.0, Scale.m(1.6), 6, col)
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit(null, MeshBuilder.vc_material(0.5))
		mi.position = Vector3(bx, IslandTerrain.SEA, bz)
		add_child(mi)
		boats.append({"node": mi, "phase": rng.randf() * TAU, "rot": 0.0})
		placed.append({"kind": "buoy", "pos": mi.position, "water_ok": true, "sink": 0.0, "ground_min": 0.0})


func _process(_delta: float) -> void:
	if not _pending_drapes.is_empty():
		_build_drapes([_pending_drapes.pop_front()])
	_warm_ruins(6)
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
	var veg_hi := 0
	var veg_lo := 0
	for name in species:
		var sp: Dictionary = species[name]
		var n: int = (sp.xf as Array).size()
		var th := (sp.mesh_hi as ArrayMesh).surface_get_array_len(0) / 3
		out["%s_count" % name] = n
		out["%s_tris_hi" % name] = th
		veg_hi += th * n
		if sp.mesh_lo:
			var tl := (sp.mesh_lo as ArrayMesh).surface_get_array_len(0) / 3
			out["%s_tris_lo" % name] = tl
			veg_lo += tl * n
		elif name != "tuft":
			veg_lo += th * n
	out["vegetation_all_hi"] = veg_hi
	out["vegetation_all_lo"] = veg_lo
	var dr := 0
	for m in drape_mi:
		if m.mesh and (m.mesh as ArrayMesh).get_surface_count() > 0:
			dr += (m.mesh as ArrayMesh).surface_get_array_len(0) / 3
	out["drapes"] = dr
	return out


func structure_count() -> int:
	return structures.size()
