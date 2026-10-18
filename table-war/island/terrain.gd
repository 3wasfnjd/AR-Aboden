class_name IslandTerrain
extends Node3D
## Faceted low-poly island terrain on a jittered grid, split into chunks.
## Units are table metres; world y of the heightmap is absolute (table top = 0).

const CELL := 0.008
const NX := 126                 # cells along x  -> 1.008 m (square grid)
const NZ := 126                 # cells along z
const CX := 21                  # cells per chunk (x)  -> 6 chunks (a crater rebuilds ~1/4 of the old 42-cell chunk)
const CZ := 21                  # cells per chunk (z)  -> 6 x 6 = 36 chunks
const RADIUS := 0.5             # round slab: 1.0 m diameter
const PLINTH_H := 0.018         # wooden plinth top (slab sits on it)
const SEA := 0.078              # sea surface height (top of resin)
const DEPTH_RANGE := 0.04       # metres encoded in the water depth texture

var ox := -NX * CELL * 0.5
var oz := -NZ * CELL * 0.5

var hts := PackedFloat32Array()
var jx := PackedFloat32Array()
var jz := PackedFloat32Array()
var scorch := PackedFloat32Array()
var ao := PackedFloat32Array()
var lush := PackedFloat32Array()
var wadi := PackedFloat32Array()       # 1 = dry stream bed, falls off over ~2 widths
var rim := PackedByteArray()        # vertex snapped onto the circular edge
var active := PackedByteArray()     # cell has at least one corner inside the circle

var layout: IslandLayout
var material: StandardMaterial3D
var chunk_nodes: Array[MeshInstance3D] = []
var depth_image: Image
var depth_texture: ImageTexture
var rebuild_count := 0

var _n_base := FastNoiseLite.new()
var _n_coast := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_col := FastNoiseLite.new()
var _n_sab := FastNoiseLite.new()

# last located triangle (filled by _locate)
var _ta := Vector3.ZERO
var _tb := Vector3.ZERO
var _tc := Vector3.ZERO

signal deformed(center: Vector3, radius: float)

# palette (sRGB)
const C_DEEP := Color(0.42, 0.47, 0.45)
const C_SHALLOW := Color(0.74, 0.70, 0.56)
const C_WET := Color(0.72, 0.63, 0.47)
const C_SAND := Color(0.86, 0.77, 0.59)
const C_SABKHA := Color(0.83, 0.81, 0.75)
const C_SABKHA2 := Color(0.70, 0.64, 0.55)
const C_SCRUB := Color(0.77, 0.67, 0.49)
const C_DRY := Color(0.63, 0.59, 0.41)
const C_GRASS := Color(0.47, 0.56, 0.31)
const C_ROCK := Color(0.60, 0.49, 0.40)
const C_ROCK2 := Color(0.49, 0.41, 0.35)
const C_CLIFF := Color(0.50, 0.38, 0.30)
const C_PEAK := Color(0.62, 0.54, 0.46)
const C_GRAVEL := Color(0.66, 0.58, 0.46)
const C_TOWN := Color(0.74, 0.68, 0.58)
const C_DUNE := Color(0.90, 0.70, 0.50)
const C_WADI := Color(0.52, 0.49, 0.40)
const C_REEF := Color(0.46, 0.44, 0.36)
const C_SCORCH := Color(0.13, 0.11, 0.10)
const C_SCORCH_RIM := Color(0.36, 0.30, 0.25)


func size() -> Vector2:
	return Vector2(NX * CELL, NZ * CELL)


func idx(i: int, j: int) -> int:
	return j * (NX + 1) + i


func vpos(i: int, j: int) -> Vector3:
	var k := j * (NX + 1) + i
	return Vector3(ox + i * CELL + jx[k], hts[k], oz + j * CELL + jz[k])


# --------------------------------------------------------------------------------------
# Generation
# --------------------------------------------------------------------------------------

