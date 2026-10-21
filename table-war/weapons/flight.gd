class_name WeaponFlight
extends RefCounted
## Flight paths for the weapon table (pure functions on diorama-local points).
##
## plan(weapon, from, to, surface, g) -> Dictionary
##   ballistic ("lofted" / "low"): {type: "ballistic", p0, v0, T, g}
##       closed form p(t) = p0 + v0 t + 1/2 g t^2, solved to hit `to` at t = T.
##   cruise: {type: "cruise", pts: PackedVector3Array, cum: PackedFloat32Array, T, crash}
##       leaves the launch point, dives at a limited slope to cruise height above the
##       terrain / sea (looking ahead so it climbs before a hill, with a limited climb
##       rate), flies flat to the target and dives onto it in the last centimetres. If a
##       hill is steeper than the climb limit the path meets it: `crash` is true and the
##       missile explodes there (PhysicsTest detects the surface crossing).
## `surface` is a Callable(x, z) -> float: the height the shell would hit (terrain or
## sea), or -INF where there is nothing (outside the slab).

const DS := 0.004            # cruise path sample step (horizontal, units; terrain cells are 8 mm)
const LOOKAHEAD := 0.04      # cruise: look this far ahead for hills
const CLIMB := 0.9           # cruise: max climb slope (dy / dx)
const DESCEND := 0.9         # cruise: max sink slope while cruising
const LAUNCH_DIVE := 1.4     # cruise: sink slope right after the launch
const DIVE_LEN := 0.022      # cruise: terminal dive length before the target
const OFF_SLAB := 0.078      # cruise: off the slab fly as over the sea (the rim and table are lower)


## `roofs` (optional) is a Callable(x, z) -> float: the top of the buildings there
## (-INF where none). A cruise path climbs over them in time (a tower block is far
## steeper than any hill it must clear).
static func plan(w: Dictionary, from: Vector3, to: Vector3, surface: Callable, g: float, roofs := Callable()) -> Dictionary:
	if String(w.get("arc", "lofted")) == "sortie":
		return _plan_sortie(w, from, to, surface)
	if String(w.get("arc", "lofted")) == "cruise":
		return _plan_cruise(w, from, to, surface, roofs)
	if String(w.get("arc", "lofted")) == "glide":
		return _plan_glide(w, from, to, surface, roofs)
	if String(w.get("arc", "lofted")) == "glidebomb":
		return _plan_glidebomb(w, from, to)
	if String(w.get("arc", "lofted")) == "torpedo":
		return _plan_torpedo(w, from, to, surface)
	var dist := from.distance_to(to)
	var fl: Array = w.get("flight", [2.0, 3.0])
	var T := lerpf(float(fl[0]), float(fl[1]), clampf(dist / 1.6, 0.0, 1.0))
	var gv := Vector3(0, -g, 0)
	var v := (to - from - 0.5 * gv * T * T) / T
	# keep the whole arc under the glass dome: a shorter flight is a lower arc
	if inside_dome(from) and inside_dome(to):
		for _i in 16:
			if _arc_under_dome(from, v, g, T):
				break
			T *= 0.9
			v = (to - from - 0.5 * gv * T * T) / T
	return {"type": "ballistic", "p0": from, "v0": v, "T": T, "g": g, "to": to}


const DOME_MARGIN := 0.02


## Strike-jet sortie: take off from the deck (along +x), climb, fly to the target at
## cruise_alt, release the bombs `RELEASE_LEAD` before it, fly on, turn and come home
## from astern to land on the deck. A path like the cruise missile's (pts / cum / T)
## plus release_t; the jet never touches the terrain and stays under the dome.
const RELEASE_LEAD := 0.035


