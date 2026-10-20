class_name Resistance
extends Node3D
## The Viper fights back (stage options `sam` and `coastal`).
##
## Air defence: every live SAM site (kind "sam") watches the sky within SAM_RANGE. When one
## of our shots comes within range it rolls once (INTERCEPT[weapon]); on a hit it launches
## an interceptor that meets the shot TAU seconds later: both burst in the air and the shot
## is gone. A site then reloads for SAM_RELOAD s. Shells (artillery) and bomblets are too
## small to engage.
##
## Coastal launchers: every `coastal` seconds a live launcher (launcher_truck, silo_open,
## silo) fires an anti-ship missile at the battleship along a sea-skimming path. The
## ship's bow gun (CIWS) fires a burst at it CIWS_RANGE out and stops it with CIWS_P;
## one that gets through damages the hull (StageRun.ship_hit).
##
## Diorama-local, a child of PhysicsTest; stepped from PhysicsTest.advance, deterministic
## (its own seeded RNG), pooled meshes.

signal intercepted(point: Vector3, wid: String)
signal ship_hit(point: Vector3)
signal ciws_kill(point: Vector3)

const SAM_RANGE := 0.15
const SAM_RELOAD := 2.5
const TAU := 0.45                 # interceptor flight time
const CIWS_RANGE := 0.07
const CIWS_P := 0.5
const ENEMY_KINDS := ["launcher_truck", "silo_open", "silo"]
const INTERCEPT := {
	"ballistic": 0.35, "cruise": 0.6, "artillery": 0.0, "mlrs": 0.2, "cluster": 0.35, "hypersonic": 0.08,
	"bunker": 0.35, "drone": 0.75, "swarm": 0.6, "antiship": 0.4, "jet": 0.4, "nuke": 0.3, "submunition": 0.0, "jetbomb": 0.0,
}
const MAX_MISSILES := 6

var phys: PhysicsTest
var sam_on := false
var coastal := 0.0                # seconds between enemy launches (0: none)
var rng := RandomNumberGenerator.new()
var _sam_cool := {}               # structure index -> s left
var _engaged := {}                # flight Dictionary id -> true (rolled once per site)
var _interceptors: Array[Dictionary] = []   # {from, to, t, flight, node, site}
var _missiles: Array[Dictionary] = []       # {plan, t, node, trail, ciws}
var _coastal_acc := 0.0
var _pool: Array[MeshInstance3D] = []
var _mesh_int: Mesh
var _mesh_enemy: Mesh
var shots_down := 0
var ship_hits := 0


func setup(p: PhysicsTest) -> void:
	phys = p
	rng.seed = 4242
	_mesh_int = _rocket_mesh(0.0016, 0.00025, Color(0.92, 0.92, 0.88))
	_mesh_enemy = _rocket_mesh(0.0030, 0.00045, Color(0.80, 0.22, 0.18))


func configure(stage: Dictionary) -> void:
	clear()
	sam_on = bool(stage.get("sam", false))
	coastal = float(stage.get("coastal", 0.0))
	_coastal_acc = coastal * 0.5      # the first one comes half an interval in


func clear() -> void:
	for it in _interceptors:
		_release(it.node)
	for m in _missiles:
		_release(m.node)
	_interceptors.clear()
	_missiles.clear()
	_sam_cool.clear()
	_engaged.clear()
	sam_on = false
	coastal = 0.0
	shots_down = 0
	ship_hits = 0


func enemy_missiles() -> int:
	return _missiles.size()


func _node() -> MeshInstance3D:
	for n in _pool:
		if not n.visible:
			return n
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_pool.append(mi)
	return mi


func _release(n: MeshInstance3D) -> void:
	n.visible = false


static func _rocket_mesh(L: float, r: float, col: Color) -> Mesh:
	var mb := MeshBuilder.new()
	mb.xform = Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(-L * 0.5, 0, 0))
	mb.cylinder(Vector3.ZERO, r, r, L * 0.7, 6, col)
	mb.cylinder(Vector3(0, L * 0.7, 0), r, 0.0, L * 0.3, 6, col.lightened(0.25))
	return mb.commit(null, MeshBuilder.vc_material(0.5))


func _orient(n: Node3D, p: Vector3, v: Vector3) -> void:
	n.position = p
	if v.length_squared() > 1e-10:
		var d := v.normalized()
		var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT
		n.basis = Basis.looking_at(d, up) * Basis(Vector3.UP, PI * 0.5)


# ------------------------------------------------------------------------------------

func step(dt: float) -> void:
	if phys == null:
		return
	if sam_on:
		_step_sams(dt)
	_step_interceptors(dt)
	if coastal > 0.0:
		_coastal_acc += dt
		if _coastal_acc >= coastal:
			_coastal_acc = 0.0
			fire_coastal()
	_step_missiles(dt)


## Live structures of these kinds: [index, position].
func _sites(kinds: Array) -> Array:
	var out: Array = []
	var ss: Array = phys.island.props.structures
	for k in ss.size():
		var st: Dictionary = ss[k]
		if st.alive and st.kind in kinds:
			out.append([k, st.pos])
	return out