func generate(lay: IslandLayout) -> void:
	layout = lay
	var nv := (NX + 1) * (NZ + 1)
	hts.resize(nv); jx.resize(nv); jz.resize(nv)
	scorch.resize(nv); ao.resize(nv); lush.resize(nv); wadi.resize(nv)
	scorch.fill(0.0); ao.fill(0.0)
	rim.resize(nv); rim.fill(0)
	var inside := PackedByteArray(); inside.resize(nv)
	_setup_noise()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for j in NZ + 1:
		for i in NX + 1:
			var k := idx(i, j)
			jx[k] = rng.randf_range(-0.3, 0.3) * CELL
			jz[k] = rng.randf_range(-0.3, 0.3) * CELL
			var gx := ox + i * CELL
			var gz := oz + j * CELL
			var x := gx + jx[k]
			var z := gz + jz[k]
			var r := sqrt(x * x + z * z)
			inside[k] = 1 if r < RADIUS else 0
			if r >= RADIUS - 0.0005:
				# snap onto the circle: the outermost ring of vertices *is* the cut edge
				x = x / r * RADIUS
				z = z / r * RADIUS
				jx[k] = x - gx
				jz[k] = z - gz
				rim[k] = 1
			hts[k] = _base_height(x, z)
			var wd := layout.wadi_distance(Vector2(x, z)) / IslandLayout.WADI_W
			wadi[k] = 1.0 - smoothstep(0.6, 2.6, wd)
			lush[k] = maxf(layout.lush_at(x, z), wadi[k] * 0.55)
	active.resize(NX * NZ)
	for j in NZ:
		for i in NX:
			var any_in := inside[idx(i, j)] + inside[idx(i + 1, j)] + inside[idx(i, j + 1)] + inside[idx(i + 1, j + 1)]
			active[j * NX + i] = 1 if any_in > 0 else 0
	layout.apply_pads(self)
	_grade_roads()
	_rebuild_depth_image(0, 0, NX, NZ)


func _setup_noise() -> void:
	_n_base.seed = 11; _n_base.frequency = 3.2; _n_base.fractal_octaves = 5
	_n_coast.seed = 23; _n_coast.frequency = 5.0; _n_coast.fractal_octaves = 4
	_n_ridge.seed = 37; _n_ridge.frequency = 11.0; _n_ridge.fractal_octaves = 4
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_detail.seed = 41; _n_detail.frequency = 38.0; _n_detail.fractal_octaves = 2
	_n_col.seed = 5; _n_col.frequency = 9.0; _n_col.fractal_octaves = 3
	_n_sab.seed = 77; _n_sab.frequency = 22.0; _n_sab.fractal_octaves = 3


func island_mask(x: float, z: float) -> float:
	# smooth union of ellipses: m = 1 at blob centres, 0 at the coast
	var acc := 0.0
	for b in layout.blobs:
		var dx := (x - b.x) / b.z
		var dz := (z - b.y) / b.w
		var m := 1.0 - sqrt(dx * dx + dz * dz)
		acc += exp(m * 8.0)
	var mask := log(acc) / 8.0
	mask += _n_coast.get_noise_2d(x, z) * 0.16
	for kn in layout.knolls:
		var d := Vector2(x - kn.x, z - kn.y).length()
		mask = maxf(mask, 0.25 * (1.0 - d / (kn.z * 1.6)))
	# keep a ring of open sea next to the round slab edge
	var e := RADIUS - sqrt(x * x + z * z)
	mask -= maxf(0.0, 0.08 - e) * 6.0
	return mask


