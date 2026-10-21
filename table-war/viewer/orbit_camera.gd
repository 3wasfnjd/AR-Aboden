class_name OrbitCamera
extends Camera3D
## "Leaning over the table" orbit camera. LMB drag = orbit, RMB/MMB drag = pan,
## wheel = distance. Click without dragging = fire at that point.

var target := Vector3(0, 0.08, 0)
var yaw := deg_to_rad(-25.0)
var pitch := deg_to_rad(42.0)
var distance := 0.85
var min_dist := 0.04
var max_dist := 2.2
var _drag := 0
var _drag_px := 0.0

signal clicked(screen_pos: Vector2)


func _ready() -> void:
	near = 0.01
	far = 40.0
	fov = 50.0
	apply()


func set_view(t: Vector3, yaw_deg: float, pitch_deg: float, dist: float, fov_deg := 50.0) -> void:
	target = t
	yaw = deg_to_rad(yaw_deg)
	pitch = deg_to_rad(pitch_deg)
	distance = dist
	fov = fov_deg
	apply()


func apply() -> void:
	pitch = clampf(pitch, deg_to_rad(2.0), deg_to_rad(89.5))
	distance = clampf(distance, min_dist, max_dist)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var pos := target + dir * distance
	var up := Vector3.UP if pitch < deg_to_rad(89.0) else Vector3(-sin(yaw), 0, -cos(yaw))
	look_at_from_position(pos, target, up)


var _touches := {}
var _pinch := 0.0


func _unhandled_input(event: InputEvent) -> void:
	# touch screens: two fingers pinch to zoom (one finger arrives as an emulated mouse)
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		_pinch = 0.0
		if _touches.size() >= 2:
			_drag = 0
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			var ks := _touches.keys()
			var gap := (_touches[ks[0]] as Vector2).distance_to(_touches[ks[1]])
			if _pinch > 0.0 and gap > 1.0:
				distance *= _pinch / gap
				apply()
			_pinch = gap
			_drag = 0
			_drag_px = 99.0
		return
	if event is InputEventMagnifyGesture:
		distance /= maxf((event as InputEventMagnifyGesture).factor, 0.01)
		apply()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance *= 0.9
			apply()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance *= 1.1
			apply()
		elif mb.pressed:
			_drag = mb.button_index
			_drag_px = 0.0
		else:
			if _drag == MOUSE_BUTTON_LEFT and _drag_px < 4.0:
				clicked.emit(mb.position)
			_drag = 0
	elif event is InputEventMouseMotion and _drag != 0:
		var mm := event as InputEventMouseMotion
		_drag_px += mm.relative.length()
		if _drag == MOUSE_BUTTON_LEFT:
			yaw -= mm.relative.x * 0.006
			pitch += mm.relative.y * 0.006
		else:
			var right := global_transform.basis.x
			var fwd := Vector3(global_transform.basis.z.x, 0, global_transform.basis.z.z).normalized()
			target += (-right * mm.relative.x + fwd * -mm.relative.y) * distance * 0.0012
		apply()