func _step_sams(dt: float) -> void:
	for k in _sam_cool:
		_sam_cool[k] = maxf(float(_sam_cool[k]) - dt, 0.0)
	var sites := _sites(["sam"])
	if sites.is_empty():
		return
	for f in phys.flights:
		var wid: String = (f.w as Dictionary).id
		var p_int := float(INTERCEPT.get(wid, 0.0))
		if p_int <= 0.0 or f.get("doomed", false):
			continue
		var p: Vector3 = (f.slot.node as Node3D).position
		var T: float = f.plan.T
		if float(f.t) > T - TAU * 1.2:
			continue                  # too close to its impact to be caught
		for s in sites:
			var key := "%d:%d" % [int(f.get("serial", 0)), int(s[0])]
			if _engaged.has(key):
				continue
			if float(_sam_cool.get(s[0], 0.0)) > 0.0:
				continue
			var sp: Vector3 = s[1]
			if Vector2(p.x - sp.x, p.z - sp.z).length() > SAM_RANGE or p.y < sp.y + 0.01:
				continue
			_engaged[key] = true
			_sam_cool[s[0]] = SAM_RELOAD
			if rng.randf() < p_int:
				_launch_interceptor(sp + Vector3(0, 0.004, 0), f, int(s[0]))
			break


func _launch_interceptor(from: Vector3, f: Dictionary, site: int) -> void:
	f["doomed"] = true
	var meet := WeaponFlight.position_at(f.plan, float(f.t) + TAU)
	var n := _node()
	n.mesh = _mesh_int
	n.visible = true
	_orient(n, from, meet - from)
	_interceptors.append({"from": from, "to": meet, "t": 0.0, "flight": f, "node": n, "site": site, "acc": 0.0})
	phys.fx.muzzle(from, (meet - from).normalized())
	phys.sfx.play("launch", from, 0.35)


func _step_interceptors(dt: float) -> void:
	var i := 0
	while i < _interceptors.size():
		var it: Dictionary = _interceptors[i]
		it.t += dt
		var k := clampf(float(it.t) / TAU, 0.0, 1.0)
		# a slight loft so it reads as a missile, not a laser
		var p: Vector3 = (it.from as Vector3).lerp(it.to, k) + Vector3(0, 0.02 * sin(k * PI), 0)
		_orient(it.node, p, (it.to as Vector3) - (it.from as Vector3))
		it.acc += dt
		if float(it.acc) > 0.02:
			it.acc = 0.0
			phys.fx.trail(p, Color(0.92, 0.92, 0.9, 0.5))
		if k >= 1.0:
			_release(it.node)
			_interceptors.remove_at(i)
			var f: Dictionary = it.flight
			var j := phys.flights.find(f)
			if j >= 0:
				var wid: String = (f.w as Dictionary).id
				phys.kill_flight(j)
				shots_down += 1
				intercepted.emit(it.to, wid)
			phys.fx.air_burst(it.to, 0.7)
			phys.sfx.play("boom", it.to, 0.35)
			continue
		i += 1


## An anti-ship missile from a live coastal launcher at the battleship (none if every
## launcher is destroyed). Returns true if one was fired.
func fire_coastal() -> bool:
	if phys.island.ship == null or _missiles.size() >= MAX_MISSILES:
		return false
	var sites := _sites(ENEMY_KINDS)
	if sites.is_empty():
		return false
	var s: Array = sites[rng.randi() % sites.size()]
	var from: Vector3 = (s[1] as Vector3) + Vector3(0, 0.006, 0)
	var ship: PlayerShip = phys.island.ship
	var to := ship.transform * Vector3(rng.randf_range(-0.04, 0.04), PlayerShip.FB + 0.002, 0.0)
	var w := WeaponTable.get_weapon("antiship")
	var pl := WeaponFlight.plan(w, from, to, phys.surface, PhysicsTest.G)
	var n := _node()
	n.mesh = _mesh_enemy
	n.visible = true
	_missiles.append({"plan": pl, "t": 0.0, "node": n, "acc": 0.0, "ciws": false, "to": to})
	phys.fx.muzzle(from, Vector3.UP)
	phys.sfx.play("launch", from, 0.5)
	return true


func _step_missiles(dt: float) -> void:
	var i := 0
	while i < _missiles.size():
		var m: Dictionary = _missiles[i]
		m.t += dt
		var pl: Dictionary = m.plan
		var p := WeaponFlight.position_at(pl, float(m.t))
		_orient(m.node, p, WeaponFlight.velocity_at(pl, float(m.t)))
		m.acc += dt
		if float(m.acc) > 0.02:
			m.acc = 0.0
			phys.fx.trail(p, Color(0.85, 0.82, 0.78, 0.45))
		var to: Vector3 = m.to
		if not m.ciws and p.distance_to(to) < CIWS_RANGE:
			m.ciws = true
			var gun := phys.island.ship.transform * PlayerShip.LAUNCHERS["gun"]
			phys.fx.tracer(gun, p)
			phys.sfx.play("thump", gun, 0.3)
			if rng.randf() < CIWS_P:
				_release(m.node)
				_missiles.remove_at(i)
				phys.fx.air_burst(p, 0.6)
				phys.sfx.play("boom", p, 0.4)
				ciws_kill.emit(p)
				continue
		if float(m.t) >= float(pl.T):
			_release(m.node)
			_missiles.remove_at(i)
			ship_hits += 1
			phys.fx.ship_fire(to, 0.9)
			phys.sfx.play("boom", to, 0.8)
			ship_hit.emit(to)
			continue
		i += 1
