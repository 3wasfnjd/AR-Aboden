class_name DebrisSystem
extends Node3D
## Lightweight rigid-box debris that collides with the terrain height field.
##
## Why not RigidBody3D: at 1:2000 the fragments are 1-4 mm. Jolt/Godot physics
## use collision margins/sleep thresholds tuned for metre-scale objects, the
## terrain changes every impact (a HeightMapShape3D/ConcavePolygonShape3D would
## have to be rebuilt), and hundreds of bodies cost a lot on Quest's CPU. Here
## each fragment is an oriented box; its 8 corners are tested against
## IslandTerrain.height_at() and resolved with an impulse (restitution +
## Coulomb friction + angular response), with sleeping. All fragments of a kind
## render in ONE MultiMesh draw call.

const MAX_BODIES := 480
## Live cap (<= MAX_BODIES). The Quest profile lowers it to 200 (GDScript physics on the headset CPU).
static var cap := MAX_BODIES
## Settled debris: a body asleep for BAKE_AFTER s leaves the simulation and is written
## ONCE into a static MultiMesh (ring buffer of SETTLED_MAX, the oldest are reused), so
## fragments stay on the island forever at no per-frame cost.
const SETTLED_MAX := 1500
const BAKE_AFTER := 0.5
## CPU budget (each awake body costs ~20-40 us of GDScript per step on desktop, ~3x on
## Quest): beyond max_awake, the oldest awake bodies that are past MIN_AGE_FREEZE are
## frozen where they are (snapped onto the ground) and baked; nothing flies longer
## than max_age. The Quest profile lowers max_awake.
static var max_awake := 400
static var max_age := 6.0
const MIN_AGE_FREEZE := 0.9
const SUBSTEPS := 1

var terrain: IslandTerrain
var props: IslandProps        # optional: standing buildings act as box colliders
var gravity := 0.5
var fx: FxSystem

var bodies: Array[Dictionary] = []
var mm_box: MultiMesh
var mm_rock: MultiMesh
var stats_contacts := 0
var mm_settled_box: MultiMesh
var mm_settled_rock: MultiMesh
## settled: {p, b, h, col, kind, slot} (slot = instance index in its static MultiMesh)
var settled: Array[Dictionary] = []
var _free_box: Array[int] = []
var _free_rock: Array[int] = []
var _next_box := 0
var _next_rock := 0
var _dirty := true


func setup(t: IslandTerrain, g: float, fx_sys: FxSystem) -> void:
	terrain = t
	gravity = g
	fx = fx_sys
	var mat := MeshBuilder.vc_material(0.85)
	var bm := MeshBuilder.new()
	bm.box(Vector3.ZERO, Vector3(2, 2, 2), Color.WHITE, false, Color(-1, 0, 0), true)
	mm_box = _mm(bm.commit(), mat, "FragBoxes")
	var rm := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 5
	rm.rock(Vector3.ZERO, Vector3(1.15, 1.0, 1.1), Color.WHITE, r, 0.3)
	mm_rock = _mm(rm.commit(), mat, "FragRocks")
	mm_settled_box = _mm(mm_box.mesh, mat, "SettledBoxes", SETTLED_MAX)
	mm_settled_rock = _mm(mm_rock.mesh, mat, "SettledRocks", SETTLED_MAX)
	mm_settled_box.visible_instance_count = -1
	mm_settled_rock.visible_instance_count = -1
	for k in SETTLED_MAX:
		mm_settled_box.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		mm_settled_rock.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))


func _mm(mesh: Mesh, mat: Material, nm: String, count := MAX_BODIES) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mm


## kind: 0 = soil/rock chunk, 1 = building fragment (box)
func spawn(pos: Vector3, basis: Basis, half: Vector3, vel: Vector3, ang: Vector3, col: Color, kind: int) -> void:
	if bodies.size() >= mini(cap, MAX_BODIES):
		# make room: bake the oldest sleeping body into the static set (it stays
		# visible), or drop the oldest flying one
		var victim := 0
		for k in bodies.size():
			if bodies[k].sleep:
				victim = k
				break
		if bodies[victim].sleep:
			_bake(bodies[victim])
		bodies.remove_at(victim)
	var h2 := half.length_squared()
	_dirty = true
	bodies.append({
		"p": pos, "v": vel, "b": basis.orthonormalized(), "w": ang, "h": half, "col": col,
		"kind": kind, "inv_i": 1.0 / maxf(0.45 * h2, 1e-12), "sleep": false, "still": 0.0,
		"wet": false, "age": 0.0, "r": half.length(), "slept": 0.0,
	})


