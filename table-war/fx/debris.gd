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
const SUBSTEPS := 1

var terrain: IslandTerrain
var gravity := 0.5
var fx: FxSystem

var bodies: Array[Dictionary] = []
var mm_box: MultiMesh
var mm_rock: MultiMesh
var stats_contacts := 0


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


func _mm(mesh: Mesh, mat: Material, nm: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = MAX_BODIES
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mm


## kind: 0 = soil/rock chunk, 1 = building fragment (box)
func spawn(pos: Vector3, basis: Basis, half: Vector3, vel: Vector3, ang: Vector3, col: Color, kind: int) -> void:
	if bodies.size() >= MAX_BODIES:
		# recycle the oldest sleeping body (or the oldest)
		var victim := 0
		for k in bodies.size():
			if bodies[k].sleep:
				victim = k
				break
		bodies.remove_at(victim)
	var h2 := half.length_squared()
	bodies.append({
		"p": pos, "v": vel, "b": basis.orthonormalized(), "w": ang, "h": half, "col": col,
		"kind": kind, "inv_i": 1.0 / maxf(0.45 * h2, 1e-12), "sleep": false, "still": 0.0,
		"wet": false, "age": 0.0, "r": half.length(),
	})


func wake_near(center: Vector3, radius: float) -> void:
	for b in bodies:
		if (b.p as Vector3).distance_to(center) < radius:
			b.sleep = false
			b.still = 0.0


func active_count() -> int:
	var n := 0
	for b in bodies:
		if not b.sleep:
			n += 1
	return n


func step(dt: float) -> void:
	var h := dt / SUBSTEPS
	stats_contacts = 0
	for _s in SUBSTEPS:
		for b in bodies:
			if b.sleep:
				continue
			_integrate(b, h)
	_upload()


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
			v = Vector3.ZERO
			w = Vector3.ZERO
	else:
		b.still = 0.0
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
	_upload()
