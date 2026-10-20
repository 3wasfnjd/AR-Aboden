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


static func plan(w: Dictionary, from: Vector3, to: Vector3, surface: Callable, g: float) -> Dictionary:
	if String(w.get("arc", "lofted")) == "cruise":
		return _plan_cruise(w, from, to, surface)
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


## Highest a shot may fly at (x, z): under the glass dome over the island, with a margin.
static func dome_ceiling(x: float, z: float) -> float:
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


static func _plan_cruise(w: Dictionary, from: Vector3, to: Vector3, surface: Callable) -> Dictionary:
	var alt: float = w.get("cruise_alt", 0.006)
	var d2 := Vector2(to.x - from.x, to.z - from.z)
	var D := d2.length()
	var dir := d2 / D if D > 1e-6 else Vector2(0, -1)
	var n := maxi(int(ceil(D / DS)), 2)
	var step := D / n
	# ground under each sample and the required cruise height (with look-ahead)
	var ground := PackedFloat32Array()
	ground.resize(n + 1)
	for k in n + 1:
		var q := Vector2(from.x, from.z) + dir * step * k
		var g := float(surface.call(q.x, q.y))
		# outside the slab: fly over the table / the wooden rim, never below it
		ground[k] = g if g > -INF else OFF_SLAB
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