func wake_near(center: Vector3, radius: float) -> void:
	for b in bodies:
		if (b.p as Vector3).distance_to(center) < radius:
			b.sleep = false
			b.still = 0.0
			b.slept = 0.0
	# settled fragments near a new impact go back into the simulation (the ground
	# under them may have changed); beyond the live cap they are blown away
	var k := 0
	while k < settled.size():
		var e: Dictionary = settled[k]
		if (e.p as Vector3).distance_to(center) < radius:
			_unbake(k)
			if bodies.size() < mini(cap, MAX_BODIES):
				spawn(e.p, e.b, e.h, Vector3(0, 0.01, 0), Vector3.ZERO, e.col, e.kind)
			continue
		k += 1


func settled_count() -> int:
	return settled.size()


## Every fragment position (live + settled), for tests.
func all_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for b in bodies:
		out.append(b.p)
	for e in settled:
		out.append(e.p)
	return out


func _bake(b: Dictionary) -> void:
	if settled.size() >= SETTLED_MAX:
		_unbake(0)
	var slot: int
	var mm: MultiMesh
	if b.kind == 1:
		mm = mm_settled_box
		slot = _free_box.pop_back() if not _free_box.is_empty() else _next_box
		_next_box = maxi(_next_box, slot + 1)
	else:
		mm = mm_settled_rock
		slot = _free_rock.pop_back() if not _free_rock.is_empty() else _next_rock
		_next_rock = maxi(_next_rock, slot + 1)
	var bb: Basis = b.b
	var hh: Vector3 = b.h
	mm.set_instance_transform(slot, Transform3D(Basis(bb.x * hh.x, bb.y * hh.y, bb.z * hh.z), b.p))
	mm.set_instance_color(slot, b.col)
	settled.append({"p": b.p, "b": b.b, "h": b.h, "col": b.col, "kind": b.kind, "slot": slot})


