class_name EnemyForces
extends Node3D
## The Viper's mobile forces (build 18), island-local, a child of PhysicsTest:
##   tank       main battle tank: patrols a road, turret turned to the battleship, fires a
##              shell at it every TANK_RELOAD s when within TANK_RANGE (shells: no CIWS)
##   apc        armoured personnel carrier: patrols, no weapon (a target)
##   spaa       mobile anti-aircraft gun: shoots our missiles passing within SPAA_RANGE
##              (SPAA_P, a tracer burst, then SPAA_RELOAD s)
##   mlauncher  mobile missile launcher: drives, stops, fires an anti-ship missile at the
##              battleship every `coastal` s (through Resistance), drives on
##   fighter    jet fighter parked on the enemy air base: every `air` s one takes off,
##              climbs under the dome, flies at the battleship, fires a missile within
##              FIGHTER_SHOT, turns home and lands. The battleship's gun (CIWS) shoots at
##              fighters within CIWS_AIR; our "aa" missile (fire_aa) homes on them.
## Ground units die in any blast that reaches them (on_blast: a burnt wreck stays); a
## parked fighter dies on the ground too. Drawn with one MultiMesh per kind (+ wrecks).
## Stage option "forces": {tank: n, apc: n, spaa: n, mlauncher: n, fighter: n, air: s}.

signal ship_damaged(point: Vector3, damage: float)
signal unit_killed(kind: String, point: Vector3)
signal fighter_down(point: Vector3)

const TANK_RANGE := 0.75
const TANK_RELOAD := 9.0
const TANK_DAMAGE := 8.0
const TANK_HIT_P := 0.6
const SHELL_T := 2.4
const SPAA_RANGE := 0.10
const SPAA_P := 0.35
const SPAA_RELOAD := 3.0
const SPEED := {"tank": 0.010, "apc": 0.016, "spaa": 0.008, "mlauncher": 0.012}
const FIGHTER_SPEED := 0.16
const FIGHTER_ALT := 0.11
const FIGHTER_SHOT := 0.28
const CIWS_AIR := 0.13
const CIWS_AIR_P := 0.45          # per second while in range
const AA_SPEED := 0.55
const KINDS := ["tank", "apc", "spaa", "mlauncher", "fighter"]
const ARMOR := ["tank", "apc", "spaa", "mlauncher"]
const MAX_PER_KIND := 12
const LOOK := 1.6                 # drawn larger than scale so they read from the player's place

var phys: PhysicsTest
var units: Array[Dictionary] = []    # {kind, alive, p, yaw, path, s, dir, cool, state, ...}
var shells: Array[Dictionary] = []   # {from, to, t, hit}
var aas: Array[Dictionary] = []      # our anti-air missiles {p, v, target, t, node}
var air_every := 0.0
var _air_acc := 0.0
var rng := RandomNumberGenerator.new()
var _mm := {}                        # kind -> MultiMesh (alive)
var _mm_wreck: MultiMesh
var _shell_mm: MultiMesh
var _aa_mesh: Mesh
var _aa_pool: Array[MeshInstance3D] = []
var _ciws_acc := 0.0
var kills := {}                      # kind -> count killed (stats / tests)


func setup(p: PhysicsTest) -> void:
	phys = p
	rng.seed = 7171
	for k in KINDS:
		_mm[k] = _make_mm("Enemy_" + k, _mesh(k), MAX_PER_KIND)
	_mm_wreck = _make_mm("EnemyWrecks", _wreck_mesh(), MAX_PER_KIND * 4)
	_shell_mm = _make_mm("TankShells", _shell_mesh(), 16)
	_aa_mesh = _aa_body()


func _make_mm(nm: String, mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-0.6, -0.1, -0.6), Vector3(1.2, 0.7, 1.2))
	add_child(mi)
	return mm


# --- meshes (low-poly, nose along +x) ----------------------------------------------------

