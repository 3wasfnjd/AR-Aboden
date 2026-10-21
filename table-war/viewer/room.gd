class_name Room
extends Node3D
## Stand-in for passthrough: a wooden table in a softly lit living room.
## Lighting: warm "window" sun with soft PCF shadows + cool fill + sky ambient.
##
## XR: set_mr(true) (passthrough) hides the whole fake room (table, walls, floor, mug,
## notebook = the "Set" node) and the lighting that fakes a room (sky background, cool
## fill, glow); a soft key light + neutral ambient stay, suited to a real room behind.
## set_mr(false) (VR fallback) shows the room again. apply_quest() is the Quest 3
## profile: one directional light, small orthogonal shadow (1.5 m), no glow / adjustments.

var sun: DirectionalLight3D
var fill: DirectionalLight3D
var env: Environment
## Everything that only fakes a room: moved with the diorama in VR (table top under its base).
var set_root: Node3D
var mr := false
var quest := false
## Sun shadows: OFF by default everywhere (owner, after build 1: they made the Quest
## build heavy). Desktop screenshots can opt in with `-- --shadows`.
static var shadows := false


func _ready() -> void:
	_environment()
	_lights()
	set_root = Node3D.new()
	set_root.name = "Set"
	add_child(set_root)
	_table()
	_room_shell()
	_table_clutter()


func set_mr(on: bool) -> void:
	mr = on
	set_root.visible = not on
	if on:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0, 0)
		# neutral, slightly warm ambient: the real room supplies the context
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.82, 0.83, 0.85)
		env.ambient_light_energy = 0.55
		env.tonemap_exposure = 1.0
		sun.light_energy = 1.05
		sun.shadow_opacity = 0.85
	else:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.38
		env.tonemap_exposure = 1.05
		sun.light_energy = 1.0
		sun.shadow_opacity = 1.0
	env.glow_enabled = not on and not quest
	fill.visible = not on and not quest
	if is_inside_tree():
		get_viewport().transparent_bg = on


## VR campaign (build 14): the battleship's operations room replaces the fake living room.
## No sky shader pass (OpsRoom draws its own low-poly sky dome); a cool, even ambient for
## the flat-shaded room and a high sun for the island.
func set_ops() -> void:
	set_root.visible = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.52, 0.80)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.76, 0.86)
	env.ambient_light_energy = 0.55
	env.tonemap_exposure = 1.0
	sun.light_energy = 1.05
	if is_inside_tree():
		get_viewport().transparent_bg = false


## The light of each map: 1 = midday, 2 = late afternoon (low warm sun, warmer ambient).
func set_map_light(map_id: int) -> void:
	_map = map_id
	if night:
		set_night(true)
		return
	if map_id == 2:
		sun.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(-120.0), 0)
		sun.light_color = Color(1.0, 0.80, 0.58)
		sun.light_energy = 1.2
		env.ambient_light_color = Color(0.92, 0.84, 0.78)
		env.ambient_light_energy = 0.7
	else:
		sun.rotation = Vector3(deg_to_rad(-47.0), deg_to_rad(-38.0), 0)
		sun.light_color = Color(1.0, 0.94, 0.84)
		sun.light_energy = 1.05
		env.ambient_light_color = Color(0.70, 0.76, 0.86)
		env.ambient_light_energy = 0.55


## Web open ocean (build 20): no room, no table: a clear sky to a sea horizon.
func set_ocean() -> void:
	set_root.visible = false
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = Color(0.30, 0.52, 0.85)
	sm.sky_horizon_color = Color(0.74, 0.84, 0.94)
	sm.ground_horizon_color = Color(0.20, 0.36, 0.55)
	sm.ground_bottom_color = Color(0.06, 0.16, 0.30)
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.84, 0.94)
	env.fog_density = 0.04
	env.fog_sky_affect = 0.0


## Web night (build 24): moonlight, a dark sky with stars and the moon, darker fog;
## the city's windows light up (structure shader, global tw_night). Off: back to the
## open-sea day. The map's own light is re-applied after it (set_map_light).
var night := false
var _sky_night: Node3D