func _unbake(k: int) -> void:
	var e: Dictionary = settled[k]
	var mm := mm_settled_box if e.kind == 1 else mm_settled_rock
	mm.set_instance_transform(e.slot, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	if e.kind == 1:
		_free_box.append(e.slot)
	else:
		_free_rock.append(e.slot)
	settled.remove_at(k)


func active_count() -> int:
	var n := 0
	for b in bodies:
		if not b.sleep:
			n += 1
	return n


func step(dt: float) -> void:
	var h := dt / SUBSTEPS
	stats_contacts = 0
	var moved := false
	for _s in SUBSTEPS:
		for b in bodies:
			if b.sleep:
				continue
			_integrate(b, h)
			moved = true
	# bodies asleep long enough leave the simulation into the static MultiMesh;
	# over the awake budget / too old: frozen in place on the ground and baked too
	var awake := 0
	for b in bodies:
		if not b.sleep:
			awake += 1
	var excess := awake - max_awake
	var k := 0
	while k < bodies.size():
		var b: Dictionary = bodies[k]
		var freeze := false
		if not b.sleep and (float(b.age) > max_age or (excess > 0 and float(b.age) > MIN_AGE_FREEZE)):
			freeze = true
			excess -= 1
		if b.sleep:
			b.slept += dt
		if freeze or (b.sleep and b.slept >= BAKE_AFTER):
			if freeze:
				var bp: Vector3 = b.p
				bp.y = maxf(bp.y, terrain.height_at(bp.x, bp.z) + float(b.h.y) * 0.6)
				b.p = bp
			_bake(b)
			bodies.remove_at(k)
			_dirty = true
			continue
		k += 1
	if moved or _dirty:
		_upload()
		_dirty = false


func _integrate(b: Dictionary, dt: float) -> void:
	var p: Vector3 = b.p
	var v: Vector3 = b.v
	var w: Vector3 = b.w
	var bs: Basis = b.b
	var half: Vector3 = b.h
	b.age += dt
	# water: drag + buoyancy, sink slowly to the sea floor
	var in_water := p.y < IslandTerrain.SEA
	var g := gravity
	if in_water:
		if not b.wet:
			b.wet = true
			if fx and v.length() > 0.02:
				fx.splash(Vector3(p.x, IslandTerrain.SEA, p.z), 0.35)
		g *= 0.25
		v *= exp(-7.0 * dt)
		w *= exp(-5.0 * dt)
	else:
		v *= exp(-0.15 * dt)      # light air drag
	v.y -= g * dt
	p += v * dt
	var wl := w.length()
	if wl > 1e-6:
		bs = Basis(w / wl, wl * dt) * bs
		bs = bs.orthonormalized()
	# contacts against the faceted height field
	var ground_c := terrain.height_at(p.x, p.z)
	var contact := false
	if p.y - b.r < ground_c + 0.0005:
		var inv_i: float = b.inv_i
		var deepest := 0.0
		var deep_n := Vector3.UP
		for iter in 1:
			for cx in [-1.0, 1.0]:
				for cy in [-1.0, 1.0]:
					for cz in [-1.0, 1.0]:
						var r := bs * Vector3(half.x * cx, half.y * cy, half.z * cz)
						var c := p + r
						var gh := terrain.height_at(c.x, c.z)
						var pen := gh - c.y
						if pen <= 0.0:
							continue
						contact = true
						stats_contacts += 1
						var n := terrain.normal_at(c.x, c.z)
						var vp := v + w.cross(r)
						var vn := vp.dot(n)
						if pen > deepest:
							deepest = pen
							deep_n = n
						if vn >= 0.0:
							continue
						var rn := r.cross(n)
						var k := 1.0 + inv_i * rn.length_squared()
						var e := 0.22 if absf(vn) > 0.03 else 0.0
						var j := -(1.0 + e) * vn / k
						var imp := n * j
						# Coulomb friction
						var vt := vp - n * vn
						var vtl := vt.length()
						if vtl > 1e-7:
							var tdir := vt / vtl
							var rt := r.cross(tdir)
							var kt := 1.0 + inv_i * rt.length_squared()
							var jt := minf(0.65 * j, vtl / kt)
							imp -= tdir * jt
						v += imp
						w += inv_i * r.cross(imp)
		if deepest > 0.0:
			p += deep_n * deepest * 0.9
		if contact:
			w *= exp(-6.0 * dt)
			v *= exp(-1.5 * dt)
			if v.length() < 0.012:
				# resting contact: kill the rocking that a corner-impulse model produces
				w *= exp(-30.0 * dt)
	# standing buildings: simple box colliders (point vs oriented box)
	if props:
		var hit: Array = props.collide_point(p, b.r * 0.6)
		if not hit.is_empty():
			var n2: Vector3 = hit[0]
			var pen2: float = hit[1]
			p += n2 * pen2
			var vn2 := v.dot(n2)
			if vn2 < 0.0:
				v -= n2 * vn2 * 1.25
				v = v.lerp(n2 * v.dot(n2), 0.25)     # friction on the wall / roof
				w *= 0.6
			if n2.y > 0.7:
				contact = true
	# keep inside the slab; drop anything that falls off the table edge
	if not terrain.is_inside(p.x, p.z, 0.002):
		var fl := Vector2(p.x, p.z)
		fl = fl.normalized() * (IslandTerrain.RADIUS - 0.002)
		p.x = fl.x
		p.z = fl.y
		v.x *= -0.3
		v.z *= -0.3
	# sleeping
	if contact and v.length() < 0.005 and w.length() < 1.5:
		b.still += dt
		if b.still > 0.25:
			b.sleep = true
			b.slept = 0.0
			v = Vector3.ZERO
			w = Vector3.ZERO
	else:
		b.still = 0.0
	# the glass dome holds everything in: a piece reaching it bounces back inside
	var ceil := WeaponFlight.dome_ceiling(p.x, p.z) + WeaponFlight.DOME_MARGIN - 0.002
	var rr := Vector2(p.x, p.z).length()
	var rmax := GlassDome.R - 0.004
	if p.y > ceil or rr > rmax:
		var n := Vector3(p.x, (p.y - IslandTerrain.SEA) / (GlassDome.K * GlassDome.K), p.z).normalized()
		if rr > rmax:
			p.x *= rmax / rr
			p.z *= rmax / rr
		p.y = minf(p.y, maxf(WeaponFlight.dome_ceiling(p.x, p.z) + WeaponFlight.DOME_MARGIN - 0.002, IslandTerrain.SEA))
		var vn := v.dot(n)
		if vn > 0.0:
			v -= n * vn * 1.4
	b.p = p
	b.v = v
	b.w = w
	b.b = bs


func _upload() -> void:
	var nb := 0
	var nr := 0
	for b in bodies:
		var bb: Basis = b.b
		var hh: Vector3 = b.h
		var xf := Transform3D(Basis(bb.x * hh.x, bb.y * hh.y, bb.z * hh.z), b.p)
		if b.kind == 1:
			mm_box.set_instance_transform(nb, xf)
			mm_box.set_instance_color(nb, b.col)
			nb += 1
		else:
			mm_rock.set_instance_transform(nr, xf)
			mm_rock.set_instance_color(nr, b.col)
			nr += 1
	mm_box.visible_instance_count = nb
	mm_rock.visible_instance_count = nr


func clear() -> void:
	bodies.clear()
	while not settled.is_empty():
		_unbake(settled.size() - 1)
	_free_box.clear()
	_free_rock.clear()
	_next_box = 0
	_next_rock = 0
	_upload()
