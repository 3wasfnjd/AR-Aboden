class_name XRGame
extends Node3D
## Meta Quest 3 mixed-reality mode: place the diorama on the real table, walk around
## it, and fire weapons FROM YOUR OWN POSITION: the launch platform is the player's
## right hand (weapons/weapon_table.gd, weapons/flight.gd, fx/physics_test.gd).
##
## Placement ("placing"): the model floats ahead at hand height until the right ray
## meets a surface: (1) the headset's scene planes / volumes facing up (Space Setup:
## table, desk, storage, couch, bed, floor), (2) a virtual plane at 0.75 m (right stick
## click: floor), (3) in MR the floor beyond its reach. The base sits on the hit point,
## facing the user; right stick Y scales 0.4x-1.5x, X turns; a ghost ring shows the
## footprint. Trigger pins.
##
## Pinned: the diorama's transform is written ONLY by the rotation inputs (left stick X,
## left grip drag, the panel's rotate buttons), which change its yaw about its own
## centre and nothing else (Placement.pinned_transform keeps the base on the table).
## Nothing else reads the head or the controllers into it; a recenter keeps it.
##   right ray on the island    target marker + trajectory preview from the hand
##   right grip                 lock / unlock the target (marker turns red)
##   right trigger              fire the selected weapon (locked target, else the
##                              pointed spot); on the panel: press the button
##   left stick X / Y           rotate / zoom the island (0.4x-1.5x, base fixed)
##   right stick Y (flick)      next / previous weapon
##   A slow motion · B re-place · left stick click FPS panel · left menu = B

const ROT_RATE := 1.2            # rad/s at full left stick
const ROT_TICK := PI / 12.0      # haptic tick every 15 degrees
const ZOOM_RATE := 0.75          # left stick Y: e-folds per second (Mafateeh's resize speed)
const ROT_STEP := PI / 12.0      # panel rotate buttons
## Launch point relative to the right controller's aim pose: just above / ahead of it.
const LAUNCH_OFFSET := Vector3(0.0, 0.035, -0.06)

var room: Room
var diorama: Node3D
var island: Island
var phys: PhysicsTest

var rig: XRRig
var surfaces: SceneSurfaces
var panel: ControlPanel
var state := "placing"          # placing | pinned
var mode := "mr"                # mr (passthrough) | vr (fake room)
var place_scale := 1.0
var user_yaw := 0.0
var cur_yaw := 0.0
var cur_p := Vector3.ZERO
var virtual_h := Placement.TABLE_H
var surface_label := ""
var aim_target: Variant = null   # island-local point under the right ray
var locked: Variant = null       # island-local locked target
var weapon := "ballistic"
var ammo := {}
var cooldown := {}
var _reload := {}
var _aim_key := Vector4(INF, INF, INF, INF)
var _aim_frame := 0
var _have_p := false
var _grab := {}
var _rot_acc := 0.0
var _flick_armed := true
var _panel_hit := {}
var _destruction_dirty := true
var missions := Missions.new()
var board: MissionBoard
var _board_acc := 0.0

var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var contact: MeshInstance3D
var fps_label: Label3D
var _fps_acc := 0.0
var _fps_frames := 0
var _fps_worst := 0.0


func setup(r: Room, d: Node3D, isl: Island, p: PhysicsTest) -> void:
	room = r
	diorama = d
	island = isl
	phys = p
	rig = XRRig.new()
	rig.name = "XROrigin3D"
	add_child(rig)
	rig.setup()
	surfaces = SceneSurfaces.new()
	surfaces.name = "SceneSurfaces"
	add_child(surfaces)
	_build_ghost()
	_build_contact_shadow()
	_build_labels()
	panel = ControlPanel.new()
	panel.name = "ControlPanel"
	panel.visible = false
	add_child(panel)
	panel.pressed.connect(_on_panel)
	missions.load_best()
	board = MissionBoard.new()
	board.name = "MissionBoard"
	board.visible = false
	diorama.add_child(board)
	for id in WeaponTable.IDS:
		var w := WeaponTable.get_weapon(id)
		ammo[id] = int(w.ammo)
		cooldown[id] = 0.0
		_reload[id] = 0.0
	phys.weapon = weapon
	phys.impacted.connect(_on_impact)


