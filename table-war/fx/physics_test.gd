class_name PhysicsTest
extends Node3D
## The weapons test: shots launched from the PLAYER (their right hand in XR, a fixed
## "player hand" point in front of the table on desktop) at a point on the island, with
## the weapon behaviours of weapons/weapon_table.gd and the paths of weapons/flight.gd.
## Several shots can fly at once (pooled nodes, no per-shot allocation).
##
## Impacts: on LAND a crater + debris + building fracture + dust / fire / smoke + flash +
## boom; in the SEA (deeper than SHALLOW) a water splash only (white column, spray,
## ring ripples, foam, a muffled thump) and the shell vanishes under the surface; in
## very shallow water near the shore a small splash + a wet-sand mark.
##
## Everything is in diorama-local units: this node and the Island are siblings under
## the Diorama, which XR moves / turns / scales onto the real table.
##
## Miniature gravity: the island is 1 m on the table; at real g a 2.5 s arc would rise
## ~7.6 m. G = 0.5 m/s^2 (~ g/20) for EVERYTHING (shells, debris) reads as "big and
## heavy" like an over-cranked miniature film shot.

const G := 0.5
const CRATER_R := 0.016
const CRATER_D := 0.0055
const BLAST_R := 0.022
const MAX_FLIGHTS := 24          # MLRS salvos and cluster bomblets fly together
const SHALLOW := 0.0015          # water shallower than this: shore splash + wet sand
const WET_MARKS := 8
## Desktop "player hand": in front of the table at the hero camera's side, ~0.4 m up.
const DESKTOP_HAND := Vector3(-0.28, 0.42, 0.66)
## Quest profile: fewer soil chunks per blast (debris is GDScript physics on the CPU).
static var ejecta_scale := 1.0

var island: Island
var debris: DebrisSystem
var fx: FxSystem
var sfx: SfxBank
## The Viper's air defence and coastal launchers (game/resistance.gd).
var resistance: Resistance
var _serial := 0

var slow_motion := false
var slow_factor := 0.2
var manual := false            # screenshots/tests drive advance() directly
var weapon := "ballistic"      # used when fire() / aim() get no weapon id

var flights: Array[Dictionary] = []   # {plan, t, w, node, glow, trail_acc}
var flying: bool:
	get:
		return not flights.is_empty() or not _pending.is_empty()
## Queued launches of a salvo: {delay, origin, tgt, wid}
var _pending: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
## Last shot fired (tests / screenshots).
var shell: Node3D
var p0 := Vector3.ZERO
var v0 := Vector3.ZERO
var flight_T := 2.5
var target := Vector3.ZERO
var last_plan := {}
var last_aim_T := 0.0
var last_aim_plan := {}
var last_impact := Vector3.INF
var last_impact_kind := ""
var impact_count := 0
var sim_time := 0.0

var preview_mm: MultiMesh
var marker: MeshInstance3D
var _mat_aim: StandardMaterial3D
var _mat_lock: StandardMaterial3D
var _mat_warn: StandardMaterial3D
## Civilians (people, cars, homes, civilian boats) inside the aimed blast: the ring turns
## yellow when there are any.
var last_marker_civilians := 0
var _pool: Array[Dictionary] = []     # {node, body, glow, glow_mat, wid}
var _meshes := {}                     # weapon id -> body mesh
var _marks: Array[MeshInstance3D] = []
var _mark_age: PackedFloat32Array
var _mark_next := 0
var _mark_mat: StandardMaterial3D

signal impacted(point: Vector3, kind: String)
## A strike jet is back on the deck (its weapon id).
signal sortie_landed(wid: String)
## A strike jet was shot down.
signal jet_lost(wid: String)


