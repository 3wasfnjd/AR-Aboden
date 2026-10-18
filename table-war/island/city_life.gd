class_name CityLife
extends Node3D
## Life in the toy city: cars driving the street grid and people walking the
## sidewalks. They react to strikes: everyone inside the blast is killed (cars turn
## into burnt wrecks, people are gone), everyone nearby panics and runs / drives away
## from the explosion, and the cratered crossings are avoided afterwards.
##
## Cheap by design: one MultiMesh for the cars and one for the people (2 draw calls),
## state in packed arrays, and the whole instance buffer written in one call per
## frame. Positions are island-local; stepped from PhysicsTest.advance (so slow
## motion and tests drive it too).

const CARS := 60
const PEOPLE := 120
const CAR_SPEED := 0.024           # m/s on the table (a 3 cm block in ~1.2 s)
const CAR_PANIC := 0.07
const WALK_SPEED := 0.0045
const RUN_SPEED := 0.022
const PANIC_T := 5.0               # s of panic after a strike nearby
const PANIC_R := 0.10              # m: strikes this close make agents flee
const LANE := 0.0011               # car offset to the right of the street centre
const WALK_SIDE := 0.0027          # sidewalk offset from the street centre
const LIFT := 0.0003
const CAR_COLS := [Color(0.92, 0.25, 0.20), Color(0.20, 0.50, 0.92), Color(0.98, 0.85, 0.25), Color(0.95, 0.95, 0.93),
	Color(0.25, 0.75, 0.40), Color(0.98, 0.55, 0.20), Color(0.30, 0.30, 0.34), Color(0.65, 0.40, 0.85)]
const SHIRT_COLS := [Color(0.95, 0.30, 0.25), Color(0.25, 0.55, 0.95), Color(0.98, 0.85, 0.30), Color(0.30, 0.80, 0.45),
	Color(0.95, 0.95, 0.95), Color(0.85, 0.45, 0.85), Color(0.98, 0.60, 0.25)]

var island: Island
var nodes := PackedVector3Array()    # street crossings (island-local, on the road)
var adj: Array[PackedInt32Array] = []
var blocked := PackedByteArray()     # crossing destroyed by a strike

# agents: cars first (0 .. CARS-1), then people
var a_from := PackedInt32Array()
var a_to := PackedInt32Array()
var a_t := PackedFloat32Array()      # 0..1 along the edge
var a_alive := PackedByteArray()     # 1 alive, 0 dead (person gone / car wreck)
var a_panic := PackedFloat32Array()  # s of panic left
var a_side := PackedFloat32Array()   # sidewalk side (+1 / -1) for people
var a_phase := PackedFloat32Array()
var a_col: Array[Color] = []
var a_pos := PackedVector3Array()    # last position (tests, wreck pose)
var a_yaw := PackedFloat32Array()
var last_blast := Vector3.INF
var mm_cars: MultiMesh
var mm_people: MultiMesh
var rng := RandomNumberGenerator.new()
var _time := 0.0
var _buf_c := PackedFloat32Array()
var _buf_p := PackedFloat32Array()


func build(isl: Island) -> void:
	island = isl
	rng.seed = 9001
	_build_graph()
	mm_cars = _make_mm("Cars", _car_mesh(), CARS)
	mm_people = _make_mm("People", _person_mesh(), PEOPLE)
	spawn()


func agent_count() -> int:
	return CARS + PEOPLE


func is_car(i: int) -> bool:
	return i < CARS


# ------------------------------------------------------------------------------------
# street graph
# ------------------------------------------------------------------------------------

func _build_graph() -> void:
	var L := island.layout
	var C := L.town_center
	var P := IslandLayout.CITY_PITCH
	var index := {}
	for j in range(-5, 6):
		for i in range(-5, 6):
			var q := C + Vector2(i * P, j * P)
			if q.distance_to(C) > L.town_radius * 0.95:
				continue
			if island.terrain.height_at(q.x, q.y) - IslandTerrain.SEA < 0.0015:
				continue
			index[Vector2i(i, j)] = nodes.size()
			nodes.append(Vector3(q.x, island.terrain.height_at(q.x, q.y) + LIFT, q.y))
	adj.resize(nodes.size())
	for k in nodes.size():
		adj[k] = PackedInt32Array()
	for key in index:
		var a: int = index[key]
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nb: Vector2i = key + d
			if not index.has(nb):
				continue
			var b: int = index[nb]
			var mid := (nodes[a] + nodes[b]) * 0.5
			if island.terrain.height_at(mid.x, mid.z) - IslandTerrain.SEA < 0.0015:
				continue
			adj[a].append(b)
			adj[b].append(a)
	blocked.resize(nodes.size())
	blocked.fill(0)


