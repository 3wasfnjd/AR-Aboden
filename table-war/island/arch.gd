class_name Arch
extends RefCounted
## Procedural architecture at 1:2000 (sizes in Scale.m(real metres)).
## Every generator writes into a MeshBuilder whose xform is already the
## structure's transform; local origin = footprint centre at ground level,
## `sink` = how far walls must extend below origin to reach the lowest ground.
## No religious buildings exist in this project (see tests).

const DARK_WOOD := Color(0.52, 0.40, 0.28)
const SLOT := Color(0.16, 0.13, 0.11)
const CONCRETE := Color(0.72, 0.71, 0.67)
const PLASTER := [
	Color(0.93, 0.91, 0.86), Color(0.94, 0.90, 0.82), Color(0.86, 0.79, 0.66), Color(0.84, 0.74, 0.58),
	Color(0.82, 0.81, 0.78), Color(0.85, 0.72, 0.62), Color(0.89, 0.84, 0.74), Color(0.80, 0.70, 0.56),
]


# --------------------------------------------------------------------------------------
# primitives
# --------------------------------------------------------------------------------------

## Box from y=-sink to y=h with window UVs (structure shader draws windows).
static func walls(mb: MeshBuilder, c: Vector3, sx: float, sz: float, h: float, sink: float, col: Color, windows := true) -> void:
	var x0 := c.x - sx * 0.5
	var x1 := c.x + sx * 0.5
	var z0 := c.z - sz * 0.5
	var z1 := c.z + sz * 0.5
	var y0 := c.y - sink
	var y1 := c.y + h
	mb.quad(Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), col.darkened(0.05))
	var faces := [
		[Vector3(x0, 0, z1), Vector3(x1, 0, z1), sx],
		[Vector3(x1, 0, z0), Vector3(x0, 0, z0), sx],
		[Vector3(x1, 0, z1), Vector3(x1, 0, z0), sz],
		[Vector3(x0, 0, z0), Vector3(x0, 0, z1), sz],
	]
	for f in faces:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var l: float = f[2]
		var A := Vector3(a.x, y0, a.z)
		var B := Vector3(b.x, y0, b.z)
		var C := Vector3(b.x, y1, b.z)
		var D := Vector3(a.x, y1, a.z)
		if windows:
			var base := c.y
			mb.quad(A, B, C, D, col, Vector2(0, y0 - base), Vector2(l, y0 - base), Vector2(l, y1 - base), Vector2(0, y1 - base), Vector2(l, y1 - base))
		else:
			mb.quad(A, B, C, D, col)


static func parapet(mb: MeshBuilder, c: Vector3, sx: float, sz: float, top: float, col: Color, merlons := false) -> void:
	var t := Scale.m(0.6)
	var h := Scale.m(1.0)
	var y := top + h * 0.5
	var pc := col.lightened(0.03)
	mb.box(Vector3(c.x, y, c.z - sz * 0.5 + t * 0.5), Vector3(sx, h, t), pc)
	mb.box(Vector3(c.x, y, c.z + sz * 0.5 - t * 0.5), Vector3(sx, h, t), pc)
	mb.box(Vector3(c.x - sx * 0.5 + t * 0.5, y, c.z), Vector3(t, h, sz - 2 * t), pc)
	mb.box(Vector3(c.x + sx * 0.5 - t * 0.5, y, c.z), Vector3(t, h, sz - 2 * t), pc)
	if merlons:
		# small stepped merlons typical of Gulf parapets
		var step := Scale.m(2.4)
		var nx := int(sx / step)
		for k in nx:
			var px := c.x - sx * 0.5 + (k + 0.5) * sx / nx
			for zz in [c.z - sz * 0.5 + t * 0.5, c.z + sz * 0.5 - t * 0.5]:
				mb.box(Vector3(px, top + h + Scale.m(0.4), zz), Vector3(Scale.m(1.0), Scale.m(0.8), t), pc)


