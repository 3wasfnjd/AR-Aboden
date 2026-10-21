class_name Garrison
extends MultiMeshInstance3D
## The web garrison's soldiers (build 28): small olive figures standing at the guard
## posts (IslandProps.soldier_spots), turning a little now and then. A blast kills the
## ones it reaches: they fall flat and darken. Soldiers are combatants, never counted as
## civilians. One MultiMesh, island-local (a child of the island).

var spots: Array[Vector3] = []          # (x, yaw, z)
var alive := PackedByteArray()
var _y := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(isl: Island) -> void:
	name = "Garrison"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spots = isl.props.soldier_spots.duplicate()
	var n := spots.size()
	alive.resize(n)
	alive.fill(1)
	_y.resize(n)
	_yaw.resize(n)
	for i in n:
		var s := spots[i]
		_y[i] = isl.surface_at(s.x, s.z)
		_yaw[i] = s.y
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _soldier()
	mm.instance_count = n
	multimesh = mm
	material_override = MeshBuilder.vc_material(0.85)
	_rng.seed = 51
	for i in n:
		_put(i)


static func _soldier() -> Mesh:
	var mb := MeshBuilder.new()
	var olive := Color(0.36, 0.40, 0.24)
	mb.box(Vector3(0, 0.0005, 0), Vector3(0.0005, 0.0010, 0.0007), olive.darkened(0.25))
	mb.box(Vector3(0, 0.00135, 0), Vector3(0.0006, 0.0008, 0.0009), olive)
	mb.box(Vector3(0, 0.0021, 0), Vector3(0.0007, 0.0006, 0.0007), Color(0.80, 0.64, 0.50))
	mb.box(Vector3(0, 0.00245, 0), Vector3(0.0008, 0.0003, 0.0008), olive.darkened(0.1))   # helmet
	mb.box(Vector3(0.0004, 0.0014, 0.0004), Vector3(0.0012, 0.00015, 0.00015), Color(0.12, 0.12, 0.12))   # rifle
	return mb.commit()


func _put(i: int) -> void:
	var s := spots[i]
	var b := Basis(Vector3.UP, _yaw[i])
	var c := Color.WHITE
	if alive[i] == 0:
		b = b * Basis(Vector3.RIGHT, PI * 0.5)     # lying on the ground
		c = Color(0.35, 0.33, 0.30)
	multimesh.set_instance_transform(i, Transform3D(b, Vector3(s.x, _y[i] + (0.0003 if alive[i] == 0 else 0.0), s.z)))
	multimesh.set_instance_color(i, c)


func alive_count() -> int:
	var n := 0
	for a in alive:
		n += a
	return n


func on_blast(p: Vector3, r: float) -> int:
	var killed := 0
	for i in spots.size():
		if alive[i] == 1 and Vector2(spots[i].x - p.x, spots[i].z - p.z).length() < r * 1.25:
			alive[i] = 0
			killed += 1
			_put(i)
	return killed


func reset() -> void:
	alive.fill(1)
	for i in spots.size():
		_put(i)


## A few soldiers turn round now and then (cheap: a handful per second).
func step(dt: float) -> void:
	_t += dt
	if _t < 0.25 or spots.is_empty():
		return
	_t = 0.0
	for k in 3:
		var i := _rng.randi() % spots.size()
		if alive[i] == 1:
			_yaw[i] += _rng.randf_range(-1.2, 1.2)
			_put(i)
