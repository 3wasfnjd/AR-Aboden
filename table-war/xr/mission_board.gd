class_name MissionBoard
extends Node3D
## Mission board floating above the far edge of the island (a child of the diorama,
## so it scales with the model; xr_game.gd turns it to face the player). Shows the
## mission name, the objective with its progress, the clock, civilian losses, three
## stars (drawn as meshes: the UI font has no star glyph) and the result.

const W := 0.52
const H := 0.20
const BG := Color(0.035, 0.05, 0.04)
const FRAME := Color(0.40, 0.85, 0.45)
const TEXT := Color(0.86, 1.0, 0.86)
const TEXT_DIM := Color(0.55, 0.75, 0.56)
const AMBER := Color(1.0, 0.72, 0.22)
const ALERT := Color(1.0, 0.22, 0.16)
const GOLD := Color(1.0, 0.80, 0.18)
const STAR_OFF := Color(0.22, 0.26, 0.22)

var title: Label3D
var goal: Label3D
var goal_en: Label3D
var info: Label3D
var result: Label3D
var best_label: Label3D
var stars: Array[MeshInstance3D] = []
var _font: Font


func _ready() -> void:
	_font = XRGame.ui_font()
	add_child(_quad(Vector2(W, H), BG, Vector3(0, 0, -0.001)))
	for r in [[Vector2(0, H * 0.5), Vector2(W, 0.002)], [Vector2(0, -H * 0.5), Vector2(W, 0.002)],
			[Vector2(-W * 0.5, 0), Vector2(0.002, H)], [Vector2(W * 0.5, 0), Vector2(0.002, H)]]:
		add_child(_quad(r[1], FRAME, Vector3(r[0].x, r[0].y, -0.0005)))
	title = _text(Vector3(0, H * 0.5 - 0.024, 0), 190, TEXT)
	goal = _text(Vector3(0, H * 0.5 - 0.058, 0), 130, AMBER)
	goal_en = _text(Vector3(0, H * 0.5 - 0.082, 0), 90, TEXT_DIM)
	info = _text(Vector3(0, H * 0.5 - 0.112, 0), 120, TEXT_DIM)
	result = _text(Vector3(-W * 0.17, -H * 0.5 + 0.03, 0), 150, FRAME)
	best_label = _text(Vector3(W * 0.3, -H * 0.5 + 0.012, 0), 80, TEXT_DIM)
	for k in 3:
		var s := MeshInstance3D.new()
		s.mesh = _star_mesh(0.016)
		s.material_override = _mat(STAR_OFF)
		s.position = Vector3(W * 0.3 + (k - 1) * 0.04, -H * 0.5 + 0.036, 0.0002)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		stars.append(s)


## Board contents from the mission state; `m` = Missions, `props` for progress.
func show_state(m: Missions, props: IslandProps) -> void:
	var d := Missions.get_def(m.active)
	visible = not d.is_empty()
	if not visible:
		return
	_put(title, "%s · %s" % [d.ar, String(d.en).to_upper()])
	var pr := m.progress(props)
	var unit := "%" if d.has("pct") else ""
	var prog := "%d%s/%d%s" % [int(pr[0]), unit, int(pr[1]), unit]
	# one language per line: mixed Arabic / Latin runs reorder unpredictably
	_put(goal, "%s  (%s)" % [d.goal_ar, prog])
	_put(goal_en, "%s  (%s)" % [d.goal_en, prog])
	var civ := m.civilians(props) if m.running or m.result != "" else 0
	var civ_txt := "خسائر مدنية: %d" % civ
	if int(d.civ_max) < 9999:
		civ_txt = "خسائر مدنية: %d من %d" % [civ, int(d.civ_max)]
	_put(info, "%s     %s" % [civ_txt, Missions.clock(m.time_left)])
	info.modulate = ALERT if m.running and m.time_left < 10.0 else TEXT_DIM
	var lit := m.stars
	match m.result:
		"won":
			_put(result, "تمت المهمة · MISSION COMPLETE")
			result.modulate = FRAME
		"failed":
			_put(result, "فشلت المهمة · MISSION FAILED")
			result.modulate = ALERT
		_:
			if m.running:
				_put(result, "جارية · IN PROGRESS")
				result.modulate = AMBER
				lit = 0
			else:
				_put(result, "اضغط ابدأ · PRESS START")
				result.modulate = TEXT_DIM
			if not m.running:
				lit = int(m.best.get(m.active, 0))
	for k in 3:
		(stars[k].material_override as StandardMaterial3D).albedo_color = GOLD if k < lit else STAR_OFF
	_put(best_label, "أفضل نتيجة · BEST" if m.result == "" and not m.running else "")


func _put(l: Label3D, t: String) -> void:
	if l.text != t:
		l.text = t


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _quad(size: Vector2, c: Color, pos: Vector3) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _mat(c)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _text(pos: Vector3, size: int, c: Color) -> Label3D:
	var l := Label3D.new()
	l.font = _font
	l.font_size = size
	l.pixel_size = 0.0001
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


## Five-pointed star in the XY plane.
static func _star_mesh(r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for k in 10:
		var a := PI * 0.5 + TAU * k / 10.0
		var rr := r if k % 2 == 0 else r * 0.42
		pts.append(Vector3(cos(a) * rr, sin(a) * rr, 0))
	for k in 10:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[(k + 1) % 10])
		st.add_vertex(pts[k])
	return st.commit()
