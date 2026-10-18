class_name FxSystem
extends Node3D
## Smoke / dust / fire / water puffs (two MultiMeshes = two draw calls), water ring
## ripples (one MultiMesh) and an impact flash light. Stepped explicitly so slow motion
## and screenshots are exact. Everything is pooled and capped: puffs at `cap` (the
## oldest goes first), ripples at MAX_RIPPLES; nothing is allocated per frame.

const MAX_PUFFS := 600
const MAX_RIPPLES := 24
## Live puff cap (<= MAX_PUFFS); the Quest profile lowers it.
static var cap := MAX_PUFFS

var puffs: Array[Dictionary] = []
var mm_smoke: MultiMesh
var mm_fire: MultiMesh
var flash_light: OmniLight3D
var flash_e := 0.0
var rng := RandomNumberGenerator.new()
var ripples: Array[Dictionary] = []
var mm_ripple: MultiMesh


func _ready() -> void:
	rng.seed = 77
	mm_smoke = _mm("res://fx/puff_smoke.gdshader", "Smoke")
	mm_fire = _mm("res://fx/puff_fire.gdshader", "Fire")
	_build_ripples()
	flash_light = OmniLight3D.new()
	flash_light.name = "FlashLight"
	flash_light.light_energy = 0.0
	flash_light.omni_range = 0.07
	flash_light.omni_attenuation = 1.6
	flash_light.light_color = Color(1.0, 0.72, 0.4)
	flash_light.shadow_enabled = false
	flash_light.visible = false
	add_child(flash_light)


func _mm(shader_path: String, nm: String) -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	# after the (blended) sea: puffs write no depth, so the water drawn later would
	# wash out a splash column standing above it
	mat.render_priority = 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = MAX_PUFFS
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 2.0
	mmi.custom_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))   # launch puffs at the player hand too
	add_child(mmi)
	return mm


## kind 0 = smoke/dust (alpha), 1 = fire/flash (additive)
func puff(pos: Vector3, vel: Vector3, size0: float, size1: float, life: float, col: Color, kind := 0, rise := 0.0, drag := 2.0) -> void:
	if puffs.size() >= mini(cap, MAX_PUFFS):
		puffs.remove_at(0)
	puffs.append({"p": pos, "v": vel, "s0": size0, "s1": size1, "life": life, "age": 0.0, "col": col,
		"kind": kind, "rise": rise, "drag": drag, "rot": rng.randf() * TAU, "spin": rng.randf_range(-0.6, 0.6),
		"seed": rng.randf(), "soft": rng.randf_range(0.0, 1.0)})


func explosion(p: Vector3, scale := 1.0) -> void:
	flash_light.position = p + Vector3(0, 0.01, 0)
	flash_e = 5.0 * scale
	flash_light.visible = true
	# 1. flash: a big, very short additive bloom + hot core
	puff(p + Vector3(0, 0.004, 0), Vector3.ZERO, 0.012 * scale, 0.034 * scale, 0.09, Color(1.0, 0.95, 0.78), 1, 0.0, 0.0)
	puff(p + Vector3(0, 0.003, 0), Vector3.ZERO, 0.005 * scale, 0.012 * scale, 0.16, Color(1.0, 0.85, 0.55), 1, 0.0, 0.0)
	# 2. short-lived fireball: hot opaque cores that cool into smoke (kind 2)
	for k in 14:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.25, 1.0), rng.randf_range(-1, 1)).normalized()
		puff(p + d * 0.002, d * rng.randf_range(0.04, 0.09) * scale, 0.004 * scale, 0.013 * scale, rng.randf_range(0.35, 0.6), Color(1.0, rng.randf_range(0.62, 0.82), 0.3, 1.0), 2, 0.015, 6.0)
	for k in 6:
		var d2 := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		puff(p + d2 * 0.002, d2 * 0.03 * scale, 0.006 * scale, 0.016 * scale, 0.3, Color(1.0, 0.7, 0.3), 1, 0.0, 6.0)
	# 3. dust ring rolling outwards along the ground
	for k in 26:
		var a := TAU * k / 26.0 + rng.randf_range(-0.1, 0.1)
		var d := Vector3(cos(a), 0.0, sin(a))
		var c := Color(0.66, 0.58, 0.47, 0.8).lerp(Color(0.55, 0.49, 0.42, 0.75), rng.randf())
		puff(p + d * 0.004 + Vector3(0, 0.002, 0), d * rng.randf_range(0.05, 0.11) * scale + Vector3(0, 0.01, 0), 0.004 * scale, 0.014 * scale, rng.randf_range(1.2, 2.2), c, 0, 0.004, 3.2)
	# 4. smoke column, under-lit orange by the fire at first (kind 3), then grey
	for k in 20:
		var d := Vector3(rng.randf_range(-0.4, 0.4), 1.0, rng.randf_range(-0.4, 0.4))
		var c := Color(0.30, 0.28, 0.26, 0.85).lerp(Color(0.55, 0.52, 0.48, 0.75), rng.randf())
		puff(p + Vector3(0, 0.002 + k * 0.0012, 0), d * rng.randf_range(0.02, 0.06) * scale, 0.004 * scale, 0.022 * scale, rng.randf_range(2.0, 3.6), c, 3, 0.012, 1.5)


