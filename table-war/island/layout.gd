class_name IslandLayout
extends RefCounted
## Hand-authored island plan in table metres (x = east, z = south/front,
## origin = slab centre). Terrain shaping (pads, road grading) and prop
## placement both read from here so they always agree.

# Land blobs: (cx, cz, rx, rz). Island mask = smooth union of ellipses + noise.
var blobs: Array[Vector4] = [
	Vector4(0.02, 0.02, 0.36, 0.22),    # main body
	Vector4(0.33, 0.075, 0.16, 0.075),  # east cape (lighthouse)
	Vector4(-0.29, -0.05, 0.20, 0.18),  # west lobe (air base)
	Vector4(0.17, -0.12, 0.23, 0.12),   # ridge massif
	Vector4(-0.05, 0.17, 0.14, 0.09),   # south shore (lagoon bar)
]

# Ridge spine (x,z) with peak height above sea (m)
var ridge := PackedVector2Array([Vector2(-0.03, -0.14), Vector2(0.10, -0.19), Vector2(0.23, -0.17), Vector2(0.31, -0.11), Vector2(0.37, -0.04)])
var ridge_peak := 0.052
var ridge_width := 0.055

# small hills: (x, z, radius, height)
var knolls: Array[Vector4] = [
	Vector4(-0.19, -0.175, 0.028, 0.011),  # radar knoll
	Vector4(0.465, 0.08, 0.026, 0.010),    # lighthouse rock
	Vector4(0.215, 0.035, 0.03, 0.006),    # fort rise
]

# Lagoon (ellipse) and its channel to the sea (capsule)
var lagoon := Vector4(-0.16, 0.115, 0.075, 0.042)
var lagoon_depth := -0.006
var channel_a := Vector2(-0.12, 0.14)
var channel_b := Vector2(-0.075, 0.30)
var channel_w := 0.013

# Air base
var runway_center := Vector2(-0.285, 0.0)
var runway_angle := deg_to_rad(-9.0)   # rotation about +y of the runway axis from +x
var runway_len := Scale.m(600.0)      # short tactical strip 600 x 25 m
var runway_w := Scale.m(25.0)
var taxi_w := Scale.m(15.0)
var taxi_offset := Scale.m(60.0)      # parallel taxiway centreline, north of runway
var apron_center := Vector2(-0.30, -0.062)
var apron_size := Vector2(0.15, 0.034)
var base_height := 0.0062
var silo_center := Vector2(-0.43, -0.12)
var radar_pos := Vector2(-0.19, -0.175)

# Town & harbour
var town_center := Vector2(0.095, 0.085)
var town_radius := 0.092
var harbour_x0 := 0.035
var harbour_x1 := 0.165
var quay_z := 0.192          # quay wall line
var quay_land_z := 0.150     # flattened port apron behind the quay
var basin_z := 0.25
var quay_height := 0.0028
var pier_x := 0.13
var pier_len := Scale.m(120.0)
var fort_pos := Vector2(0.215, 0.035)
var lighthouse_pos := Vector2(0.468, 0.08)

# Vegetation zones: (x, z, radius)
var groves: Array[Vector3] = [
	Vector3(-0.045, 0.10, 0.04),
	Vector3(0.18, 0.13, 0.025),
	Vector3(0.30, 0.105, 0.03),
	Vector3(-0.22, 0.075, 0.03),
	Vector3(0.0, 0.0, 0.03),
]
var sabkha_center := Vector2(-0.33, 0.115)
var sabkha_radius := 0.085

const ROAD_W := 0.004          # 8 m two-lane road at 1:2000

# Road polylines (smoothed with Catmull-Rom).
var roads: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(-0.235, -0.07), Vector2(-0.17, -0.05), Vector2(-0.10, -0.01), Vector2(-0.03, 0.03), Vector2(0.03, 0.06), Vector2(0.10, 0.075), Vector2(0.17, 0.07), Vector2(0.26, 0.085), Vector2(0.35, 0.075), Vector2(0.43, 0.08), Vector2(0.455, 0.08)]),
	PackedVector2Array([Vector2(0.10, 0.075), Vector2(0.098, 0.12), Vector2(0.10, 0.165)]),
	PackedVector2Array([Vector2(-0.215, -0.08), Vector2(-0.205, -0.12), Vector2(-0.192, -0.16)]),
	PackedVector2Array([Vector2(-0.37, -0.085), Vector2(-0.41, -0.10), Vector2(-0.43, -0.115)]),
	PackedVector2Array([Vector2(0.17, 0.07), Vector2(0.20, 0.045), Vector2(0.21, 0.037)]),
]

