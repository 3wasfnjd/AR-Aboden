class_name ReconMarks
extends MultiMeshInstance3D
## What the reconnaissance drone has spotted (web, build 27): an amber diamond floating
## over every enemy target it saw (military sites, warships, the moving forces), with a
## ring on the ground round it; a mark follows a moving unit, fades after SPOT_T seconds
## and is gone when the target is destroyed. One MultiMesh, island-local (diorama child).

const MAX := 64
const SPOT_T := 60.0
const SIZE := 0.008
## Structure kinds the drone reports (the enemy's military sites and warships).
const SITE_KINDS := ["sam", "launcher_truck", "silo", "silo_open", "radar_base", "radar_sphere", "bunker",
	"tank_vehicle", "has", "jet", "barracks", "ctower", "mast", "frigate", "watchtower", "mil_truck"]

var spotted: Array[Dictionary] = []    # {st | unit, t}
var _t := 0.0
var rings: MultiMeshInstance3D


func _init() -> void:
	name = "ReconMarks"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = _mm(_diamond())
	material_override = _mat(Color(1.0, 0.74, 0.18, 0.95))
	custom_aabb = AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.6, 2))
	rings = MultiMeshInstance3D.new()
	rings.multimesh = _mm(_ring())
	rings.material_override = _mat(Color(1.0, 0.74, 0.18, 0.7))
	rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rings.custom_aabb = custom_aabb
	add_child(rings)


func _mm(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	return mm


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	m.render_priority = 3
	return m


static func _diamond() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 1, 0)
	var bot := Vector3(0, -1, 0)
	var q := [Vector3(0.6, 0, 0), Vector3(0, 0, 0.6), Vector3(-0.6, 0, 0), Vector3(0, 0, -0.6)]
	for k in 4:
		for v in [top, q[k], q[(k + 1) % 4], bot, q[(k + 1) % 4], q[k]]:
			st.add_vertex(v)
	return st.commit()


static func _ring() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p := [Vector3(cos(a0) * 0.8, 0, sin(a0) * 0.8), Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1) * 0.8, 0, sin(a1) * 0.8), Vector3(cos(a1), 0, sin(a1))]
		for v in [p[0], p[1], p[2], p[2], p[1], p[3]]:
			st.add_vertex(v)
	return st.commit()


func clear_all() -> void:
	spotted.clear()
	multimesh.visible_instance_count = 0
	rings.multimesh.visible_instance_count = 0


## The drone at `p` looks over `r`: mark what it sees. Returns how many are new.
func scan(p: Vector3, r: float, props: IslandProps, forces: EnemyForces) -> int:
	var fresh := 0
	var p2 := Vector2(p.x, p.z)
	for st in props.structures:
		if st.alive and st.kind in SITE_KINDS and Vector2(st.pos.x, st.pos.z).distance_to(p2) < r:
			fresh += _spot({"st": st})
	if forces:
		for u in forces.units:
			if u.alive and Vector2(u.p.x, u.p.z).distance_to(p2) < r:
				fresh += _spot({"unit": u})
	return fresh


func _spot(e: Dictionary) -> int:
	var o: Dictionary = e.get("st", e.get("unit"))
	for s in spotted:
		if s.get("st", s.get("unit")) == o:
			s.t = 0.0
			return 0
	if spotted.size() >= MAX:
		spotted.remove_at(0)
	e.t = 0.0
	spotted.append(e)
	return 1


func count() -> int:
	return spotted.size()


func refresh(dt: float, ground: Callable) -> void:
	_t += dt
	var n := 0
	var i := 0
	while i < spotted.size():
		var s: Dictionary = spotted[i]
		s.t = float(s.t) + dt
		var o: Dictionary = s.get("st", s.get("unit"))
		if float(s.t) > SPOT_T or not bool(o.alive):
			spotted.remove_at(i)
			continue
		var base: Vector3 = (o.pos if s.has("st") else o.p)
		var h := 0.004
		if s.has("st") and o.get("size") is Vector3:
			h = (o.size as Vector3).y
		var g := float(ground.call(base.x, base.z))
		var gy := g if g > -INF else base.y
		var fade := clampf((SPOT_T - float(s.t)) / 8.0, 0.25, 1.0)
		var b := Basis(Vector3.UP, _t * 2.0 + n).scaled(Vector3.ONE * SIZE * (0.6 + 0.4 * fade))
		multimesh.set_instance_transform(n, Transform3D(b, base + Vector3(0, h + 0.018 + 0.003 * sin(_t * 3.0 + n), 0)))
		var rr := 0.012 + 0.002 * sin(_t * 4.0 + n)
		rings.multimesh.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(rr, 1, rr)), Vector3(base.x, gy + 0.0006, base.z)))
		n += 1
		i += 1
	multimesh.visible_instance_count = n
	rings.multimesh.visible_instance_count = n
