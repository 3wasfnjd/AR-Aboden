class_name PhysicsTest
extends Node3D
## Ballistic "test shell" fired from the air-base launcher at a point on the
## island: preview arc, flight with smoke trail, impact -> crater + debris +
## building fracture + dust/smoke + flash. Optional slow motion.
##
## Miniature gravity: the island is 1 m on the table; at real g a 2.5 s arc
## would rise ~7.6 m. We use G = 0.5 m/s^2 (≈ g/20, i.e. time runs ~4.4x slower
## than true 1:1 Froude scaling) for EVERYTHING (shell, debris), which reads as
## "big and heavy" like an over-cranked miniature film shot. Flight time is
## picked from distance (2..3 s), launch velocity solved analytically.

const G := 0.5
const CRATER_R := 0.016
const CRATER_D := 0.0055
const BLAST_R := 0.022

var island: Island
var debris: DebrisSystem
var fx: FxSystem

var slow_motion := false
var slow_factor := 0.2
var manual := false            # screenshots/tests drive advance() directly

var shell: MeshInstance3D
var shell_glow: MeshInstance3D
var flying := false
var t_flight := 0.0
var p0 := Vector3.ZERO
var v0 := Vector3.ZERO
var flight_T := 2.5
var target := Vector3.ZERO
var last_impact := Vector3.INF
var impact_count := 0
var _trail_acc := 0.0
var sim_time := 0.0

var preview_mm: MultiMesh
var marker: MeshInstance3D

signal impacted(point: Vector3)


func setup(isl: Island) -> void:
	island = isl
	fx = FxSystem.new()
	fx.name = "Fx"
	add_child(fx)
	debris = DebrisSystem.new()
	debris.name = "Debris"
	add_child(debris)
	debris.setup(island.terrain, G, fx)
	# shell: tiny elongated body + additive tracer glow
	var mb := MeshBuilder.new()
	mb.xform = Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(-0.0012, 0, 0))
	mb.cylinder(Vector3.ZERO, 0.00055, 0.00055, 0.0018, 8, Color(0.35, 0.36, 0.33))
	mb.cylinder(Vector3(0, 0.0018, 0), 0.00055, 0.0, 0.0011, 8, Color(0.6, 0.5, 0.3))
	shell = MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = mb.commit(null, MeshBuilder.vc_material(0.5))
	shell.visible = false
	add_child(shell)
	var glow := SphereMesh.new()
	glow.radius = 0.0009
	glow.height = 0.0018
	glow.radial_segments = 10
	glow.rings = 6
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.75, 0.35)
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.6, 0.2)
	gm.emission_energy_multiplier = 3.0
	glow.material = gm
	shell_glow = MeshInstance3D.new()
	shell_glow.mesh = glow
	shell_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.add_child(shell_glow)
	shell_glow.position = Vector3(-0.0016, 0, 0)
	# trajectory preview dots (one MultiMesh) + target ring
	var dot := SphereMesh.new()
	dot.radius = 0.0011
	dot.height = 0.0022
	dot.radial_segments = 8
	dot.rings = 4
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(1.0, 0.55, 0.2)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = dm
	preview_mm = MultiMesh.new()
	preview_mm.transform_format = MultiMesh.TRANSFORM_3D
	preview_mm.use_colors = true
	preview_mm.mesh = dot
	preview_mm.instance_count = 120
	preview_mm.visible_instance_count = 0
	var pmi := MultiMeshInstance3D.new()
	pmi.name = "Preview"
	pmi.multimesh = preview_mm
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmi.custom_aabb = AABB(Vector3(-1, 0, -1), Vector3(2, 1.5, 2))
	add_child(pmi)
	marker = MeshInstance3D.new()
	marker.name = "TargetMarker"
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)


# ------------------------------------------------------------------------------------

func muzzle() -> Vector3:
	return island.props.launcher_muzzle()


func solve(from: Vector3, to: Vector3) -> Dictionary:
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	var T := clampf(1.6 + dist * 1.6, 2.0, 3.0)
	var g := Vector3(0, -G, 0)
	var v := (to - from - 0.5 * g * T * T) / T
	return {"v": v, "T": T}


func position_at(t: float) -> Vector3:
	return p0 + v0 * t + 0.5 * Vector3(0, -G, 0) * t * t


func aim(tgt: Vector3) -> void:
	target = tgt
	var from := muzzle()
	var sol := solve(from, tgt)
	island.props.aim_launcher(sol.v)
	from = muzzle()
	sol = solve(from, tgt)
	p0 = from
	v0 = sol.v
	flight_T = sol.T
	_show_preview()
	_build_marker(tgt)


func _show_preview() -> void:
	var n := preview_mm.instance_count
	var shown := 0
	for k in n:
		var t := flight_T * float(k) / (n - 1)
		var p := position_at(t)
		if t > 0.2 and p.y < island.surface_at(p.x, p.z):
			break
		var a := 0.9 * (1.0 - 0.6 * float(k) / n)
		var s := 1.0 if k % 2 == 0 else 0.6
		preview_mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * s), p))
		preview_mm.set_instance_color(k, Color(1.0, 0.62, 0.25, a))
		shown += 1
	preview_mm.visible_instance_count = shown


func hide_preview() -> void:
	preview_mm.visible_instance_count = 0
	marker.visible = false