var _road_samples: Array[PackedVector2Array] = []

## The plan above was drawn for a 1.09 x 0.8 m rectangle; the slab is now a
## 1.0 m disc, so the whole plan is squeezed in x and stretched in z once here.
const SX := 0.86
const SZ := 1.12


func _init() -> void:
	var sv := Vector2(SX, SZ)
	for k in blobs.size():
		var b := blobs[k]
		blobs[k] = Vector4(b.x * SX, b.y * SZ, b.z * SX, b.w * SZ)
	for k in ridge.size():
		ridge[k] *= sv
	for k in knolls.size():
		var n := knolls[k]
		knolls[k] = Vector4(n.x * SX, n.y * SZ, n.z, n.w)
	lagoon = Vector4(lagoon.x * SX, lagoon.y * SZ, lagoon.z * SX, lagoon.w * SZ)
	channel_a *= sv
	channel_b *= sv
	runway_center *= sv
	# apron north of the parallel taxiway (derived, not scaled)
	var rd0 := runway_dir()
	var north0 := Vector2(rd0.y, -rd0.x)
	apron_size = Vector2(Scale.m(260.0), Scale.m(70.0))
	apron_center = runway_center + rd0 * Scale.m(10.0) + north0 * (taxi_offset + taxi_w * 0.5 + Scale.m(10.0) + apron_size.y * 0.5)
	# missile pad in the far north-west corner of the base
	silo_center = runway_center + rd0 * Scale.m(-205.0) + north0 * Scale.m(236.0)
	silo_center *= sv
	radar_pos *= sv
	town_center *= sv
	harbour_x0 *= SX
	harbour_x1 *= SX
	pier_x *= SX
	quay_z *= SZ
	quay_land_z *= SZ
	basin_z *= SZ
	fort_pos *= sv
	lighthouse_pos *= sv
	sabkha_center *= sv
	for k in groves.size():
		var g := groves[k]
		groves[k] = Vector3(g.x * SX, g.y * SZ, g.z)
	for r in roads.size():
		var pts := roads[r]
		for k in pts.size():
			pts[k] *= sv
		roads[r] = pts
	roads.append(PackedVector2Array([Vector2(0.255, 0.094), Vector2(0.262, 0.118), Vector2(0.27, 0.141)]))


# --- realism pass: world-coordinate features (not scaled) -------------------------------
# wadis: dry stream beds from the ridge to the coast / lagoon
var wadis: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(0.235, -0.095), Vector2(0.28, -0.04), Vector2(0.33, 0.01), Vector2(0.38, 0.035), Vector2(0.425, 0.045)]),
	PackedVector2Array([Vector2(0.02, -0.12), Vector2(-0.02, -0.07), Vector2(-0.05, -0.01), Vector2(-0.075, 0.05), Vector2(-0.11, 0.105)]),
	PackedVector2Array([Vector2(0.10, -0.205), Vector2(0.09, -0.245), Vector2(0.085, -0.285)]),
]
const WADI_W := 0.009
# offshore sandbar (capsule) south-west of the lagoon mouth
var sandbar_a := Vector2(-0.31, 0.215)
var sandbar_b := Vector2(-0.235, 0.30)
# coastal power + desalination plant (south-east coast)
var plant_center := Vector2(0.272, 0.150)
var plant_size := Vector2(0.074, 0.044)
# desert tyre tracks (pairs of ruts)
var tracks: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(-0.10, -0.075), Vector2(-0.06, -0.10), Vector2(-0.02, -0.115), Vector2(0.03, -0.11)]),
	PackedVector2Array([Vector2(-0.36, 0.09), Vector2(-0.31, 0.12), Vector2(-0.26, 0.16), Vector2(-0.21, 0.19)]),
	PackedVector2Array([Vector2(0.12, 0.03), Vector2(0.16, -0.02), Vector2(0.22, -0.05), Vector2(0.27, -0.045), Vector2(0.31, -0.02)]),
	PackedVector2Array([Vector2(0.34, 0.06), Vector2(0.36, 0.11), Vector2(0.33, 0.15)]),
]