## Starts OpenXR. False (and nothing is changed) without a headset runtime.
func start() -> bool:
	if not rig.start():
		return false
	rig.camera.current = true
	surfaces.attach(rig)
	rig.button.connect(_on_button)
	rig.session_started.connect(func(): set_mode("mr"))
	rig.recentered.connect(_on_recentered)
	set_mode("mr")
	state = "placing"
	return true


## A recenter (long press on the Meta button) moves the tracking origin: the island
## keeps its world transform and stays pinned (B re-places it if it no longer matches).
func _on_recentered() -> void:
	print("XR: recentered, island kept at its world transform")


func set_mode(m: String) -> String:
	m = rig.set_mode(m)
	mode = m
	room.set_mr(m == "mr")
	contact.visible = m == "mr" and (state == "pinned" or surface_label != "")
	return m


# ------------------------------------------------------------------------------------
# visuals
# ------------------------------------------------------------------------------------

func _build_ghost() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 96
	for ring in [[Placement.OUTER_R + 0.006, Placement.OUTER_R + 0.012], [0.497, 0.5]]:
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var r0: float = ring[0]
			var r1: float = ring[1]
			var q := [Vector3(cos(a0) * r0, 0, sin(a0) * r0), Vector3(cos(a0) * r1, 0, sin(a0) * r1),
				Vector3(cos(a1) * r0, 0, sin(a1) * r0), Vector3(cos(a1) * r1, 0, sin(a1) * r1)]
			for v in [q[0], q[2], q[1], q[1], q[2], q[3]]:
				st.add_vertex(v)
	ghost = MeshInstance3D.new()
	ghost.name = "PlaceGhost"
	ghost.mesh = st.commit()
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost_mat.albedo_color = Color(1, 1, 1, 0.45)
	ghost.material_override = ghost_mat
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	add_child(ghost)


## Soft dark disc under the base: darkens the passthrough table (alpha blend) like a
## real object's contact shadow. Child of the diorama, so it scales with it.
func _build_contact_shadow() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float r_in = 0.53;
uniform float r_out = 0.60;
uniform float strength = 0.55;
void fragment() {
	float r = length(UV * 2.0 - 1.0) * r_out;
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(r_in * 0.92, r_out, r));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = -1
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	q.orientation = PlaneMesh.FACE_Y
	contact = MeshInstance3D.new()
	contact.name = "ContactShadow"
	contact.mesh = q
	contact.material_override = m
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact.position = Vector3(0, 0.0004, 0)
	contact.visible = false
	diorama.add_child(contact)


static func ui_font() -> Font:
	var latin: FontFile = load("res://assets/fonts/cairo-latin-500-normal.woff2")
	var arabic: FontFile = load("res://assets/fonts/cairo-arabic-500-normal.woff2")
	if latin == null:
		return null
	# multichannel SDF glyphs: text stays sharp at any size / distance (bitmap glyphs
	# at these tiny pixel sizes were blurry in the headset)
	var f := latin.duplicate() as FontFile
	f.multichannel_signed_distance_field = true
	f.msdf_pixel_range = 8
	f.msdf_size = 48
	if arabic:
		var a := arabic.duplicate() as FontFile
		a.multichannel_signed_distance_field = true
		a.msdf_pixel_range = 8
		a.msdf_size = 48
		f.fallbacks = [a]
	return f


func _label(size: int, px: float) -> Label3D:
	var l := Label3D.new()
	l.font = ui_font()
	l.font_size = size
	l.pixel_size = px
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.75)
	l.modulate = Color(1, 0.97, 0.9, 0.95)
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


func _build_labels() -> void:
	# build 3: no explanatory text in the view (the ghost ring and the panel say enough)
	fps_label = _label(30, 0.00025)
	fps_label.name = "FpsPanel"
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	fps_label.position = Vector3(0.0, -0.02, 0.06)   # under the tablet
	fps_label.rotation.x = deg_to_rad(-55.0)
	fps_label.visible = false
	rig.hands["left"].grip.add_child(fps_label)