## Barjeel (wind tower): square shaft rising above the roof with vertical slots.
static func barjeel(mb: MeshBuilder, base: Vector3, col: Color, r: RandomNumberGenerator) -> void:
	var w := Scale.m(3.2)
	var h := Scale.m(r.randf_range(5.5, 7.5))
	mb.box(base + Vector3(0, h * 0.5, 0), Vector3(w, h, w), col.lightened(0.04))
	var sl := Scale.m(0.5)
	for k in 2:
		var o := (k - 0.5) * w * 0.45
		for f in [[Vector3(o, 0, w * 0.5 + 0.00003), Vector3(sl, h * 0.45, 0.00005)], [Vector3(o, 0, -w * 0.5 - 0.00003), Vector3(sl, h * 0.45, 0.00005)],
				[Vector3(w * 0.5 + 0.00003, 0, o), Vector3(0.00005, h * 0.45, sl)], [Vector3(-w * 0.5 - 0.00003, 0, o), Vector3(0.00005, h * 0.45, sl)]]:
			mb.box(base + f[0] + Vector3(0, h * 0.68, 0), f[1], SLOT)
	mb.box(base + Vector3(0, h + Scale.m(0.3), 0), Vector3(w * 1.15, Scale.m(0.6), w * 1.15), col)


## Mashrabiya oriel: dark timber screen box projecting from a facade.
static func mashrabiya(mb: MeshBuilder, at: Vector3, normal: Vector3) -> void:
	var w := Scale.m(3.2)
	var h := Scale.m(2.6)
	var d := Scale.m(0.5)
	var size := Vector3(w, h, d) if absf(normal.z) > 0.5 else Vector3(d, h, w)
	mb.box(at + normal * d * 0.5, size, DARK_WOOD)


# --------------------------------------------------------------------------------------
# buildings
# --------------------------------------------------------------------------------------

## Traditional flat-roofed house: block + parapet + roof stair box + tanks, barjeel/mashrabiya sometimes.
static func house(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, r: RandomNumberGenerator) -> void:
	walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col)
	parapet(mb, Vector3.ZERO, sz.x, sz.z, sz.y, col, r.randf() < 0.4)
	if r.randf() < 0.6:
		walls(mb, Vector3(sz.x * 0.25, sz.y, -sz.z * 0.2), Scale.m(4.0), Scale.m(4.0), Scale.m(3.0), 0.0, col, false)
	for k in r.randi_range(1, 2):
		mb.cylinder(Vector3(r.randf_range(-0.3, 0.3) * sz.x, sz.y, r.randf_range(-0.3, 0.3) * sz.z), Scale.m(1.0), Scale.m(1.0), Scale.m(1.6), 6, Color(0.88, 0.88, 0.86))
	if r.randf() < 0.3:
		barjeel(mb, Vector3(-sz.x * 0.3, sz.y, sz.z * 0.25), col, r)
	if sz.y > Scale.storeys(1.5) and r.randf() < 0.5:
		mashrabiya(mb, Vector3(0, sz.y - Scale.m(3.0), sz.z * 0.5), Vector3(0, 0, 1))


