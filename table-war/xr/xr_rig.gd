class_name XRRig
extends XROrigin3D
## OpenXR session, passthrough and controller input for the war-table test build.
## Adapted from the Dahrooj Quest rig (scripts/xr/xr_rig.gd): it exposes plain values
## and signals and knows nothing about the island.
##
## Roomscale: project.godot uses the local-floor reference space, so this origin is the
## floor under the player's head at launch. The player walks around the real table; the
## origin never moves (no locomotion, no snap or smooth turn).
##
## Buttons reported by the `button` signal (Godot default OpenXR action map):
##   trigger (trigger_click / trigger > 0.75), grip (grip_click / grip > 0.75),
##   ax (A / X), by (B / Y), menu (left menu button), stick (thumbstick click).

signal button(hand: String, name: String, pressed: bool)
signal session_started
signal focus_changed(focused: bool)
signal recentered

var xr_interface: OpenXRInterface
var xr_active := false
var focused := true
var passthrough_supported := false
var mode := "mr"

## Tests without a headset: controllers count as tracked, sticks read sim_stick.
var sim := false
var sim_stick := {"left": Vector2.ZERO, "right": Vector2.ZERO}
var pulses := 0

var camera: XRCamera3D
var hands := {}  # "left"/"right" -> {aim: XRController3D, grip: XRController3D, ray: MeshInstance3D, dot: MeshInstance3D}
var _prev := {}


func setup() -> void:
	camera = XRCamera3D.new()
	camera.name = "XRCamera3D"
	camera.near = 0.01   # lean in close over the miniature
	camera.far = 60.0
	add_child(camera)
	for hand in ["left", "right"]:
		var aim := XRController3D.new()
		aim.name = hand.capitalize() + "Aim"
		aim.tracker = hand + "_hand"
		aim.pose = "aim"
		add_child(aim)
		var grip := XRController3D.new()
		grip.name = hand.capitalize() + "Grip"
		grip.tracker = hand + "_hand"
		grip.pose = "grip"
		add_child(grip)
		if ClassDB.class_exists("OpenXRFbRenderModel"):
			var model: Node3D = ClassDB.instantiate("OpenXRFbRenderModel")
			if hand == "right":
				model.set("render_model_type", 1)
			grip.add_child(model)
		else:
			grip.add_child(_fallback_controller())
		var ray := MeshInstance3D.new()
		ray.name = "Ray"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.0008
		cyl.bottom_radius = 0.0018
		cyl.height = 1.0
		cyl.radial_segments = 6
		cyl.rings = 1
		ray.mesh = cyl
		ray.material_override = _unshaded(Color(1.0, 0.92, 0.7, 0.45), true)
		ray.rotation.x = -PI / 2
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ray.visible = false
		aim.add_child(ray)
		var dot := MeshInstance3D.new()
		dot.name = "Dot"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.003
		torus.outer_radius = 0.0045
		torus.rings = 16
		torus.ring_segments = 6
		dot.mesh = torus
		dot.material_override = _unshaded(Color(1.0, 0.86, 0.45, 0.95), false)
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.top_level = true
		dot.visible = false
		add_child(dot)
		hands[hand] = {"aim": aim, "grip": grip, "ray": ray, "dot": dot}
		_prev[hand] = {}


func _fallback_controller() -> Node3D:
	var m := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = 0.02
	c.height = 0.11
	m.mesh = c
	m.rotation.x = PI / 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.22)
	m.material_override = mat
	return m