func set_night(on: bool) -> void:
	night = on
	RenderingServer.global_shader_parameter_set("tw_night", 1.0 if on else 0.0)
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	if on:
		sm.sky_top_color = Color(0.010, 0.018, 0.05)
		sm.sky_horizon_color = Color(0.05, 0.08, 0.16)
		sm.ground_horizon_color = Color(0.03, 0.05, 0.10)
		sm.ground_bottom_color = Color(0.01, 0.02, 0.04)
		sm.sun_angle_max = 0.0
		env.ambient_light_energy = 0.9
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.16, 0.20, 0.32)
		env.fog_light_color = Color(0.04, 0.06, 0.12)
		env.fog_density = 0.05
		sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(140.0), 0)
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = 0.32
		if _fill_e < 0.0:
			_fill_e = fill.light_energy
		fill.light_energy = 0.0
	else:
		set_ocean()
		sm.sun_angle_max = 30.0
		if _fill_e >= 0.0:
			fill.light_energy = _fill_e
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.6
		set_map_light(_map)
	if _sky_night == null:
		_sky_night = _make_night_sky()
		add_child(_sky_night)
	_sky_night.visible = on


var _fill_e := -1.0
var _map := 1


## Day and night in turn (web, build 25): the hour `h` (0-24) sets the sun's height and
## heading, its colour (white at noon, orange at sunset / sunrise), the sky (blue, a
## red-gold horizon at dusk, dark with stars at night), the ambient light and the fog;
## the moon lights the night. Returns the night factor (0 day .. 1 night) for the city
## windows, the sea and the smoke (global tw_night).
func set_hour(h: float) -> float:
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	var el := sin((h - 6.0) / 12.0 * PI) * deg_to_rad(68.0)      # sun elevation
	var n := smoothstep(deg_to_rad(3.0), deg_to_rad(-9.0), el)      # night
	var dusk := (1.0 - smoothstep(0.0, deg_to_rad(22.0), absf(el))) * (1.0 - n * 0.7)
	var day_top := Color(0.30, 0.52, 0.85)
	var day_hz := Color(0.74, 0.84, 0.94)
	var dusk_hz := Color(1.0, 0.56, 0.32)
	var night_top := Color(0.010, 0.018, 0.05)
	var night_hz := Color(0.05, 0.08, 0.16)
	sm.sky_top_color = day_top.lerp(Color(0.22, 0.24, 0.45), dusk * 0.6).lerp(night_top, n)
	sm.sky_horizon_color = day_hz.lerp(dusk_hz, dusk).lerp(night_hz, n)
	sm.ground_horizon_color = Color(0.20, 0.36, 0.55).lerp(Color(0.03, 0.05, 0.10), n)
	sm.ground_bottom_color = Color(0.06, 0.16, 0.30).lerp(Color(0.01, 0.02, 0.04), n)
	sm.sun_angle_max = 30.0 * (1.0 - n)
	var sun_e := 1.1 * smoothstep(deg_to_rad(-4.0), deg_to_rad(10.0), el)
	var moon_e := 0.32 * n
	if sun_e >= moon_e:
		# the sun crosses from the east (morning) to the west (evening)
		var az := lerpf(deg_to_rad(80.0), deg_to_rad(-100.0), clampf((h - 6.0) / 12.0, 0.0, 1.0))
		sun.rotation = Vector3(-maxf(el, deg_to_rad(4.0)), az, 0)
		sun.light_color = Color(1.0, 0.94, 0.84).lerp(Color(1.0, 0.58, 0.30), dusk)
		sun.light_energy = sun_e
	else:
		sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(140.0), 0)
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = moon_e
	if _fill_e < 0.0:
		_fill_e = fill.light_energy
	fill.light_energy = _fill_e * (1.0 - n)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.82).lerp(Color(0.85, 0.62, 0.52), dusk * 0.5).lerp(Color(0.16, 0.20, 0.32), n)
	env.ambient_light_energy = lerpf(0.75, 0.9, n)
	env.fog_light_color = day_hz.lerp(dusk_hz, dusk * 0.6).lerp(Color(0.04, 0.06, 0.12), n)
	RenderingServer.global_shader_parameter_set("tw_night", n)
	if _sky_night == null:
		_sky_night = _make_night_sky()
		add_child(_sky_night)
	_sky_night.visible = n > 0.25
	return n