static func _plan_sortie(w: Dictionary, from: Vector3, to: Vector3, surface: Callable) -> Dictionary:
	var alt: float = w.get("cruise_alt", 0.1)
	var lead: float = w.get("release_lead", RELEASE_LEAD)
	var fwd := Vector3(1, 0, 0)
	var d2 := Vector3(to.x - from.x, 0, to.z - from.z)
	var dir := d2.normalized() if d2.length() > 1e-4 else fwd
	var side := Vector3(-dir.z, 0, dir.x)
	var cruise_y := maxf(from.y, to.y) + alt
	var key: Array[Vector3] = [
		from,
		from + fwd * 0.05 + Vector3(0, 0.012, 0),
		from + fwd * 0.10 + Vector3(0, alt * 0.6, 0),
		Vector3(to.x, cruise_y, to.z) - dir * (lead + 0.06),
		Vector3(to.x, cruise_y, to.z) - dir * lead,
		Vector3(to.x, cruise_y, to.z) + dir * 0.04,
		Vector3(to.x, cruise_y, to.z) + dir * 0.07 + side * 0.06,
		Vector3(to.x, cruise_y, to.z) + side * 0.09,
		from - fwd * 0.14 + Vector3(0, alt * 0.5, 0),
		from - fwd * 0.07 + Vector3(0, 0.015, 0),
		from + Vector3(0, 0.001, 0),
	]
	# reconnaissance: two wide circles round the target at cruise height before home
	var orbit := float(w.get("orbit", 0.0))
	if orbit > 0.0:
		var c := Vector3(to.x, cruise_y, to.z)
		var a0 := atan2(-dir.z, -dir.x)
		var ring: Array[Vector3] = []
		for q in 17:
			var a := a0 + TAU * q / 8.0
			ring.append(c + Vector3(cos(a), 0, sin(a)) * orbit)
		var nk: Array[Vector3] = [key[0], key[1], key[2], key[3], key[4]]
		nk.append_array(ring)
		nk.append_array([key[7], key[8], key[9], key[10]])
		key = nk
	var pts := PackedVector3Array()
	var release_i := 0
	for k in key.size() - 1:
		var p0 := key[maxi(k - 1, 0)]
		var p1 := key[k]
		var p2 := key[k + 1]
		var p3 := key[mini(k + 2, key.size() - 1)]
		var n := maxi(4, int(ceil(p1.distance_to(p2) / 0.01)))
		if k == 4:
			release_i = pts.size()
		for s in n:
			var t := float(s) / n
			var t2 := t * t
			var t3 := t2 * t
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			# clear of the ground (except at the deck) and under the glass
			if k > 0 and k < key.size() - 2:
				var gy := float(surface.call(q.x, q.z))
				if gy > -INF:
					q.y = maxf(q.y, gy + 0.025)
			q.y = minf(q.y, dome_ceiling(q.x, q.z) - 0.01)
			pts.append(q)
	pts.append(key[key.size() - 1])
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	var L := cum[cum.size() - 1]
	var T := L / float(w.get("speed", 0.14))
	return {"type": "cruise", "sortie": true, "pts": pts, "cum": cum, "T": T, "crash": false, "to": to,
		"release_t": T * cum[release_i] / L}


## Highest a shot may fly at (x, z): under the glass dome over the island, with a margin.
static func dome_ceiling(x: float, z: float) -> float:
	if not GlassDome.enabled:
		return 100.0
	var r2 := x * x + z * z
	var R := GlassDome.R
	if r2 >= R * R:
		return IslandTerrain.SEA
	return IslandTerrain.SEA + GlassDome.K * sqrt(R * R - r2) - DOME_MARGIN


static func inside_dome(p: Vector3) -> bool:
	return p.y <= dome_ceiling(p.x, p.z) + DOME_MARGIN


static func _arc_under_dome(p0: Vector3, v: Vector3, g: float, T: float) -> bool:
	for k in range(1, 32):
		var t := T * k / 32.0
		var p := p0 + v * t + 0.5 * Vector3(0, -g, 0) * t * t
		if p.y > dome_ceiling(p.x, p.z):
			return false
	return true


static func position_at(pl: Dictionary, t: float) -> Vector3:
	if pl.type == "ballistic":
		return (pl.p0 as Vector3) + (pl.v0 as Vector3) * t + 0.5 * Vector3(0, -float(pl.g), 0) * t * t
	var pts: PackedVector3Array = pl.pts
	var cum: PackedFloat32Array = pl.cum
	var L: float = cum[cum.size() - 1]
	if t >= float(pl.T):
		return pts[pts.size() - 1]
	var u := clampf(t / float(pl.T), 0.0, 1.0) * L
	var i := clampi(cum.bsearch(u) - 1, 0, pts.size() - 2)
	var seg := cum[i + 1] - cum[i]
	var f := 0.0 if seg <= 1e-9 else (u - cum[i]) / seg
	return pts[i].lerp(pts[i + 1], clampf(f, 0.0, 1.0))


static func velocity_at(pl: Dictionary, t: float) -> Vector3:
	if pl.type == "ballistic":
		return (pl.v0 as Vector3) + Vector3(0, -float(pl.g), 0) * t
	var dt := 0.01
	return (position_at(pl, t + dt) - position_at(pl, maxf(t - dt, 0.0))) / (dt + minf(t, dt))