func _base_height(x: float, z: float) -> float:
	var m := island_mask(x, z)
	var hs: float
	var nb := _n_base.get_noise_2d(x, z)
	if m >= 0.0:
		hs = 0.0032 * smoothstep(0.0, 0.07, m) + 0.010 * smoothstep(0.06, 0.5, m)
		hs += nb * 0.0045 * smoothstep(0.04, 0.25, m)
		hs += _n_detail.get_noise_2d(x, z) * 0.0009 * smoothstep(0.02, 0.1, m)
		# low barchan-ish dune ridges across the plains (stretched along the wind)
		var dn := 1.0 - absf(_n_sab.get_noise_2d(x * 0.55 + z * 0.25, z * 1.6 - x * 0.3))
		hs += dn * dn * 0.0016 * smoothstep(0.08, 0.25, m) * (1.0 - smoothstep(0.35, 0.6, m))
	else:
		var dm := -m
		# wide sandy shelf (turquoise), then the drop-off into deep blue
		# narrow sandy shelf (real Gulf fringing shelf ~50-100 m), then the drop-off
		hs = -0.0035 * smoothstep(0.0, 0.03, dm) - 0.026 * smoothstep(0.035, 0.30, dm)
		hs += nb * 0.0025 * smoothstep(0.03, 0.2, dm)
		# patch reefs on the outer shelf edge
		var reef := _n_sab.get_noise_2d(x * 1.3 + 40.0, z * 1.3)
		hs += smoothstep(0.25, 0.55, reef) * 0.0022 * (1.0 - smoothstep(0.03, 0.11, dm)) * smoothstep(0.01, 0.03, dm)
	# ridge
	var rd := IslandLayout.poly_dist(Vector2(x, z), layout.ridge)
	var along := pow(sin(PI * clampf(rd.y, 0.0, 1.0)), 0.6)
	var rn := _n_ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var ridge := layout.ridge_peak * along * exp(-pow(rd.x / layout.ridge_width, 2.0)) * (0.55 + 0.6 * rn)
	hs += ridge * smoothstep(-0.12, 0.08, m)
	# knolls
	for kn in layout.knolls:
		var d := Vector2(x - kn.x, z - kn.y).length()
		hs += kn.w * exp(-pow(d / kn.z, 2.0)) * (0.85 + 0.3 * rn)
	# wadis: shallow flat-bottomed dry stream beds cut into the plains
	var wdd := layout.wadi_distance(Vector2(x, z)) / IslandLayout.WADI_W
	if wdd < 2.5 and hs > 0.0:
		var cut := 0.0024 * (1.0 - smoothstep(0.5, 1.6, wdd))
		hs = maxf(hs - cut, minf(hs, 0.0016))
	# offshore sandbar
	var sbd := IslandLayout.seg_dist(Vector2(x, z), layout.sandbar_a, layout.sandbar_b)
	if sbd < 0.016 and hs < 0.0:
		var bar := -0.0024 - 0.012 * pow(sbd / 0.016, 1.6) + _n_detail.get_noise_2d(x, z) * 0.0005
		hs = maxf(hs, bar)
	# lagoon + channel
	var ld := Vector2((x - layout.lagoon.x) / layout.lagoon.z, (z - layout.lagoon.y) / layout.lagoon.w).length()
	ld += _n_coast.get_noise_2d(x * 3.0, z * 3.0) * 0.18
	var cd := IslandLayout.seg_dist(Vector2(x, z), layout.channel_a, layout.channel_b) / layout.channel_w
	# low, flat shore around the lagoon so it reads as a tidal lagoon, not a pit
	var shore_w := maxf(1.0 - smoothstep(0.9, 1.9, ld), 1.0 - smoothstep(1.0, 2.6, cd))
	if shore_w > 0.0 and hs > 0.0:
		hs = lerpf(hs, minf(hs, 0.0022 + 0.004 * smoothstep(1.0, 1.9, minf(ld, cd * 0.7))), shore_w)
	var lw := maxf(1.0 - smoothstep(0.35, 1.1, ld), 1.0 - smoothstep(0.4, 1.3, cd))
	if lw > 0.0:
		var floor_h := layout.lagoon_depth * (0.55 + 0.45 * (1.0 - smoothstep(0.0, 0.9, ld))) + _n_detail.get_noise_2d(x, z) * 0.0008
		hs = lerpf(hs, minf(hs, floor_h), lw)
	return SEA + hs


