class_name MissionBoard
extends Node3D
## Mission screen in the player's view (build 13): a transparent, holographic display
## curved round the eyes, in the upper part of the view (a child of the XR camera).
## Left X shows / hides it. In free play it shows the island's destruction.
##
## The content (mission name, objective + progress, clock, civilian losses, three
## stars, result) is laid out in 2D inside a SubViewport with a transparent
## background and mapped onto a cylindrical strip round the eyes. The viewport
## re-renders only when the text changes (about once a second while the clock runs).

const TEX := Vector2i(1280, 520)
const DIST := 0.75                 # m from the eyes
const AZ_HALF := 0.30              # half the strip width, radians round the eyes
const Y0 := 0.11                   # strip bottom / top (m above eye level at DIST)
const Y1 := 0.29
const FRAME := Color(0.45, 1.0, 0.55)
const TEXT := Color(0.86, 1.0, 0.88)
const TEXT_DIM := Color(0.60, 0.85, 0.64)
const AMBER := Color(1.0, 0.76, 0.28)
const ALERT := Color(1.0, 0.30, 0.22)
const GOLD := Color(1.0, 0.82, 0.22)
const STAR_OFF := Color(0.45, 0.60, 0.48, 0.45)

var viewport: SubViewport
var screen: MeshInstance3D
var title: Label
var goal: Label
var goal_en: Label
var info: Label
var result: Label
var best_label: Label
var stars: Array[Polygon2D] = []
var _dirty := true


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = TEX
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	_build_ui()
	screen = MeshInstance3D.new()
	screen.name = "DomeScreen"
	screen.mesh = _patch_mesh()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = viewport.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.render_priority = 20         # over the scene: a head-up display
	m.no_depth_test = true
	screen.material_override = m
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(screen)


## The 2D layout: a faint green tint, a frame with corner brackets, scan lines, text.
func _build_ui() -> void:
	var root := Control.new()
	root.size = Vector2(TEX)
	viewport.add_child(root)
	var tint := ColorRect.new()
	tint.color = Color(0.10, 0.35, 0.16, 0.16)
	tint.position = Vector2(20, 20)
	tint.size = Vector2(TEX) - Vector2(40, 40)
	root.add_child(tint)
	for k in range(30, TEX.y - 30, 12):
		var sl := ColorRect.new()
		sl.color = Color(0.45, 1.0, 0.55, 0.035)
		sl.position = Vector2(24, k)
		sl.size = Vector2(TEX.x - 48, 2)
		root.add_child(sl)
	_frame(root, Rect2(20, 20, TEX.x - 40, TEX.y - 40), Color(FRAME, 0.55), 3)
	for c in [Vector2(14, 14), Vector2(TEX.x - 14, 14), Vector2(14, TEX.y - 14), Vector2(TEX.x - 14, TEX.y - 14)]:
		var sx := 1.0 if c.x < TEX.x * 0.5 else -1.0
		var sy := 1.0 if c.y < TEX.y * 0.5 else -1.0
		_bar(root, Rect2(Vector2(minf(c.x, c.x + sx * 70), c.y - 4), Vector2(70, 8)), FRAME)
		_bar(root, Rect2(Vector2(c.x - 4, minf(c.y, c.y + sy * 70)), Vector2(8, 70)), FRAME)
	var font := XRGame.ui_font()
	title = _label(root, font, 64, TEXT, Rect2(40, 34, TEX.x - 80, 80))
	_bar(root, Rect2(60, 118, TEX.x - 120, 3), Color(FRAME, 0.5))
	goal = _label(root, font, 50, AMBER, Rect2(40, 132, TEX.x - 80, 66))
	goal_en = _label(root, font, 36, TEXT_DIM, Rect2(40, 196, TEX.x - 80, 50))
	info = _label(root, font, 46, TEXT_DIM, Rect2(40, 252, TEX.x - 80, 60))
	_bar(root, Rect2(60, 326, TEX.x - 120, 3), Color(FRAME, 0.5))
	result = _label(root, font, 56, FRAME, Rect2(40, 350, TEX.x * 0.6, 80))
	best_label = _label(root, font, 30, TEXT_DIM, Rect2(TEX.x * 0.62, 440, TEX.x * 0.33, 40))
	for k in 3:
		var p := Polygon2D.new()
		p.polygon = _star_points(34.0)
		p.position = Vector2(TEX.x * 0.70 + k * 92, 392)
		p.color = STAR_OFF
		root.add_child(p)
		stars.append(p)


