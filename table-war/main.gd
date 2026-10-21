extends Node3D
## Island war-table prototype: desktop viewer, and on Meta Quest 3 the mixed-reality
## test build (xr/xr_game.gd: place the diorama on the real table, fire test shells).
## Desktop keys: F fire at random target | click = fire at point | Space slow-motion |
##       T tilt-shift | 1-6 camera presets | H help | R reset debris
## Args (after --): --shots  render the screenshot set into res://shots/ and quit
##                  --stats  print triangle / draw-call numbers and quit
##                  --quest  desktop preview of the Quest 3 performance profile
##                  --mr-preview  render the MR / VR placement previews (shots/x_*) and quit
##                  --out=<dir>  write screenshots there instead of res://shots
##                  --shadows  sun shadows on (off by default everywhere)
##                  --xr     try OpenXR on desktop too (the Android build always does)

var room: Room
## The whole model (island + physics test). Identity on desktop; in XR it is moved,
## turned and scaled onto the real table. Everything inside works in its local space.
var diorama: Node3D
var island: Island
var phys: PhysicsTest
var cam: OrbitCamera
var xr_game: XRGame
var quest := false
## Build 19: the web version (free play: island, weapons, enemy forces; no campaign).
var web := false
var web_hud: WebHud
var tilt_layer: CanvasLayer
var tilt_rect: ColorRect
var hud: Label
var rng := RandomNumberGenerator.new()
var _island_xf := Transform3D(Basis(), Vector3(INF, INF, INF))

## Desktop "player eye", above / behind PhysicsTest.DESKTOP_HAND.
const DESKTOP_EYE := Vector3(-0.36, 0.62, 0.92)

const PRESETS := {
	"hero": [Vector3(0.0, 0.06, 0.04), -30.0, 40.0, 1.15, 50.0],
	"top": [Vector3(0.0, 0.05, 0.0), 0.0, 89.6, 1.62, 40.0],
	"town": [Vector3(0.085, 0.085, 0.14), -18.0, 34.0, 0.24, 50.0],
	"base": [Vector3(-0.25, 0.085, -0.04), 28.0, 36.0, 0.30, 50.0],
	"oldtown": [Vector3(0.07, 0.085, 0.085), -25.0, 40.0, 0.10, 50.0],
	"plant": [Vector3(0.272, 0.085, 0.162), -40.0, 34.0, 0.16, 50.0],
	"side": [Vector3(-0.22, 0.055, 0.42), -38.0, 13.0, 0.36, 45.0],
	"lean": [Vector3(0.02, 0.08, 0.02), -10.0, 58.0, 0.66, 60.0],
}


## Quest 3 profile (README "أداء Quest 3"): set before the island is built.
static func apply_quest_profile() -> void:
	# 2x2 tiles with visibility-range LOD (the merged per-instance vertex LOD submitted
	# every hi + lo triangle, ~215k, each frame: dropped on Quest after build 1)
	IslandProps.merged_veg = false
	IslandProps.tufts = false          # no grass tufts at all
	IslandProps.small_shadows = false  # shrubs / rocks cast no shadow
	IslandWater.opaque = true          # opaque sea variant
	DebrisSystem.cap = 80              # live GDScript debris; settled ones are baked
	PhysicsTest.ejecta_scale = 0.35    # fewer soil chunks per blast
	IslandTerrain.defer_meshes = true  # crater chunk meshes over the next frames
	DebrisSystem.max_awake = 28        # CPU budget: older awake ones freeze + bake
	DebrisSystem.max_age = 2.5
	IslandProps.max_chunks = 20        # fracture pieces per building
	FxSystem.cap = 260                 # smoke / dust / water puffs (the nuke cloud needs ~200)