func setup(isl: Island) -> void:
	island = isl
	fx = FxSystem.new()
	fx.name = "Fx"
	add_child(fx)
	debris = DebrisSystem.new()
	debris.name = "Debris"
	add_child(debris)
	debris.setup(island.terrain, G, fx)
	debris.props = island.props
	sfx = SfxBank.new()
	sfx.name = "Sfx"
	add_child(sfx)
	resistance = Resistance.new()
	resistance.name = "Resistance"
	add_child(resistance)
	resistance.setup(self)
	for k in MAX_FLIGHTS:
		_pool.append(_make_shell_node(k))
	shell = _pool[0].node
	# trajectory preview dots (one MultiMesh) + target marker (ring + crosshair)
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
	preview_mm.instance_count = 56
	preview_mm.visible_instance_count = 0
	var pmi := MultiMeshInstance3D.new()
	pmi.name = "Preview"
	pmi.multimesh = preview_mm
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmi.custom_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
	add_child(pmi)
	_build_marker()
	_build_wet_marks()


func _make_shell_node(k: int) -> Dictionary:
	var n := Node3D.new()
	n.name = "Shell%d" % k
	n.visible = false
	add_child(n)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(body)
	var glow := SphereMesh.new()
	glow.radius = 0.0009
	glow.height = 0.0018
	glow.radial_segments = 10
	glow.rings = 6
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.75, 0.35)
	glow.material = gm
	var gi := MeshInstance3D.new()
	gi.name = "Glow"
	gi.mesh = glow
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(gi)
	return {"node": n, "body": body, "glow": gi, "glow_mat": gm, "wid": ""}


## Body mesh of a weapon: a cylinder along +X with a nose cone (built once per weapon).
func _shell_mesh(w: Dictionary) -> Mesh:
	var id: String = w.id
	if _meshes.has(id):
		return _meshes[id]
	var L: float = w.length
	var r: float = w.radius
	var mb := MeshBuilder.new()
	mb.xform = Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(-L * 0.5, 0, 0))
	mb.cylinder(Vector3.ZERO, r, r, L * 0.7, 8, w.col)
	mb.cylinder(Vector3(0, L * 0.7, 0), r, 0.0, L * 0.3, 8, (w.col as Color).lightened(0.2))
	if bool(w.get("wings", false)):
		var span := 1.5 if id == "drone" else (0.75 if id == "jet" else 0.9)
		mb.box(Vector3(0, L * 0.45, 0), Vector3(L * span, L * 0.12, r * 0.4), w.col)   # wings
	if id == "jet":
		mb.box(Vector3(0, L * 0.08, r * 1.3), Vector3(L * 0.05, L * 0.18, r * 1.8), (w.col as Color).darkened(0.15))   # tail fin
		mb.box(Vector3(0, L * 0.06, 0), Vector3(L * 0.36, L * 0.08, r * 0.3), w.col)   # tailplane
		mb.box(Vector3(0, L * 0.72, r * 0.8), Vector3(r * 0.9, L * 0.12, r * 0.6), Color(0.25, 0.35, 0.45))   # canopy
	_meshes[id] = mb.commit(null, MeshBuilder.vc_material(0.5))
	return _meshes[id]


func _build_marker() -> void:
	# unit ring (r 0.85..1.0) + crosshair: one mesh, placed / scaled per target
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var q := [Vector3(cos(a0) * 0.85, 0, sin(a0) * 0.85), Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1) * 0.85, 0, sin(a1) * 0.85), Vector3(cos(a1), 0, sin(a1))]
		for v in [q[0], q[2], q[1], q[1], q[2], q[3]]:
			st.add_vertex(v)
	for arm in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var a := Vector3(arm.x, 0, arm.y)
		var s := Vector3(-arm.y, 0, arm.x) * 0.05
		var p_in := a * 0.25
		var p_out := a * 1.25
		for v in [p_in - s, p_out - s, p_in + s, p_in + s, p_out - s, p_out + s]:
			st.add_vertex(v)
	marker = MeshInstance3D.new()
	marker.name = "TargetMarker"
	marker.mesh = st.commit()
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	_mat_aim = _marker_mat(Color(1.0, 0.62, 0.2, 0.85))
	_mat_lock = _marker_mat(Color(1.0, 0.12, 0.08, 0.95))
	_mat_warn = _marker_mat(Color(1.0, 0.86, 0.10, 0.95))
	marker.material_override = _mat_aim
	add_child(marker)