## Board contents from the mission state; `m` = Missions, `props` for progress.
func show_state(m: Missions, props: IslandProps) -> void:
	var d := Missions.get_def(m.active)
	if d.is_empty():
		_free_play(props)
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
	_tint(info, ALERT if m.running and m.time_left < 10.0 else TEXT_DIM)
	var lit := m.stars
	match m.result:
		"won":
			_put(result, "تمت المهمة · MISSION COMPLETE")
			_tint(result, FRAME)
		"failed":
			_put(result, "فشلت المهمة · MISSION FAILED")
			_tint(result, ALERT)
		_:
			if m.running:
				_put(result, "جارية · IN PROGRESS")
				_tint(result, AMBER)
				lit = 0
			else:
				_put(result, "اضغط ابدأ · PRESS START")
				_tint(result, TEXT_DIM)
				lit = int(m.best.get(m.active, 0))
	for k in 3:
		var c := GOLD if k < lit else STAR_OFF
		if stars[k].color != c:
			stars[k].color = c
			_dirty = true
	_put(best_label, "أفضل نتيجة · BEST" if m.result == "" and not m.running else "")
	if _dirty:
		_dirty = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Free play: the island's destruction and what is left.
func _free_play(props: IslandProps) -> void:
	var d := props.destruction()
	_put(title, "لعب حر · FREE PLAY")
	_put(goal, "تدمير الجزيرة: %d%%" % int(floor(float(d.pct))))
	_put(goal_en, "Island destroyed: %d%%" % int(floor(float(d.pct))))
	_put(info, "أهداف متبقية: %d" % int(d.left))
	_tint(info, TEXT_DIM)
	_put(result, "اختر مهمة من اللوحة · PICK A MISSION")
	_tint(result, TEXT_DIM)
	_put(best_label, "")
	for k in 3:
		if stars[k].color != Color(0, 0, 0, 0):
			stars[k].color = Color(0, 0, 0, 0)
			_dirty = true
	if _dirty:
		_dirty = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _put(l: Label, t: String) -> void:
	if l.text != t:
		l.text = t
		_dirty = true


func _tint(l: Label, c: Color) -> void:
	if l.modulate != c:
		l.modulate = c
		_dirty = true


func _label(root: Control, font: Font, size: int, c: Color, r: Rect2) -> Label:
	var l := Label.new()
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.12, 0.04, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.modulate = c
	root.add_child(l)
	return l


func _bar(root: Control, r: Rect2, c: Color) -> void:
	var b := ColorRect.new()
	b.color = c
	b.position = r.position
	b.size = r.size
	root.add_child(b)


func _frame(root: Control, r: Rect2, c: Color, t: float) -> void:
	_bar(root, Rect2(r.position, Vector2(r.size.x, t)), c)
	_bar(root, Rect2(Vector2(r.position.x, r.end.y - t), Vector2(r.size.x, t)), c)
	_bar(root, Rect2(r.position, Vector2(t, r.size.y)), c)
	_bar(root, Rect2(Vector2(r.end.x - t, r.position.y), Vector2(t, r.size.y)), c)


static func _star_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + TAU * k / 10.0
		var rr := r if k % 2 == 0 else r * 0.42
		pts.append(Vector2(cos(a) * rr, sin(a) * rr))
	return pts


## A strip of a cylinder round the eyes (camera-local, -z ahead), upper part of the view.
func _patch_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na := 24
	for i in na:
		var a0 := lerpf(-AZ_HALF, AZ_HALF, float(i) / na)
		var a1 := lerpf(-AZ_HALF, AZ_HALF, float(i + 1) / na)
		var u0 := float(i) / na
		var u1 := float(i + 1) / na
		var q := [Vector3(sin(a0) * DIST, Y0, -cos(a0) * DIST), Vector3(sin(a1) * DIST, Y0, -cos(a1) * DIST),
			Vector3(sin(a1) * DIST, Y1, -cos(a1) * DIST), Vector3(sin(a0) * DIST, Y1, -cos(a0) * DIST)]
		var uv := [Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.0), Vector2(u0, 0.0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[k])
			st.add_vertex(q[k])
	return st.commit()