func splash(p: Vector3, scale := 1.0) -> void:
	for k in int(10 * scale) + 3:
		var d := Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5))
		puff(p + Vector3(0, 0.001, 0), d * rng.randf_range(0.03, 0.12) * scale, 0.002 * scale, 0.007 * scale, rng.randf_range(0.5, 1.0), Color(0.95, 0.97, 0.98, 0.8), 0, -0.05, 2.5)


func muzzle(p: Vector3, dir: Vector3) -> void:
	puff(p, dir * 0.03, 0.002, 0.006, 0.12, Color(1.0, 0.8, 0.45), 1, 0.0, 5.0)
	for k in 8:
		var d := (dir * 0.6 + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 0.5), rng.randf_range(-0.5, 0.5))).normalized()
		puff(p, d * rng.randf_range(0.01, 0.04), 0.002, 0.009, rng.randf_range(0.9, 1.8), Color(0.82, 0.80, 0.76, 0.75), 0, 0.006, 2.0)


func trail(p: Vector3, col := Color(0.86, 0.85, 0.82, 0.55)) -> void:
	puff(p, Vector3(rng.randf_range(-0.002, 0.002), 0.0, rng.randf_range(-0.002, 0.002)), 0.0012, 0.004, rng.randf_range(0.7, 1.1), col, 0, 0.002, 1.0)


## Ballistic missile coming down: a hot glowing re-entry streak + darker smoke.
func reentry(p: Vector3) -> void:
	puff(p, Vector3.ZERO, 0.0016, 0.0035, 0.25, Color(1.0, 0.72, 0.38), 1, 0.0, 0.0)
	puff(p, Vector3(rng.randf_range(-0.002, 0.002), 0.003, rng.randf_range(-0.002, 0.002)), 0.0015, 0.005, rng.randf_range(0.8, 1.2), Color(0.62, 0.60, 0.57, 0.55), 0, 0.002, 1.0)


## Shell into the sea: a white water column that falls back, spray droplets, foam on
## the surface and expanding ring ripples. No fire, no flash, no crater.
func water_splash(p: Vector3, scale := 1.0) -> void:
	var k := sqrt(scale)
	var white := Color(1.0, 1.0, 1.0, 1.0)
	var ks := maxf(k, 0.8)
	# column: dense white puffs stacked by speed; rises fast and falls back under the
	# miniature gravity (rise < 0), spreading a little as it goes
	for i in int(24 * k) + 10:
		var d := Vector3(rng.randf_range(-0.1, 0.1), 1.0, rng.randf_range(-0.1, 0.1))
		var up := rng.randf_range(0.04, 0.24) * k
		puff(Vector3(p.x, p.y + 0.0008, p.z) + Vector3(rng.randf_range(-0.001, 0.001), 0.0, rng.randf_range(-0.001, 0.001)), d * up, 0.0035 * ks, 0.011 * ks, rng.randf_range(1.0, 1.6), white, 0, -0.42, 0.4)
	# spray: small droplets thrown outward
	for i in int(18 * k) + 4:
		var a := rng.randf() * TAU
		var d2 := Vector3(cos(a) * rng.randf_range(0.5, 1.0), rng.randf_range(0.6, 1.4), sin(a) * rng.randf_range(0.5, 1.0))
		puff(p + Vector3(0, 0.001, 0), d2 * rng.randf_range(0.05, 0.12) * k, 0.0012 * ks, 0.0024 * ks, rng.randf_range(0.6, 1.0), Color(0.95, 0.97, 0.98, 0.95), 0, -0.45, 1.2)
	# foam: flat white patches that stay a while on the surface
	for i in int(10 * k) + 3:
		var a2 := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.006) * scale
		puff(p + Vector3(cos(a2) * r, 0.0004, sin(a2) * r), Vector3(cos(a2), 0, sin(a2)) * 0.01 * k, 0.003 * scale, 0.011 * scale, rng.randf_range(2.5, 4.0), Color(0.97, 0.98, 0.98, 0.75), 0, 0.0, 3.0)
	# ring ripples on the water surface
	for i in 3:
		ripple(Vector3(p.x, p.y + 0.0003, p.z), (0.022 + 0.01 * i) * scale, 1.8 + 0.5 * i, 0.18 * i)


