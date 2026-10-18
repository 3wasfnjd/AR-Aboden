extends Node3D
## (Copied unchanged from the Dahrooj Quest build: scripts/xr/scene_anchor_probe.gd.)
## Instanced by OpenXRFbSceneManager under the XRAnchor3D of each Meta scene entity
## (the room the user captured in Space Setup): walls, floor, ceiling, tables, couch,
## bed, storage, screens, other furniture... It records the entity's semantic label,
## its bounded 2D plane (if any) and its bounded 3D volume (if any). Nothing is drawn.
##
## Meta's convention (kept as is): a plane lies in the anchor's local XY plane and its
## normal is the anchor's local +Z (into the room for walls, up for floor and table
## tops, down for the ceiling). A volume is an AABB in the anchor's local space.

static var registry: Array = []

const C_BOUNDED_2D := 3  # OpenXRFbSpatialEntity.COMPONENT_TYPE_BOUNDED_2D
const C_BOUNDED_3D := 4  # OpenXRFbSpatialEntity.COMPONENT_TYPE_BOUNDED_3D

var label := ""
var raw := ""
var rect := Rect2()
var box := AABB()


## Meta's labels (lower case, as the plugin gives them) to the game's names.
static func normalize(l: String) -> String:
	l = l.to_lower()
	if l == "wall_face" or l == "invisible_wall_face" or l == "inner_wall_face" or l == "wall":
		return "wall"
	return l


func setup_scene(entity) -> void:
	var labels: PackedStringArray = entity.get_semantic_labels()
	raw = String(labels[0]).to_lower() if not labels.is_empty() else "other"
	label = normalize(raw)
	if label == "global_mesh":
		return  # the whole-room mesh: the floor and every wall again, not used
	if entity.is_component_enabled(C_BOUNDED_2D):
		rect = entity.get_bounding_box_2d()
	if entity.is_component_enabled(C_BOUNDED_3D):
		box = entity.get_bounding_box_3d()
	if has_plane() or has_box():
		registry.append(self)


func has_plane() -> bool:
	return rect.size.x > 0.0 and rect.size.y > 0.0


func has_box() -> bool:
	return box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0


func _exit_tree() -> void:
	registry.erase(self)


## World transform with its origin at the centre of the plane's rectangle.
func plane_xform() -> Transform3D:
	var gt := global_transform.orthonormalized()
	var c := rect.get_center()
	return gt * Transform3D(Basis(), Vector3(c.x, c.y, 0.0))


## World transform with its origin at the centre of the volume.
func box_xform() -> Transform3D:
	return global_transform.orthonormalized() * Transform3D(Basis(), box.get_center())