func _grade_roads() -> void:
	var nv := hts.size()
	var best_d := PackedFloat32Array(); best_d.resize(nv); best_d.fill(1e9)
	var best_h := PackedFloat32Array(); best_h.resize(nv)
	var half := IslandLayout.ROAD_W * 0.5
	var reach := half + 0.012
	for r in layout.road_samples():
		var raw := PackedFloat32Array()
		for p in r:
			raw.append(maxf(height_at(p.x, p.y), SEA + 0.0025))
		# smooth the profile along the road
		for _pass in 4:
			var sm := raw.duplicate()
			for s in raw.size():
				var acc := 0.0
				var cnt := 0
				for o in range(-4, 5):
					var q := clampi(s + o, 0, raw.size() - 1)
					acc += raw[q]
					cnt += 1
				sm[s] = acc / cnt
			raw = sm
		for s in r.size():
			var p := r[s]
			var i0 := clampi(int(floor((p.x - reach - ox) / CELL)), 0, NX)
			var i1 := clampi(int(ceil((p.x + reach - ox) / CELL)), 0, NX)
			var j0 := clampi(int(floor((p.y - reach - oz) / CELL)), 0, NZ)
			var j1 := clampi(int(ceil((p.y + reach - oz) / CELL)), 0, NZ)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var k := idx(i, j)
					var v := vpos(i, j)
					var d := Vector2(v.x, v.z).distance_to(p)
					if d < best_d[k]:
						best_d[k] = d
						best_h[k] = raw[s]
	for k in nv:
		if best_d[k] < reach:
			var f := 1.0 - smoothstep(half + 0.002, reach, best_d[k])
			hts[k] = lerpf(hts[k], best_h[k], f)


# --------------------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------------------

func _tri_h(a: Vector3, b: Vector3, c: Vector3, x: float, z: float) -> float:
	var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(d) < 1e-14:
		return NAN
	var l1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
	var l2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
	var l3 := 1.0 - l1 - l2
	if l1 >= -1e-6 and l2 >= -1e-6 and l3 >= -1e-6:
		return l1 * a.y + l2 * b.y + l3 * c.y
	return NAN


func _cell_tris(i: int, j: int, x: float, z: float) -> float:
	if active[j * NX + i] == 0:
		return NAN
	var v00 := vpos(i, j)
	var v10 := vpos(i + 1, j)
	var v01 := vpos(i, j + 1)
	var v11 := vpos(i + 1, j + 1)
	var h: float
	if (i + j) % 2 == 0:
		h = _tri_h(v00, v01, v11, x, z)
		if not is_nan(h):
			_ta = v00; _tb = v01; _tc = v11
			return h
		h = _tri_h(v00, v11, v10, x, z)
		if not is_nan(h):
			_ta = v00; _tb = v11; _tc = v10
			return h
	else:
		h = _tri_h(v00, v01, v10, x, z)
		if not is_nan(h):
			_ta = v00; _tb = v01; _tc = v10
			return h
		h = _tri_h(v10, v01, v11, x, z)
		if not is_nan(h):
			_ta = v10; _tb = v01; _tc = v11
			return h
	return NAN


func _locate(x: float, z: float) -> float:
	var rr := sqrt(x * x + z * z)
	if rr > RADIUS - 1e-4:
		x = x / rr * (RADIUS - 1e-4)
		z = z / rr * (RADIUS - 1e-4)
	var ci := clampi(int(floor((x - ox) / CELL)), 0, NX - 1)
	var cj := clampi(int(floor((z - oz) / CELL)), 0, NZ - 1)
	var h := _cell_tris(ci, cj, x, z)
	if not is_nan(h):
		return h
	for dj in [-1, 0, 1]:
		for di in [-1, 0, 1]:
			if di == 0 and dj == 0:
				continue
			var i: int = ci + di
			var j: int = cj + dj
			if i < 0 or j < 0 or i >= NX or j >= NZ:
				continue
			h = _cell_tris(i, j, x, z)
			if not is_nan(h):
				return h
	# fallback (sliver gaps at the rim): nearest vertex
	var k := idx(clampi(int(round((x - ox) / CELL)), 0, NX), clampi(int(round((z - oz) / CELL)), 0, NZ))
	_ta = Vector3(x, hts[k], z); _tb = _ta + Vector3(0, 0, 1e-3); _tc = _ta + Vector3(1e-3, 0, 0)
	return hts[k]


## Exact height of the rendered (faceted) surface.
func height_at(x: float, z: float) -> float:
	return _locate(x, z)


## Face normal of the facet under (x, z).
func normal_at(x: float, z: float) -> Vector3:
	_locate(x, z)
	var n := (_tb - _ta).cross(_tc - _ta)
	if n.y < 0.0:
		n = -n
	return n.normalized() if n.length_squared() > 0.0 else Vector3.UP