func _set_text(l: Label3D, t: String) -> void:
	if l.text != t:
		l.text = t


# ------------------------------------------------------------------------------------
# input
# ------------------------------------------------------------------------------------

func _on_button(hand: String, name: String, pressed: bool) -> void:
	if hand == "right" and name == "trigger" and pressed:
		if state == "placing":
			pin()
		elif not _panel_hit.is_empty():
			if String(_panel_hit.id) != "":
				panel.press(_panel_hit.id)
				rig.pulse("right", 0.25, 0.02)
		else:
			fire()
	elif hand == "right" and name == "grip" and pressed and state == "pinned":
		toggle_lock()
	elif pressed and ((hand == "right" and name == "by") or (hand == "left" and name == "menu")):
		if state == "pinned":
			unpin()
	elif hand == "right" and name == "ax" and pressed:
		toggle_slow()
	elif hand == "left" and name == "stick" and pressed:
		fps_label.visible = not fps_label.visible
	elif hand == "right" and name == "stick" and pressed and state == "placing":
		virtual_h = 0.0 if virtual_h > 0.1 else Placement.TABLE_H
	elif hand == "left" and name == "grip":
		if pressed and state == "pinned":
			var a := _hand_angle()
			_grab = {} if is_nan(a) else {"a0": a, "yaw0": cur_yaw}
		else:
			_grab = {}


func _on_panel(id: String) -> void:
	match id:
		"slow":
			toggle_slow()
		"reset":
			reset_island()
			if missions.active != "":
				missions.start(island.props)
				rig.pulse("left", 0.5, 0.05)
		"m_prev", "m_next":
			select_mission(Missions.cycle(missions.active, -1 if id == "m_prev" else 1))
		"rot_l":
			rotate_island(ROT_STEP)
		"rot_r":
			rotate_island(-ROT_STEP)
		_:
			if id.begins_with("w_"):
				select_weapon(id.substr(2))


## Pick a mission ("" = free play): the board shows it, RESET turns into START.
func select_mission(id: String) -> void:
	missions.select(id)
	if id == "":
		panel.set_button_text("reset", "إعادة", "RESET")
	else:
		panel.set_button_text("reset", "ابدأ", "START")
	_update_board(true)
	rig.pulse("left", 0.2, 0.02)


## The board stands behind the island's far side and turns (yaw only) to the player.
func _update_board(force := false) -> void:
	if board == null:
		return
	board.show_state(missions, island.props)
	if not board.visible:
		return
	var head := rig.head_transform().origin
	var inv := diorama.global_transform.affine_inverse()
	var hl := inv * head
	var dir := Vector2(hl.x, hl.z)
	if dir.length_squared() < 1e-6:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	# opposite side of the island from the player, raised above the mountain
	board.position = Vector3(-dir.x * 0.6, 0.3, -dir.y * 0.6)   # outside the glass dome
	board.rotation = Vector3(0, atan2(dir.x, dir.y), 0)
	if force:
		_board_acc = 0.0


func select_weapon(id: String) -> void:
	weapon = id
	phys.weapon = id
	panel.set_selected(id)
	_aim_key = Vector4(INF, INF, INF, INF)
	rig.pulse("left", 0.2, 0.02)


func toggle_slow() -> void:
	phys.set_slow_motion(not phys.slow_motion)
	rig.pulse("right", 0.2, 0.03)


func toggle_lock() -> void:
	if aim_target != null:
		locked = aim_target
		phys.show_marker(locked, true, weapon)
		rig.pulse("right", 0.45, 0.04)
	else:
		locked = null
	_aim_key = Vector4(INF, INF, INF, INF)


func reset_island() -> void:
	phys.reset_island()
	locked = null
	aim_target = null
	for id in WeaponTable.IDS:
		ammo[id] = int(WeaponTable.get_weapon(id).ammo)
		cooldown[id] = 0.0
	_aim_key = Vector4(INF, INF, INF, INF)
	_destruction_dirty = true