static func _marker_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 3
	m.albedo_color = c
	return m


func _build_wet_marks() -> void:
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.vertex_color_use_as_albedo = true
	_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_mat.roughness = 0.35
	_mark_age.resize(WET_MARKS)
	for k in WET_MARKS:
		var mi := MeshInstance3D.new()
		mi.name = "WetMark%d" % k
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_marks.append(mi)


# ------------------------------------------------------------------------------------

## The player's launch point when there is no tracked hand (desktop, tests).
## Launch point: the weapon's launcher on the player's warship (build 8), else the
## desktop "player hand".
func default_origin(wid := "") -> Vector3:
	if island and island.ship:
		return island.ship.launch_point(wid if wid != "" else weapon)
	return DESKTOP_HAND


## The surface a shot can hit at (x, z): terrain or sea; -INF outside the slab.
func surface(x: float, z: float) -> float:
	if not island.terrain.is_inside(x, z):
		return -INF
	return island.surface_at(x, z)


func plan(tgt: Vector3, origin := Vector3.INF, wid := "") -> Dictionary:
	var w := WeaponTable.get_weapon(wid if wid != "" else weapon)
	var o := origin if origin != Vector3.INF else default_origin(w.id)
	return WeaponFlight.plan(w, o, tgt, surface, G)


## Trajectory preview (dots from the launch point to the target) + target marker.
func aim(tgt: Vector3, origin := Vector3.INF, wid := "", locked := false) -> void:
	var pl := plan(tgt, origin, wid)
	last_aim_T = pl.T
	last_aim_plan = pl
	_show_preview(pl)
	show_marker(tgt, locked, wid)


func _show_preview(pl: Dictionary) -> void:
	var n := preview_mm.instance_count
	var T: float = pl.T
	var shown := 0
	for k in n:
		var t := T * float(k) / (n - 1)
		var p := WeaponFlight.position_at(pl, t)
		var s := surface(p.x, p.z)
		if t > 0.1 and s > -INF and p.y < s:
			break
		var a := 0.9 * (1.0 - 0.6 * float(k) / n)
		var sc := 1.0 if k % 2 == 0 else 0.6
		preview_mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * sc), p))
		preview_mm.set_instance_color(k, Color(1.0, 0.62, 0.25, a))
		shown += 1
	preview_mm.visible_instance_count = shown


func show_marker(tgt: Vector3, locked := false, wid := "") -> void:
	var w := WeaponTable.get_weapon(wid if wid != "" else weapon)
	var n := island.terrain.smooth_normal_at(tgt.x, tgt.z, 0.004) if island.terrain.is_inside(tgt.x, tgt.z) else Vector3.UP
	if tgt.y <= IslandTerrain.SEA + 1e-5:
		n = Vector3.UP
	var r: float = CRATER_R * float(w.blast)
	var b := Basis(Quaternion(Vector3.UP, n.normalized())) * Basis().scaled(Vector3(r, r, r))
	marker.transform = Transform3D(b, tgt + n * 0.0006)
	last_marker_civilians = civilians_near(tgt, BLAST_R * float(w.blast) if not bool(w.get("nuke", false)) else float(w.nuke_r))
	# a locked target stays red (the panel's target line still counts the civilians)
	marker.material_override = _mat_lock if locked else (_mat_warn if last_marker_civilians > 0 else _mat_aim)
	marker.visible = true


## People and cars alive in the city + civilian buildings / boats still standing within r.
func civilians_near(p: Vector3, r: float) -> int:
	var n := island.life.alive_near(p, r) if island.life else 0
	for st in island.props.structures:
		if st.alive and (st.kind in StageRun.CIVIL or st.kind in StageRun.CIVIL_BOATS):
			if Vector2(st.pos.x - p.x, st.pos.z - p.z).length() < r:
				n += 1
	return n


func hide_preview() -> void:
	preview_mm.visible_instance_count = 0
	marker.visible = false