## Stars (tiny unshaded dots on a far dome) and the moon.
func _make_night_sky() -> Node3D:
	var root := Node3D.new()
	root.name = "NightSky"
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for k in 900:
		var az := r.randf() * TAU
		var el := asin(r.randf_range(0.04, 1.0))
		var d := Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az))
		var p := d * 45.0
		var s := r.randf_range(0.04, 0.11) * (2.0 if r.randf() < 0.05 else 1.0)
		var t1 := d.cross(Vector3.UP).normalized()
		if t1.length() < 0.1:
			t1 = Vector3.RIGHT
		var t2 := d.cross(t1).normalized()
		var c := Color(1, 1, 1).lerp(Color(0.75, 0.85, 1.0), r.randf())
		mb.tri_out(p + t1 * s, p - t1 * s + t2 * s, p - t1 * s - t2 * s, c, -d)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	var stars := MeshInstance3D.new()
	stars.mesh = mb.commit(null, mat)
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(stars)
	var moon := MeshInstance3D.new()
	var q := SphereMesh.new()
	q.radius = 1.4
	q.height = 2.8
	moon.mesh = q
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.95, 0.95, 0.88)
	mm.disable_fog = true
	moon.material_override = mm
	var md := Vector3(-0.45, 0.55, 0.70).normalized()
	moon.position = md * 44.0
	root.add_child(moon)
	return root


func apply_quest() -> void:
	quest = true
	env.glow_enabled = false
	env.adjustment_enabled = false   # a full-screen pass on the Compatibility renderer
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	fill.visible = false
	sun.shadow_enabled = false       # no shadow-casting light at all on Quest
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 1.5


func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.93, 0.91, 0.87)
	sky_mat.sky_horizon_color = Color(0.86, 0.80, 0.72)
	sky_mat.ground_horizon_color = Color(0.55, 0.46, 0.37)
	sky_mat.ground_bottom_color = Color(0.30, 0.24, 0.19)
	sky_mat.sun_angle_max = 1.0
	sky_mat.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.38
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 2.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "WindowSun"
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.0
	sun.rotation = Vector3(deg_to_rad(-47.0), deg_to_rad(-38.0), 0)
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 3.0
	sun.directional_shadow_split_1 = 0.25
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.1
	sun.shadow_blur = 2.6
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.80, 0.86, 1.0)
	fill.light_energy = 0.36
	fill.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(150.0), 0)
	fill.shadow_enabled = false
	add_child(fill)


func _wood(light: Color, dark: Color, plank: float, gloss: float, scale := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://island/wood.gdshader")
	m.set_shader_parameter("col_light", light)
	m.set_shader_parameter("col_dark", dark)
	m.set_shader_parameter("plank", plank)
	m.set_shader_parameter("gloss", gloss)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("island_local", false)
	return m


func _table() -> void:
	var top := MeshInstance3D.new()
	top.name = "TableTop"
	var bm := BoxMesh.new()
	bm.size = Vector3(2.6, 0.045, 1.5)
	top.mesh = bm
	top.position = Vector3(0, -0.0225, 0.05)
	top.material_override = _wood(Color(0.66, 0.48, 0.32), Color(0.44, 0.29, 0.18), 0.19, 0.45, 1.0)
	set_root.add_child(top)
	for lx in [-1.2, 1.2]:
		for lz in [-0.62, 0.72]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.07, 0.72, 0.07)
			leg.mesh = lm
			leg.position = Vector3(lx, -0.405, lz)
			leg.material_override = top.material_override
			set_root.add_child(leg)


