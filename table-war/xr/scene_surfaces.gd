class_name SceneSurfaces
extends Node
## The real room through the Meta Scene API (OpenXR Vendors OpenXRFbSceneManager),
## adapted from the Dahrooj Quest build (scripts/xr/scene_surfaces.gd). Here the point
## is the opposite of Dahrooj: we WANT the furniture tops (the table from Space Setup),
## so every upward-facing plane (table, desk, storage, couch, bed, floor...) is listed.
## With no room setup or a denied permission the lists stay empty and placement falls
## back to a virtual plane (see Placement.virtual_hit()).
##
## planes(): [{label, xform: Transform3D, size: Vector2, normal: Vector3}] world space.
##   The plane is xform's local XY plane centred on xform.origin; normal = xform.basis.z
##   (Meta's convention: up for floor and table tops).
## boxes(): [{label, xform, size: Vector3}] world space volumes (their top face counts).

signal surfaces_changed

const Probe := preload("res://xr/scene_anchor_probe.gd")
const USE_SCENE := "com.oculus.permission.USE_SCENE"
## Labels that can carry the diorama. Walls, ceilings, screens, windows... cannot.
const TOPS := ["table", "floor", "storage", "couch", "bed", "other"]

var manager: Node = null
var status := "unavailable"  # unavailable | waiting | ready | no_data | denied
var _tests: Array = []


func attach(origin: XROrigin3D) -> void:
	if not ClassDB.class_exists("OpenXRFbSceneManager"):
		return
	manager = ClassDB.instantiate("OpenXRFbSceneManager")
	var probe := Node3D.new()
	probe.set_script(Probe)
	var packed := PackedScene.new()
	packed.pack(probe)
	probe.free()
	manager.set("default_scene", packed)
	manager.set("auto_create", true)
	origin.add_child(manager)
	status = "waiting"
	if manager.has_signal("openxr_fb_scene_anchor_created"):
		manager.connect("openxr_fb_scene_anchor_created", func(_a, _b): _changed())
	if manager.has_signal("openxr_fb_scene_data_missing"):
		manager.connect("openxr_fb_scene_data_missing", _on_missing)
	if manager.has_signal("openxr_fb_scene_capture_completed"):
		manager.connect("openxr_fb_scene_capture_completed", func(_ok): reload())
	# The room is behind a runtime permission (USE_SCENE): ask again if it arrives late.
	if OS.get_name() == "Android":
		get_tree().on_request_permissions_result.connect(_on_permission)
		if not OS.get_granted_permissions().has(USE_SCENE):
			OS.request_permission(USE_SCENE)


func _on_missing() -> void:
	if OS.get_name() == "Android" and not OS.get_granted_permissions().has(USE_SCENE):
		status = "denied"
	else:
		status = "no_data"
	surfaces_changed.emit()


func _on_permission(permission: String, granted: bool) -> void:
	if permission != USE_SCENE:
		return
	if granted:
		reload()
	else:
		status = "denied"
		surfaces_changed.emit()


func reload() -> void:
	if manager == null:
		return
	status = "waiting"
	if bool(manager.call("are_scene_anchors_created")):
		manager.call("remove_scene_anchors")
	manager.call("create_scene_anchors")
	surfaces_changed.emit()


func _changed() -> void:
	status = "ready"
	surfaces_changed.emit()


func _probes() -> Array:
	var out: Array = []
	for p in Probe.registry:
		if is_instance_valid(p) and p.is_inside_tree():
			out.append(p)
	return out


func planes() -> Array:
	var out: Array = []
	for p in _probes():
		if p.has_plane():
			var xf: Transform3D = p.plane_xform()
			out.append({"label": p.label, "xform": xf, "size": p.rect.size, "normal": xf.basis.z.normalized()})
	for t in _tests:
		if not t.has("box"):
			out.append({"label": t.label, "xform": t.xform, "size": t.size, "normal": (t.xform as Transform3D).basis.z.normalized()})
	return out


func boxes() -> Array:
	var out: Array = []
	for p in _probes():
		if p.has_box():
			out.append({"label": p.label, "xform": p.box_xform(), "size": p.box.size})
	for t in _tests:
		if t.has("box"):
			out.append({"label": t.label, "xform": t.xform, "size": t.size})
	return out


## A stand-in plane (tests / desktop): xform as in planes() (centre, normal = basis.z).
func add_test_plane(xform: Transform3D, size: Vector2, label := "table") -> void:
	_tests.append({"label": label, "xform": xform.orthonormalized(), "size": size})
	if status == "unavailable":
		status = "ready"
	surfaces_changed.emit()


## A stand-in volume (tests / desktop): xform at the box centre.
func add_test_box(xform: Transform3D, size: Vector3, label := "table") -> void:
	_tests.append({"label": label, "xform": xform.orthonormalized(), "size": size, "box": true})
	if status == "unavailable":
		status = "ready"
	surfaces_changed.emit()


func clear_tests() -> void:
	_tests.clear()
	surfaces_changed.emit()


func count_tops() -> int:
	var n := 0
	for pl in planes():
		if (pl.normal as Vector3).y > 0.9 and pl.label in TOPS:
			n += 1
	for bx in boxes():
		if bx.label in TOPS:
			n += 1
	return n


## The nearest upward-facing real surface along a ray: {p, n, label} or {}.
## Planes count from their front (upper) side only; volumes by their top face.
func ray_surface(origin: Vector3, dir: Vector3, max_dist := 6.0) -> Dictionary:
	var d := dir.normalized()
	var best := {}
	var best_t := max_dist
	for pl in planes():
		var n: Vector3 = pl.normal
		if n.y < 0.9 or not pl.label in TOPS:
			continue
		var dn := d.dot(n)
		if dn > -1e-4:
			continue
		var xf: Transform3D = pl.xform
		var t := (xf.origin - origin).dot(n) / dn
		if t <= 0.0 or t >= best_t:
			continue
		var p := origin + d * t
		var l := xf.affine_inverse() * p
		var sz: Vector2 = pl.size
		if absf(l.x) <= sz.x / 2.0 and absf(l.y) <= sz.y / 2.0:
			best_t = t
			best = {"p": p, "n": Vector3.UP, "label": pl.label}
	for bx in boxes():
		if not bx.label in TOPS:
			continue
		var xf: Transform3D = bx.xform
		var inv := xf.affine_inverse()
		var hit := ray_box(inv * origin, inv.basis * d, (bx.size as Vector3) / 2.0)
		if hit.is_empty() or float(hit.t) <= 0.0 or float(hit.t) >= best_t:
			continue
		var n := (xf.basis * (hit.n as Vector3)).normalized()
		if n.y < 0.9:
			continue
		best_t = hit.t
		best = {"p": origin + d * best_t, "n": Vector3.UP, "label": bx.label}
	return best


## Ray against an axis-aligned box centred at the origin with half extents h (slab test):
## {t, n} of the entry face, or {} (also {} when the ray starts inside).
static func ray_box(o: Vector3, d: Vector3, h: Vector3) -> Dictionary:
	var t0 := -INF
	var t1 := INF
	var n := Vector3.ZERO
	for a in 3:
		if absf(d[a]) < 1e-9:
			if absf(o[a]) > h[a]:
				return {}
			continue
		var ta := (-h[a] - o[a]) / d[a]
		var tb := (h[a] - o[a]) / d[a]
		var na := Vector3.ZERO
		na[a] = -1.0
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
			na[a] = 1.0
		if ta > t0:
			t0 = ta
			n = na
		t1 = minf(t1, tb)
		if t0 > t1:
			return {}
	if t0 < 0.0:
		return {}
	return {"t": t0, "n": n}
