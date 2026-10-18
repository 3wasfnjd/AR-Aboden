class_name Toon
extends RefCounted
## Cartoon building kit (build 3): chunky, bright, readable at arm's length on the
## table. Buildings use a "toy" scale of about 1:1000 (twice the 1:2000 terrain) so a
## house is ~1 cm and a skyscraper up to ~8 cm: big shapes, few triangles, flat
## colours (toon shading in island/structure.gdshader).
## Every generator writes into a MeshBuilder whose xform is the structure transform:
## local origin = footprint centre at ground level, `sink` = how far the walls reach
## below it (sloped ground). Walls built with Arch.walls carry window UVs.
## No religious buildings exist in this project (see tests).

const STOREY := 0.0028            # toy storey (m on the table)

# --- palette ----------------------------------------------------------------------------
const PASTEL := [
	Color(0.98, 0.93, 0.80), Color(0.99, 0.80, 0.62), Color(0.80, 0.93, 0.82), Color(0.74, 0.86, 0.98),
	Color(0.99, 0.72, 0.68), Color(0.99, 0.92, 0.55), Color(0.90, 0.82, 0.98), Color(0.95, 0.95, 0.93),
]
const ROOF := Color(0.62, 0.62, 0.66)
const GLASS := [Color(0.42, 0.72, 0.92), Color(0.36, 0.84, 0.84), Color(0.55, 0.62, 0.95), Color(0.70, 0.86, 0.96)]
const WHITE := Color(0.96, 0.96, 0.94)
const RED := Color(0.92, 0.25, 0.20)
const STEEL := Color(0.72, 0.76, 0.80)
const PIPE := Color(0.95, 0.75, 0.20)
const DARK := Color(0.22, 0.24, 0.27)
const OLIVE := Color(0.46, 0.55, 0.33)
const NAVY := Color(0.58, 0.64, 0.70)
const FLAME := Color(1.0, 0.62, 0.15, 0.25)    # alpha < 1 => emissive in the structure shader
const WATER_BLUE := Color(0.30, 0.62, 0.95)


static func storeys(n: float) -> float:
	return n * STOREY


static func pastel(r: RandomNumberGenerator) -> Color:
	return PASTEL[r.randi() % PASTEL.size()]


# ======================================================================================
# city
# ======================================================================================

## Small house: block, coloured parapet, door, rooftop water tank.
static func house(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, r: RandomNumberGenerator) -> void:
	Arch.walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col)
	_rim(mb, Vector3.ZERO, sz.x, sz.z, sz.y, col.darkened(0.18))
	mb.box(Vector3(0, 0.0011, sz.z * 0.5 + 0.00006), Vector3(0.0016, 0.0022, 0.0001), DARK)
	if r.randf() < 0.7:
		mb.cylinder(Vector3(sz.x * 0.22, sz.y, -sz.z * 0.2), 0.0009, 0.0009, 0.0014, 8, WHITE)


## Villa: two offset blocks, a garden wall and a small blue pool.
static func villa(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, r: RandomNumberGenerator) -> void:
	var a := Vector3(-sz.x * 0.18, 0, -sz.z * 0.15)
	Arch.walls(mb, a, sz.x * 0.62, sz.z * 0.6, sz.y, sink, col)
	_rim(mb, a, sz.x * 0.62, sz.z * 0.6, sz.y, col.darkened(0.15))
	var b := Vector3(sz.x * 0.22, 0, sz.z * 0.05)
	Arch.walls(mb, b, sz.x * 0.45, sz.z * 0.5, sz.y * 0.55, sink, col.lightened(0.08))
	_rim(mb, b, sz.x * 0.45, sz.z * 0.5, sz.y * 0.55, col.darkened(0.15))
	# pool + garden
	mb.box(Vector3(-sz.x * 0.2, 0.0003 - sink * 0.5, sz.z * 0.32), Vector3(sz.x * 0.36, 0.0006 + sink, sz.z * 0.22), Color(0.55, 0.80, 0.42))
	mb.box(Vector3(-sz.x * 0.2, 0.00065, sz.z * 0.32), Vector3(sz.x * 0.24, 0.0001, sz.z * 0.13), WATER_BLUE)
	if r.randf() < 0.6:
		mb.sphere(Vector3(sz.x * 0.3, 0.0022, sz.z * 0.36), Vector3.ONE * 0.0016, 3, 6, Color(0.36, 0.70, 0.30))