func ripple(p: Vector3, r_end: float, life: float, delay := 0.0) -> void:
	if ripples.size() >= MAX_RIPPLES:
		ripples.remove_at(0)
	ripples.append({"p": p, "r1": r_end, "life": life, "age": -delay})


func _build_ripples() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var q := [Vector3(cos(a0) * 0.86, 0, sin(a0) * 0.86), Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1) * 0.86, 0, sin(a1) * 0.86), Vector3(cos(a1), 0, sin(a1))]
		for v in [q[0], q[2], q[1], q[1], q[2], q[3]]:
			st.add_vertex(v)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 1
	mm_ripple = MultiMesh.new()
	mm_ripple.transform_format = MultiMesh.TRANSFORM_3D
	mm_ripple.use_colors = true
	mm_ripple.mesh = st.commit()
	mm_ripple.instance_count = MAX_RIPPLES
	mm_ripple.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Ripples"
	mmi.multimesh = mm_ripple
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-1, -0.2, -1), Vector3(2, 1, 2))
	add_child(mmi)


func clear() -> void:
	puffs.clear()
	ripples.clear()
	flash_e = 0.0
	flash_light.visible = false
	_upload()


func step(dt: float) -> void:
	var k := 0
	while k < puffs.size():
		var q: Dictionary = puffs[k]
		q.age += dt
		if q.age >= q.life:
			# swap-remove: O(1), order does not matter for drawing
			puffs[k] = puffs[puffs.size() - 1]
			puffs.pop_back()
			continue
		var v: Vector3 = q.v
		v *= exp(-q.drag * dt)
		v.y += q.rise * dt
		q.v = v
		q.p = (q.p as Vector3) + v * dt
		q.rot += q.spin * dt
		k += 1
	if flash_e > 0.0:
		flash_e *= exp(-dt * 18.0)
		if flash_e < 0.02:
			flash_e = 0.0
			flash_light.visible = false
	flash_light.light_energy = flash_e
	var j := 0
	while j < ripples.size():
		ripples[j].age += dt
		if ripples[j].age >= ripples[j].life:
			ripples.remove_at(j)
			continue
		j += 1
	_upload()


func _upload() -> void:
	var ns := 0
	var nf := 0
	for q in puffs:
		var t: float = q.age / q.life
		var s := lerpf(q.s0, q.s1, 1.0 - pow(1.0 - t, 2.0))
		var col: Color = q.col
		var a := col.a
		if q.kind == 0:
			a *= smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(0.45, 1.0, t))
		elif q.kind == 2:
			# white-hot -> orange -> soot
			col = Color(1.0, 0.97, 0.85).lerp(col, smoothstep(0.0, 0.12, t)).lerp(Color(0.20, 0.17, 0.15), smoothstep(0.25, 0.7, t))
			a *= 1.0 - smoothstep(0.55, 1.0, t)
		elif q.kind == 3:
			# smoke lit from below by the fireball for its first moments
			col = Color(0.95, 0.52, 0.22).lerp(col, smoothstep(0.03, 0.3, t))
			a *= smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(0.45, 1.0, t))
		else:
			a *= 1.0 - smoothstep(0.2, 1.0, t)
			col = col.lerp(Color(0.8, 0.25, 0.08), t)
		col.a = a
		var xf := Transform3D(Basis().scaled(Vector3.ONE * s), q.p)
		var cd := Color(q.rot, q.seed, q.soft, 0.0)
		if q.kind != 1:
			mm_smoke.set_instance_transform(ns, xf)
			mm_smoke.set_instance_color(ns, col)
			mm_smoke.set_instance_custom_data(ns, cd)
			ns += 1
		else:
			mm_fire.set_instance_transform(nf, xf)
			mm_fire.set_instance_color(nf, col)
			mm_fire.set_instance_custom_data(nf, cd)
			nf += 1
	mm_smoke.visible_instance_count = ns
	mm_fire.visible_instance_count = nf
	var nr := 0
	for r in ripples:
		if r.age < 0.0:
			continue
		var t: float = r.age / r.life
		var rad: float = lerpf(0.002, r.r1, 1.0 - pow(1.0 - t, 2.0))
		mm_ripple.set_instance_transform(nr, Transform3D(Basis().scaled(Vector3(rad, 1.0, rad)), r.p))
		mm_ripple.set_instance_color(nr, Color(0.96, 0.98, 1.0, 0.6 * (1.0 - t)))
		nr += 1
	mm_ripple.visible_instance_count = nr