static func _mesh(kind: String) -> Mesh:
	var mb := MeshBuilder.new()
	var olive := Color(0.40, 0.42, 0.28)
	var dark := Color(0.20, 0.21, 0.16)
	match kind:
		"tank":
			mb.box(Vector3(0, 0.0007, 0), Vector3(0.0062, 0.0012, 0.0036), dark)            # tracks
			mb.box(Vector3(0, 0.0016, 0), Vector3(0.0058, 0.0010, 0.0030), olive)           # hull
			mb.box(Vector3(-0.0004, 0.0026, 0), Vector3(0.0028, 0.0010, 0.0022), olive.lightened(0.08))   # turret
			mb.box(Vector3(0.0028, 0.0026, 0), Vector3(0.0034, 0.00035, 0.00035), dark)     # gun
		"apc":
			mb.box(Vector3(0, 0.0007, 0), Vector3(0.0052, 0.0010, 0.0030), dark)
			mb.box(Vector3(-0.0002, 0.0018, 0), Vector3(0.0050, 0.0014, 0.0028), Color(0.50, 0.48, 0.34))
			mb.box(Vector3(0.0018, 0.0027, 0.0006), Vector3(0.0010, 0.0005, 0.0008), dark)
		"spaa":
			mb.box(Vector3(0, 0.0007, 0), Vector3(0.0056, 0.0012, 0.0034), dark)
			mb.box(Vector3(0, 0.0016, 0), Vector3(0.0052, 0.0010, 0.0028), olive)
			mb.box(Vector3(0, 0.0026, 0), Vector3(0.0026, 0.0012, 0.0024), olive.lightened(0.1))
			for s in [-1.0, 1.0]:
				mb.box(Vector3(0.0018, 0.0034, s * 0.0007), Vector3(0.0026, 0.00025, 0.00025), dark)
			mb.box(Vector3(-0.0008, 0.0038, 0), Vector3(0.0003, 0.0012, 0.0016), Color(0.25, 0.27, 0.22))   # radar dish
		"mlauncher":
			mb.box(Vector3(0.0024, 0.0013, 0), Vector3(0.0018, 0.0016, 0.0026), Color(0.45, 0.46, 0.33))   # cab
			mb.box(Vector3(-0.0010, 0.0008, 0), Vector3(0.0058, 0.0008, 0.0026), dark)                    # chassis
			var saved := mb.xform
			mb.xform = saved * Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(18.0)), Vector3(-0.0012, 0.0019, 0))
			for s in [-1.0, 1.0]:
				mb.box(Vector3(0, 0, s * 0.0006), Vector3(0.0050, 0.0007, 0.0008), Color(0.75, 0.75, 0.70))   # missiles
			mb.xform = saved
		"fighter":
			var g := Color(0.52, 0.55, 0.50)
			mb.box(Vector3.ZERO, Vector3(0.0070, 0.0011, 0.0011), g)                                    # fuselage
			mb.box(Vector3(-0.0006, 0, 0), Vector3(0.0022, 0.0003, 0.0068), g)                          # wings
			mb.box(Vector3(-0.0030, 0.0009, 0), Vector3(0.0012, 0.0016, 0.0003), g.darkened(0.15))     # fin
			mb.box(Vector3(-0.0031, 0, 0), Vector3(0.0010, 0.0002, 0.0026), g)                          # tailplane
			mb.box(Vector3(0.0018, 0.0007, 0), Vector3(0.0014, 0.0005, 0.0006), Color(0.25, 0.32, 0.40))   # canopy
			mb.box(Vector3(-0.0006, -0.0006, 0.002), Vector3(0.002, 0.0003, 0.0003), Color(0.8, 0.8, 0.78))   # missile
	return mb.commit(null, MeshBuilder.vc_material(0.7))


static func _wreck_mesh() -> Mesh:
	var mb := MeshBuilder.new()
	var c := Color(0.12, 0.11, 0.10)
	mb.box(Vector3(0, 0.0006, 0), Vector3(0.0056, 0.0010, 0.0032), c)
	mb.box(Vector3(-0.0006, 0.0015, 0.0003), Vector3(0.0024, 0.0008, 0.0018), c.lightened(0.05))
	return mb.commit(null, MeshBuilder.vc_material(0.95))