## Smooth normal from central differences (for placement / alignment).
func smooth_normal_at(x: float, z: float, e := 0.006) -> Vector3:
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func is_inside(x: float, z: float, margin := 0.0) -> bool:
	return x * x + z * z < (RADIUS - margin) * (RADIUS - margin)


## March a ray against the surface (used by the viewer for click-to-target).
func raycast(from: Vector3, dir: Vector3, max_dist := 4.0) -> Variant:
	var t := 0.0
	var step := 0.004
	var prev_above := true
	while t < max_dist:
		var p := from + dir * t
		if is_inside(p.x, p.z):
			var above := p.y > maxf(height_at(p.x, p.z), SEA)
			if not above and prev_above:
				var lo := t - step
				var hi := t
				for _i in 20:
					var mid := (lo + hi) * 0.5
					var q := from + dir * mid
					if q.y > maxf(height_at(q.x, q.z), SEA):
						lo = mid
					else:
						hi = mid
				return from + dir * hi
			prev_above = above
		t += step
	return null


# --------------------------------------------------------------------------------------
# Mesh
# --------------------------------------------------------------------------------------

func build_meshes() -> void:
	if material == null:
		material = MeshBuilder.vc_material(0.92)
	for c in chunk_nodes:
		c.queue_free()
	chunk_nodes.clear()
	for cj in NZ / CZ:
		for ci in NX / CX:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci, cj]
			add_child(mi)
			chunk_nodes.append(mi)
			_build_chunk(ci, cj)


func triangle_count() -> int:
	var n := 0
	for a in active:
		n += a
	return n * 2


## Outer boundary edges of the active mesh (pairs of rim vertex indices), i.e.
## the polygon the cut side of the round slab is built on.
func rim_edges() -> Array[Vector2i]:
	var count := {}
	for j in NZ:
		for i in NX:
			if active[j * NX + i] == 0:
				continue
			var k00 := idx(i, j); var k10 := idx(i + 1, j); var k01 := idx(i, j + 1); var k11 := idx(i + 1, j + 1)
			var tris := [[k00, k01, k11], [k00, k11, k10]] if (i + j) % 2 == 0 else [[k00, k01, k10], [k10, k01, k11]]
			for t in tris:
				for e in 3:
					var a: int = t[e]
					var b: int = t[(e + 1) % 3]
					var key := Vector2i(mini(a, b), maxi(a, b))
					count[key] = count.get(key, 0) + 1
	var out: Array[Vector2i] = []
	for key in count:
		if count[key] == 1:
			out.append(key)
	return out


func _build_chunk(ci: int, cj: int) -> void:
	var mb := MeshBuilder.new()
	mb.verts.resize(0)
	for j in range(cj * CZ, (cj + 1) * CZ):
		for i in range(ci * CX, (ci + 1) * CX):
			if active[j * NX + i] == 0:
				continue
			var v00 := vpos(i, j)
			var v10 := vpos(i + 1, j)
			var v01 := vpos(i, j + 1)
			var v11 := vpos(i + 1, j + 1)
			var k00 := idx(i, j); var k10 := idx(i + 1, j); var k01 := idx(i, j + 1); var k11 := idx(i + 1, j + 1)
			if (i + j) % 2 == 0:
				_face(mb, v00, v01, v11, k00, k01, k11, i * 2 + j * 7919)
				_face(mb, v00, v11, v10, k00, k11, k10, i * 2 + 1 + j * 7919)
			else:
				_face(mb, v00, v01, v10, k00, k01, k10, i * 2 + j * 7919)
				_face(mb, v10, v01, v11, k10, k01, k11, i * 2 + 1 + j * 7919)
	var mesh := mb.commit(null, material)
	var mi := chunk_nodes[cj * (NX / CX) + ci]
	mi.mesh = mesh
	rebuild_count += 1


