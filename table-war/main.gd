extends Node3D
## Desktop viewer for the island war-table prototype.
## Keys: F fire at random target | click = fire at point | Space slow-motion |
##       T tilt-shift | 1-6 camera presets | H help | R reset debris
## Args (after --): --shots  render the screenshot set into res://shots/ and quit
##                  --stats  print triangle / draw-call numbers and quit

var room: Room
var island: Island
var phys: PhysicsTest
var cam: OrbitCamera
var tilt_layer: CanvasLayer
var tilt_rect: ColorRect
var hud: Label
var rng := RandomNumberGenerator.new()

const PRESETS := {
	"hero": [Vector3(0.0, 0.06, 0.04), -30.0, 40.0, 1.15, 50.0],
	"top": [Vector3(0.0, 0.05, 0.0), 0.0, 89.6, 1.62, 40.0],
	"town": [Vector3(0.085, 0.085, 0.14), -18.0, 34.0, 0.24, 50.0],
	"base": [Vector3(-0.25, 0.085, -0.04), 28.0, 36.0, 0.30, 50.0],
	"side": [Vector3(-0.22, 0.055, 0.42), -38.0, 13.0, 0.36, 45.0],
	"lean": [Vector3(0.02, 0.08, 0.02), -10.0, 58.0, 0.66, 60.0],
}


func _ready() -> void:
	rng.seed = 2024
	room = Room.new()
	room.name = "Room"
	add_child(room)
	island = Island.new()
	island.name = "Island"
	add_child(island)
	phys = PhysicsTest.new()
	phys.name = "PhysicsTest"
	add_child(phys)
	phys.setup(island)
	cam = OrbitCamera.new()
	cam.name = "Camera"
	add_child(cam)
	cam.current = true
	cam.clicked.connect(_on_click)
	_apply_preset("hero")
	_build_overlay()
	var args := OS.get_cmdline_user_args()
	if "--shots" in args:
		_run_shots.call_deferred()
	elif "--stats" in args:
		_run_stats.call_deferred()


func _build_overlay() -> void:
	tilt_layer = CanvasLayer.new()
	add_child(tilt_layer)
	tilt_rect = ColorRect.new()
	tilt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tilt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://viewer/tiltshift.gdshader")
	tilt_rect.material = m
	tilt_rect.visible = false
	tilt_layer.add_child(tilt_rect)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	hud.add_theme_constant_override("outline_size", 4)
	hud.text = "LMB drag orbit · RMB pan · wheel zoom · click = fire there · F random fire · Space slow-mo · T tilt-shift · 1-6 views · H hide"
	tilt_layer.add_child(hud)


func _apply_preset(name: String) -> void:
	var p: Array = PRESETS[name]
	cam.set_view(p[0], p[1], p[2], p[3], p[4])


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F:
			phys.fire(_random_target())
		KEY_SPACE:
			phys.set_slow_motion(not phys.slow_motion)
		KEY_T:
			tilt_rect.visible = not tilt_rect.visible
		KEY_H:
			hud.visible = not hud.visible
		KEY_R:
			phys.debris.clear()
		KEY_1: _apply_preset("hero")
		KEY_2: _apply_preset("top")
		KEY_3: _apply_preset("town")
		KEY_4: _apply_preset("base")
		KEY_5: _apply_preset("side")
		KEY_6: _apply_preset("lean")


func _on_click(pos: Vector2) -> void:
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var hit: Variant = island.terrain.raycast(from, dir)
	if hit != null:
		phys.fire(hit)


func _random_target() -> Vector3:
	var alive: Array[Dictionary] = []
	for s in island.props.structures:
		if s.alive and s.fragile and s.kind in ["house", "tower", "warehouse", "hangar", "barracks"]:
			alive.append(s)
	if alive.is_empty() or rng.randf() < 0.3:
		for _i in 50:
			var x := rng.randf_range(-0.35, 0.4)
			var z := rng.randf_range(-0.2, 0.2)
			var h := island.height_at(x, z)
			if h > IslandTerrain.SEA + 0.002:
				return Vector3(x, h, z)
	var s: Dictionary = alive[rng.randi() % alive.size()]
	var p: Vector3 = s.pos
	return Vector3(p.x, island.height_at(p.x, p.z), p.z)


# ======================================================================================
# screenshots & stats
# ======================================================================================

func _frames(n: int) -> void:
	for _i in n:
		await RenderingServer.frame_post_draw


func _capture(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("SHOT ", path, " ", img.get_size())


func render_stats(label: String) -> Dictionary:
	var vp := get_viewport()
	var d := {
		"label": label,
		"draw_calls": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"objects": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		"shadow_draw_calls": vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_primitives": vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
	}
	print("RENDER_STATS ", JSON.stringify(d))
	return d


func _run_stats() -> void:
	hud.visible = false
	print("ISLAND_STATS ", JSON.stringify(island.stats()))
	_apply_preset("hero")
	await _frames(8)
	render_stats("hero")
	_apply_preset("lean")
	await _frames(4)
	render_stats("lean")
	_apply_preset("town")
	await _frames(4)
	render_stats("town")
	get_tree().quit()


func _run_shots() -> void:
	hud.visible = false
	phys.manual = true
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	await _frames(12)
	print("ISLAND_STATS ", JSON.stringify(island.stats()))
	var views := [["a_hero", "hero", false], ["a2_hero_tiltshift", "hero", true], ["b_top", "top", false],
		["c_town_harbour", "town", false], ["d_base", "base", false], ["e_slab_side", "side", false], ["e2_lean_over", "lean", true]]
	for v in views:
		if only != "" and not (v[0] as String).substr(0, 1) in only:
			continue
		_apply_preset(v[1])
		tilt_rect.visible = v[2]
		await _capture(v[0])
		if v[0] == "a_hero":
			render_stats("hero")
	tilt_rect.visible = false
	if only == "" or "f" in only:
		await _physics_shots()
	get_tree().quit()


func _physics_shots() -> void:
	# target: the tallest downtown tower
	var best: Dictionary = {}
	for s in island.props.structures:
		if s.kind in ["tower", "house"] and (best.is_empty() or s.size.y > best.size.y):
			best = s
	var tp: Vector3 = best.pos if not best.is_empty() else Vector3(0.1, 0.09, 0.12)
	var tgt := Vector3(tp.x, island.height_at(tp.x, tp.z), tp.z)
	phys.fire(tgt)
	phys.advance(0.10)
	var m := phys.p0
	cam.set_view(Vector3(m.x + 0.01, m.y + 0.008, m.z), 35.0, 16.0, 0.06, 55.0)
	await _capture("f_launch")
	phys.advance(1.1)
	cam.set_view(Vector3((m.x + tgt.x) * 0.5, 0.2, (m.z + tgt.z) * 0.5 + 0.02), -8.0, 18.0, 1.0, 50.0)
	await _capture("g_midflight")
	while phys.flying:
		phys.advance(1.0 / 60.0)
	print("IMPACT ", phys.last_impact, " target ", tgt, " err ", Vector2(phys.last_impact.x - tgt.x, phys.last_impact.z - tgt.z).length())
	phys.advance(0.3)
	cam.set_view(tgt + Vector3(0, 0.012, 0), -20.0, 28.0, 0.2, 50.0)
	await _capture("h_impact")
	phys.advance(3.5)
	cam.set_view(tgt, -20.0, 48.0, 0.16, 50.0)
	await _capture("i_aftermath")