static func _shell_mesh() -> Mesh:
	var mb := MeshBuilder.new()
	mb.sphere(Vector3.ZERO, Vector3(0.0006, 0.0006, 0.0006), 3, 5, Color(1.0, 0.8, 0.4))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return mb.commit(null, m)


static func _aa_body() -> Mesh:
	var mb := MeshBuilder.new()
	mb.xform = Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(-0.0012, 0, 0))
	mb.cylinder(Vector3.ZERO, 0.00035, 0.00035, 0.0018, 6, Color(0.92, 0.92, 0.9))
	mb.cylinder(Vector3(0, 0.0018, 0), 0.00035, 0.0, 0.0007, 6, Color(0.95, 0.4, 0.3))
	return mb.commit(null, MeshBuilder.vc_material(0.5))


# --- spawning ---------------------------------------------------------------------------

func clear() -> void:
	units.clear()
	shells.clear()
	for a in aas:
		(a.node as Node3D).visible = false
	aas.clear()
	air_every = 0.0
	_air_acc = 0.0
	kills.clear()
	_upload()


## Spawn the stage's forces on the current island (paths from IslandLayout.military_paths).
func configure(stage: Dictionary) -> void:
	clear()
	var f: Dictionary = stage.get("forces", {})
	if f.is_empty():
		return
	var lay: IslandLayout = phys.island.layout
	var paths := lay.military_paths()
	if bool(f.get("patrol", false)):
		# web: armour also patrols the roads between the island's sites
		for r in lay.roads:
			if r.size() >= 2 and r[0].distance_to(lay.town_center) > lay.town_radius * 0.8 and r[r.size() - 1].distance_to(lay.town_center) > lay.town_radius * 0.8:
				paths.append(r)
	var k := 0
	for kind in ARMOR:
		for n in int(f.get(kind, 0)):
			var path: PackedVector2Array = paths[k % paths.size()]
			k += 1
			var s0 := rng.randf()
			units.append({"kind": kind, "alive": true, "path": path, "len": _length(path), "s": s0 * _length(path),
				"dir": 1.0 if rng.randf() < 0.5 else -1.0, "cool": rng.randf_range(2.0, TANK_RELOAD), "p": Vector3.ZERO, "yaw": 0.0,
				"turret": 0.0, "stop": 0.0})
	var spots := lay.fighter_spots()
	for n in mini(int(f.get("fighter", 0)), spots.size()):
		var sp: Vector3 = spots[n]
		var gp := Vector3(sp.x, phys.island.surface_at(sp.x, sp.z) + 0.0008, sp.z)
		units.append({"kind": "fighter", "alive": true, "state": "parked", "p": gp, "home": gp, "yaw": sp.y, "v": Vector3.ZERO,
			"t": 0.0, "fired": false, "cool": 0.0})
	air_every = float(f.get("air", 0.0))
	_air_acc = air_every * 0.6
	for u in units:
		if u.kind in ARMOR:
			_place(u, 0.0)
	_upload()


static func _length(path: PackedVector2Array) -> float:
	var L := 0.0
	for i in range(1, path.size()):
		L += path[i].distance_to(path[i - 1])
	return maxf(L, 1e-4)