## Base perimeter (runway frame): along [-a0, a1], lateral north [s0, s1]
func base_frame() -> Dictionary:
	return {"along0": -runway_len * 0.5 - 0.022, "along1": runway_len * 0.5 + 0.012, "lat0": -runway_w * 0.5 - 0.016, "lat1": 0.15}


func base_local(p: Vector2) -> Vector2:
	var rd := runway_dir()
	var north := Vector2(rd.y, -rd.x)
	var d := p - runway_center
	return Vector2(d.dot(rd), d.dot(north))


func base_world(along: float, lat: float) -> Vector2:
	var rd := runway_dir()
	var north := Vector2(rd.y, -rd.x)
	return runway_center + rd * along + north * lat


func inside_base(p: Vector2, margin := 0.0) -> bool:
	var f := base_frame()
	var l := base_local(p)
	return l.x > f.along0 - margin and l.x < f.along1 + margin and l.y > f.lat0 - margin and l.y < f.lat1 + margin


func wadi_distance(p: Vector2) -> float:
	var best := 1e9
	for w in wadis:
		best = minf(best, poly_dist(p, w).x)
	return best


func runway_dir() -> Vector2:
	return Vector2(cos(runway_angle), -sin(runway_angle))


## Signed distance-ish weight helpers -------------------------------------------------

static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func poly_dist(p: Vector2, pts: PackedVector2Array) -> Vector2:
	## returns (distance, normalised position along polyline 0..1)
	var best := 1e9
	var best_t := 0.0
	var total := 0.0
	var lens := PackedFloat32Array()
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		lens.append(l)
		total += l
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			best_t = (acc + lens[i] * t) / maxf(total, 1e-9)
		acc += lens[i]
	return Vector2(best, best_t)


## Oriented rectangle coverage: 1 inside, falls to 0 over `feather` outside.
static func rect_weight(p: Vector2, c: Vector2, dir: Vector2, half: Vector2, feather: float) -> float:
	var d := p - c
	var lx := absf(d.dot(dir)) - half.x
	var lz := absf(d.dot(Vector2(-dir.y, dir.x))) - half.y
	var outside := Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length()
	return 1.0 - smoothstep(0.0, feather, outside)


func road_samples() -> Array[PackedVector2Array]:
	if _road_samples.is_empty():
		for r in roads:
			_road_samples.append(catmull(r, 0.003))
	return _road_samples