func _face(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, ka: int, kb: int, kc: int, seed: int) -> void:
	var n := (b - a).cross(c - a).normalized()
	var cen := (a + b + c) / 3.0
	var sc := (scorch[ka] + scorch[kb] + scorch[kc]) / 3.0
	var a_o := (ao[ka] + ao[kb] + ao[kc]) / 3.0
	var lu := (lush[ka] + lush[kb] + lush[kc]) / 3.0
	_face_n = n
	_face_wadi = (wadi[ka] + wadi[kb] + wadi[kc]) / 3.0
	var col := face_color(cen, n.y, lu, sc, a_o, seed)
	_face_n = Vector3.UP
	_face_wadi = 0.0
	mb.tri(a, b, c, col)


static func _hash(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x & 0xffff) / 65535.0


var _face_n := Vector3.UP
var _face_wadi := 0.0


func face_color(cen: Vector3, ny: float, lu: float, sc: float, a_o: float, seed: int) -> Color:
	var hs := cen.y - SEA
	var x := cen.x
	var z := cen.z
	var nc := _n_col.get_noise_2d(x, z)
	var c: Color
	if hs < -0.0018:
		c = C_SHALLOW.lerp(C_DEEP, smoothstep(0.002, 0.026, -hs))
		# patch reefs / seagrass: dark mottling on the shelf
		var rf := _n_sab.get_noise_2d(x * 1.3 + 40.0, z * 1.3)
		c = c.lerp(C_REEF, smoothstep(0.2, 0.5, rf) * (1.0 - smoothstep(0.004, 0.012, -hs)) * 0.8)
	elif hs < 0.0011:
		# wet sand: darkest right at the waterline
		c = C_WET.darkened(0.12 * (1.0 - smoothstep(0.0, 0.0011, hs))).lerp(C_SHALLOW, smoothstep(0.0, -0.0018, hs) * 0.5)
	elif hs < 0.0034 and ny > 0.95:
		c = C_SAND
	else:
		c = C_SCRUB.lerp(C_SAND, clampf(0.55 + 0.5 * nc, 0.0, 1.0))
		c = c.lerp(C_DRY, clampf(smoothstep(0.004, 0.012, hs) * (0.35 + 0.4 * nc), 0.0, 1.0))
		# gravel / desert-pavement patches and wind streaks
		var gv := _n_sab.get_noise_2d(x * 0.35 + 3.0, z * 0.9)
		c = c.lerp(C_GRAVEL, smoothstep(0.05, 0.45, gv) * 0.55 * smoothstep(0.002, 0.005, hs))
		# scattered salt pans on any low, flat ground near the coast
		var pan := _n_sab.get_noise_2d(x * 0.8 + 11.0, z * 0.8 - 7.0)
		var pan_w := smoothstep(0.25, 0.45, pan) * smoothstep(0.0055, 0.003, hs) * smoothstep(0.975, 0.995, ny)
		c = c.lerp(C_SABKHA.lerp(C_SABKHA2, smoothstep(0.3, 0.6, pan)), pan_w * 0.85)
		# olive scrub patches
		var scrub_p := _n_col.get_noise_2d(x * 2.2 - 5.0, z * 2.2 + 3.0)
		c = c.lerp(C_DRY.darkened(0.08), smoothstep(0.2, 0.55, scrub_p) * 0.45 * smoothstep(0.003, 0.006, hs) * smoothstep(0.9, 0.97, ny))
		# broad gravel plains (darker, greyer) and reddish dune fields: breaks up
		# the beige at viewing distance
		var plain := _n_base.get_noise_2d(x * 0.6 + 9.0, z * 0.6 - 4.0)
		c = c.lerp(C_GRAVEL.darkened(0.12), smoothstep(0.0, 0.3, plain) * 0.8 * smoothstep(0.004, 0.008, hs))
		c = c.lerp(C_DUNE, smoothstep(0.05, 0.35, -plain) * 0.6 * smoothstep(0.003, 0.006, hs))
		# wadi beds: coarse darker gravel, green tinge along the banks
		if _face_wadi > 0.0:
			c = c.lerp(C_WADI, _face_wadi * 0.85)
		# compacted ground in the town
		var td := Vector2(x, z).distance_to(layout.town_center) / layout.town_radius
		c = c.lerp(C_TOWN, (1.0 - smoothstep(0.6, 1.1, td)) * 0.6)
		# sabkha salt flats: low, flat, patchy
		var sab := _n_sab.get_noise_2d(x, z)
		var sd := Vector2(x, z).distance_to(layout.sabkha_center) / layout.sabkha_radius
		var sab_w := (1.0 - smoothstep(0.5, 1.15, sd)) * smoothstep(0.0075, 0.004, hs) * smoothstep(0.96, 0.99, ny)
		if sab_w > 0.0:
			var sc2 := C_SABKHA.lerp(C_SABKHA2, smoothstep(-0.1, 0.5, sab))
			c = c.lerp(sc2, sab_w)
		c = c.lerp(C_GRASS, lu * smoothstep(0.0015, 0.004, hs) * smoothstep(0.85, 0.95, ny) * 0.85)
		var rocky := clampf(smoothstep(0.94, 0.78, ny) + smoothstep(0.016, 0.034, hs), 0.0, 1.0)
		var rockc := C_ROCK.lerp(C_ROCK2, clampf(0.5 + nc, 0.0, 1.0))
		c = c.lerp(rockc, rocky)
		c = c.lerp(C_CLIFF, smoothstep(0.72, 0.55, ny))
		c = c.lerp(C_PEAK, smoothstep(0.036, 0.05, hs) * smoothstep(0.6, 0.85, ny))
	var j := 1.0 + (_hash(seed) - 0.5) * 0.09
	if hs > 0.002:
		j *= 1.0 + clampf(_face_n.x * 0.7 - _face_n.z * 0.4, -0.25, 0.25) * 0.35
	c = Color(c.r * j, c.g * j, c.b * j)
	if a_o > 0.0:
		var f := 1.0 - clampf(a_o, 0.0, 1.0) * 0.32
		c = Color(c.r * f, c.g * f, c.b * f)
	if sc > 0.0:
		var sc_col := C_SCORCH_RIM.lerp(C_SCORCH, smoothstep(0.45, 0.9, sc))
		c = c.lerp(sc_col, clampf(sc * 1.3, 0.0, 0.95))
	return c