func _room_shell() -> void:
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mi.mesh = pm
	floor_mi.position = Vector3(0, -0.77, 0)
	floor_mi.material_override = _wood(Color(0.42, 0.30, 0.22), Color(0.28, 0.19, 0.13), 0.14, 0.3, 1.0)
	set_root.add_child(floor_mi)
	var rug := MeshInstance3D.new()
	var rm := PlaneMesh.new()
	rm.size = Vector2(3.4, 2.4)
	rug.mesh = rm
	rug.position = Vector3(0, -0.768, 0.1)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.55, 0.38, 0.30)
	rmat.roughness = 1.0
	rug.material_override = rmat
	set_root.add_child(rug)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.86, 0.82, 0.76)
	wall_mat.roughness = 0.95
	for w in [[Vector3(0, 0.6, -3.0), Vector3(0, 0, 0)], [Vector3(-3.4, 0.6, 0), Vector3(0, PI * 0.5, 0)], [Vector3(3.4, 0.6, 0), Vector3(0, -PI * 0.5, 0)], [Vector3(0, 0.6, 3.4), Vector3(0, PI, 0)]]:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(8, 3)
		mi.mesh = qm
		mi.position = w[0]
		mi.rotation = w[1]
		mi.material_override = wall_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		set_root.add_child(mi)
	# skirting + a window glow panel on the left wall (where the sun comes from)
	var win := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(1.6, 1.3)
	win.mesh = wq
	win.position = Vector3(-3.39, 0.9, -0.6)
	win.rotation = Vector3(0, PI * 0.5, 0)
	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.albedo_color = Color(1.0, 0.98, 0.92)
	win.material_override = wmat
	win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_root.add_child(win)


func _table_clutter() -> void:
	# a ceramic mug and a closed notebook: instant real-world scale cues
	var mb := MeshBuilder.new()
	var c := Color(0.90, 0.88, 0.84)
	mb.cylinder(Vector3(0, 0, 0), 0.041, 0.043, 0.095, 28, c, true, Color(0.25, 0.16, 0.10))
	mb.cylinder(Vector3(0, 0.0, 0), 0.036, 0.036, 0.003, 28, c)
	# handle
	for k in 10:
		var a0 := PI * (k / 10.0) - PI * 0.5
		var a1 := PI * ((k + 1) / 10.0) - PI * 0.5
		var p0 := Vector3(0.043 + cos(a0) * 0.024, 0.048 + sin(a0) * 0.028, 0)
		var p1 := Vector3(0.043 + cos(a1) * 0.024, 0.048 + sin(a1) * 0.028, 0)
		mb.box((p0 + p1) * 0.5, Vector3(0.008, (p1 - p0).length() + 0.002, 0.009) if absf(cos((a0 + a1) * 0.5)) > 0.7 else Vector3((p1 - p0).length() + 0.002, 0.008, 0.009), c)
	var mug := MeshInstance3D.new()
	mug.name = "Mug"
	mug.mesh = mb.commit(null, MeshBuilder.vc_material(0.25))
	mug.position = Vector3(0.78, 0, -0.42)
	set_root.add_child(mug)
	var nb := MeshBuilder.new()
	nb.box(Vector3(0.002, 0.006, 0.0), Vector3(0.203, 0.0105, 0.146), Color(0.92, 0.90, 0.84))
	nb.box(Vector3(-0.1045, 0.006, 0.0), Vector3(0.003, 0.0125, 0.152), Color(0.20, 0.30, 0.36))
	nb.box(Vector3(0.0, 0.0115, 0.0), Vector3(0.212, 0.0012, 0.152), Color(0.20, 0.30, 0.36))
	nb.box(Vector3(0.0, 0.0006, 0.0), Vector3(0.212, 0.0012, 0.152), Color(0.20, 0.30, 0.36))
	var book := MeshInstance3D.new()
	book.name = "Notebook"
	book.mesh = nb.commit(null, MeshBuilder.vc_material(0.7))
	book.position = Vector3(-0.80, 0, 0.55)
	book.rotation.y = 0.35
	set_root.add_child(book)