## A path through `pts` flown in `T` (the same form as a cruise path).
static func _path(pts: PackedVector3Array, T: float, type: String, to: Vector3) -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	return {"type": type, "pts": pts, "cum": cum, "T": T, "crash": false, "to": to}


static func _path_len(pts: PackedVector3Array) -> float:
	var L := 0.0
	for k in range(1, pts.size()):
		L += pts[k].distance_to(pts[k - 1])
	return L


## Hypersonic glide vehicle: a short steep boost to the top of the arc (a fifth of the
## way), then a long, depressed glide that weaves side to side (two S-turns, the
## manoeuvres that make it hard to intercept) sinking towards the target, kept clear
## of the ground and the roofs, and a steep terminal dive the last eighth.
static func _plan_glide(w: Dictionary, from: Vector3, to: Vector3, surface: Callable, roofs: Callable) -> Dictionary:
	var d2 := Vector2(to.x - from.x, to.z - from.z)
	var D := maxf(d2.length(), 1e-4)
	var dir := d2 / D
	var side := Vector2(-dir.y, dir.x)
	var top := maxf(from.y, to.y) + clampf(D * 0.32, 0.05, 0.22)
	var low := maxf(from.y, to.y) + clampf(D * 0.08, 0.025, 0.06)
	var weave := clampf(D * 0.06, 0.008, 0.04)
	var n := 90
	var pts := PackedVector3Array()
	var y_d0 := -INF
	for k in n + 1:
		var u := float(k) / n
		var h := Vector2(from.x, from.z) + d2 * u
		var env := smoothstep(0.22, 0.36, u) * (1.0 - smoothstep(0.72, 0.86, u))
		h += side * weave * env * sin(TAU * 2.0 * (u - 0.22) / 0.64)
		var y: float
		if u < 0.2:
			y = lerpf(from.y, top, sin(u / 0.2 * PI * 0.5))
		elif u < 0.87:
			var g := (u - 0.2) / 0.67
			y = lerpf(top, low, smoothstep(0.0, 1.0, g))
			var gy := float(surface.call(h.x, h.y))
			if roofs.is_valid():
				gy = maxf(gy, float(roofs.call(h.x, h.y)))
			if gy > -INF:
				y = maxf(y, gy + 0.02)
		else:
			if y_d0 == -INF:
				y_d0 = pts[pts.size() - 1].y
			var f := (u - 0.87) / 0.13
			y = lerpf(y_d0, to.y, f * f * 0.5 + f * 0.5)
		pts.append(Vector3(h.x, y, h.y))
	pts[pts.size() - 1] = to
	var fl: Array = w.get("flight", [1.1, 2.2])
	var T := clampf(_path_len(pts) / float(w.get("speed", 1.0)), float(fl[0]), float(fl[1]))
	return _path(pts, T, "glide", to)


## Glide bomb: released by a jet far out, it glides in on its wings, flat at first,
## steeper at the end, onto the target.
static func _plan_glidebomb(w: Dictionary, from: Vector3, to: Vector3) -> Dictionary:
	var n := 40
	var pts := PackedVector3Array()
	for k in n + 1:
		var u := float(k) / n
		var p := from.lerp(to, u)
		p.y = lerpf(from.y, to.y, u * u)
		pts.append(p)
	var fl: Array = w.get("flight", [0.6, 3.0])
	var T := clampf(_path_len(pts) / float(w.get("speed", 0.2)), float(fl[0]), float(fl[1]))
	return _path(pts, T, "cruise", to)


## Torpedo: dropped over the side, it runs just under the surface straight at the
## target; a torpedo cannot leave the water, so it goes off where the sea ends (the
## shore) if the target is on land.
const TORPEDO_DEPTH := 0.0016