static func _unshaded(c: Color, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Starts OpenXR; false on desktop / headless (no runtime), where nothing changes.
## Eye-buffer resolution x the panel default (1.0). Build 13: the highest quality
## setting (2.25x the pixels, with 4x MSAA) for the headset test; lower it if the
## FPS panel (left stick click) shows frames dropping below 72.
const SUPERSAMPLE := 1.5


func start() -> bool:
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null:
		return false
	# render above the panel's native resolution (supersampling: smoother edges and
	# text); must be set before the session starts. Light foveation only.
	xr_interface.render_target_size_multiplier = SUPERSAMPLE
	if not xr_interface.is_initialized() and not xr_interface.initialize():
		return false
	xr_active = true
	var vp := get_viewport()
	vp.use_xr = true
	# Tile GPU: 4x MSAA is cheap and keeps the millimetre-scale model crisp.
	vp.msaa_3d = Viewport.MSAA_4X
	xr_interface.foveation_level = 1
	xr_interface.foveation_dynamic = true
	# Quest refresh rate: keep the runtime default (72 Hz).
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	xr_interface.session_begun.connect(_on_session_begun)
	xr_interface.session_visible.connect(func(): _set_focus(false))
	xr_interface.session_focussed.connect(func(): _set_focus(true))
	xr_interface.session_stopping.connect(func(): _set_focus(false))
	xr_interface.pose_recentered.connect(func(): recentered.emit())
	return true


func _on_session_begun() -> void:
	passthrough_supported = xr_interface.get_supported_environment_blend_modes().has(
		XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
	session_started.emit()


func _set_focus(f: bool) -> void:
	if focused == f:
		return
	focused = f
	focus_changed.emit(f)


## "mr": passthrough (alpha blend); "vr": opaque. Falls back to VR when the headset
## does not offer alpha-blend passthrough. Returns the mode actually set. The scene
## side (transparent background, hiding the fake room) is Room.set_mr().
func set_mode(m: String) -> String:
	if m == "mr" and xr_active and not passthrough_supported:
		m = "vr"
	mode = m
	if xr_active:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if m == "mr" else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	return m


func tracked(hand: String) -> bool:
	if sim:
		return true
	var c: XRController3D = hands[hand].aim
	return xr_active and focused and c.get_is_active() and c.get_has_tracking_data()


func stick(hand: String) -> Vector2:
	if sim:
		return sim_stick.get(hand, Vector2.ZERO)
	if not tracked(hand):
		return Vector2.ZERO
	return hands[hand].aim.get_vector2("primary")


## [origin, direction] of a hand's aim ray (world).
func ray(hand: String) -> Array:
	var c: XRController3D = hands[hand].aim
	var t := c.global_transform
	return [t.origin, -t.basis.z.normalized()]


func pulse(hand: String, amplitude := 0.3, seconds := 0.04) -> void:
	pulses += 1
	if xr_active and tracked(hand):
		hands[hand].aim.trigger_haptic_pulse("haptic", 0.0, amplitude, seconds, 0.0)


func head_transform() -> Transform3D:
	return camera.global_transform


func grip_transform(hand: String) -> Transform3D:
	return hands[hand].grip.global_transform


func aim_transform(hand: String) -> Transform3D:
	return hands[hand].aim.global_transform


## Pointer: the ray up to `hit` (a world point or null) and a ring on it.
func set_pointer(hand: String, hit, show_ray: bool) -> void:
	var h: Dictionary = hands[hand]
	var length := 0.6
	h.dot.visible = false
	if hit != null:
		var origin: Vector3 = ray(hand)[0]
		length = origin.distance_to(hit)
		h.dot.visible = show_ray
		h.dot.global_position = hit + Vector3.UP * 0.001
		h.dot.global_basis = Basis()
	h.ray.visible = show_ray and tracked(hand)
	h.ray.scale = Vector3(1, maxf(length, 0.001), 1)
	h.ray.position = Vector3(0, 0, -length / 2.0)


func _process(_delta: float) -> void:
	if not xr_active:
		return
	for hand in ["left", "right"]:
		var c: XRController3D = hands[hand].aim
		var now := {
			"trigger": c.is_button_pressed("trigger_click") or c.get_float("trigger") > 0.75,
			"grip": c.is_button_pressed("grip_click") or c.get_float("grip") > 0.75,
			"menu": c.is_button_pressed("menu_button"),
			"ax": c.is_button_pressed("ax_button"),
			"by": c.is_button_pressed("by_button"),
			"stick": c.is_button_pressed("primary_click"),
		}
		var was: Dictionary = _prev[hand]
		var ok := tracked(hand)
		for k in now:
			if now[k] != was.get(k, false) and (ok or not now[k]):
				button.emit(hand, k, now[k])
		_prev[hand] = now