static func _at(path: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in range(1, path.size()):
		var l := path[i].distance_to(path[i - 1])
		if acc + l >= s or i == path.size() - 1:
			var f := clampf((s - acc) / maxf(l, 1e-6), 0.0, 1.0)
			return [path[i - 1].lerp(path[i], f), (path[i] - path[i - 1]).normalized()]
		acc += l
	return [path[0], Vector2.RIGHT]


func count(kinds: Array, alive_only := false) -> int:
	var n := 0
	for u in units:
		if u.kind in kinds and (u.alive or not alive_only):
			n += 1
	return n


func alive(kinds: Array) -> int:
	return count(kinds, true)


# --- per frame --------------------------------------------------------------------------

func step(dt: float) -> void:
	if units.is_empty() and shells.is_empty() and aas.is_empty():
		return
	var ship := phys.island.ship
	var ship_p := ship.transform * Vector3(0, PlayerShip.FB, 0) if ship else Vector3.INF
	for u in units:
		if not u.alive:
			continue
		if u.kind == "fighter":
			_step_fighter(u, dt, ship_p)
			continue
		# drive along the patrol path (ping-pong); launchers stop to fire
		var sp: float = SPEED[u.kind]
		if float(u.stop) > 0.0:
			u.stop = float(u.stop) - dt
		else:
			u.s = float(u.s) + float(u.dir) * sp * dt
			if float(u.s) > float(u.len) or float(u.s) < 0.0:
				u.dir = -float(u.dir)
				u.s = clampf(float(u.s), 0.0, float(u.len))
		_place(u, dt)
		u.cool = float(u.cool) - dt
		match u.kind:
			"tank":
				if ship_p != Vector3.INF and float(u.cool) <= 0.0 and (u.p as Vector3).distance_to(ship_p) < TANK_RANGE:
					u.cool = TANK_RELOAD * rng.randf_range(0.85, 1.2)
					_fire_shell(u, ship_p)
			"mlauncher":
				var every := float(phys.resistance.coastal) if phys.resistance.coastal > 0.0 else 14.0
				if float(u.cool) <= 0.0:
					u.cool = every * rng.randf_range(0.9, 1.25)
					u.stop = 2.5
					phys.resistance.launch_at_ship((u.p as Vector3) + Vector3(0, 0.004, 0))
			"spaa":
				if float(u.cool) <= 0.0:
					_spaa_engage(u)
	# fighters take off in turn
	if air_every > 0.0:
		_air_acc += dt
		if _air_acc >= air_every:
			_air_acc = 0.0
			for u in units:
				if u.alive and u.kind == "fighter" and u.state == "parked":
					u.state = "takeoff"
					u.t = 0.0
					u.fired = false
					break
	_step_ciws(dt, ship_p)
	_step_shells(dt)
	_step_aa(dt)
	_upload()


func _place(u: Dictionary, _dt: float) -> void:
	var r := _at(u.path, float(u.s))
	var q: Vector2 = r[0]
	var d: Vector2 = r[1] * float(u.dir)
	u.p = Vector3(q.x, phys.island.surface_at(q.x, q.y), q.y)
	u.yaw = atan2(-d.y, d.x)


func _fire_shell(u: Dictionary, ship_p: Vector3) -> void:
	var from: Vector3 = (u.p as Vector3) + Vector3(0, 0.003, 0)
	var miss := rng.randf() > TANK_HIT_P
	var to := ship_p + Vector3(rng.randf_range(-0.03, 0.03), 0.0, rng.randf_range(-0.012, 0.012))
	if miss:
		to += Vector3(rng.randf_range(-0.05, 0.05), -PlayerShip.FB, rng.randf_range(0.03, 0.06) * (1.0 if rng.randf() < 0.5 else -1.0))
	shells.append({"from": from, "to": to, "t": 0.0, "hit": not miss})
	phys.fx.muzzle(from, (to - from).normalized())
	phys.sfx.play("thump", from, 0.3)


func _step_shells(dt: float) -> void:
	var i := 0
	while i < shells.size():
		var s: Dictionary = shells[i]
		s.t = float(s.t) + dt
		if float(s.t) >= SHELL_T:
			var to: Vector3 = s.to
			if bool(s.hit):
				phys.fx.ship_fire(to, 0.5)
				phys.sfx.play("boom", to, 0.5)
				ship_damaged.emit(to, TANK_DAMAGE)
			else:
				phys.fx.water_splash(Vector3(to.x, IslandTerrain.SEA, to.z), 0.5)
				phys.sfx.play("thump", to, 0.3)
			shells.remove_at(i)
			continue
		i += 1


## Shell position: a lofted arc from the tank to the target.
func shell_pos(s: Dictionary) -> Vector3:
	var k := float(s.t) / SHELL_T
	var a: Vector3 = s.from
	var b: Vector3 = s.to
	return a.lerp(b, k) + Vector3(0, 0.12 * 4.0 * k * (1.0 - k), 0)


func _spaa_engage(u: Dictionary) -> void:
	var p: Vector3 = u.p
	for j in phys.flights.size():
		var f: Dictionary = phys.flights[j]
		var wid: String = (f.w as Dictionary).id
		if wid in ["artillery", "submunition", "jetbomb"] or f.get("doomed", false):
			continue
		var q: Vector3 = (f.slot.node as Node3D).position
		if q.distance_to(p) < SPAA_RANGE and q.y > p.y + 0.008:
			u.cool = SPAA_RELOAD
			phys.fx.tracer(p + Vector3(0, 0.004, 0), q)
			phys.sfx.play("thump", p, 0.25)
			if rng.randf() < SPAA_P:
				phys.kill_flight(j)
				phys.fx.air_burst(q, 0.6)
				phys.resistance.shots_down += 1
				phys.resistance.intercepted.emit(q, wid)
			return


func _step_fighter(u: Dictionary, dt: float, ship_p: Vector3) -> void:
	if u.state == "parked" or ship_p == Vector3.INF:
		return
	u.t = float(u.t) + dt
	var p: Vector3 = u.p
	var home: Vector3 = u.home
	var goal: Vector3
	match String(u.state):
		"takeoff":
			goal = home + Vector3(cos(-float(u.yaw)) * 0.12, FIGHTER_ALT, sin(-float(u.yaw)) * 0.12)
			if p.distance_to(goal) < 0.02:
				u.state = "attack"
		"attack":
			goal = ship_p + Vector3(0, FIGHTER_ALT * 0.7, 0)
			if not u.fired and Vector2(p.x - ship_p.x, p.z - ship_p.z).length() < FIGHTER_SHOT:
				u.fired = true
				phys.resistance.launch_at_ship(p)
				u.state = "egress"
		"egress":
			goal = home + Vector3(0, FIGHTER_ALT, 0)
			if Vector2(p.x - home.x, p.z - home.z).length() < 0.05:
				u.state = "landing"
		"landing":
			goal = home
			if p.distance_to(home) < 0.004:
				u.state = "parked"
				u.p = home
				return
	var want := (goal - p)
	if want.length() > 1e-5:
		var v: Vector3 = u.v
		var tv := want.normalized() * FIGHTER_SPEED * (0.5 if u.state == "landing" else 1.0)
		v = v.lerp(tv, 1.0 - exp(-dt * 2.5))
		u.v = v
		var np := p + v * dt
		# stay under the glass dome and above the ground
		np.y = minf(np.y, WeaponFlight.dome_ceiling(np.x, np.z) - 0.005)
		np.y = maxf(np.y, phys.island.surface_at(np.x, np.z) + (0.0008 if u.state == "landing" else 0.01))
		u.p = np
		if v.length() > 1e-4:
			u.yaw = atan2(-v.z, v.x)


func _step_ciws(dt: float, ship_p: Vector3) -> void:
	if ship_p == Vector3.INF:
		return
	_ciws_acc += dt
	if _ciws_acc < 0.5:
		return
	_ciws_acc = 0.0
	var gun := phys.island.ship.transform * PlayerShip.LAUNCHERS["gun"]
	for u in units:
		if u.alive and u.kind == "fighter" and u.state in ["attack", "egress"] and (u.p as Vector3).distance_to(ship_p) < CIWS_AIR:
			phys.fx.tracer(gun, u.p)
			phys.sfx.play("thump", gun, 0.25)
			if rng.randf() < CIWS_AIR_P * 0.5:
				_kill_fighter(u)
			return


func _kill_fighter(u: Dictionary) -> void:
	u.alive = false
	var p: Vector3 = u.p
	phys.fx.air_burst(p, 1.0)
	phys.sfx.play("boom", p, 0.6)
	kills["fighter"] = int(kills.get("fighter", 0)) + 1
	fighter_down.emit(p)
	unit_killed.emit("fighter", p)


## Airborne enemy fighters (for our anti-air missile).
func airborne() -> Array:
	var out: Array = []
	for u in units:
		if u.alive and u.kind == "fighter" and u.state in ["takeoff", "attack", "egress"]:
			out.append(u)
	return out


## Fire our anti-air missile from `from` at the nearest airborne fighter. False if none.
func fire_aa(from: Vector3) -> bool:
	var best: Dictionary = {}
	var bd := INF
	for u in airborne():
		var d := (u.p as Vector3).distance_to(from)
		if d < bd:
			bd = d
			best = u
	if best.is_empty():
		return false
	var node: MeshInstance3D = null
	for n in _aa_pool:
		if not n.visible:
			node = n
	if node == null:
		node = MeshInstance3D.new()
		node.mesh = _aa_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_aa_pool.append(node)
	node.visible = true
	node.position = from
	aas.append({"p": from, "v": Vector3(0, AA_SPEED * 0.6, 0), "target": best, "t": 0.0, "node": node, "acc": 0.0})
	phys.fx.muzzle(from, Vector3.UP)
	phys.sfx.play("launch", from, 0.6)
	return true


func _step_aa(dt: float) -> void:
	var i := 0
	while i < aas.size():
		var a: Dictionary = aas[i]
		a.t = float(a.t) + dt
		var tgt: Dictionary = a.target
		var p: Vector3 = a.p
		if not tgt.alive or float(a.t) > 6.0:
			# lost its target: self-destructs
			phys.fx.air_burst(p, 0.4)
			(a.node as Node3D).visible = false
			aas.remove_at(i)
			continue
		var to := (tgt.p as Vector3) - p
		var v: Vector3 = a.v
		v = v.lerp(to.normalized() * AA_SPEED, 1.0 - exp(-dt * 6.0))
		a.v = v
		p += v * dt
		p.y = minf(p.y, WeaponFlight.dome_ceiling(p.x, p.z) - 0.003)
		a.p = p
		var n: Node3D = a.node
		n.position = p
		if v.length() > 1e-5:
			n.basis = Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT) * Basis(Vector3.UP, PI * 0.5)
		a.acc = float(a.acc) + dt
		if float(a.acc) > 0.02:
			a.acc = 0.0
			phys.fx.trail(p, Color(0.92, 0.92, 0.9, 0.5))
		if to.length() < 0.008:
			_kill_fighter(tgt)
			(a.node as Node3D).visible = false
			aas.remove_at(i)
			continue
		i += 1