## Quest: nothing casts a shadow (the sun has none either; Room.apply_quest).
static func no_shadows(n: Node) -> void:
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	rng.seed = 2024
	var args := OS.get_cmdline_user_args()
	var want_xr := OS.has_feature("android") or "--xr" in args
	quest = OS.has_feature("android") or "--quest" in args
	web = OS.has_feature("web") or "--web" in args
	if web:
		want_xr = false
	if quest or web:
		apply_quest_profile()
	Room.shadows = "--shadows" in args and not quest
	process_priority = 100   # shader globals after XRGame / the camera moved this frame
	room = Room.new()
	room.name = "Room"
	add_child(room)
	if quest:
		room.apply_quest()
	diorama = Node3D.new()
	diorama.name = "Diorama"
	add_child(diorama)
	island = Island.new()
	island.name = "Island"
	for a in args:
		if a.begins_with("--map="):
			island.map_id = int(a.trim_prefix("--map="))
	diorama.add_child(island)
	phys = PhysicsTest.new()
	phys.name = "PhysicsTest"
	diorama.add_child(phys)
	phys.setup(island)
	if quest:
		no_shadows(self)
	if want_xr:
		# build 14: the campaign in VR (the operations room); --mr keeps the old
		# mixed-reality placement test flow
		XRGame.campaign_vr = not ("--mr" in args)
		# test build: every built chapter open (the store build asks Store.owns)
		Progress.unlock_all = true
		xr_game = XRGame.new()
		xr_game.name = "XRGame"
		add_child(xr_game)
		xr_game.setup(room, diorama, island, phys)
		xr_game.map_changed.connect(func(isl: Island) -> void: island = isl)
		if xr_game.start():
			print("XR: OpenXR session starting (mixed-reality placement)")
			return
		print("XR: no OpenXR runtime, desktop viewer instead")
		xr_game.queue_free()
		xr_game = null
	cam = OrbitCamera.new()
	cam.name = "Camera"
	add_child(cam)
	cam.current = true
	cam.clicked.connect(_on_click)
	_apply_preset("hero")
	_build_overlay()
	if web:
		hud.visible = false
		cam.max_dist = 1.8
		web_hud = WebHud.new()
		web_hud.name = "WebHud"
		add_child(web_hud)
		web_hud.setup(phys)
		web_hud.map_requested.connect(_switch_map)
		if "--web-shot" in args:
			_run_web_shot.call_deferred()
		return
	if "--shots" in args:
		_run_shots.call_deferred()
	elif "--stats" in args:
		_run_stats.call_deferred()
	elif "--mr-preview" in args:
		_run_mr_preview.call_deferred()
	elif "--map-shot" in args:
		_run_map_shot.call_deferred()
	elif "--vr-preview" in args:
		_run_vr_preview.call_deferred()


## World -> diorama transform and head position for the shaders (island-local
## patterns, per-instance vegetation LOD of the Quest profile).
func _process(_delta: float) -> void:
	var xf := diorama.global_transform
	if xf != _island_xf:
		_island_xf = xf
		RenderingServer.global_shader_parameter_set("tw_island_inv", Projection(xf.affine_inverse()))
		RenderingServer.global_shader_parameter_set("tw_lod_scale", xf.basis.get_scale().x)
	var c := get_viewport().get_camera_3d()
	if c:
		RenderingServer.global_shader_parameter_set("tw_eye", c.global_position)


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
	hud.text = "LMB drag orbit · RMB pan · wheel zoom · click = fire there · F random fire · W weapon (%s) · Space slow-mo · T tilt-shift · 1-6 views · R reset · H hide" % phys.weapon
	tilt_layer.add_child(hud)


func _apply_preset(name: String) -> void:
	var p: Array = PRESETS[name]
	cam.set_view(p[0], p[1], p[2], p[3], p[4])


func _unhandled_key_input(event: InputEvent) -> void:
	if web:
		return   # the web HUD owns the keys (weapons 1-9, 0, -, =)
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
			phys.reset_island()
		KEY_W:
			phys.weapon = WeaponTable.next_id(phys.weapon)
			hud.text = hud.text.substr(0, hud.text.find("W weapon")) + "W weapon (%s)" % phys.weapon + hud.text.substr(hud.text.find(") ·") + 1)
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
	if web_hud:
		if hit != null or web_hud.weapon == "aa":
			web_hud.try_fire(hit if hit != null else Vector3.ZERO)
		return
	if hit != null:
		phys.fire(hit)


## Web preview: a few shots at the island, the enemy fighting back (shots/w_*.png).
func _run_web_shot() -> void:
	phys.manual = true
	_apply_preset("hero")
	var tgts := [Vector3(-0.22, 0, -0.09), Vector3(0.05, 0, -0.15), Vector3(0.33, 0, 0.03)]
	var ws := ["cruise", "mlrs", "ballistic"]
	for k in 3:
		var t: Vector3 = tgts[k]
		t.y = island.surface_at(t.x, t.z)
		web_hud.select(ws[k])
		web_hud.try_fire(t)
		for f in 40:
			phys.advance(1.0 / 60.0)
	for f in 60 * 14:
		phys.advance(1.0 / 60.0)
		web_hud._process(1.0 / 60.0)
	await _frames(4)
	await _capture("w_play")
	_apply_preset("base")
	await _frames(4)
	await _capture("w_base")
	get_tree().quit()