## Colour of the surface at a point (used for debris tint).
func color_at(x: float, z: float) -> Color:
	var h := height_at(x, z)
	var n := normal_at(x, z)
	return face_color(Vector3(x, h, z), n.y, layout.lush_at(x, z), 0.0, 0.0, 0)


func wadi_at(x: float, z: float) -> float:
	var i := clampi(int(round((x - ox) / CELL)), 0, NX)
	var j := clampi(int(round((z - oz) / CELL)), 0, NZ)
	return wadi[idx(i, j)]


func scorch_at(x: float, z: float) -> float:
	var i := clampi(int(round((x - ox) / CELL)), 0, NX)
	var j := clampi(int(round((z - oz) / CELL)), 0, NZ)
	return scorch[idx(i, j)]


## Darken terrain around a footprint (fake contact shadow / AO baked in vertex colour).
func stamp_ao(center: Vector2, radius: float, strength: float) -> void:
	var i0 := clampi(int(floor((center.x - radius - ox) / CELL)), 0, NX)
	var i1 := clampi(int(ceil((center.x + radius - ox) / CELL)), 0, NX)
	var j0 := clampi(int(floor((center.y - radius - oz) / CELL)), 0, NZ)
	var j1 := clampi(int(ceil((center.y + radius - oz) / CELL)), 0, NZ)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var v := vpos(i, j)
			var d := Vector2(v.x, v.z).distance_to(center) / radius
			if d < 1.0:
				var k := idx(i, j)
				ao[k] = minf(1.0, ao[k] + strength * (1.0 - d * d))


# --------------------------------------------------------------------------------------
# Deformation
# --------------------------------------------------------------------------------------