## Courtyard house: perimeter compound wall, L-shaped two-storey wings around an
## open courtyard, wind tower, mashrabiya on the street side.
static func courtyard(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, r: RandomNumberGenerator) -> void:
	var h := sz.y
	var wall_h := Scale.m(2.6)
	var t := Scale.m(0.6)
	walls(mb, Vector3(0, 0, -sz.z * 0.5 + t * 0.5), sz.x, t, wall_h, sink, col.darkened(0.04), false)
	walls(mb, Vector3(0, 0, sz.z * 0.5 - t * 0.5), sz.x, t, wall_h, sink, col.darkened(0.04), false)
	walls(mb, Vector3(-sz.x * 0.5 + t * 0.5, 0, 0), t, sz.z, wall_h, sink, col.darkened(0.04), false)
	walls(mb, Vector3(sz.x * 0.5 - t * 0.5, 0, 0), t, sz.z, wall_h, sink, col.darkened(0.04), false)
	# courtyard floor
	mb.box(Vector3(0, Scale.m(0.1) - sink * 0.5, 0), Vector3(sz.x - 2 * t, Scale.m(0.2) + sink, sz.z - 2 * t), Color(0.80, 0.73, 0.60))
	# north wing (full height) and west wing (one storey lower)
	var dn := sz.z * 0.42
	var cn := Vector3(0, 0, -sz.z * 0.5 + dn * 0.5)
	walls(mb, cn, sz.x, dn, h, sink, col)
	parapet(mb, cn, sz.x, dn, h, col, true)
	var ww := sz.x * 0.36
	var hw := maxf(h - Scale.STOREY / Scale.RATIO, Scale.storeys(1.0))
	var cw := Vector3(-sz.x * 0.5 + ww * 0.5, 0, dn * 0.5)
	walls(mb, cw, ww, sz.z - dn, hw, sink, col.lightened(0.02))
	parapet(mb, cw, ww, sz.z - dn, hw, col)
	if r.randf() < 0.75:
		barjeel(mb, Vector3(sz.x * 0.3, h, -sz.z * 0.5 + dn * 0.5), col, r)
	if r.randf() < 0.6:
		mashrabiya(mb, Vector3(-sz.x * 0.1, h - Scale.m(3.2), -sz.z * 0.5), Vector3(0, 0, -1))
	# a small tree in the yard
	if r.randf() < 0.6:
		mb.cylinder(Vector3(sz.x * 0.15, 0, sz.z * 0.2), Scale.m(0.3), Scale.m(0.2), Scale.m(2.5), 4, Color(0.4, 0.32, 0.24))
		mb.sphere(Vector3(sz.x * 0.15, Scale.m(3.5), sz.z * 0.2), Vector3.ONE * Scale.m(2.2), 3, 6, Color(0.42, 0.52, 0.28))


## Modern mid-rise block (5-8 storeys): balcony bands, roof plant room.
static func midrise(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, r: RandomNumberGenerator) -> void:
	walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col)
	parapet(mb, Vector3.ZERO, sz.x, sz.z, sz.y, col)
	var n := int(round(sz.y / Scale.storeys(1.0)))
	var band := col.darkened(0.12)
	for k in range(1, n):
		var y := k * Scale.storeys(1.0)
		if k % 2 == 0:
			mb.box(Vector3(0, y, sz.z * 0.5 + Scale.m(0.5)), Vector3(sz.x * 0.8, Scale.m(0.35), Scale.m(1.0)), band)
			mb.box(Vector3(0, y, -sz.z * 0.5 - Scale.m(0.5)), Vector3(sz.x * 0.8, Scale.m(0.35), Scale.m(1.0)), band)
	walls(mb, Vector3(-sz.x * 0.2, sz.y, 0), sz.x * 0.3, sz.z * 0.4, Scale.m(3.0), 0.0, col.darkened(0.08), false)
	for k in 3:
		mb.box(Vector3(sz.x * (0.1 + 0.12 * k), sz.y + Scale.m(0.7), sz.z * 0.2), Vector3(Scale.m(2.0), Scale.m(1.4), Scale.m(2.0)), Color(0.78, 0.78, 0.76))


## Tower on a podium (10-16 storeys).
static func tower(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, r: RandomNumberGenerator) -> void:
	var pod_h := Scale.storeys(2.0)
	walls(mb, Vector3.ZERO, sz.x, sz.z, pod_h, sink, Color(0.82, 0.80, 0.76))
	parapet(mb, Vector3.ZERO, sz.x, sz.z, pod_h, Color(0.82, 0.80, 0.76))
	var tx := sz.x * 0.68
	var tz := sz.z * 0.68
	walls(mb, Vector3(0, pod_h, 0), tx, tz, sz.y - pod_h, 0.0, col)
	var crown := Vector3(tx * 0.8, Scale.m(4.0), tz * 0.8)
	mb.box(Vector3(0, sz.y + crown.y * 0.5, 0), crown, col.darkened(0.06))
	mb.box(Vector3(0, sz.y + crown.y + Scale.m(0.3), 0), Vector3(tx * 0.9, Scale.m(0.6), tz * 0.9), col.lightened(0.1))
	if r.randf() < 0.5:
		mb.cylinder(Vector3(0, sz.y + crown.y + Scale.m(0.6), 0), Scale.m(0.25), Scale.m(0.15), Scale.m(8.0), 4, Color(0.8, 0.8, 0.8))