## Everyone back on the streets (build, reset island).
func spawn() -> void:
	var n := agent_count()
	for arr in [a_from, a_to, a_t, a_alive, a_panic, a_side, a_phase, a_pos, a_yaw]:
		arr.resize(n)
	a_col.resize(n)
	blocked.fill(0)
	_written.resize(n)
	_written.fill(0)
	last_blast = Vector3.INF
	var usable: Array[int] = []
	for k in nodes.size():
		if adj[k].size() > 0:
			usable.append(k)
	for i in n:
		a_alive[i] = 1 if not usable.is_empty() else 0
		a_panic[i] = 0.0
		a_side[i] = 1.0 if rng.randf() < 0.5 else -1.0
		a_phase[i] = rng.randf() * TAU
		a_col[i] = CAR_COLS[rng.randi() % CAR_COLS.size()] if is_car(i) else SHIRT_COLS[rng.randi() % SHIRT_COLS.size()]
		if usable.is_empty():
			continue
		var f: int = usable[rng.randi() % usable.size()]
		a_from[i] = f
		a_to[i] = adj[f][rng.randi() % adj[f].size()]
		a_t[i] = rng.randf()
	step(0.0)
	step(0.0)


# ------------------------------------------------------------------------------------
# strikes
# ------------------------------------------------------------------------------------

## A strike at `p` (island-local) with blast radius `r`: kill inside, panic around,
## block the crossings it cratered.
func on_blast(p: Vector3, r: float) -> void:
	last_blast = p
	var p2 := Vector2(p.x, p.z)
	for k in nodes.size():
		if Vector2(nodes[k].x, nodes[k].z).distance_to(p2) < r * 1.1:
			blocked[k] = 1
	for i in agent_count():
		if a_alive[i] == 0:
			continue
		var q := a_pos[i]
		var d := Vector2(q.x, q.z).distance_to(p2)
		if d < r * (1.0 if is_car(i) else 1.2):
			a_alive[i] = 0
			if is_car(i):
				a_col[i] = Color(0.10, 0.09, 0.08)   # burnt wreck stays on the street
			continue
		if d < PANIC_R:
			a_panic[i] = PANIC_T * rng.randf_range(0.8, 1.2)
			# heading towards the blast: turn round at once
			var df := Vector2(nodes[a_from[i]].x, nodes[a_from[i]].z).distance_to(p2)
			var dt := Vector2(nodes[a_to[i]].x, nodes[a_to[i]].z).distance_to(p2)
			if dt < df:
				var f := a_from[i]
				a_from[i] = a_to[i]
				a_to[i] = f
				a_t[i] = 1.0 - a_t[i]


func _next_node(i: int) -> int:
	var at := a_to[i]
	var nb := adj[at]
	if nb.is_empty():
		return a_from[i]
	var panic := a_panic[i] > 0.0 and last_blast != Vector3.INF
	var best := -1
	var best_s := -INF
	for k in nb.size():
		var c: int = nb[k]
		if blocked[c] == 1:
			continue
		var s := rng.randf()
		if c == a_from[i]:
			s -= 0.9            # rarely turn back
		if panic:
			# run away: the crossing farthest from the blast wins
			s += 40.0 * Vector2(nodes[c].x - last_blast.x, nodes[c].z - last_blast.z).length()
		if s > best_s:
			best_s = s
			best = c
	return best if best >= 0 else a_from[i]


# ------------------------------------------------------------------------------------
# per frame
# ------------------------------------------------------------------------------------

func step(dt: float) -> void:
	_time += dt
	if _buf_c.size() != CARS * 16:
		_buf_c.resize(CARS * 16)
		_buf_p.resize(PEOPLE * 16)
		_written.resize(agent_count())
		_written.fill(0)
	_buf_c = _step_range(0, CARS, dt, _buf_c, 1, 0)
	# people walk slowly: each half of them is stepped every second frame (2 x dt)
	_frame += 1
	_buf_p = _step_range(CARS, agent_count(), dt * 2.0, _buf_p, 2, _frame % 2)
	mm_cars.buffer = _buf_c
	mm_people.buffer = _buf_p


var _written := PackedByteArray()    # dead agent already written in its final pose
var _frame := 0