## Zoom the pinned island by `k` (0.4x-1.5x): its foot stays where it stands.
func scale_island(k: float) -> void:
	place_scale = Placement.clamp_scale(place_scale * k)
	diorama.transform = Placement.pinned_transform(cur_p, cur_yaw, place_scale)


## Turn the pinned island about its own vertical axis: only the yaw changes, the base
## stays exactly where it stands on the table.
func rotate_island(d_yaw: float) -> void:
	cur_yaw = wrapf(cur_yaw + d_yaw, -PI, PI)
	diorama.transform = Placement.pinned_transform(cur_p, cur_yaw, place_scale)
	_rot_acc += absf(d_yaw)
	while _rot_acc >= ROT_TICK:
		_rot_acc -= ROT_TICK
		rig.pulse("left", 0.15, 0.015)


func pin() -> void:
	if surface_label == "":
		rig.pulse("right", 0.1, 0.02)
		return
	state = "pinned"
	# exactly the transform the user saw: no easing continues after this
	cur_p = diorama.transform.origin
	diorama.transform = Placement.pinned_transform(cur_p, cur_yaw, place_scale)
	ghost.visible = false
	contact.visible = mode == "mr"
	panel.visible = true
	_destruction_dirty = true
	rig.pulse("right", 0.6, 0.06)


func unpin() -> void:
	state = "placing"
	_grab = {}
	aim_target = null
	locked = null
	panel.visible = false
	phys.hide_preview()


## World launch point: just above / ahead of the right controller.
## Shots leave the selected weapon's launcher on the player's warship (the hand aims).
func launch_point_world() -> Vector3:
	return diorama.global_transform * launch_point_local()


func launch_point_local() -> Vector3:
	return phys.default_origin(weapon)


func fire() -> bool:
	var tgt: Variant = locked if locked != null else aim_target
	if tgt == null:
		return false
	if float(cooldown[weapon]) > 0.0 or int(ammo[weapon]) <= 0:
		rig.pulse("right", 0.08, 0.02)
		return false
	var w := WeaponTable.get_weapon(weapon)
	phys.fire(tgt, launch_point_local(), weapon)
	missions.on_shot()
	ammo[weapon] = int(ammo[weapon]) - 1
	cooldown[weapon] = float(w.cooldown)
	rig.pulse("right", 0.8, 0.07)
	return true


func _on_impact(_point: Vector3, _kind: String) -> void:
	rig.pulse("right", 0.5 if _kind == "land" else 0.25, 0.08)
	_aim_key = Vector4(INF, INF, INF, INF)   # preview + (locked) marker again
	_destruction_dirty = true


func _hand_angle() -> float:
	var g := rig.grip_transform("left").origin
	var dx := g.x - cur_p.x
	var dz := g.z - cur_p.z
	if dx * dx + dz * dz < 0.0025:
		return NAN
	return atan2(dx, dz)


# ------------------------------------------------------------------------------------
# per frame
# ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not rig.xr_active and not rig.sim:
		return
	var dt := minf(delta, 0.05)
	if state == "placing":
		_step_placing(dt)
	else:
		_step_pinned(dt)
	if mode == "vr":
		room.set_root.transform = Transform3D(Basis(Vector3.UP, cur_yaw), cur_p)
	_step_fps(delta)


func aim_surface(origin: Vector3, dir: Vector3) -> Dictionary:
	var hit := surfaces.ray_surface(origin, dir)
	if mode == "vr" and not hit.is_empty() and hit.label == "floor":
		hit = {}
	if hit.is_empty():
		hit = Placement.virtual_hit(origin, dir, virtual_h if mode == "mr" else Placement.TABLE_H)
	if hit.is_empty() and mode == "mr" and virtual_h > 0.0:
		hit = Placement.virtual_hit(origin, dir, 0.0)
	return hit