func fire(tgt: Vector3, origin := Vector3.INF, wid := "") -> Dictionary:
	var w := WeaponTable.get_weapon(wid if wid != "" else weapon)
	var o := origin if origin != Vector3.INF else default_origin(w.id)
	# MLRS: the rest of the salvo follows a rocket every 90 ms, scattered round the target
	for k in range(1, int(w.get("salvo", 1))):
		_pending.append({"delay": k * 0.09, "origin": o, "tgt": _scatter(tgt, float(w.spread)), "wid": w.id})
	return _launch(w, o, tgt)


## A point within `r` of `tgt`, on the surface there.
func _scatter(tgt: Vector3, r: float) -> Vector3:
	var a := _rng.randf() * TAU
	var d := sqrt(_rng.randf()) * r
	var p := tgt + Vector3(cos(a) * d, 0.0, sin(a) * d)
	var su := surface(p.x, p.z)
	p.y = su if su > -INF else tgt.y
	return p


func _launch(w: Dictionary, o: Vector3, tgt: Vector3, quiet := false) -> Dictionary:
	var pl := WeaponFlight.plan(w, o, tgt, surface, G)
	if flights.size() >= MAX_FLIGHTS:
		_end_flight(0)
	var slot := _free_slot()
	var node: Node3D = slot.node
	if slot.wid != w.id:
		(slot.body as MeshInstance3D).mesh = _shell_mesh(w)
		(slot.glow as Node3D).position = Vector3(-float(w.length) * 0.55, 0, 0)
		slot.wid = w.id
	(slot.glow as Node3D).scale = Vector3.ONE
	(slot.glow_mat as StandardMaterial3D).albedo_color = Color(1.0, 0.75, 0.35)
	node.position = o
	node.visible = true
	_serial += 1
	var f := {"plan": pl, "t": 0.0, "w": w, "slot": slot, "trail_acc": 0.0, "tgt": tgt, "split": false, "serial": _serial}
	flights.append(f)
	_orient(f)
	last_plan = pl
	shell = node
	p0 = o
	v0 = WeaponFlight.velocity_at(pl, 0.0)
	flight_T = pl.T
	target = tgt
	if not quiet:
		fx.muzzle(o, v0.normalized())
		sfx.play("launch", o, 0.6)
	return pl


func _free_slot() -> Dictionary:
	for s in _pool:
		var used := false
		for f in flights:
			if f.slot == s:
				used = true
				break
		if not used:
			return s
	return _pool[0]


## A shot shot down in the air (Resistance): gone without an impact. A strike jet does
## not come back (jet_lost).
func kill_flight(i: int) -> void:
	var wid: String = (flights[i].w as Dictionary).id
	_end_flight(i)
	if wid == "jet":
		jet_lost.emit(wid)
	if flights.is_empty() and _pending.is_empty():
		hide_preview()


func _end_flight(i: int) -> void:
	var f: Dictionary = flights[i]
	(f.slot.node as Node3D).visible = false
	flights.remove_at(i)


func set_slow_motion(on: bool) -> void:
	slow_motion = on


func _physics_process(delta: float) -> void:
	if not manual:
		advance(delta * (slow_factor if slow_motion else 1.0))


## Advance the whole simulation by dt seconds of game time.
func advance(dt: float) -> void:
	sim_time += dt
	var k := 0
	while k < _pending.size():
		var q: Dictionary = _pending[k]
		q.delay -= dt
		if q.delay <= 0.0:
			_pending.remove_at(k)
			_launch(WeaponTable.get_weapon(q.wid), q.origin, q.tgt)
			continue
		k += 1
	var steps := maxi(1, int(ceil(dt / (1.0 / 120.0))))
	var h := dt / steps
	for _i in steps:
		_step_flights(h)      # shells need the small step (exact impact points)
	resistance.step(dt)
	# debris and smoke step once per frame: half the GDScript cost of the 120 Hz
	# substeps at 72 fps (long frames still split, so a step never exceeds 1/50 s)
	var ds := maxi(1, int(ceil(dt / 0.02)))
	for _j in ds:
		debris.step(dt / ds)
		fx.step(dt / ds)
	if island.life:
		island.life.step(dt)
	_step_marks(dt)