## A blast on the island: ground units (and parked fighters) within reach are destroyed.
func on_blast(p: Vector3, r: float) -> void:
	for u in units:
		if not u.alive:
			continue
		if u.kind == "fighter" and u.state != "parked":
			continue
		var q: Vector3 = u.p
		if Vector2(q.x - p.x, q.z - p.z).length() < r * 1.1 + 0.002:
			u.alive = false
			kills[u.kind] = int(kills.get(u.kind, 0)) + 1
			unit_killed.emit(String(u.kind), q)
	_upload()


func _upload() -> void:
	var n := {}
	for k in KINDS:
		n[k] = 0
	var nw := 0
	for u in units:
		var xf := Transform3D(Basis(Vector3.UP, float(u.yaw)).scaled(Vector3.ONE * LOOK), u.p)
		if u.alive:
			var mm: MultiMesh = _mm[u.kind]
			if int(n[u.kind]) < MAX_PER_KIND:
				if u.kind == "fighter" and u.state != "parked":
					var v: Vector3 = u.v
					var bank := clampf(-v.normalized().y * 1.5, -0.5, 0.5) if v.length() > 1e-4 else 0.0
					xf = Transform3D((Basis(Vector3.UP, float(u.yaw)) * Basis(Vector3(0, 0, 1), -bank)).scaled(Vector3.ONE * LOOK), u.p)
				mm.set_instance_transform(int(n[u.kind]), xf)
				n[u.kind] = int(n[u.kind]) + 1
		elif u.kind != "fighter" or u.state == "parked":
			if nw < _mm_wreck.instance_count:
				_mm_wreck.set_instance_transform(nw, xf)
				nw += 1
	for k in KINDS:
		(_mm[k] as MultiMesh).visible_instance_count = int(n[k])
	_mm_wreck.visible_instance_count = nw
	var ns := 0
	for s in shells:
		if ns < _shell_mm.instance_count:
			_shell_mm.set_instance_transform(ns, Transform3D(Basis(), shell_pos(s)))
			ns += 1
	_shell_mm.visible_instance_count = ns