## Souq / covered market hall (civic): arcaded long hall with a raised
## clerestory spine, stepped merlons and wind towers. Replaces the former
## landmark; deliberately secular.
static func souq(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, r: RandomNumberGenerator) -> void:
	walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col, false)
	parapet(mb, Vector3.ZERO, sz.x, sz.z, sz.y, col, true)
	# arcade openings along both long sides (dark recesses with lintel)
	var bay := Scale.m(5.0)
	var n := int(sz.x / bay)
	for k in n:
		var px := -sz.x * 0.5 + (k + 0.5) * sz.x / n
		for side in [-1.0, 1.0]:
			mb.box(Vector3(px, Scale.m(2.0), side * (sz.z * 0.5 + 0.00002)), Vector3(Scale.m(3.0), Scale.m(4.0), 0.00006), SLOT)
	# clerestory spine with windows
	var spine := Vector3(sz.x * 0.7, Scale.m(3.0), sz.z * 0.32)
	walls(mb, Vector3(0, sz.y, 0), spine.x, spine.z, spine.y, 0.0, col.lightened(0.03))
	parapet(mb, Vector3(0, sz.y, 0), spine.x, spine.z, sz.y + spine.y, col)
	for k in 3:
		barjeel(mb, Vector3(-sz.x * 0.36 + k * sz.x * 0.36, sz.y, sz.z * 0.32), col, r)
	# shade awnings at the entrances
	for side in [-1.0, 1.0]:
		mb.box(Vector3(side * (sz.x * 0.5 + Scale.m(1.5)), Scale.m(3.2), 0), Vector3(Scale.m(3.0), Scale.m(0.3), sz.z * 0.5), Color(0.62, 0.50, 0.36))


static func warehouse(mb: MeshBuilder, sz: Vector3, sink: float, col: Color) -> void:
	walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col, false)
	var ry := Scale.m(2.5)
	var hx := sz.x * 0.5 + Scale.m(0.5)
	var hz := sz.z * 0.5 + Scale.m(0.5)
	var rc := col.darkened(0.1)
	mb.quad(Vector3(-hx, sz.y, -hz), Vector3(-hx, sz.y + ry, 0), Vector3(hx, sz.y + ry, 0), Vector3(hx, sz.y, -hz), rc)
	mb.quad(Vector3(-hx, sz.y + ry, 0), Vector3(-hx, sz.y, hz), Vector3(hx, sz.y, hz), Vector3(hx, sz.y + ry, 0), rc.lightened(0.05))
	mb.tri_out(Vector3(-hx, sz.y, -hz), Vector3(-hx, sz.y, hz), Vector3(-hx, sz.y + ry, 0), col, Vector3.LEFT)
	mb.tri_out(Vector3(hx, sz.y, -hz), Vector3(hx, sz.y, hz), Vector3(hx, sz.y + ry, 0), col, Vector3.RIGHT)
	var nd := int(sz.x / Scale.m(15.0))
	for k in nd:
		var px := -sz.x * 0.5 + (k + 0.5) * sz.x / nd
		mb.box(Vector3(px, Scale.m(3.0), sz.z * 0.5 + 0.00004), Vector3(Scale.m(6.0), Scale.m(6.0), 0.00008), Color(0.35, 0.37, 0.38))


# --------------------------------------------------------------------------------------
# port
# --------------------------------------------------------------------------------------

## Container block: rows x bays of 20 ft boxes, stacked 1-4 high.
static func container_block(mb: MeshBuilder, sz: Vector3, r: RandomNumberGenerator) -> void:
	var palette := [Color(0.72, 0.25, 0.20), Color(0.20, 0.38, 0.58), Color(0.85, 0.62, 0.22), Color(0.30, 0.52, 0.40),
		Color(0.86, 0.86, 0.83), Color(0.55, 0.30, 0.45), Color(0.62, 0.62, 0.60), Color(0.15, 0.30, 0.40)]
	var cl := Scale.m(6.1)
	var cw := Scale.m(2.44)
	var ch := Scale.m(2.6)
	var bays := maxi(1, int(sz.x / (cl + Scale.m(0.4))))
	var rows := maxi(1, int(sz.z / (cw + Scale.m(0.3))))
	for bx in bays:
		for rz in rows:
			var stack := r.randi_range(1, 4)
			if r.randf() < 0.08:
				continue
			for ry in stack:
				var p := Vector3(-sz.x * 0.5 + (bx + 0.5) * sz.x / bays, ch * 0.5 + ry * ch, -sz.z * 0.5 + (rz + 0.5) * sz.z / rows)
				mb.box(p, Vector3(cl, ch * 0.97, cw * 0.95), palette[r.randi() % palette.size()])