## Mid-rise block (4-8 storeys): coloured balcony bands every second floor, roof box.
static func midrise(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, r: RandomNumberGenerator) -> void:
	Arch.walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col)
	_rim(mb, Vector3.ZERO, sz.x, sz.z, sz.y, col.darkened(0.2))
	var band: Color = col.darkened(0.22) if r.randf() < 0.5 else (PASTEL[r.randi() % PASTEL.size()] as Color).darkened(0.1)
	var n := int(round(sz.y / STOREY))
	for k in range(2, n, 2):
		mb.box(Vector3(0, k * STOREY, sz.z * 0.5 + 0.0003), Vector3(sz.x * 0.86, 0.0004, 0.0006), band)
		mb.box(Vector3(0, k * STOREY, -sz.z * 0.5 - 0.0003), Vector3(sz.x * 0.86, 0.0004, 0.0006), band)
	mb.box(Vector3(-sz.x * 0.15, sz.y + 0.001, 0), Vector3(sz.x * 0.35, 0.002, sz.z * 0.4), ROOF)


## Skyscraper, three silhouettes picked by the seed:
##   0 stepped glass tower with two setbacks and a spire
##   1 round glass tower with a crown ring
##   2 tapering "sail" slab with a lit crown
static func skyscraper(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, r: RandomNumberGenerator) -> void:
	var v := r.randi() % 3
	var glass: Color = col
	var frame := WHITE.darkened(0.04)
	var pod := storeys(2.0)
	Arch.walls(mb, Vector3.ZERO, sz.x, sz.z, pod, sink, frame)
	_rim(mb, Vector3.ZERO, sz.x, sz.z, pod, frame.darkened(0.12))
	var h := sz.y - pod
	match v:
		0:
			var s0 := Vector2(sz.x * 0.8, sz.z * 0.8)
			var h0 := h * 0.55
			Arch.walls(mb, Vector3(0, pod, 0), s0.x, s0.y, h0, 0.0, glass)
			_rim(mb, Vector3(0, pod, 0), s0.x, s0.y, pod + h0, frame)
			var s1 := s0 * 0.75
			var h1 := h * 0.3
			Arch.walls(mb, Vector3(0, pod + h0, 0), s1.x, s1.y, h1, 0.0, glass.lightened(0.08))
			_rim(mb, Vector3(0, pod + h0, 0), s1.x, s1.y, pod + h0 + h1, frame)
			var s2 := s1 * 0.7
			Arch.walls(mb, Vector3(0, pod + h0 + h1, 0), s2.x, s2.y, h * 0.15, 0.0, glass.lightened(0.15))
			mb.cylinder(Vector3(0, sz.y, 0), 0.0005, 0.0001, h * 0.22, 6, WHITE)
			mb.box(Vector3(0, sz.y + h * 0.22, 0), Vector3(0.0007, 0.0007, 0.0007), Color(1.0, 0.2, 0.2, 0.3))
		1:
			var rr := minf(sz.x, sz.z) * 0.42
			mb.cylinder(Vector3(0, pod, 0), rr, rr * 0.92, h, 14, glass, true, frame)
			for k in range(1, 6):
				mb.cylinder(Vector3(0, pod + h * k / 6.0, 0), rr * 1.02 * (1.0 - 0.08 * k / 6.0), rr * 1.02 * (1.0 - 0.08 * k / 6.0), 0.0005, 14, frame, false)
			mb.cylinder(Vector3(0, sz.y, 0), rr * 0.95, rr * 0.7, h * 0.06, 14, frame)
			mb.cylinder(Vector3(0, sz.y + h * 0.06, 0), 0.0004, 0.0001, h * 0.18, 6, WHITE)
		_:
			# tapering slab: stacked boxes, each a little narrower
			var n := 6
			var y := pod
			for k in n:
				var f := 1.0 - 0.45 * float(k) / n
				var hk := h / n
				Arch.walls(mb, Vector3(0, y, 0), sz.x * 0.85 * f, sz.z * 0.7, hk, 0.0, glass.lightened(0.04 * k))
				y += hk
			mb.box(Vector3(0, sz.y + 0.0012, 0), Vector3(sz.x * 0.4, 0.0024, sz.z * 0.5), Color(1.0, 0.85, 0.45, 0.35))