func _step_flights(dt: float) -> void:
	var i := 0
	while i < flights.size():
		var f: Dictionary = flights[i]
		var pl: Dictionary = f.plan
		var t_prev: float = f.t
		var t: float = t_prev + dt
		f.t = t
		var p := WeaponFlight.position_at(pl, t)
		if pl.get("sortie", false):
			# strike jet: bombs away over the target, then home to the deck
			if not f.split and t >= float(pl.release_t):
				f.split = true
				var spread_j: float = f.w.spread
				for _b in int(f.w.bombs):
					_launch(WeaponTable.get_weapon("jetbomb"), p, _scatter(f.tgt, spread_j), true)
			if t >= float(pl.T):
				var jid: String = (f.w as Dictionary).id
				_end_flight(i)
				sortie_landed.emit(jid)
				continue
			(f.slot.node as Node3D).position = p
			_orient(f)
			_trail(f, p, dt)
			i += 1
			continue
		var s := surface(p.x, p.z)
		if t > 0.05 and s > -INF and p.y <= s + 1e-6:
			var lo := t_prev
			var hi := t
			for _k in 24:
				var mid := (lo + hi) * 0.5
				var q := WeaponFlight.position_at(pl, mid)
				var sq := surface(q.x, q.z)
				if sq == -INF or q.y > sq:
					lo = mid
				else:
					hi = mid
			var w: Dictionary = f.w
			_end_flight(i)
			if flights.is_empty():
				hide_preview()   # XR re-aims (and re-shows a locked marker) next frame
			_impact(WeaponFlight.position_at(pl, hi), w)
			continue
		if (s == -INF and p.y < -0.02) or t > float(pl.T) + 3.0:
			_end_flight(i)   # missed the table: gone
			continue
		(f.slot.node as Node3D).position = p
		var nsplit := int((f.w as Dictionary).get("split", 0))
		if nsplit > 0 and not f.split and t >= float(pl.T) * 0.62:
			# cluster missile: the case opens, the bomblets fall over the target area
			f.split = true
			var aim: Vector3 = f.tgt
			var spread: float = f.w.spread
			_end_flight(i)
			fx.splash(p, 0.6)
			for _b in nsplit:
				_launch(WeaponTable.get_weapon("submunition"), p, _scatter(aim, spread), true)
			continue
		_orient(f)
		_trail(f, p, dt)
		i += 1


func _orient(f: Dictionary) -> void:
	var vel := WeaponFlight.velocity_at(f.plan, f.t)
	if vel.length() > 1e-5:
		var up := Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT
		(f.slot.node as Node3D).basis = Basis.looking_at(vel.normalized(), up) * Basis(Vector3.UP, PI * 0.5)


func _trail(f: Dictionary, p: Vector3, dt: float) -> void:
	var w: Dictionary = f.w
	f.trail_acc += dt
	var reentry := false
	if bool(w.glow):
		var T: float = f.plan.T
		var vy: float = WeaponFlight.velocity_at(f.plan, f.t).y
		var k := clampf((float(f.t) / T - 0.5) / 0.3, 0.0, 1.0) if vy < 0.0 else 0.0
		reentry = k > 0.05
		(f.slot.glow as Node3D).scale = Vector3.ONE * (1.0 + 1.6 * k)
		(f.slot.glow_mat as StandardMaterial3D).albedo_color = Color(1.0, 0.75, 0.35).lerp(Color(1.0, 0.95, 0.85), k)
	if f.trail_acc > float(w.trail):
		f.trail_acc = 0.0
		if reentry:
			fx.reentry(p)
		else:
			fx.trail(p, w.trail_col)


