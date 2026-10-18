class_name Placement
extends RefCounted
## Mixed-reality placement maths (pure functions, tested headless).
##
## The diorama's local origin is the centre of the underside of its base (the recessed
## foot starts at y = 0, see island/base.gd), so a transform whose origin is a point on
## a real surface makes the base sit exactly on that surface. Scale is uniform:
## 1.0 = the real model (1.0 m slab, 1.072 m with the wooden rim).

const MIN_SCALE := 0.4
const MAX_SCALE := 1.5
const TABLE_H := 0.75          # m: the virtual table when the headset knows no real one
const OUTER_R := 0.536         # m at scale 1: slab radius 0.5 + wooden rim 0.036
const FLOAT_AHEAD := 0.75      # m in front of the head while nothing is aimed at
const HAND_DROP := 0.55        # m below the eyes: "hand height"
const ZOOM_RATE := 0.9         # stick Y: e-folds per second
const TURN_RATE := 1.6         # stick X: rad/s
const DEADZONE := 0.3


static func clamp_scale(s: float) -> float:
	return clampf(s, MIN_SCALE, MAX_SCALE)


## The diorama transform for a base standing on `point` (on a horizontal surface),
## turned `yaw` radians about +Y and scaled `s` (clamped to 0.4-1.5).
static func pinned_transform(point: Vector3, yaw: float, s: float) -> Transform3D:
	var k := clamp_scale(s)
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(k, k, k)), point)


## Yaw that turns the model's front (local +Z: the engraved name plate) towards `eye`.
static func facing_yaw(point: Vector3, eye: Vector3, fallback := 0.0) -> float:
	var dx := eye.x - point.x
	var dz := eye.z - point.z
	if dx * dx + dz * dz < 1e-4:
		return fallback
	return atan2(dx, dz)


## Where the model floats before anything is aimed at: ahead of the head, at hand height.
static func float_point(head: Transform3D) -> Vector3:
	var f := -head.basis.z
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 1e-4 else Vector3.FORWARD
	var p := head.origin + f * FLOAT_AHEAD
	p.y = maxf(head.origin.y - HAND_DROP, 0.3)
	return p


## No real surface along the ray: a virtual horizontal plane at `plane_h` (the table
## height, or 0 = the floor). {p, n, label} or {} when the ray does not reach it.
static func virtual_hit(origin: Vector3, dir: Vector3, plane_h := TABLE_H, max_dist := 4.0) -> Dictionary:
	var d := dir.normalized()
	if d.y > -0.03 or origin.y <= plane_h + 0.01:
		return {}
	var t := (plane_h - origin.y) / d.y
	if t <= 0.0 or t > max_dist:
		return {}
	return {"p": origin + d * t, "n": Vector3.UP, "label": "virtual_floor" if plane_h < 0.05 else "virtual_table"}


## Stick input while placing: Y scales (exponential, clamped), X turns. Returns [scale, yaw].
static func apply_stick(s: float, yaw: float, stick: Vector2, dt: float) -> Array:
	if absf(stick.y) > DEADZONE:
		s = clamp_scale(s * exp(stick.y * ZOOM_RATE * dt))
	if absf(stick.x) > DEADZONE:
		yaw = wrapf(yaw - stick.x * TURN_RATE * dt, -PI, PI)
	return [s, yaw]


## A world ray clipped to the diorama's slab (local cylinder r <= 0.5, 0 <= y <= 0.2):
## [local_origin, local_dir, t0, t1] in diorama-local units, or [] when it misses.
static func local_ray(diorama: Transform3D, origin: Vector3, dir: Vector3) -> Array:
	var inv := diorama.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	var R := 0.5
	var t0 := 0.0
	var t1 := 1e9
	# vertical slab
	if absf(d.y) < 1e-9:
		if o.y < 0.0 or o.y > 0.2:
			return []
	else:
		var ta := (0.0 - o.y) / d.y
		var tb := (0.2 - o.y) / d.y
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	# infinite cylinder x^2 + z^2 <= R^2
	var a := d.x * d.x + d.z * d.z
	var b := 2.0 * (o.x * d.x + o.z * d.z)
	var c := o.x * o.x + o.z * o.z - R * R
	if a < 1e-12:
		if c > 0.0:
			return []
	else:
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			return []
		var sq := sqrt(disc)
		t0 = maxf(t0, (-b - sq) / (2.0 * a))
		t1 = minf(t1, (-b + sq) / (2.0 * a))
	if t1 <= t0:
		return []
	return [o, d, t0, t1]