## Web: build the island of another map on the table (a few seconds).
func _switch_map(id: int) -> void:
	if island.map_id == id:
		return
	web_hud.flash("جاري تجهيز %s ..." % Campaign.map_name(id))
	await get_tree().process_frame
	await get_tree().process_frame
	var idx := island.get_index()
	diorama.remove_child(island)
	island.queue_free()
	island = Island.new()
	island.name = "Island"
	island.map_id = id
	diorama.add_child(island)
	diorama.move_child(island, idx)
	phys.set_island(island)
	room.set_map_light(id)
	no_shadows(island)
	web_hud.map_id = id
	web_hud.reset()


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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			dir = a.substr(6)
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
		["c_town_harbour", "town", false], ["c2_old_town", "oldtown", false], ["c3_power_plant", "plant", false], ["d_base", "base", false], ["e_slab_side", "side", false], ["e2_lean_over", "lean", true]]
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
	if "n" in only:
		await _nuke_shots()
	get_tree().quit()


## The nuclear test on the city centre (shots n_nuke_*), and the player's ship.
func _nuke_shots() -> void:
	phys.reset_island()
	var c := island.layout.town_center
	var tgt := Vector3(c.x, island.height_at(c.x, c.y), c.y)
	_apply_preset("hero")
	await _frames(4)
	await _capture("n_ship")
	phys.fire(tgt, Vector3.INF, "nuke")
	var g := 0
	while phys.flying and g < 4000:
		phys.advance(1.0 / 60.0)
		g += 1
	for t in [0.15, 1.5, 5.0]:
		var steps := int(t * 60.0)
		for k in steps:
			phys.advance(1.0 / 60.0)
		await _frames(2)
		await _capture("n_nuke_%0.1f" % t)
		phys.manual = true


func _physics_shots() -> void:
	# target: the tallest downtown tower; the shot leaves the player's hand
	var best: Dictionary = {}
	for s in island.props.structures:
		if s.kind in ["skyscraper", "midrise"] and (best.is_empty() or s.size.y > best.size.y):
			best = s
	var tp: Vector3 = best.pos if not best.is_empty() else Vector3(0.1, 0.09, 0.12)
	var tgt := Vector3(tp.x, island.height_at(tp.x, tp.z), tp.z)
	phys.weapon = "ballistic"
	phys.aim(tgt)
	phys.fire(tgt)
	phys.advance(0.12)
	var m := phys.p0
	cam.min_dist = 0.01
	# over the player's shoulder: the shot leaving the hand, the island ahead
	var eye := DESKTOP_EYE
	cam.fov = 60.0
	cam.global_transform = Transform3D(Basis.looking_at((Vector3(0.0, 0.1, 0.0) - eye).normalized(), Vector3.UP), eye)
	await _capture("f_launch")
	phys.advance(1.2)
	cam.set_view((m + tgt) * 0.5 + Vector3(0, 0.05, 0), -75.0, 14.0, 1.25, 50.0)
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
	# a shell into the sea: water column, spray, ripples, foam; no crater
	var sea := Vector3(0.05, IslandTerrain.SEA, 0.40)
	phys.weapon = "artillery"
	phys.fire(sea)
	while phys.flying:
		phys.advance(1.0 / 60.0)
	print("SEA_IMPACT ", phys.last_impact, " kind ", phys.last_impact_kind)
	phys.advance(0.28)
	cam.set_view(sea + Vector3(0, 0.012, 0), -30.0, 22.0, 0.17, 50.0)
	await _capture("j_sea_splash")
	phys.advance(0.9)
	cam.set_view(sea, -30.0, 40.0, 0.17, 50.0)
	await _capture("j2_sea_ripples")
	# each weapon from the player's eye: preview from the hand + the shot in flight
	var eye_target := Vector3(0.0, 0.05, 0.0)
	var targets := {"ballistic": Vector3(0.02, 0.0, 0.10), "cruise": Vector3(0.24, 0.0, -0.02), "artillery": Vector3(-0.18, 0.0, 0.16)}
	for id in WeaponTable.IDS:
		var t: Vector3 = targets[id]
		t.y = island.surface_at(t.x, t.z)
		phys.weapon = id
		phys.aim(t, Vector3.INF, id, true)
		phys.fire(t)
		phys.advance(phys.flight_T * (0.8 if id == "ballistic" else 0.55))
		cam.fov = 60.0
		cam.global_transform = Transform3D(Basis.looking_at((eye_target - DESKTOP_EYE).normalized(), Vector3.UP), DESKTOP_EYE)
		await _capture("k_weapon_" + id)
		while phys.flying:
			phys.advance(1.0 / 60.0)
		print("WEAPON ", id, " err ", Vector2(phys.last_impact.x - t.x, phys.last_impact.z - t.z).length(), " T ", phys.flight_T)
		phys.advance(1.5)
	phys.hide_preview()
	phys.weapon = "ballistic"