func _step_placing(dt: float) -> void:
	var hit := {}
	if rig.tracked("right"):
		var r := rig.ray("right")
		hit = aim_surface(r[0], r[1])
	place_toward(hit, rig.head_transform(), rig.stick("right"), dt)
	rig.set_pointer("right", hit.p if not hit.is_empty() else null, true)


func place_toward(hit: Dictionary, head: Transform3D, stick: Vector2, dt: float) -> void:
	var st := Placement.apply_stick(place_scale, user_yaw, stick, dt)
	place_scale = st[0]
	user_yaw = st[1]
	var target: Vector3 = hit.p if not hit.is_empty() else Placement.float_point(head)
	surface_label = "" if hit.is_empty() else String(hit.label)
	if not _have_p:
		cur_p = target
		_have_p = true
	cur_p = cur_p.lerp(target, 1.0 - exp(-dt * 20.0))
	cur_yaw = Placement.facing_yaw(cur_p, head.origin, cur_yaw - user_yaw) + user_yaw
	diorama.transform = Placement.pinned_transform(cur_p, cur_yaw, place_scale)
	var on := surface_label != ""
	ghost.visible = on
	if on:
		var k := Placement.clamp_scale(place_scale)
		ghost.transform = Transform3D(Basis(Vector3.UP, cur_yaw).scaled(Vector3(k, k, k)), cur_p + Vector3.UP * 0.0015)
		ghost_mat.albedo_color = Color(1, 1, 1, 0.5) if not surface_label.begins_with("virtual") else Color(1.0, 0.75, 0.4, 0.5)
	contact.visible = on and mode == "mr"


func _step_pinned(dt: float) -> void:
	# cooldowns and the slow reload of ammo
	for id in WeaponTable.IDS:
		var w := WeaponTable.get_weapon(id)
		cooldown[id] = maxf(float(cooldown[id]) - dt, 0.0)
		if int(ammo[id]) < int(w.ammo):
			_reload[id] = float(_reload[id]) + dt
			if float(_reload[id]) >= float(w.reload):
				_reload[id] = 0.0
				ammo[id] = int(ammo[id]) + 1
	# rotation inputs: the ONLY writers of the pinned transform
	var ls := rig.stick("left")
	if absf(ls.x) > Placement.DEADZONE:
		rotate_island(-ls.x * ROT_RATE * dt)
	# left stick Y: zoom the whole scene (as in Mafateeh), the base stays on the table
	if absf(ls.y) > Placement.DEADZONE:
		scale_island(exp(ls.y * ZOOM_RATE * dt))
	# right stick Y flick: next / previous weapon
	var rs := rig.stick("right")
	if absf(rs.y) > 0.7 and _flick_armed:
		_flick_armed = false
		select_weapon(WeaponTable.next_id(weapon, 1 if rs.y > 0.0 else -1))
	elif absf(rs.y) < 0.3:
		_flick_armed = true
	if not _grab.is_empty() and rig.tracked("left"):
		var a := _hand_angle()
		if not is_nan(a):
			var yaw := float(_grab.yaw0) + wrapf(a - float(_grab.a0), -PI, PI)
			rotate_island(wrapf(yaw - cur_yaw, -PI, PI))
	_place_panel(dt)
	if missions.step(dt, island.props):
		rig.pulse("right", 0.9 if missions.result == "won" else 0.4, 0.25)
		rig.pulse("left", 0.9 if missions.result == "won" else 0.4, 0.25)
		_destruction_dirty = true
	_board_acc += dt
	if _board_acc > 0.1:
		_board_acc = 0.0
		_update_board()
	# right ray: the panel first, else the island
	var world_hit: Variant = null
	_panel_hit = {}
	if rig.tracked("right"):
		var r := rig.ray("right")
		if panel.visible:
			_panel_hit = panel.hit(r[0], r[1])
		if _panel_hit.is_empty():
			world_hit = aim_at(r[0], r[1])
		else:
			world_hit = _panel_hit.point
	else:
		aim_at(Vector3.ZERO, Vector3.ZERO)
	rig.set_pointer("right", world_hit, true)
	_update_panel()