func _impact(p: Vector3, w: Dictionary) -> void:
	last_impact = p
	impact_count += 1
	var b: float = w.blast
	var terr := island.terrain
	var ground := terr.height_at(p.x, p.z)
	var depth := IslandTerrain.SEA - ground
	if depth > SHALLOW:
		# deep enough: a water splash only. No crater, scorch, fire or debris.
		last_impact_kind = "water"
		var ps := Vector3(p.x, IslandTerrain.SEA, p.z)
		fx.water_splash(ps, b)
		sfx.play("thump", ps, 0.5 + 0.35 * b)
		debris.wake_near(ps, BLAST_R * b)   # floating debris rocks in the wave
		# ships are targets: a hit near one wrecks it (fire on the hull, pieces flying)
		var sfrags := island.props.blast(ps, BLAST_R * b)
		if not sfrags.is_empty():
			fx.ship_fire(ps, b)
			sfx.play("boom", ps, 0.5 + 0.3 * b)
			for f in sfrags:
				debris.spawn(f.pos, f.basis, f.half, f.vel, f.ang, f.col, 1)
		impacted.emit(ps, last_impact_kind)
		return
	if depth > 0.0:
		# very shallow water at the shore: small splash + a wet-sand mark
		last_impact_kind = "shallow"
		var ps2 := Vector3(p.x, IslandTerrain.SEA, p.z)
		fx.water_splash(ps2, b * 0.45)
		wet_mark(Vector3(p.x, ground, p.z), CRATER_R * b * 1.1)
		sfx.play("thump", ps2, 0.35 + 0.2 * b)
		impacted.emit(ps2, last_impact_kind)
		return
	if bool(w.get("nuke", false)):
		_nuke(p, w)
		return
	last_impact_kind = "land"
	var rng := RandomNumberGenerator.new()
	rng.seed = impact_count * 977
	var cr := CRATER_R * b
	var soil := terr.color_at(p.x, p.z)
	terr.crater(p, cr, CRATER_D * pow(b, 0.8) * float(w.get("crater_k", 1.0)))
	fx.explosion(p, b)
	sfx.play("boom", p, 0.6 + 0.3 * b)
	debris.wake_near(p, BLAST_R * b * 2.5)
	var frags := island.props.blast(p, BLAST_R * b)
	if island.life:
		island.life.on_blast(p, BLAST_R * b)
	for f in frags:
		debris.spawn(f.pos, f.basis, f.half, f.vel, f.ang, f.col, 1)
	var burnt := island.props.on_crater(p, cr)
	if island.props.paving_at(Vector2(p.x, p.z), cr):
		for k in int(12 * b):
			var a2 := rng.randf() * TAU
			var dir2 := Vector3(cos(a2), 0, sin(a2))
			var sp := p + dir2 * rng.randf_range(0.0, cr * 0.6) + Vector3(0, 0.002, 0)
			var half2 := Vector3(rng.randf_range(0.0008, 0.0018), rng.randf_range(0.00018, 0.0003), rng.randf_range(0.0006, 0.0014))
			var vel2 := dir2 * rng.randf_range(0.03, 0.09) + Vector3(0, rng.randf_range(0.08, 0.2), 0)
			var tone := rng.randf_range(0.28, 0.42)
			debris.spawn(sp, Basis(Vector3.UP, rng.randf() * TAU), half2, vel2, Vector3(rng.randf_range(-10, 10), rng.randf_range(-4, 4), rng.randf_range(-10, 10)), Color(tone, tone, tone * 1.02), 1)
	for bt in burnt:
		var d := ((bt.pos as Vector3) - p) * Vector3(1, 0, 1)
		var vel := d.normalized() * rng.randf_range(0.03, 0.08) + Vector3(0, rng.randf_range(0.08, 0.16), 0)
		debris.spawn(bt.pos, Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU), bt.half, vel, Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8)), bt.col, 1)
	var n := int(float(w.ejecta) * ejecta_scale)
	for k in n:
		var a := rng.randf() * TAU
		var spread := rng.randf_range(0.2, 1.0)
		var dir := Vector3(cos(a) * spread, 1.0, sin(a) * spread).normalized()
		var speed := rng.randf_range(0.09, 0.30) * sqrt(b)
		var vel := Vector3(dir.x * speed * 0.55, dir.y * speed, dir.z * speed * 0.55)
		var s := rng.randf_range(0.0005, 0.0016) * (1.8 if rng.randf() < 0.1 else 1.0)
		var c := soil.darkened(rng.randf_range(0.0, 0.35))
		if rng.randf() < 0.35:
			c = Color(0.20, 0.17, 0.15)
		var start := p + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, cr * 0.5) + Vector3(0, 0.002, 0)
		debris.spawn(start, Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU), Vector3(s, s * rng.randf_range(0.6, 1.0), s * rng.randf_range(0.7, 1.1)), vel, Vector3(rng.randf_range(-20, 20), rng.randf_range(-20, 20), rng.randf_range(-20, 20)), c, 0)
	impacted.emit(p, last_impact_kind)


