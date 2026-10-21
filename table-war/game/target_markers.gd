class_name TargetMarkers
extends MultiMeshInstance3D
## The stage's objectives, marked on the island: a red holographic arrow floating over
## every target still standing, bobbing gently, gone when it is destroyed. One MultiMesh
## (one draw call), island-local, refreshed by the game a few times a second.

const MAX := 48
const LIFT := 0.035              # above the structure's base
const SIZE := 0.006

var targets: Array = []          # structure Dictionaries of the objective
var _t := 0.0


func _init() -> void:
	name = "TargetMarkers"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _arrow()
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.22, 0.16, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 3
	material_override = m
	custom_aabb = AABB(Vector3(-0.6, -0.1, -0.6), Vector3(1.2, 0.6, 1.2))


## An inverted pyramid (four faces) pointing down.
static func _arrow() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, -1.0, 0)
	var q := [Vector3(-0.6, 0.4, -0.6), Vector3(0.6, 0.4, -0.6), Vector3(0.6, 0.4, 0.6), Vector3(-0.6, 0.4, 0.6)]
	for k in 4:
		for v in [tip, q[k], q[(k + 1) % 4]]:
			st.add_vertex(v)
	for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()


var forces: EnemyForces
var force_kinds: Array = []


## Mark the objective of `run` on `props` (and the enemy units it names).
func setup_run(run: StageRun, props: IslandProps, f: EnemyForces = null) -> void:
	targets.clear()
	forces = f
	force_kinds = []
	for k in run.stage.get("kinds", []):
		if k in EnemyForces.KINDS:
			force_kinds.append(k)
	for st in props.structures:
		if run.is_target(String(st.kind)):
			targets.append(st)
	refresh(0.0)


func clear_all() -> void:
	targets.clear()
	force_kinds = []
	multimesh.visible_instance_count = 0


func refresh(dt: float) -> void:
	_t += dt
	var n := 0
	for st in targets:
		if not st.alive or n >= MAX:
			continue
		var p: Vector3 = st.pos
		var sz: Variant = st.get("size", Vector3.ZERO)
		if sz is Vector3:
			p.y += (sz as Vector3).y
		var bob := 0.004 * sin(_t * 2.4 + float(n) * 0.9)
		var b := Basis(Vector3.UP, _t * 1.5 + n).scaled(Vector3.ONE * SIZE)
		multimesh.set_instance_transform(n, Transform3D(b, p + Vector3(0, LIFT + bob, 0)))
		n += 1
	if forces and not force_kinds.is_empty():
		for u in forces.units:
			if not u.alive or not (u.kind in force_kinds) or n >= MAX:
				continue
			var q: Vector3 = u.p
			var b2 := Basis(Vector3.UP, _t * 1.5 + n).scaled(Vector3.ONE * SIZE * 0.8)
			multimesh.set_instance_transform(n, Transform3D(b2, q + Vector3(0, 0.018 + 0.003 * sin(_t * 2.4 + n), 0)))
			n += 1
	multimesh.visible_instance_count = n


func alive_count() -> int:
	var n := 0
	for st in targets:
		if st.alive:
			n += 1
	return n