## The tablet in the left hand, turned toward the eyes.
func _place_panel(_dt: float) -> void:
	if not panel.visible:
		return
	var g := rig.grip_transform("left")
	var pos := g.origin + g.basis * Vector3(0.0, 0.06, -0.03)
	var eye := rig.head_transform().origin
	var to_eye := eye - pos
	if to_eye.length_squared() < 1e-6:
		return
	panel.global_transform = Transform3D(Basis.looking_at(to_eye.normalized(), Vector3.UP, true), pos)


func _update_panel() -> void:
	var cool := {}
	for id in WeaponTable.IDS:
		cool[id] = float(cooldown[id]) / maxf(float(WeaponTable.get_weapon(id).cooldown), 0.01)
	var tgt: Variant = locked if locked != null else aim_target
	var txt := "TGT  ---   ·   الهدف: لا يوجد"
	if tgt != null:
		var dist_m := (diorama.global_transform * (tgt as Vector3)).distance_to(launch_point_world())
		var T: float = phys.last_aim_T if phys.last_aim_T > 0.0 else 0.0
		txt = "%s  RNG %.2f m  ·  T+%.1f s   ·   %s" % ["LOCKED" if locked != null else "TGT", dist_m, T, "مقفل" if locked != null else "الهدف"]
	panel.update_state(ammo, cool, txt, phys.slow_motion)
	if _destruction_dirty:
		_destruction_dirty = false
		panel.update_destruction(island.props.destruction())


## Pinned: a world ray on the island sets aim_target (island-local). The preview runs
## from the launch point (the hand) to the locked target, else to the pointed spot.
## Returns the world hit point or null. A zero direction clears the pointer target.
func aim_at(origin: Vector3, dir: Vector3) -> Variant:
	var world_hit: Variant = null
	aim_target = null
	if dir.length_squared() > 1e-8:
		var lr := Placement.local_ray(diorama.global_transform, origin, dir)
		if not lr.is_empty():
			var o: Vector3 = lr[0]
			var d: Vector3 = lr[1]
			var hit: Variant = island.terrain.raycast(o + d * float(lr[2]), d, float(lr[3]) - float(lr[2]) + 0.004)
			if hit != null:
				aim_target = hit
				world_hit = diorama.global_transform * (hit as Vector3)
	var tgt: Variant = locked if locked != null else aim_target
	if tgt == null:
		if _aim_key.x != INF:
			phys.hide_preview()
			_aim_key = Vector4(INF, INF, INF, INF)
		return world_hit
	# re-plan only when the hand or the target moved: ballistic at most ~18 Hz, cruise
	# paths (terrain-following, the costly ones) ~7 Hz; a big jump at most every 2nd frame
	_aim_frame += 1
	var lp := launch_point_local()
	var key := Vector4((tgt as Vector3).x, (tgt as Vector3).z, lp.x + lp.y * 3.1, lp.z)
	var dk := key.distance_to(_aim_key) if _aim_key.x != INF else INF
	var every := 10 if weapon == "cruise" else 4
	if (dk > 0.02 and _aim_frame % 2 == 0) or (dk > 0.003 and _aim_frame % every == 0) or _aim_key.x == INF:
		phys.aim(tgt, lp, weapon, locked != null)
		_aim_key = key
	return world_hit


func _step_fps(delta: float) -> void:
	_fps_acc += delta
	_fps_frames += 1
	_fps_worst = maxf(_fps_worst, delta)
	if _fps_acc < 0.25:
		return
	if fps_label.visible:
		var fps := _fps_frames / _fps_acc
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		_set_text(fps_label, "%.0f fps · %.1f ms (worst %.1f)\ncpu %.1f ms · phys %.1f ms\ndraw %d · %dk tris\ndebris %d+%d · puffs %d · %s" % [
			fps, 1000.0 * _fps_acc / _fps_frames, 1000.0 * _fps_worst,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			dc, prim / 1000, phys.debris.bodies.size(), phys.debris.settled_count(), phys.fx.puffs.size(), mode.to_upper()])
	_fps_acc = 0.0
	_fps_frames = 0
	_fps_worst = 0.0