## The nuclear test: a wide flash, fireball and mushroom cloud, a shock ring over the
## ground, everything within `nuke_r` destroyed (only the nearest buildings break into
## pieces; the tiles re-upload over the next frames), a wide scorched area and a crater.
func _nuke(p: Vector3, w: Dictionary) -> void:
	last_impact_kind = "nuke"
	var r: float = w.nuke_r
	var ps := Vector3(p.x, maxf(p.y, IslandTerrain.SEA), p.z)
	fx.nuke(ps, r)
	sfx.play("boom", ps, 1.5)
	sfx.play("thump", ps, 1.5)
	if island.terrain.height_at(p.x, p.z) > IslandTerrain.SEA:
		island.terrain.crater(p, 0.034, 0.012)
	island.terrain.scorch_area(p, r * 0.85)
	var frags := island.props.blast(ps, r, 10)
	for f in frags:
		debris.spawn(f.pos, f.basis, f.half, f.vel * 2.0, f.ang, f.col, 1)
	island.props.on_crater(p, r * 0.8)
	if island.life:
		island.life.on_blast(ps, r)
	debris.wake_near(ps, r)
	impacted.emit(ps, last_impact_kind)


## Darker, glossier wet sand where a shell hit the shallows (pooled, fades in ~40 s).
func wet_mark(c: Vector3, radius: float) -> void:
	var mb := MeshBuilder.new()
	var seg := 24
	var rings := 3
	var col := Color(0.18, 0.13, 0.08, 0.55)
	for ring in rings:
		var r0 := radius * float(ring) / rings
		var r1 := radius * float(ring + 1) / rings
		var a0c := col
		a0c.a = col.a * (1.0 - float(ring) / rings)
		var a1c := col
		a1c.a = col.a * (1.0 - float(ring + 1) / rings)
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var pts: Array[Vector3] = []
			for q in [[r0, a0], [r1, a0], [r1, a1], [r0, a1]]:
				var x: float = c.x + cos(q[1]) * q[0]
				var z: float = c.z + sin(q[1]) * q[0]
				pts.append(Vector3(x, island.height_at(x, z) + 0.00012, z))
			mb.tri_out(pts[0], pts[1], pts[2], a0c, Vector3.UP)
			mb.tri_out(pts[0], pts[2], pts[3], a0c, Vector3.UP)
	var mi := _marks[_mark_next]
	mi.mesh = mb.commit(null, _mark_mat)
	mi.transparency = 0.0
	mi.visible = true
	_mark_age[_mark_next] = 0.0
	_mark_next = (_mark_next + 1) % WET_MARKS


func wet_mark_count() -> int:
	var n := 0
	for m in _marks:
		if m.visible:
			n += 1
	return n


func _step_marks(dt: float) -> void:
	for k in WET_MARKS:
		var mi := _marks[k]
		if not mi.visible:
			continue
		_mark_age[k] += dt
		mi.transparency = clampf((_mark_age[k] - 20.0) / 20.0, 0.0, 1.0)
		if _mark_age[k] > 40.0:
			mi.visible = false


## "Reset island": craters, buildings, vegetation, roads back; debris, smoke, shots gone.
func reset_island() -> void:
	resistance.clear()
	_pending.clear()
	while not flights.is_empty():
		_end_flight(0)
	hide_preview()
	debris.clear()
	fx.clear()
	for m in _marks:
		m.visible = false
	island.reset_damage()
	debris.terrain = island.terrain
	debris.props = island.props