func _step_range(i0: int, i1: int, dt: float, buf: PackedFloat32Array, stride: int, first: int) -> PackedFloat32Array:
	var car := i0 < CARS
	for i in range(i0 + first, i1, stride):
		var alive := a_alive[i] == 1
		if not alive and _written[i] == 1:
			continue
		if alive and not nodes.is_empty():
			var panic := a_panic[i] > 0.0
			if panic:
				a_panic[i] = maxf(a_panic[i] - dt, 0.0)
			var a := nodes[a_from[i]]
			var b := nodes[a_to[i]]
			var len := maxf(Vector2(b.x - a.x, b.z - a.z).length(), 1e-4)
			var sp: float
			if car:
				sp = CAR_PANIC if panic else CAR_SPEED
			else:
				sp = RUN_SPEED if panic else WALK_SPEED * (0.8 + 0.4 * fmod(a_phase[i], 1.0))
			var t := a_t[i] + sp * dt / len
			if t >= 1.0:
				t -= 1.0
				var nx := _next_node(i)
				a_from[i] = a_to[i]
				a_to[i] = nx
				a = nodes[a_from[i]]
				b = nodes[a_to[i]]
			a_t[i] = minf(t, 1.0)
			var dx := b.x - a.x
			var dz := b.z - a.z
			var dl := maxf(sqrt(dx * dx + dz * dz), 1e-6)
			dx /= dl
			dz /= dl
			var off := LANE if car else WALK_SIDE * a_side[i]
			var p := a.lerp(b, a_t[i]) + Vector3(-dz, 0.0, dx) * off
			if not car:
				p.y += absf(sin(_time * (22.0 if panic else 9.0) + a_phase[i])) * (0.0005 if panic else 0.00025)
			a_pos[i] = p
			a_yaw[i] = atan2(-dz, dx)
		# instance: rotation about y (+ wreck skew), uniform scale, colour as custom data
		var s := 1.0
		var yaw := a_yaw[i]
		if not alive:
			_written[i] = 1
			if car:
				yaw += 0.5
			else:
				s = 0.0
		var cs := cos(yaw) * s
		var sn := sin(yaw) * s
		var p2 := a_pos[i]
		var c := a_col[i]
		var k := (i - i0) * 16
		buf[k] = cs; buf[k + 1] = 0.0; buf[k + 2] = sn; buf[k + 3] = p2.x
		buf[k + 4] = 0.0; buf[k + 5] = s; buf[k + 6] = 0.0; buf[k + 7] = p2.y
		buf[k + 8] = -sn; buf[k + 9] = 0.0; buf[k + 10] = cs; buf[k + 11] = p2.z
		buf[k + 12] = c.r; buf[k + 13] = c.g; buf[k + 14] = c.b; buf[k + 15] = 1.0
	return buf


## Alive agents within `r` of a point (tests).
func alive_near(p: Vector3, r: float) -> int:
	var n := 0
	for i in agent_count():
		if a_alive[i] == 1 and Vector2(a_pos[i].x - p.x, a_pos[i].z - p.z).length() < r:
			n += 1
	return n


func alive_count() -> int:
	var n := 0
	for i in agent_count():
		n += a_alive[i]
	return n


# ------------------------------------------------------------------------------------
# meshes: vertex alpha 1 = tinted by the instance colour (body / shirt), < 1 = a fixed
# colour picked in the shader
# ------------------------------------------------------------------------------------

func _make_mm(nm: String, mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;
// COLOR = vertex colour x instance colour (body / shirt tint). Instance custom data
// is not used: with vertex colours it reads garbage in GL Compatibility. Parts that
// keep their own colour are marked by the vertex alpha: 0.6 skin, 0.45 glass, 0.25 dark.
void fragment() {
	vec3 c = COLOR.rgb;
	float a = COLOR.a;
	if (a < 0.99) {
		c = a > 0.55 ? vec3(0.92, 0.74, 0.58) : (a > 0.35 ? vec3(0.35, 0.55, 0.70) : vec3(0.12, 0.13, 0.17));
	}
	ALBEDO = pow(c, vec3(2.2));
	ROUGHNESS = 0.7;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.3, 1.0))
	add_child(mi)
	return mm


## Toy car, nose along +x: body, cabin, dark windows, wheels. (Vertex alpha: see the shader.)
func _car_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var body := Color(1, 1, 1, 1)
	var dark := Color(0.12, 0.13, 0.15, 0.25)
	var glass := Color(0.35, 0.55, 0.70, 0.45)
	mb.box(Vector3(0, 0.0009, 0), Vector3(0.0046, 0.0010, 0.0021), body)
	mb.box(Vector3(-0.0003, 0.0018, 0), Vector3(0.0024, 0.0009, 0.0019), body)
	mb.box(Vector3(-0.0003, 0.0018, 0), Vector3(0.0025, 0.0006, 0.00195), glass)
	for wx in [-0.0014, 0.0014]:
		for wz in [-0.0010, 0.0010]:
			mb.box(Vector3(wx, 0.0004, wz), Vector3(0.0009, 0.0008, 0.0003), dark)
	return mb.commit()


## Toy person: legs, shirt (tinted), head.
func _person_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var shirt := Color(1, 1, 1, 1)
	var legs := Color(0.20, 0.24, 0.40, 0.25)
	var skin := Color(0.92, 0.74, 0.58, 0.6)
	mb.box(Vector3(0, 0.0005, 0), Vector3(0.0005, 0.0010, 0.0007), legs)
	mb.box(Vector3(0, 0.00135, 0), Vector3(0.0006, 0.0008, 0.0009), shirt)
	mb.box(Vector3(0, 0.0021, 0), Vector3(0.0007, 0.0007, 0.0007), skin)
	return mb.commit()