static func _plan_torpedo(w: Dictionary, from: Vector3, to: Vector3, surface: Callable) -> Dictionary:
	var d2 := Vector2(to.x - from.x, to.z - from.z)
	var D := maxf(d2.length(), 1e-4)
	var dir := d2 / D
	var run_y := IslandTerrain.SEA - TORPEDO_DEPTH
	var pts := PackedVector3Array([from])
	var n := maxi(int(ceil(D / DS)), 2)
	var end := to
	for k in range(1, n + 1):
		var q := Vector2(from.x, from.z) + d2 * float(k) / n
		var g := float(surface.call(q.x, q.y))
		var y := run_y if k > 2 else lerpf(from.y, run_y, float(k) / 2.0)
		if g > IslandTerrain.SEA + 1e-5 and k > 2:
			end = Vector3(q.x, IslandTerrain.SEA, q.y)    # the shore: it hits the beach
			pts.append(end)
			break
		pts.append(Vector3(q.x, y, q.y))
	if pts[pts.size() - 1] != end:
		end = Vector3(to.x, minf(to.y, IslandTerrain.SEA), to.z)
		pts[pts.size() - 1] = end
	var fl: Array = w.get("flight", [0.8, 9.0])
	var T := clampf(_path_len(pts) / float(w.get("speed", 0.16)), float(fl[0]), float(fl[1]))
	var pl := _path(pts, T, "torpedo", end)
	return pl


static func _plan_cruise(w: Dictionary, from: Vector3, to: Vector3, surface: Callable, roofs := Callable()) -> Dictionary:
	var alt: float = w.get("cruise_alt", 0.006)
	var d2 := Vector2(to.x - from.x, to.z - from.z)
	var D := d2.length()
	var dir := d2 / D if D > 1e-6 else Vector2(0, -1)
	var n := maxi(int(ceil(D / DS)), 2)
	var step := D / n
	# ground under each sample and the required cruise height (with look-ahead)
	var ground := PackedFloat32Array()
	ground.resize(n + 1)
	var roof := PackedFloat32Array()
	roof.resize(n + 1)
	roof.fill(-INF)
	for k in n + 1:
		var q := Vector2(from.x, from.z) + dir * step * k
		var g := float(surface.call(q.x, q.y))
		# outside the slab: fly over the table / the wooden rim, never below it
		ground[k] = g if g > -INF else OFF_SLAB
		if roofs.is_valid():
			roof[k] = float(roofs.call(q.x, q.y))
			ground[k] = maxf(ground[k], roof[k])
	var look := int(ceil(LOOKAHEAD / step))
	var req := PackedFloat32Array()
	req.resize(n + 1)
	# max of ground[k .. k+look]: sliding-window maximum from the end (monotonic deque)
	var dq := PackedInt32Array()
	var head := 0
	for k in range(n, -1, -1):
		while dq.size() > head and ground[dq[dq.size() - 1]] <= ground[k]:
			dq.resize(dq.size() - 1)
		dq.append(k)
		while dq[head] > k + look:
			head += 1
		req[k] = ground[dq[head]] + alt
	var dive_k := maxi(n - int(ceil(DIVE_LEN / step)), 1)
	# start climbing early enough for a building (a tower block is far steeper than
	# any hill): before each roof, the height wanted rises no faster than CLIMB
	if roofs.is_valid():
		var need := -INF
		for k in range(n, -1, -1):
			need = maxf(need - CLIMB * step, roof[k] + alt if roof[k] > -INF else -INF)
			if k < dive_k:
				req[k] = maxf(req[k], need)
	var pts := PackedVector3Array([from])
	var y := from.y
	var launched := true    # still sinking from the launch height
	var crash := false
	var y_dive0 := 0.0
	for k in range(1, n + 1):
		var want: float
		if k >= dive_k:
			if k == dive_k:
				y_dive0 = y
			var f := float(k - dive_k) / float(maxi(n - dive_k, 1))
			want = lerpf(y_dive0, to.y, f * f * (3.0 - 2.0 * f) * 0.6 + f * 0.4)
			# over a roof on the way down: keep clear of it (then a steeper plunge)
			if k < n:
				want = maxf(want, ground[k] + alt * 0.25)
			y = want
		else:
			want = req[k]
			if launched:
				y = maxf(want, y - LAUNCH_DIVE * step)
				if y <= want + 1e-6:
					launched = false
			else:
				y = clampf(want, y - DESCEND * step, y + CLIMB * step)
		var q := Vector2(from.x, from.z) + dir * step * k
		pts.append(Vector3(q.x, y, q.y))
		if k < n - 1 and y < ground[k]:
			crash = true
	pts[pts.size() - 1] = to
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	var L := cum[cum.size() - 1]
	var fl: Array = w.get("flight", [1.5, 3.0])
	var T := clampf(L / float(w.get("speed", 0.4)), float(fl[0]), float(fl[1]))
	return {"type": "cruise", "pts": pts, "cum": cum, "T": T, "crash": crash, "to": to}