## Ship-to-shore gantry crane. Local +z points to the water. Rail gauge 30 m,
## boom 40 m above quay, 50 m outreach, 15 m backreach.
static func sts_crane(mb: MeshBuilder, col: Color) -> void:
	var g := Scale.m(30.0)
	var span := Scale.m(18.0)
	var hb := Scale.m(40.0)
	var leg := Scale.m(1.6)
	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			mb.box(Vector3(lx * span * 0.5, hb * 0.5, lz * g * 0.5), Vector3(leg, hb, leg), col)
		mb.box(Vector3(lx * span * 0.5, Scale.m(10.0), 0), Vector3(leg * 0.8, leg * 0.8, g), col)
		mb.box(Vector3(lx * span * 0.5, Scale.m(1.0), 0), Vector3(Scale.m(3.0), Scale.m(2.0), g + Scale.m(4.0)), col.darkened(0.2))
	mb.box(Vector3(0, hb, 0), Vector3(span + leg, leg, leg), col)
	mb.box(Vector3(0, hb, -g * 0.5), Vector3(span + leg, leg, leg), col)
	# boom: backreach + gantry + outreach
	var z0 := -g * 0.5 - Scale.m(15.0)
	var z1 := g * 0.5 + Scale.m(50.0)
	mb.box(Vector3(0, hb + leg, (z0 + z1) * 0.5), Vector3(Scale.m(3.0), Scale.m(2.4), z1 - z0), col.darkened(0.05))
	# A-frame apex and stays
	var apex := Vector3(0, hb + Scale.m(18.0), -g * 0.25)
	for lx in [-1.0, 1.0]:
		var a := Vector3(lx * span * 0.4, hb, -g * 0.5)
		var b := Vector3(lx * span * 0.4, hb, g * 0.0)
		for p in [a, b]:
			_strut(mb, p, apex + Vector3(lx * Scale.m(2.0), 0, 0), Scale.m(0.9), col)
		_strut(mb, apex + Vector3(lx * Scale.m(2.0), 0, 0), Vector3(lx * Scale.m(1.0), hb + leg, z1 - Scale.m(2.0)), Scale.m(0.35), col.darkened(0.15))
	# machinery house and trolley over the berth
	mb.box(Vector3(0, hb + Scale.m(4.0), z0 + Scale.m(6.0)), Vector3(Scale.m(8.0), Scale.m(5.0), Scale.m(9.0)), Color(0.86, 0.86, 0.84))
	mb.box(Vector3(0, hb - Scale.m(1.5), g * 0.5 + Scale.m(20.0)), Vector3(Scale.m(4.0), Scale.m(3.0), Scale.m(4.0)), Color(0.3, 0.3, 0.3))