## Blast a crater: bowl of `depth` inside `radius`, raised rim out to 1.6 r, scorch.
## Only the chunks touching the edited vertices are rebuilt.
func crater(center: Vector3, radius: float, depth: float) -> Array[Vector2i]:
	var rim_r := radius * 1.7
	var i0 := clampi(int(floor((center.x - rim_r - ox) / CELL)) - 1, 1, NX - 1)
	var i1 := clampi(int(ceil((center.x + rim_r - ox) / CELL)) + 1, 1, NX - 1)
	var j0 := clampi(int(floor((center.z - rim_r - oz) / CELL)) - 1, 1, NZ - 1)
	var j1 := clampi(int(ceil((center.z + rim_r - oz) / CELL)) + 1, 1, NZ - 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(center.x * 1e4), int(center.z * 1e4)))
	var floor_min := PLINTH_H + 0.006
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := idx(i, j)
			if rim[k] == 1:
				continue    # never move the cut edge (keeps the slab walls watertight)
			var v := vpos(i, j)
			var d := Vector2(v.x - center.x, v.z - center.z).length() / radius
			var dh := 0.0
			if d < 1.0:
				dh = -depth * (1.0 - d * d) * rng.randf_range(0.85, 1.15)
			elif d < 1.7:
				dh = depth * 0.32 * sin((d - 1.0) / 0.7 * PI) * rng.randf_range(0.7, 1.2)
			hts[k] = maxf(hts[k] + dh, floor_min)
			if d < 2.3:
				scorch[k] = maxf(scorch[k], clampf(1.35 - d * 0.55, 0.0, 1.0) * rng.randf_range(0.85, 1.0))
	var touched: Array[Vector2i] = []
	var nci := NX / CX
	var ncj := NZ / CZ
	for cj in range(clampi((j0 - 1) / CZ, 0, ncj - 1), clampi((j1 + 1) / CZ, 0, ncj - 1) + 1):
		for ci in range(clampi((i0 - 1) / CX, 0, nci - 1), clampi((i1 + 1) / CX, 0, nci - 1) + 1):
			touched.append(Vector2i(ci, cj))
			if not chunk_nodes.is_empty():
				if defer_meshes:
					if not Vector2i(ci, cj) in _pending_chunks:
						_pending_chunks.append(Vector2i(ci, cj))
				else:
					_build_chunk(ci, cj)
	_rebuild_depth_image(i0 - 1, j0 - 1, i1 + 1, j1 + 1)
	deformed.emit(center, rim_r)
	return touched


# --------------------------------------------------------------------------------------
# Water depth texture (read by the water shader)
# --------------------------------------------------------------------------------------

const DEPTH_RES := 2      # depth texels per terrain cell (4 mm texels: crisper shoreline)

## Quest profile: a crater's chunk meshes are rebuilt over the next frames (one per
## frame) instead of all in the impact frame; heights (physics) change at once.
static var defer_meshes := false
var _pending_chunks: Array[Vector2i] = []


func _process(_delta: float) -> void:
	if not _pending_chunks.is_empty():
		var c: Vector2i = _pending_chunks.pop_front()
		_build_chunk(c.x, c.y)


func pending_rebuilds() -> int:
	return _pending_chunks.size()


var _hts0 := PackedFloat32Array()
var _scorch0 := PackedFloat32Array()


## Remember the undamaged surface (after the props stamped their AO).
func snapshot() -> void:
	_hts0 = hts.duplicate()
	_scorch0 = scorch.duplicate()


## Every crater undone: heights, scorch, meshes and the water depth texture.
func reset_damage() -> void:
	if _hts0.is_empty():
		return
	hts = _hts0.duplicate()
	scorch = _scorch0.duplicate()
	_pending_chunks.clear()
	build_meshes()
	_rebuild_depth_image(0, 0, NX, NZ)


func _rebuild_depth_image(i0: int, j0: int, i1: int, j1: int) -> void:
	if depth_image == null:
		depth_image = Image.create(NX * DEPTH_RES + 1, NZ * DEPTH_RES + 1, false, Image.FORMAT_L8)
	for j in range(maxi(j0, 0) * DEPTH_RES, mini(j1, NZ) * DEPTH_RES + 1):
		for i in range(maxi(i0, 0) * DEPTH_RES, mini(i1, NX) * DEPTH_RES + 1):
			var x := ox + i * CELL / DEPTH_RES
			var z := oz + j * CELL / DEPTH_RES
			var d := SEA - height_at(x, z)
			var v := clampf(0.2 + 0.8 * d / DEPTH_RANGE, 0.0, 1.0)
			depth_image.set_pixel(i, j, Color(v, v, v))
	if depth_texture == null:
		depth_texture = ImageTexture.create_from_image(depth_image)
	else:
		depth_texture.update(depth_image)