## Desktop check of the XR look: the model pinned at 0.6x on a 0.75 m virtual table,
## seen from standing eye height. MR: fake room hidden, transparent background (the PNG
## keeps the alpha), contact shadow. VR: the fake room's table under the base.
## Also the left-hand control panel close up (x_panel).
## Build 14 previews from the player's eye in the operations room: the campaign screen,
## the briefing, a stage in play and the debrief (shots/v_*.png).
func _run_vr_preview() -> void:
	hud.visible = false
	XRGame.campaign_vr = true
	var x := XRGame.new()
	x.name = "XRGamePreview"
	add_child(x)
	x.setup(room, diorama, island, phys)
	x.map_changed.connect(func(isl: Island) -> void: island = isl)
	x.progress = Progress.new()
	x.rig.sim = true
	x.set_mode("vr")
	var head := Transform3D(Basis(), Vector3(0.0, 1.62, 0.0))
	x.place_campaign(head)
	cam.min_dist = 0.01
	cam.fov = 80.0
	var eye := Vector3(0.0, 1.62, 0.05)
	var out := _out_dir()
	var shots := [
		["v_campaign", Vector3(0.0, 1.35, -2.0), "menu"],
		["v_room", Vector3(0.0, 1.0, -2.0), "wide"],
		["v_briefing", Vector3(0.0, 1.35, -2.0), "brief"],
		["v_briefing2", Vector3(0.0, 1.35, -2.0), "brief2"],
		["v_briefing3", Vector3(0.0, 1.35, -2.0), "brief3"],
		["v_play", Vector3(0.0, 0.8, -1.0), "play"],
		["v_debrief", Vector3(0.0, 1.35, -2.0), "debrief"],
		["v_forces", Vector3(0.0, 0.75, -1.0), "forces"],
		["v_forces2", Vector3(0.0, 0.75, -1.0), "forces2"],
		["v_nuke1", Vector3(0.0, 0.85, -1.0), "nuke:1.0"],
		["v_nuke2", Vector3(0.0, 0.85, -1.0), "nuke:3.0"],
		["v_nuke3", Vector3(0.0, 0.85, -1.0), "nuke:6.0"],
		["v_nuke4", Vector3(0.0, 0.85, -1.0), "nuke:11.0"],
	]
	var nuke_t := 0.0
	for sh in shots:
		match String(sh[2]):
			"brief":
				x.screen.press("st_c1s1")
				x.screen.press("start")
			"brief2":
				x.screen.press("brief_next")
			"brief3":
				x.screen.show_briefing("c1s5", 2)
			"play":
				x.start_stage("c1s1")
				phys.manual = true
				var tgt := Vector3(-0.056, 0.0, -0.160)
				tgt.y = island.surface_at(tgt.x, tgt.z)
				phys.aim(tgt, Vector3.INF, "cruise")
				phys.fire(tgt, Vector3.INF, "cruise")
				for k in 70:
					phys.advance(1.0 / 60.0)
				x._update_board(true)
			"forces":
				Progress.unlock_all = true
				await x.start_stage("c2s5")
				phys.manual = true
				for k in 60 * 16:
					phys.advance(1.0 / 60.0)
				x._update_board(true)
			"forces2":
				for k in 60 * 9:
					phys.advance(1.0 / 60.0)
			"debrief":
				for st in island.props.structures:
					if st.kind == "radar_sphere":
						st.alive = false
				phys.manual = false
				x._process(1.0 / 72.0)
		if String(sh[2]).begins_with("nuke:"):
			if nuke_t == 0.0:
				x.back_to_campaign()
				x.screen.visible = false
				phys.manual = true
				var np := Vector3(0.05, 0.0, 0.02)
				np.y = island.surface_at(np.x, np.z)
				phys._nuke(np, WeaponTable.get_weapon("nuke"))
			var want := float(String(sh[2]).substr(5))
			while nuke_t < want:
				phys.advance(1.0 / 60.0)
				nuke_t += 1.0 / 60.0
		var c := Camera3D.new()
		c.fov = 82.0
		c.near = 0.01
		c.far = 2000.0
		add_child(c)
		c.look_at_from_position(eye if String(sh[2]) != "wide" else Vector3(1.6, 1.7, 1.2), sh[1])
		c.current = true
		for k in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out.path_join(String(sh[0]) + ".png"))
		print("vr-preview: ", sh[0])
		c.queue_free()
	get_tree().quit()