## Shopping mall: big low box with a glass atrium and a car park.
static func mall(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, _r: RandomNumberGenerator) -> void:
	Arch.walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col, false)
	_rim(mb, Vector3.ZERO, sz.x, sz.z, sz.y, RED)
	mb.box(Vector3(0, sz.y + 0.0012, 0), Vector3(sz.x * 0.4, 0.0024, sz.z * 0.4), GLASS[0])
	mb.box(Vector3(0, sz.y * 0.5, sz.z * 0.5 + 0.0001), Vector3(sz.x * 0.3, sz.y * 0.6, 0.0002), GLASS[1])


## Football stadium: an oval stand ring around a green pitch.
static func stadium(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, _r: RandomNumberGenerator) -> void:
	var seg := 20
	var rx := sz.x * 0.5
	var rz := sz.z * 0.5
	mb.box(Vector3(0, 0.0003 - sink * 0.5, 0), Vector3(sz.x * 0.62, 0.0006 + sink, sz.z * 0.55), Color(0.35, 0.75, 0.32))
	mb.box(Vector3(0, 0.00065, 0), Vector3(sz.x * 0.02, 0.0001, sz.z * 0.5), WHITE)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var o0 := Vector3(cos(a0) * rx, 0, sin(a0) * rz)
		var o1 := Vector3(cos(a1) * rx, 0, sin(a1) * rz)
		var i0 := o0 * 0.72
		var i1 := o1 * 0.72
		var top := Vector3(0, sz.y, 0)
		var c := col if k % 2 == 0 else col.lightened(0.12)
		# outer wall, sloping stand, roof lip
		mb.tri_out(o0 - Vector3(0, sink, 0), o1 - Vector3(0, sink, 0), o1 + top, c.darkened(0.15), o0 + o1)
		mb.tri_out(o0 - Vector3(0, sink, 0), o1 + top, o0 + top, c.darkened(0.15), o0 + o1)
		mb.tri_out(o0 + top, o1 + top, i1 + Vector3(0, 0.001, 0), c, Vector3.UP)
		mb.tri_out(o0 + top, i1 + Vector3(0, 0.001, 0), i0 + Vector3(0, 0.001, 0), c, Vector3.UP)


