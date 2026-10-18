class_name XRGame
extends Node3D
## Meta Quest 3 mixed-reality test mode: place the diorama on the real table, then walk
## around it and fire the ballistic test shell at points on the island.
##
## Placement (state "placing"): the model floats ahead of the user at hand height until
## the right controller's ray meets a surface. Surfaces, in order:
##   1. the headset's own scene planes / volumes facing up (Space Setup: tables, desks,
##      storage, couch, bed, floor) via SceneSurfaces,
##   2. a virtual horizontal plane at 0.75 m (a table) - right stick click switches it
##      to the floor (0 m) and back,
##   3. (MR) the floor when the ray passes beyond the virtual table's reach.
## The base sits on the hit point (Placement.pinned_transform), facing the user; right
## stick Y scales 0.4x-1.5x, X turns; a ghost ring marks the footprint. Trigger pins.
## Pinned: right trigger aims (ray on the island shows the trajectory preview) and fires,
## A toggles slow motion, B (or the left menu button) un-pins, left grip held + move
## turns the model, left stick click shows the FPS panel at the left hand.

const HINT_PLACE_AR := "وجّه اليد اليمنى للطاولة، العصا للحجم والدوران، الزناد للتثبيت"
const HINT_PLACE_EN := "Point at your table, stick to size/rotate, trigger to pin"
const HINT_PLAY_AR := "الزناد: أطلق قذيفة · A: حركة بطيئة · B: نقل الجزيرة"
const HINT_PLAY_EN := "Trigger: fire shell · A: slow motion · B: move island"

var room: Room
var diorama: Node3D
var island: Island
var phys: PhysicsTest

var rig: XRRig
var surfaces: SceneSurfaces
var state := "placing"          # placing | pinned
var mode := "mr"                # mr (passthrough) | vr (fake room)
var place_scale := 1.0
var user_yaw := 0.0             # stick turn added to "facing the user"
var cur_yaw := 0.0
var cur_p := Vector3.ZERO
var virtual_h := Placement.TABLE_H
var surface_label := ""
var aim_target: Variant = null
var _aim_sent := Vector3.INF
var _have_p := false
var _grab := {}                 # left-grip turn: {a0, yaw0}

var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var contact: MeshInstance3D
var hint: Label3D
var hint_status: Label3D
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
	phys.impacted.connect(_on_impact)


## Starts OpenXR. False (and nothing is changed) without a headset runtime.
func start() -> bool:
	if not rig.start():
		return false
	rig.camera.current = true
	surfaces.attach(rig)
	rig.button.connect(_on_button)
	rig.session_started.connect(func(): set_mode("mr"))
	rig.recentered.connect(unpin)
	set_mode("mr")   # until the session reports passthrough support (VR without it)
	state = "placing"
	_update_hint()
	return true


## "mr" hides the fake room (Room.set_mr) and shows a contact shadow on the real table;
## "vr" (no passthrough) shows the room. Returns the mode actually set.
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
	# a thin ring just outside the base + a faint inner ring at the slab edge
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
	var f := latin.duplicate() as FontFile
	if arabic:
		f.fallbacks = [arabic]
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
	# head-locked hint: small, below the line of sight
	hint = _label(40, 0.00028)
	hint.name = "Hint"
	hint.position = Vector3(0, -0.15, -0.6)
	hint.rotation.x = deg_to_rad(12.0)
	rig.camera.add_child(hint)
	hint_status = _label(28, 0.00028)
	hint_status.name = "HintStatus"
	hint_status.modulate = Color(1, 0.86, 0.55, 0.85)
	hint_status.position = Vector3(0, -0.188, -0.6)
	hint_status.rotation.x = deg_to_rad(12.0)
	rig.camera.add_child(hint_status)
	# FPS / frame time near the left hand (left stick click)
	fps_label = _label(30, 0.00025)
	fps_label.name = "FpsPanel"
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	fps_label.position = Vector3(0.0, 0.05, 0.02)
	fps_label.rotation.x = deg_to_rad(-55.0)
	fps_label.visible = false
	rig.hands["left"].grip.add_child(fps_label)


func _update_hint() -> void:
	if state == "placing":
		hint.text = HINT_PLACE_AR + "\n" + HINT_PLACE_EN
	else:
		hint.text = HINT_PLAY_AR + "\n" + HINT_PLAY_EN


# ------------------------------------------------------------------------------------
# input
# ------------------------------------------------------------------------------------