## Top and hero views of the current map (shots/m<id>_top.png, m<id>_hero.png).
func _run_map_shot() -> void:
	hud.visible = false
	for v in [["top", "top"], ["hero", "hero"]]:
		_apply_preset(v[0])
		await _frames(6)
		await _capture("m%d_%s" % [island.map_id, v[1]])
	get_tree().quit()


func _out_dir() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			return a.trim_prefix("--out=")
	return ProjectSettings.globalize_path("res://shots")


func _run_mr_preview() -> void:
	hud.visible = false
	phys.manual = true
	var spot := Vector3(0.0, Placement.TABLE_H, -0.1)
	diorama.transform = Placement.pinned_transform(spot, 0.4, 0.6)
	var x := XRGame.new()
	x.name = "XRGamePreview"
	add_child(x)
	x.setup(room, diorama, island, phys)
	x.cur_p = spot
	x.cur_yaw = 0.4
	x.state = "pinned"
	cam.min_dist = 0.01
	cam.set_view(spot + Vector3(0, 0.05, 0), -20.0, 48.0, 0.95, 60.0)
	var tgt := Vector3(0.1, 0.0, 0.12)
	tgt.y = island.surface_at(tgt.x, tgt.z)
	var hand_w := spot + Vector3(-0.25, 0.42, 0.62)
	var hand_l := diorama.global_transform.affine_inverse() * hand_w
	for m in ["mr", "vr"]:
		x.set_mode(m)
		room.set_root.transform = Transform3D(Basis(Vector3.UP, x.cur_yaw), spot)
		phys.aim(tgt, hand_l, "ballistic", true)
		await _capture("x_%s_preview" % m)
	# mission board above the island
	x.set_mode("mr")
	x.select_mission("blackout")
	x.missions.start(island.props)
	var kp := 0
	for st in island.props.structures:
		if IslandProps.TARGETS.has(st.kind) and IslandProps.TARGETS[st.kind][0] == "power" and kp < 3:
			st.alive = false
			kp += 1
	x.missions.step(23.0, island.props)
	cam.set_view(spot + Vector3(0, 0.12, -0.05), 0.0, 22.0, 0.95, 70.0)
	await _frames(1)
	x.rig.camera.global_transform = cam.global_transform   # the screen turns to this eye
	x._update_board(true)
	await _capture("x_board")
	# the tablet in the left hand, from the eye (the screen in the view off for this one)
	x.board_shown = false
	x._update_board(true)
	var eye := spot + Vector3(-0.05, 0.62, 0.70)
	var ppos := eye + Vector3(-0.12, -0.2, -0.22)
	x.panel.visible = true
	x.panel.global_transform = Transform3D(Basis.looking_at((eye - ppos).normalized(), Vector3.UP, true), ppos)
	x.select_weapon("cruise")
	x.locked = tgt
	x.ammo["ballistic"] = 4
	x.cooldown["cruise"] = 1.2
	x.panel.update_state(x.ammo, {"ballistic": 0.0, "cruise": 0.4, "artillery": 0.0}, "LOCKED  RNG 0.86 m  ·  T+2.4 s   ·   مقفل", false)
	# some damage for the destruction meter
	var k := 0
	for st in island.props.structures:
		if st.alive and IslandProps.TARGETS.has(st.kind) and k % 4 == 0:
			st.alive = false
		k += 1
	x.panel.update_destruction(island.props.destruction())
	x.panel.hit(eye, (x.panel.button_center("reset") - eye).normalized())
	cam.global_transform = Transform3D(Basis.looking_at((ppos - eye).normalized(), Vector3.UP), eye)
	cam.fov = 40.0
	await _capture("x_panel")
	get_tree().quit()