## TV / communications tower: needle with a pod (a classic war-table target).
static func tv_tower(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var h := sz.y
	mb.cylinder(Vector3(0, -sink, 0), sz.x * 0.5, sz.x * 0.5, sink + 0.002, 8, Color(0.85, 0.85, 0.82))
	mb.cylinder(Vector3(0, 0.002, 0), 0.0016, 0.0009, h * 0.7, 8, WHITE)
	mb.cylinder(Vector3(0, h * 0.62, 0), 0.0012, 0.0040, h * 0.05, 12, RED)
	mb.cylinder(Vector3(0, h * 0.67, 0), 0.0040, 0.0040, h * 0.04, 12, GLASS[0])
	mb.cylinder(Vector3(0, h * 0.71, 0), 0.0040, 0.0010, h * 0.04, 12, RED)
	mb.cylinder(Vector3(0, h * 0.75, 0), 0.0005, 0.0001, h * 0.25, 6, WHITE)


# ======================================================================================
# oil refinery
# ======================================================================================

## Crude oil tank: wide white cylinder, floating-roof ring, red band.
static func crude_tank(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var R := sz.x * 0.5
	mb.cylinder(Vector3(0, -sink, 0), R, R, sink + sz.y, 18, WHITE, true, Color(0.80, 0.80, 0.78))
	mb.cylinder(Vector3(0, sz.y * 0.72, 0), R * 1.01, R * 1.01, sz.y * 0.1, 18, RED, false)
	mb.cylinder(Vector3(0, sz.y, 0), R * 0.94, R * 0.94, 0.0003, 18, Color(0.55, 0.56, 0.58))


## Distillation column: tall thin cylinder with platform rings and a red top.
static func column(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var R := sz.x * 0.5
	mb.cylinder(Vector3(0, -sink, 0), R * 1.3, R * 1.3, sink + 0.001, 10, STEEL.darkened(0.2))
	mb.cylinder(Vector3(0, 0.001, 0), R, R, sz.y - 0.001, 10, STEEL, true, RED)
	for k in range(1, 5):
		mb.cylinder(Vector3(0, sz.y * k / 5.0, 0), R * 1.35, R * 1.35, 0.0004, 10, PIPE, true)
	mb.cylinder(Vector3(0, sz.y, 0), R * 0.5, R * 0.4, 0.002, 8, RED)


## Cracking unit: open steel frame block with yellow pipes and a small stack.
static func cracker(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var leg := 0.0007
	for fx in [-1.0, 1.0]:
		for fz in [-1.0, 1.0]:
			mb.box(Vector3(fx * (sz.x * 0.5 - leg), (sz.y - sink) * 0.5, fz * (sz.z * 0.5 - leg)), Vector3(leg, sz.y + sink, leg), STEEL)
	for k in 3:
		var y := sz.y * (0.33 + 0.33 * k)
		mb.box(Vector3(0, y, 0), Vector3(sz.x, 0.0005, sz.z), STEEL.darkened(0.12))
	mb.box(Vector3(0, sz.y * 0.4, 0), Vector3(sz.x * 0.55, sz.y * 0.6, sz.z * 0.5), Color(0.86, 0.88, 0.90))
	for k in 3:
		mb.box(Vector3(-sz.x * 0.35 + k * sz.x * 0.35, sz.y * 0.18, sz.z * 0.5 + 0.0005), Vector3(0.0006, 0.0006, sz.z * 0.6), PIPE)
	mb.cylinder(Vector3(sz.x * 0.3, sz.y, -sz.z * 0.25), 0.0008, 0.0006, sz.y * 0.7, 8, RED)


## Flare stack: tall thin chimney with a bright flame on top.
static func flare(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	mb.cylinder(Vector3(0, -sink, 0), sz.x * 0.5, sz.x * 0.25, sink + sz.y, 8, Color(0.88, 0.88, 0.86), true, DARK)
	for k in range(1, 4):
		mb.cylinder(Vector3(0, sz.y * k / 4.0, 0), sz.x * 0.45, sz.x * 0.45, 0.0006, 8, RED, false)
	mb.sphere(Vector3(0, sz.y + 0.0018, 0), Vector3(0.0016, 0.0026, 0.0016), 4, 8, FLAME)


## LPG sphere on legs.
static func sphere_tank(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var R := sz.x * 0.5
	for k in 6:
		var a := TAU * k / 6.0
		mb.box(Vector3(cos(a) * R * 0.75, (R - sink) * 0.5, sin(a) * R * 0.75), Vector3(0.0006, R + sink, 0.0006), STEEL.darkened(0.2))
	mb.sphere(Vector3(0, R * 1.05, 0), Vector3.ONE * R, 6, 12, WHITE)


## Pipe rack: long low frame with bundled coloured pipes (along local x).
static func pipe_rack(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var n := maxi(2, int(sz.x / 0.008))
	for k in n + 1:
		var px := -sz.x * 0.5 + k * sz.x / n
		mb.box(Vector3(px, (sz.y - sink) * 0.5, 0), Vector3(0.0006, sz.y + sink, sz.z), STEEL.darkened(0.15))
	for j in 3:
		var pz := (j - 1) * sz.z * 0.3
		mb.box(Vector3(0, sz.y, pz), Vector3(sz.x, 0.0007, 0.0007), [PIPE, RED, WHITE][j])


# ======================================================================================
# power & water
# ======================================================================================

## Gas power station hall: tall shed, blue cladding stripe.
static func power_hall(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, _r: RandomNumberGenerator) -> void:
	Arch.walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col, false)
	_rim(mb, Vector3.ZERO, sz.x, sz.z, sz.y, Color(0.25, 0.45, 0.80))
	for side in [-1.0, 1.0]:
		mb.box(Vector3(0, sz.y * 0.75, side * (sz.z * 0.5 + 0.0001)), Vector3(sz.x * 0.9, sz.y * 0.16, 0.0002), Color(0.25, 0.45, 0.80))
	mb.box(Vector3(sz.x * 0.3, sz.y * 0.4, sz.z * 0.5 + 0.0001), Vector3(0.004, sz.y * 0.8, 0.0002), DARK)


## Red / white chimney.
static func chimney(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var R := sz.x * 0.5
	mb.cylinder(Vector3(0, -sink, 0), R * 1.2, R * 1.2, sink + 0.002, 10, Color(0.80, 0.80, 0.78))
	var n := 6
	for k in n:
		var t0 := float(k) / n
		var c := RED if k % 2 == 1 or k == n - 1 else WHITE
		mb.cylinder(Vector3(0, 0.002 + (sz.y - 0.002) * t0, 0), lerpf(R, R * 0.75, t0), lerpf(R, R * 0.75, t0 + 1.0 / n), (sz.y - 0.002) / n, 10, c, k == n - 1, DARK)


## Hyperbolic cooling tower.
static func cooling_tower(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var R := sz.x * 0.5
	var prof := [[0.0, 1.0], [0.25, 0.82], [0.55, 0.66], [0.8, 0.68], [1.0, 0.74]]
	mb.cylinder(Vector3(0, -sink, 0), R, R, sink, 16, Color(0.82, 0.82, 0.80), false)
	for k in prof.size() - 1:
		var a: Array = prof[k]
		var b: Array = prof[k + 1]
		var c := Color(0.90, 0.90, 0.88) if k < 3 else Color(0.86, 0.86, 0.84)
		mb.cylinder(Vector3(0, sz.y * float(a[0]), 0), R * float(a[1]), R * float(b[1]), sz.y * (float(b[0]) - float(a[0])), 16, c, false)
	mb.cylinder(Vector3(0, sz.y - 0.0002, 0), R * 0.7, R * 0.7, 0.0002, 16, DARK)


## Transformer yard: grid of transformer boxes + two pylons.
static func transformer(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	mb.box(Vector3(0, 0.0002 - sink * 0.5, 0), Vector3(sz.x, 0.0004 + sink, sz.z), Color(0.70, 0.70, 0.66))
	for i in 3:
		for j in 2:
			mb.box(Vector3(-sz.x * 0.3 + i * sz.x * 0.3, 0.0012, -sz.z * 0.2 + j * sz.z * 0.4), Vector3(0.002, 0.002, 0.0016), Color(0.45, 0.55, 0.45))
	for e in [-1.0, 1.0]:
		var px: float = e * sz.x * 0.45
		mb.cylinder(Vector3(px, 0, 0), 0.0008, 0.0002, sz.y, 4, STEEL)
		mb.box(Vector3(px, sz.y * 0.85, 0), Vector3(0.0003, 0.0003, sz.z * 0.7), STEEL)


## Desalination train: long white hall with blue roof modules and a blue pipe.
static func desal(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	Arch.walls(mb, Vector3(0, 0, -sz.z * 0.1), sz.x, sz.z * 0.7, sz.y, sink, WHITE, false)
	var n := maxi(2, int(sz.x / 0.007))
	for k in n:
		var px := -sz.x * 0.5 + (k + 0.5) * sz.x / n
		mb.box(Vector3(px, sz.y + 0.0007, -sz.z * 0.1), Vector3(sz.x / n * 0.8, 0.0014, sz.z * 0.6), WATER_BLUE)
	mb.box(Vector3(0, 0.0018, sz.z * 0.38), Vector3(sz.x, 0.0012, 0.0012), Color(0.2, 0.5, 0.9))
	for k in n + 1:
		mb.box(Vector3(-sz.x * 0.5 + k * sz.x / n, 0.0006 - sink * 0.5, sz.z * 0.38), Vector3(0.0005, 0.0012 + sink, 0.0016), STEEL)


## Water storage tank (blue).
static func water_tank(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var R := sz.x * 0.5
	mb.cylinder(Vector3(0, -sink, 0), R, R, sink + sz.y, 16, WATER_BLUE, true, Color(0.85, 0.90, 0.95))
	mb.cylinder(Vector3(0, sz.y * 0.5, 0), R * 1.01, R * 1.01, sz.y * 0.12, 16, WHITE, false)


# ======================================================================================
# military
# ======================================================================================

## SAM battery: truck with four angled launch tubes.
static func sam(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	mb.box(Vector3(0, (0.0012 - sink) * 0.5, 0), Vector3(sz.x, 0.0012 + sink, sz.z), OLIVE.darkened(0.1))
	mb.box(Vector3(sz.x * 0.36, 0.0018, 0), Vector3(sz.x * 0.24, 0.0012, sz.z * 0.9), OLIVE)
	var saved := mb.xform
	mb.xform = saved * Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(35.0)), Vector3(-sz.x * 0.08, 0.0024, 0))
	for k in 4:
		var pz := (k - 1.5) * sz.z * 0.22
		mb.cylinder(Vector3(-sz.x * 0.25, 0, pz), 0.0006, 0.0006, sz.x * 0.75, 6, OLIVE.lightened(0.1), true, DARK)
	mb.xform = saved


## Bunker: low concrete mound with a dark slit and a door.
static func bunker(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	mb.cylinder(Vector3(0, -sink, 0), sz.x * 0.5, sz.x * 0.36, sink + sz.y, 10, Color(0.70, 0.68, 0.62), true, Color(0.62, 0.62, 0.56))
	mb.box(Vector3(0, sz.y * 0.6, sz.x * 0.42), Vector3(sz.x * 0.4, 0.0005, 0.0012), DARK)


## Main battle tank (toy): hull, turret, gun.
static func tank_vehicle(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	mb.box(Vector3(0, 0.0005 - sink * 0.5, 0), Vector3(sz.x, 0.001 + sink, sz.z * 1.05), DARK)
	mb.box(Vector3(0, 0.0014, 0), Vector3(sz.x * 0.95, 0.0009, sz.z * 0.8), OLIVE)
	mb.box(Vector3(-sz.x * 0.05, 0.0024, 0), Vector3(sz.x * 0.45, 0.0011, sz.z * 0.6), OLIVE.lightened(0.08))
	mb.box(Vector3(sz.x * 0.42, 0.0025, 0), Vector3(sz.x * 0.55, 0.0004, 0.0004), OLIVE.darkened(0.2))


## Military barracks: long low block, olive roof.
static func barracks(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, _r: RandomNumberGenerator) -> void:
	Arch.walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col)
	mb.box(Vector3(0, sz.y + 0.0003, 0), Vector3(sz.x * 1.04, 0.0006, sz.z * 1.08), OLIVE)


## Radar dome on a tower.
static func radar_sphere(mb: MeshBuilder, sz: Vector3, sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var R := sz.x * 0.5
	mb.cylinder(Vector3(0, -sink, 0), R * 0.7, R * 0.6, sink + sz.y * 0.55, 8, Color(0.82, 0.82, 0.80))
	mb.sphere(Vector3(0, sz.y * 0.55, 0), Vector3(R, R, R), 6, 12, WHITE, true)


# ======================================================================================
# ships (bow towards +x; local y = 0 is the waterline)
# ======================================================================================

## Hull helper: a pointed hull with deck at `fb` above the water.
static func _hull(mb: MeshBuilder, L: float, B: float, fb: float, col: Color, deck: Color) -> void:
	var hull := [Vector2(-L * 0.5, -B * 0.45), Vector2(L * 0.25, -B * 0.5), Vector2(L * 0.5, 0), Vector2(L * 0.25, B * 0.5), Vector2(-L * 0.5, B * 0.45)]
	var draft := fb * 0.8
	for k in hull.size():
		var a: Vector2 = hull[k]
		var b: Vector2 = hull[(k + 1) % hull.size()]
		var outd := Vector3((a.x + b.x) * 0.5, 0, (a.y + b.y) * 0.5)
		var A := Vector3(a.x, fb, a.y)
		var Bv := Vector3(b.x, fb, b.y)
		var Aw := Vector3(a.x * 0.97, -draft, a.y * 0.75)
		var Bw := Vector3(b.x * 0.97, -draft, b.y * 0.75)
		mb.tri_out(A, Bv, Bw, col, outd)
		mb.tri_out(A, Bw, Aw, col, outd)
		# red boot top at the waterline
		mb.tri_out(Vector3(a.x * 1.002, 0.0003, a.y * 1.002), Vector3(b.x * 1.002, 0.0003, b.y * 1.002), Vector3(b.x * 0.99, -0.0004, b.y * 0.93), RED.darkened(0.15), outd)
		mb.tri_out(Vector3(a.x * 1.002, 0.0003, a.y * 1.002), Vector3(b.x * 0.99, -0.0004, b.y * 0.93), Vector3(a.x * 0.99, -0.0004, a.y * 0.93), RED.darkened(0.15), outd)
	for k in range(1, hull.size() - 1):
		var a2: Vector2 = hull[0]
		var b2: Vector2 = hull[k]
		var c2: Vector2 = hull[k + 1]
		mb.tri_out(Vector3(a2.x, fb, a2.y), Vector3(b2.x, fb, b2.y), Vector3(c2.x, fb, c2.y), deck, Vector3.UP)


## Oil tanker: long red-black hull, deck pipes, white bridge aft.
static func tanker(mb: MeshBuilder, sz: Vector3, _sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var L := sz.x
	var B := sz.z
	var fb := 0.0022
	_hull(mb, L, B, fb, Color(0.20, 0.22, 0.28), Color(0.62, 0.30, 0.25))
	mb.box(Vector3(-L * 0.05, fb + 0.0004, 0), Vector3(L * 0.7, 0.0006, 0.0008), PIPE)
	mb.box(Vector3(-L * 0.40, fb + 0.0028, 0), Vector3(L * 0.1, 0.0056, B * 0.8), WHITE)
	mb.box(Vector3(-L * 0.44, fb + 0.006, 0), Vector3(0.0016, 0.004, 0.0016), RED)


## Cargo ship: blue hull with stacked toy containers and a bridge.
static func cargo(mb: MeshBuilder, sz: Vector3, _sink: float, _col: Color, r: RandomNumberGenerator) -> void:
	var L := sz.x
	var B := sz.z
	var fb := 0.002
	_hull(mb, L, B, fb, Color(0.20, 0.40, 0.70), Color(0.55, 0.55, 0.55))
	mb.box(Vector3(-L * 0.40, fb + 0.003, 0), Vector3(L * 0.1, 0.006, B * 0.8), WHITE)
	var cols := [RED, Color(0.2, 0.5, 0.9), PIPE, Color(0.3, 0.75, 0.4), WHITE]
	for bx in 5:
		for row in 3:
			var tiers := r.randi_range(1, 3)
			for t in tiers:
				mb.box(Vector3(-L * 0.25 + bx * L * 0.14, fb + 0.0008 + t * 0.0015, (row - 1) * B * 0.28), Vector3(L * 0.12, 0.0014, B * 0.26), cols[r.randi() % cols.size()])


## Frigate / destroyer: grey hull, superstructure, gun turret, mast, helipad.
static func frigate(mb: MeshBuilder, sz: Vector3, _sink: float, _col: Color, _r: RandomNumberGenerator) -> void:
	var L := sz.x
	var B := sz.z
	var fb := 0.0018
	_hull(mb, L, B, fb, NAVY, NAVY.darkened(0.15))
	mb.box(Vector3(-L * 0.02, fb + 0.002, 0), Vector3(L * 0.36, 0.004, B * 0.6), NAVY.lightened(0.1))
	mb.box(Vector3(L * 0.08, fb + 0.0048, 0), Vector3(L * 0.12, 0.0018, B * 0.45), NAVY.lightened(0.15))
	mb.cylinder(Vector3(-L * 0.02, fb + 0.004, 0), 0.0005, 0.0002, 0.006, 4, DARK)
	mb.box(Vector3(-L * 0.12, fb + 0.0055, 0), Vector3(0.0014, 0.003, 0.0014), DARK)
	mb.cylinder(Vector3(L * 0.3, fb, 0), 0.0012, 0.001, 0.001, 10, NAVY.lightened(0.05))
	mb.box(Vector3(L * 0.37, fb + 0.0007, 0), Vector3(L * 0.12, 0.0004, 0.0004), DARK)
	mb.box(Vector3(-L * 0.38, fb + 0.00005, 0), Vector3(L * 0.18, 0.0001, B * 0.6), DARK.lightened(0.2))


## Small boat (fishing / patrol), destroyable target too.
static func boat(mb: MeshBuilder, sz: Vector3, _sink: float, col: Color, _r: RandomNumberGenerator) -> void:
	_hull(mb, sz.x, sz.z, 0.0010, col, Color(0.85, 0.80, 0.70))
	mb.box(Vector3(-sz.x * 0.1, 0.0018, 0), Vector3(sz.x * 0.3, 0.0016, sz.z * 0.6), WHITE)


# ======================================================================================
# helpers
# ======================================================================================

## Coloured roof rim (parapet) on a block.
static func _rim(mb: MeshBuilder, c: Vector3, sx: float, sz: float, top: float, col: Color) -> void:
	var t := 0.0005
	var h := 0.0007
	var y := top + h * 0.5
	mb.box(Vector3(c.x, y, c.z - sz * 0.5 + t * 0.5), Vector3(sx, h, t), col)
	mb.box(Vector3(c.x, y, c.z + sz * 0.5 - t * 0.5), Vector3(sx, h, t), col)
	mb.box(Vector3(c.x - sx * 0.5 + t * 0.5, y, c.z), Vector3(t, h, sz - 2 * t), col)
	mb.box(Vector3(c.x + sx * 0.5 - t * 0.5, y, c.z), Vector3(t, h, sz - 2 * t), col)