static func _strut(mb: MeshBuilder, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 1e-7:
		return
	var y := d / len
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var saved := mb.xform
	mb.xform = saved * Transform3D(Basis(x, y, z), (a + b) * 0.5)
	mb.box(Vector3.ZERO, Vector3(w, len, w), col, false, Color(-1, 0, 0), true)
	mb.xform = saved


## Rubber-tyred gantry straddling a container block (along local x).
static func rtg(mb: MeshBuilder, sz: Vector3, col: Color) -> void:
	var leg := Scale.m(1.2)
	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			mb.box(Vector3(lx * sz.x * 0.5, sz.y * 0.5, lz * sz.z * 0.5), Vector3(leg, sz.y, leg), col)
		mb.box(Vector3(lx * sz.x * 0.5, sz.y, 0), Vector3(leg * 1.2, leg, sz.z + leg), col)
	mb.box(Vector3(0, sz.y + leg * 0.6, 0), Vector3(sz.x, leg * 0.8, Scale.m(3.0)), col.darkened(0.1))


## Feeder container ship, bow towards +x. 140 x 22 m.
static func ship(mb: MeshBuilder, sz: Vector3, r: RandomNumberGenerator) -> void:
	var L := sz.x
	var B := sz.z
	var fb := Scale.m(6.0)          # freeboard above water
	var draft := Scale.m(7.0)
	var hull := [Vector2(-L * 0.5, -B * 0.5), Vector2(L * 0.32, -B * 0.5), Vector2(L * 0.5, 0), Vector2(L * 0.32, B * 0.5), Vector2(-L * 0.5, B * 0.5)]
	var hc := Color(0.20, 0.27, 0.36)
	var bottom := Color(0.55, 0.20, 0.16)
	for k in hull.size():
		var a: Vector2 = hull[k]
		var b: Vector2 = hull[(k + 1) % hull.size()]
		var outd := Vector3((a.x + b.x) * 0.5, 0, (a.y + b.y) * 0.5)
		var A := Vector3(a.x, fb, a.y)
		var Bv := Vector3(b.x, fb, b.y)
		var Aw := Vector3(a.x, Scale.m(0.4), a.y)
		var Bw := Vector3(b.x, Scale.m(0.4), b.y)
		var Ak := Vector3(a.x * 0.95, -draft, a.y * 0.7)
		var Bk := Vector3(b.x * 0.95, -draft, b.y * 0.7)
		mb.tri_out(A, Bv, Bw, hc, outd)
		mb.tri_out(A, Bw, Aw, hc, outd)
		mb.tri_out(Aw, Bw, Bk, bottom, outd)
		mb.tri_out(Aw, Bk, Ak, bottom, outd)
	for k in range(1, hull.size() - 1):
		var a2: Vector2 = hull[0]
		var b2: Vector2 = hull[k]
		var c2: Vector2 = hull[k + 1]
		mb.tri_out(Vector3(a2.x, fb, a2.y), Vector3(b2.x, fb, b2.y), Vector3(c2.x, fb, c2.y), Color(0.45, 0.42, 0.38), Vector3.UP)
	# accommodation block aft + funnel
	var ax := -L * 0.40
	walls(mb, Vector3(ax, fb, 0), Scale.m(12.0), B * 0.85, Scale.m(16.0), 0.0, Color(0.93, 0.93, 0.91))
	mb.box(Vector3(ax, fb + Scale.m(16.5), 0), Vector3(Scale.m(14.0), Scale.m(1.0), B * 0.95), Color(0.93, 0.93, 0.91))
	mb.box(Vector3(ax - Scale.m(7.0), fb + Scale.m(14.0), 0), Vector3(Scale.m(4.0), Scale.m(10.0), Scale.m(4.0)), Color(0.75, 0.22, 0.18))
	# container bays on deck
	var bays := 8
	var palette := [Color(0.72, 0.25, 0.20), Color(0.20, 0.38, 0.58), Color(0.85, 0.62, 0.22), Color(0.30, 0.52, 0.40), Color(0.86, 0.86, 0.83), Color(0.55, 0.30, 0.45)]
	for bx in bays:
		var px := -L * 0.30 + (bx + 0.5) * (L * 0.62) / bays
		var tiers := r.randi_range(2, 4)
		for row in 7:
			var pz := -B * 0.42 + (row + 0.5) * (B * 0.84) / 7
			for t in tiers:
				mb.box(Vector3(px, fb + Scale.m(1.3) + t * Scale.m(2.6), pz), Vector3(Scale.m(6.0), Scale.m(2.55), Scale.m(2.4)), palette[r.randi() % palette.size()])


# --------------------------------------------------------------------------------------
# air base / industry
# --------------------------------------------------------------------------------------

## Hardened aircraft shelter: low concrete vault, door facing local +z.
static func has(mb: MeshBuilder, sz: Vector3, sink: float, col: Color) -> void:
	var L := sz.z
	var R := sz.x * 0.5
	var H := sz.y
	var seg := 8
	for k in seg:
		var a0 := PI * k / seg
		var a1 := PI * (k + 1) / seg
		var p0 := Vector3(cos(a0) * R, sin(a0) * H, 0)
		var p1 := Vector3(cos(a1) * R, sin(a1) * H, 0)
		var shade := col * (0.9 + 0.1 * sin(a0))
		shade.a = 1.0
		mb.tri_out(p0 + Vector3(0, 0, -L * 0.5), p1 + Vector3(0, 0, -L * 0.5), p1 + Vector3(0, 0, L * 0.5), shade, (p0 + p1) * 0.5)
		mb.tri_out(p0 + Vector3(0, 0, -L * 0.5), p1 + Vector3(0, 0, L * 0.5), p0 + Vector3(0, 0, L * 0.5), shade, (p0 + p1) * 0.5)
		mb.tri_out(Vector3(0, 0, -L * 0.5), p0 + Vector3(0, 0, -L * 0.5), p1 + Vector3(0, 0, -L * 0.5), col.darkened(0.1), Vector3.FORWARD)
	mb.box(Vector3(0, -sink * 0.5, 0), Vector3(sz.x, sink, L), col.darkened(0.1))
	# thick front headwall with blast doors
	mb.box(Vector3(0, H * 0.5, L * 0.5 + Scale.m(1.0)), Vector3(sz.x + Scale.m(4.0), H, Scale.m(2.0)), col.darkened(0.05))
	mb.box(Vector3(0, H * 0.36, L * 0.5 + Scale.m(2.05)), Vector3(sz.x * 0.75, H * 0.72, Scale.m(0.2)), Color(0.42, 0.44, 0.42))
	mb.box(Vector3(0, H * 0.36, L * 0.5 + Scale.m(2.2)), Vector3(Scale.m(0.3), H * 0.72, Scale.m(0.1)), Color(0.28, 0.29, 0.28))


## Fuel / water storage tank with an earth bund wall.
static func tank(mb: MeshBuilder, sz: Vector3, sink: float, col: Color, bund := true) -> void:
	mb.cylinder(Vector3(0, -sink, 0), sz.x * 0.5, sz.x * 0.5, sz.y + sink, 16, col, true, col.darkened(0.06))
	mb.cylinder(Vector3(0, sz.y, 0), sz.x * 0.5, sz.x * 0.15, Scale.m(1.5), 16, col.darkened(0.03))
	mb.box(Vector3(sz.x * 0.35, sz.y * 0.5, sz.x * 0.35), Vector3(Scale.m(0.6), sz.y, Scale.m(0.6)), col.darkened(0.2))
	if bund:
		var b := sz.x * 0.5 + Scale.m(5.0)
		var t := Scale.m(1.5)
		var h := Scale.m(1.5)
		for f in [[Vector3(0, 0, -b), Vector3(b * 2, h, t)], [Vector3(0, 0, b), Vector3(b * 2, h, t)], [Vector3(-b, 0, 0), Vector3(t, h, b * 2)], [Vector3(b, 0, 0), Vector3(t, h, b * 2)]]:
			mb.box(f[0] + Vector3(0, h * 0.5 - sink * 0.5, 0), f[1] + Vector3(0, sink, 0), Color(0.72, 0.66, 0.54))


## Tall power-station chimney with red/white aviation bands.
static func stack(mb: MeshBuilder, sz: Vector3, sink: float) -> void:
	var h := sz.y
	var r0 := sz.x * 0.5
	var r1 := r0 * 0.75
	mb.cylinder(Vector3(0, -sink, 0), r0 * 1.15, r0 * 1.1, sink + Scale.m(3.0), 10, CONCRETE)
	var bands := [0.0, 0.78, 0.84, 0.90, 0.96, 1.0]
	mb.cylinder(Vector3(0, Scale.m(3.0), 0), r0, lerpf(r0, r1, 0.78), (h - Scale.m(3.0)) * 0.78, 10, Color(0.82, 0.81, 0.78), false)
	for k in range(1, bands.size() - 1):
		var t0: float = bands[k]
		var t1: float = bands[k + 1]
		var c := Color(0.80, 0.20, 0.17) if k % 2 == 1 else Color(0.93, 0.93, 0.91)
		var y0 := Scale.m(3.0) + (h - Scale.m(3.0)) * t0
		mb.cylinder(Vector3(0, y0, 0), lerpf(r0, r1, t0), lerpf(r0, r1, t1), (h - Scale.m(3.0)) * (t1 - t0), 10, c, k == bands.size() - 2, Color(0.12, 0.11, 0.10))


## Turbine hall: tall shed with ribbed roof and a high window strip.
static func turbine_hall(mb: MeshBuilder, sz: Vector3, sink: float, col: Color) -> void:
	walls(mb, Vector3.ZERO, sz.x, sz.z, sz.y, sink, col, false)
	var ribs := int(sz.x / Scale.m(6.0))
	for k in ribs:
		var px := -sz.x * 0.5 + (k + 0.5) * sz.x / ribs
		mb.box(Vector3(px, sz.y + Scale.m(0.3), 0), Vector3(Scale.m(0.6), Scale.m(0.6), sz.z), col.darkened(0.1))
	for side in [-1.0, 1.0]:
		mb.box(Vector3(0, sz.y * 0.78, side * (sz.z * 0.5 + 0.00002)), Vector3(sz.x * 0.92, Scale.m(3.0), 0.00005), Color(0.25, 0.32, 0.38))
	# heat-recovery boilers behind the hall
	for k in 3:
		var bx := -sz.x * 0.3 + k * sz.x * 0.3
		walls(mb, Vector3(bx, 0, -sz.z * 0.5 - Scale.m(9.0)), Scale.m(12.0), Scale.m(16.0), Scale.m(24.0), sink, Color(0.78, 0.78, 0.76), false)


## Multi-stage-flash desalination train: long low modules on a pipe rack.
static func desal(mb: MeshBuilder, sz: Vector3, sink: float, col: Color) -> void:
	walls(mb, Vector3(0, 0, -sz.z * 0.2), sz.x, sz.z * 0.55, sz.y, sink, col, false)
	var n := int(sz.x / Scale.m(10.0))
	for k in n:
		var px := -sz.x * 0.5 + (k + 0.5) * sz.x / n
		mb.box(Vector3(px, sz.y + Scale.m(0.6), -sz.z * 0.2), Vector3(Scale.m(7.0), Scale.m(1.2), sz.z * 0.5), col.lightened(0.05))
	# pipe rack
	mb.box(Vector3(0, Scale.m(4.0), sz.z * 0.32), Vector3(sz.x, Scale.m(1.5), Scale.m(4.0)), Color(0.55, 0.56, 0.58))
	for k in int(sz.x / Scale.m(8.0)):
		mb.box(Vector3(-sz.x * 0.5 + k * Scale.m(8.0), Scale.m(2.0) - sink * 0.5, sz.z * 0.32), Vector3(Scale.m(0.6), Scale.m(4.0) + sink, Scale.m(3.0)), Color(0.45, 0.46, 0.48))


## Intake / outfall jetty on piles, running along local +z into the sea.
static func jetty(mb: MeshBuilder, sz: Vector3, terrain: IslandTerrain, xf: Transform3D) -> void:
	mb.box(Vector3(0, 0, 0), sz, CONCRETE.darkened(0.05))
	var n := int(sz.z / Scale.m(10.0)) + 1
	for k in n:
		var pz := -sz.z * 0.5 + k * sz.z / maxf(n - 1, 1)
		for px in [-1.0, 1.0]:
			var wp: Vector3 = xf * Vector3(px * sz.x * 0.4, 0, pz)
			var gy := terrain.height_at(wp.x, wp.z)
			mb.cylinder(Vector3(px * sz.x * 0.4, gy - xf.origin.y - Scale.m(1.0), pz), Scale.m(0.6), Scale.m(0.6), xf.origin.y - gy + Scale.m(1.0), 5, CONCRETE.darkened(0.3))
	mb.box(Vector3(0, Scale.m(1.0), sz.z * 0.5 - Scale.m(4.0)), Vector3(sz.x * 1.6, Scale.m(2.0), Scale.m(8.0)), CONCRETE)


## Navigation beacon (breakwater head): white column, green top.
static func beacon(mb: MeshBuilder, sz: Vector3, sink: float, top: Color) -> void:
	mb.cylinder(Vector3(0, -sink, 0), sz.x * 0.6, sz.x * 0.5, sz.y * 0.75 + sink, 8, Color(0.92, 0.92, 0.90))
	mb.cylinder(Vector3(0, sz.y * 0.75, 0), sz.x * 0.5, sz.x * 0.45, sz.y * 0.25, 8, top)