static func catmull(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		var segs := maxi(2, int(ceil(p1.distance_to(p2) / step)))
		for s in segs:
			var t := float(s) / segs
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out


func road_distance(p: Vector2) -> float:
	var best := 1e9
	for r in road_samples():
		for i in r.size() - 1:
			# cheap reject
			if absf(r[i].x - p.x) > 0.03 + best or absf(r[i].y - p.y) > 0.03 + best:
				continue
			best = minf(best, seg_dist(p, r[i], r[i + 1]))
	return best


## Distance to anything "built" (runway, apron, harbour, roads): used to keep
## vegetation and rocks off infrastructure.
func infrastructure_distance(p: Vector2) -> float:
	var d := road_distance(p) - ROAD_W * 0.5
	var rd := runway_dir()
	d = minf(d, _rect_dist(p, runway_center, rd, Vector2(runway_len * 0.5 + 0.01, runway_w * 0.5 + 0.004)))
	d = minf(d, _rect_dist(p, apron_center, rd, apron_size * 0.5))
	d = minf(d, _rect_dist(p, runway_center + Vector2(rd.y, -rd.x) * taxi_offset, rd, Vector2(runway_len * 0.5, taxi_w * 0.5 + 0.002)))
	d = minf(d, _rect_dist(p, plant_center, Vector2.RIGHT, plant_size * 0.5 + Vector2(0.003, 0.003)))
	d = minf(d, _rect_dist(p, silo_center, rd, Vector2(0.035, 0.024)))
	d = minf(d, _rect_dist(p, Vector2((harbour_x0 + harbour_x1) * 0.5, (quay_land_z + quay_z) * 0.5), Vector2.RIGHT, Vector2((harbour_x1 - harbour_x0) * 0.5, (quay_z - quay_land_z) * 0.5 + 0.004)))
	return d


static func _rect_dist(p: Vector2, c: Vector2, dir: Vector2, half: Vector2) -> float:
	var d := p - c
	var lx := absf(d.dot(dir)) - half.x
	var lz := absf(d.dot(Vector2(-dir.y, dir.x))) - half.y
	return Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length() + minf(maxf(lx, lz), 0.0)


func lush_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var l := 0.0
	for g in groves:
		var d := p.distance_to(Vector2(g.x, g.y)) / g.z
		l = maxf(l, 1.0 - smoothstep(0.6, 1.4, d))
	# lagoon shore oasis
	var ld := Vector2((x - lagoon.x) / lagoon.z, (z - lagoon.y) / lagoon.w).length()
	l = maxf(l, (1.0 - smoothstep(1.0, 1.6, ld)) * 0.8)
	return l


## Terrain pads: flatten areas for the runway, apron, harbour quay etc.
func apply_pads(t: IslandTerrain) -> void:
	var sea := IslandTerrain.SEA
	var rd := runway_dir()
	var town := town_center
	for j in IslandTerrain.NZ + 1:
		for i in IslandTerrain.NX + 1:
			var k := t.idx(i, j)
			var v := t.vpos(i, j)
			var p := Vector2(v.x, v.z)
			var h := v.y
			# air base: runway + apron + silo pad share one level
			var w := rect_weight(p, runway_center, rd, Vector2(runway_len * 0.5 + 0.012, runway_w * 0.5 + 0.008), 0.03)
			var north := Vector2(rd.y, -rd.x)
			w = maxf(w, rect_weight(p, runway_center + north * taxi_offset * 0.5, rd, Vector2(runway_len * 0.5 + 0.008, taxi_offset * 0.5 + 0.008), 0.025))
			w = maxf(w, rect_weight(p, apron_center, rd, apron_size * 0.5 + Vector2(0.006, 0.006), 0.025))
			w = maxf(w, rect_weight(p, silo_center, rd, Vector2(0.038, 0.026), 0.02))
			if w > 0.0:
				h = lerpf(h, sea + base_height, w)
			# power plant pad
			var pw := rect_weight(p, plant_center, Vector2.RIGHT, plant_size * 0.5 + Vector2(0.004, 0.004), 0.02)
			if pw > 0.0:
				h = lerpf(h, sea + 0.0032, pw)
			# town: soften relief
			var td := p.distance_to(town) / town_radius
			if td < 1.3:
				var tw := (1.0 - smoothstep(0.7, 1.3, td)) * 0.7
				h = lerpf(h, sea + 0.0075 + (h - sea - 0.0075) * 0.25, tw)
			# harbour: quay apron (land) + dredged basin (water)
			if p.x > harbour_x0 - 0.02 and p.x < harbour_x1 + 0.02:
				var ex := 1.0 - smoothstep(0.0, 0.02, maxf(harbour_x0 - p.x, p.x - harbour_x1))
				if p.y > quay_land_z - 0.02 and p.y <= quay_z - 0.005:
					var ez := 1.0 - smoothstep(0.0, 0.02, quay_land_z - p.y)
					h = lerpf(h, sea + quay_height, ex * ez)
				elif p.y > quay_z - 0.005 and p.y < basin_z + 0.03:
					var ez2 := 1.0 - smoothstep(basin_z - 0.02, basin_z + 0.03, p.y)
					h = lerpf(h, minf(h, sea - 0.010), ex * ez2)
			# sabkha: very flat salt pan barely above the sea
			var sd := p.distance_to(sabkha_center) / sabkha_radius
			if sd < 1.2 and h > sea:
				var sw := 1.0 - smoothstep(0.6, 1.2, sd)
				h = lerpf(h, sea + 0.0022 + (h - sea) * 0.12, sw)
			t.hts[k] = h