func _on_button(hand: String, name: String, pressed: bool) -> void:
	if hand == "right" and name == "trigger" and pressed:
		if state == "placing":
			pin()
		else:
			fire()
	elif pressed and ((hand == "right" and name == "by") or (hand == "left" and name == "menu")):
		if state == "pinned":
			unpin()
	elif hand == "right" and name == "ax" and pressed:
		phys.set_slow_motion(not phys.slow_motion)
		rig.pulse("right", 0.2, 0.03)
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


func _on_impact(_point: Vector3) -> void:
	rig.pulse("right", 0.5, 0.08)


func pin() -> void:
	if surface_label == "":
		rig.pulse("right", 0.1, 0.02)   # nothing under the model yet
		return
	state = "pinned"
	ghost.visible = false
	contact.visible = mode == "mr"
	rig.pulse("right", 0.6, 0.06)
	_update_hint()


func unpin() -> void:
	state = "placing"
	_grab = {}
	aim_target = null
	_aim_sent = Vector3.INF
	if not phys.flying:
		phys.hide_preview()
	_update_hint()


func fire() -> void:
	if aim_target == null or phys.flying:
		return
	phys.fire(aim_target)
	rig.pulse("right", 0.8, 0.07)


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
	if not rig.xr_active:
		return
	var dt := minf(delta, 0.05)
	if state == "placing":
		_step_placing(dt)
	else:
		_step_pinned(dt)
	if mode == "vr":
		# the fake room's table top stays under the base
		room.set_root.transform = Transform3D(Basis(Vector3.UP, cur_yaw), cur_p)
	_step_fps(delta)


## The surface the right ray points at: {p, n, label} or {}.
func aim_surface(origin: Vector3, dir: Vector3) -> Dictionary:
	var hit := surfaces.ray_surface(origin, dir)
	if mode == "vr" and not hit.is_empty() and hit.label == "floor":
		hit = {}   # VR: the fake room's table must stand on something above the floor
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


## One placing step: the model eases towards `hit` (or floats ahead of `head` when hit
## is {}), facing the user, with the stick's scale / turn applied.
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
	var where := {"table": "طاولة حقيقية · real table", "floor": "الأرض · floor", "virtual_table": "طاولة افتراضية 0.75 م · virtual table", "virtual_floor": "أرض افتراضية · virtual floor"}
	hint_status.text = "%s   ×%.2f" % [where.get(surface_label, surface_label if on else "-"), Placement.clamp_scale(place_scale)]


func _step_pinned(_dt: float) -> void:
	hint_status.text = "×%.2f%s" % [Placement.clamp_scale(place_scale), "   · slow-mo" if phys.slow_motion else ""]
	# left grip held: turn the model about its centre with the hand
	if not _grab.is_empty() and rig.tracked("left"):
		var a := _hand_angle()
		if not is_nan(a):
			cur_yaw = float(_grab.yaw0) + wrapf(a - float(_grab.a0), -PI, PI)
			diorama.transform = Placement.pinned_transform(cur_p, cur_yaw, place_scale)
	var world_hit: Variant = null
	if rig.tracked("right"):
		var r := rig.ray("right")
		world_hit = aim_at(r[0], r[1])
	else:
		aim_at(Vector3.ZERO, Vector3.ZERO)
	rig.set_pointer("right", world_hit, true)


## Pinned: a world ray on the island sets aim_target (island-local) and shows the
## trajectory preview to it. Returns the world hit point or null. A zero direction clears.
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
	if phys.flying:
		return world_hit
	if aim_target != null:
		if (aim_target as Vector3).distance_to(_aim_sent) > 0.0015:
			phys.aim(aim_target)
			_aim_sent = aim_target
	elif _aim_sent != Vector3.INF:
		phys.hide_preview()
		_aim_sent = Vector3.INF
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
		fps_label.text = "%.0f fps · %.1f ms (worst %.1f)\ncpu %.1f ms · phys %.1f ms\ndraw %d · %dk tris\ndebris %d/%d · %s" % [
			fps, 1000.0 * _fps_acc / _fps_frames, 1000.0 * _fps_worst,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			dc, prim / 1000, phys.debris.bodies.size(), mini(DebrisSystem.cap, DebrisSystem.MAX_BODIES), mode.to_upper()]
	_fps_acc = 0.0
	_fps_frames = 0
	_fps_worst = 0.0