func _build_marker(c: Vector3) -> void:
	var mb := MeshBuilder.new()
	var seg := 40
	var col := Color(1.0, 0.35, 0.18)
	for ring in [[CRATER_R * 0.85, CRATER_R], [0.0016, 0.0026]]:
		var r0: float = ring[0]
		var r1: float = ring[1]
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var pts: Array[Vector3] = []
			for q in [[r0, a0], [r1, a0], [r1, a1], [r0, a1]]:
				var x: float = c.x + cos(q[1]) * q[0]
				var z: float = c.z + sin(q[1]) * q[0]
				pts.append(Vector3(x, island.surface_at(x, z) + 0.0005, z))
			mb.tri_out(pts[0], pts[1], pts[2], col, Vector3.UP)
			mb.tri_out(pts[0], pts[2], pts[3], col, Vector3.UP)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.85)
	marker.mesh = mb.commit(null, m)
	marker.visible = true


func fire(tgt: Vector3) -> void:
	aim(tgt)
	flying = true
	t_flight = 0.0
	shell.visible = true
	shell.global_position = p0
	fx.muzzle(p0, v0.normalized())


func set_slow_motion(on: bool) -> void:
	slow_motion = on


func _physics_process(delta: float) -> void:
	if not manual:
		advance(delta * (slow_factor if slow_motion else 1.0))


## Advance the whole simulation by dt seconds of game time.
func advance(dt: float) -> void:
	sim_time += dt
	var steps := maxi(1, int(ceil(dt / (1.0 / 120.0))))
	var h := dt / steps
	for _i in steps:
		_step_shell(h)
		debris.step(h)
		fx.step(h)


func _step_shell(dt: float) -> void:
	if not flying:
		return
	var t_prev := t_flight
	t_flight += dt
	var p := position_at(t_flight)
	_trail_acc += dt
	if _trail_acc > 0.018:
		_trail_acc = 0.0
		fx.trail(p)
	if t_flight > 0.15 and p.y <= island.surface_at(p.x, p.z):
		# bisection for the exact surface crossing
		var lo := t_prev
		var hi := t_flight
		for _k in 24:
			var mid := (lo + hi) * 0.5
			var q := position_at(mid)
			if q.y > island.surface_at(q.x, q.z):
				lo = mid
			else:
				hi = mid
		_impact(position_at(hi))
		return
	shell.global_position = p
	var vel := v0 + Vector3(0, -G, 0) * t_flight
	if vel.length() > 1e-5:
		shell.global_transform.basis = Basis.looking_at(vel.normalized(), Vector3.UP).rotated(Vector3.UP, 0.0) * Basis(Vector3.UP, PI * 0.5)


func _impact(p: Vector3) -> void:
	flying = false
	shell.visible = false
	hide_preview()
	last_impact = p
	impact_count += 1
	var terr := island.terrain
	var ground := terr.height_at(p.x, p.z)
	var in_water := ground < IslandTerrain.SEA - 0.0015
	var rng := RandomNumberGenerator.new()
	rng.seed = impact_count * 977
	# sample soil colour before scorching
	var soil := terr.color_at(p.x, p.z)
	if in_water:
		fx.splash(p, 2.2)
		fx.explosion(p, 0.6)
		terr.crater(Vector3(p.x, ground, p.z), CRATER_R * 0.8, CRATER_D * 0.5)
	else:
		terr.crater(p, CRATER_R, CRATER_D)
		fx.explosion(p, 1.0)
	debris.wake_near(p, BLAST_R * 2.5)
	# structures inside the blast break into their pre-fractured chunks
	var frags := island.props.blast(p, BLAST_R)
	for f in frags:
		debris.spawn(f.pos, f.basis, f.half, f.vel, f.ang, f.col, 1)
	var burnt := island.props.on_crater(p, CRATER_R)
	for b in burnt:
		var d := ((b.pos as Vector3) - p) * Vector3(1, 0, 1)
		var vel := d.normalized() * rng.randf_range(0.03, 0.08) + Vector3(0, rng.randf_range(0.08, 0.16), 0)
		debris.spawn(b.pos, Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU), b.half, vel, Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8)), b.col, 1)
	# soil / rock ejecta
	var n := 70 if not in_water else 18
	for k in n:
		var a := rng.randf() * TAU
		var spread := rng.randf_range(0.2, 1.0)
		var dir := Vector3(cos(a) * spread, 1.0, sin(a) * spread).normalized()
		var speed := rng.randf_range(0.09, 0.30)
		var vel := Vector3(dir.x * speed * 0.55, dir.y * speed, dir.z * speed * 0.55)
		var s := rng.randf_range(0.0005, 0.0016) * (1.8 if rng.randf() < 0.1 else 1.0)
		var c := soil.darkened(rng.randf_range(0.0, 0.35))
		if rng.randf() < 0.35:
			c = Color(0.20, 0.17, 0.15)
		var start := p + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, CRATER_R * 0.5) + Vector3(0, 0.002, 0)
		debris.spawn(start, Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU), Vector3(s, s * rng.randf_range(0.6, 1.0), s * rng.randf_range(0.7, 1.1)), vel, Vector3(rng.randf_range(-20, 20), rng.randf_range(-20, 20), rng.randf_range(-20, 20)), c, 0)
	impacted.emit(p)
