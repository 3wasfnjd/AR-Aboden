class_name CampaignScreen
extends Node3D
## The big screen of the operations room (VR, build 14): the campaign map, the team's
## briefing before a stage, the debrief after it, and the pause menu. A flat panel
## (W x H m) whose content is laid out in 2D in a SubViewport; the right ray points at it
## (hit()) and the trigger presses the button under the ray (press()).
##
## Pages:
##   campaign   title, chapter tabs, the five stage cards of the chapter (number, name,
##              stars, or locked / buy / in development), the selected stage's details and
##              START
##   briefing   the speaker (badge, name, role), the line in Arabic and English, NEXT /
##              START MISSION, SKIP
##   debrief    MISSION COMPLETE / FAILED, stars, civilian casualties, time, shots shot
##              down, hull; the commander's line; NEXT STAGE / RETRY / CAMPAIGN
##   pause      RESUME / RESTART / CAMPAIGN
## The viewport re-renders only when the page or the hover changes.

signal pressed(id: String)

const W := 2.5
const H := 1.316
const TEX := Vector2i(1900, 1000)
const BG := Color(0.035, 0.07, 0.10, 0.92)
const FRAME := Color(0.30, 0.85, 1.0)
const TEXT := Color(0.88, 0.96, 1.0)
const DIM := Color(0.55, 0.70, 0.80)
const AMBER := Color(1.0, 0.76, 0.30)
const GOLD := Color(1.0, 0.82, 0.22)
const RED := Color(1.0, 0.36, 0.28)
const GREEN := Color(0.45, 1.0, 0.55)
const CARD := Color(0.07, 0.14, 0.19)
const CARD_HOVER := Color(0.10, 0.22, 0.30)
const CARD_SEL := Color(0.12, 0.30, 0.40)

var viewport: SubViewport
var screen: MeshInstance3D
var root: Control
var page := "campaign"
var chapter := 1
var selected := "c1s1"
var hover := ""
var buttons: Array[Dictionary] = []     # {id, rect: Rect2 (px), panel: Control}
var progress: Progress
var brief_i := 0
var debrief := {}
var _font: Font


func _ready() -> void:
	_font = XRGame.ui_font()
	viewport = SubViewport.new()
	viewport.size = TEX
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	root = Control.new()
	root.size = Vector2(TEX)
	viewport.add_child(root)
	screen = MeshInstance3D.new()
	screen.name = "Screen"
	var q := QuadMesh.new()
	q.size = Vector2(W, H)
	screen.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = viewport.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	screen.material_override = m
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(screen)


func _redraw() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# --- pages -----------------------------------------------------------------------------

func show_campaign(p: Progress, ch := -1, sel := "") -> void:
	progress = p
	page = "campaign"
	if ch >= 0:
		chapter = ch
	if sel != "":
		selected = sel
	var list := Campaign.stages_of(chapter)
	var ok := false
	for s in list:
		if s.id == selected:
			ok = true
	if not ok and not list.is_empty():
		selected = list[0].id
	_build()


func show_briefing(stage_id: String, i := 0) -> void:
	page = "briefing"
	selected = stage_id
	brief_i = i
	_build()


func show_debrief(d: Dictionary) -> void:
	page = "debrief"
	debrief = d
	_build()


## "Loading the map": shown while another island is built for the next chapter.
func show_loading(map_name: String) -> void:
	page = "loading"
	for c in root.get_children():
		c.free()
	buttons.clear()
	_rect(Rect2(Vector2.ZERO, Vector2(TEX)), BG)
	_frame(Rect2(8, 8, TEX.x - 16, TEX.y - 16), Color(FRAME, 0.6), 3)
	_label("جاري تجهيز الخريطة · LOADING MAP", 60, TEXT, Rect2(60, 330, TEX.x - 120, 90))
	_label(map_name, 52, AMBER, Rect2(60, 450, TEX.x - 120, 80))
	_redraw()


func show_pause() -> void:
	page = "pause"
	_build()


## The number of briefing lines of the selected stage.
func brief_lines() -> Array:
	return Campaign.get_stage(selected).get("brief", [])


# --- layout ----------------------------------------------------------------------------

func _build() -> void:
	for c in root.get_children():
		c.free()
	buttons.clear()
	_rect(Rect2(Vector2.ZERO, Vector2(TEX)), BG)
	_frame(Rect2(8, 8, TEX.x - 16, TEX.y - 16), Color(FRAME, 0.6), 3)
	match page:
		"campaign":
			_page_campaign()
		"briefing":
			_page_briefing()
		"debrief":
			_page_debrief()
		"pause":
			_page_pause()
	_paint()
	_redraw()


func _page_campaign() -> void:
	_label("عملية الدرع الأزرق", 70, TEXT, Rect2(60, 30, TEX.x - 120, 90), HORIZONTAL_ALIGNMENT_RIGHT)
	_label("OPERATION BLUE SHIELD", 34, DIM, Rect2(60, 52, 900, 60), HORIZONTAL_ALIGNMENT_LEFT)
	var stars_all := progress.total_stars() if progress else 0
	_stars(1, 1, Vector2(84, 125), 20.0)
	_label("%d" % stars_all, 40, GOLD, Rect2(112, 100, 300, 50), HORIZONTAL_ALIGNMENT_LEFT)
	# chapter tabs (right to left: chapter 0 at the right)
	var tw := (TEX.x - 120 - 4 * 14) / 5.0
	for k in Campaign.CHAPTERS.size():
		var c: Dictionary = Campaign.CHAPTERS[k]
		var x := TEX.x - 60 - (k + 1) * tw - k * 14
		var r := Rect2(x, 160, tw, 110)
		var id := "ch_%d" % c.n
		var p := _button(id, r)
		var sel := int(c.n) == chapter
		p.set_meta("sel", sel)
		var lock := ""
		if progress and not progress.owns(int(c.n)):
			lock = " · مدفوع"
		if not bool(c.built):
			lock = " · قريبًا"
		_label(("الفصل %d" % c.n if int(c.n) > 0 else "تدريب") + lock, 30, AMBER if sel else DIM, Rect2(x, 166, tw, 40))
		_label(String(c.ar), 38, TEXT, Rect2(x, 204, tw, 56))
	var ch := Campaign.chapter(chapter)
	_label("%s · %s" % [ch.sub_ar, ch.sub_en], 30, DIM, Rect2(60, 285, TEX.x - 120, 44))
	# stage cards (right to left)
	var list := Campaign.stages_of(chapter)
	var cols := mini(list.size(), 5)
	var rows := int(ceil(list.size() / 5.0))
	var cw := (TEX.x - 120 - (cols - 1) * 16) / float(cols)
	var chh := 150.0 if rows > 1 else 230.0
	for i in list.size():
		var s: Dictionary = list[i]
		var col := i % 5
		var row := i / 5
		var x := TEX.x - 60 - (col + 1) * cw - col * 16
		var y := 345 + row * (chh + 14)
		var r := Rect2(x, y, cw, chh)
		var st := progress.stage_state(s) if progress else "open"
		var p := _button("st_" + String(s.id), r)
		p.set_meta("sel", s.id == selected)
		_label("%d" % int(s.n), 54 if rows == 1 else 36, AMBER if st == "open" else DIM, Rect2(x + cw - 90, y + 8, 80, 70))
		_label(String(s.ar), 36 if rows == 1 else 28, TEXT if st == "open" else DIM, Rect2(x + 10, y + (80 if rows == 1 else 54), cw - 20, 50))
		_label(String(s.en), 24, DIM, Rect2(x + 10, y + (128 if rows == 1 else 90), cw - 20, 34))
		var foot := ""
		var fc := GOLD
		match st:
			"open":
				var n := progress.stars(String(s.id)) if progress else 0
				_stars(n, 3, Vector2(x + cw * 0.5, y + chh - (34 if rows == 1 else 22)), 20.0 if rows == 1 else 14.0)
			"locked":
				foot = "مقفلة · LOCKED"
				fc = DIM
			"buy":
				foot = "للشراء · PREMIUM"
				fc = AMBER
			"soon":
				foot = "قيد التطوير · SOON"
				fc = DIM
		_label(foot, 34 if rows == 1 else 26, fc, Rect2(x + 10, y + chh - (56 if rows == 1 else 40), cw - 20, 44))
	# details of the selected stage
	var s2 := Campaign.get_stage(selected)
	var y2 := 345 + rows * (chh + 14) + 10
	_bar(Rect2(60, y2, TEX.x - 120, 2), Color(FRAME, 0.4))
	if not s2.is_empty():
		_label("%s · %s" % [s2.ar, s2.en], 46, TEXT, Rect2(400, y2 + 16, TEX.x - 460, 60), HORIZONTAL_ALIGNMENT_RIGHT)
		_label(String(s2.get("goal_ar", "")), 36, AMBER, Rect2(400, y2 + 80, TEX.x - 460, 50), HORIZONTAL_ALIGNMENT_RIGHT)
		_label(String(s2.get("goal_en", "")), 26, DIM, Rect2(400, y2 + 130, TEX.x - 460, 40), HORIZONTAL_ALIGNMENT_RIGHT)
		var info: Array = []
		if s2.has("time"):
			info.append("الوقت %s" % Missions.clock(float(s2.time)))
		if bool(s2.get("sam", false)):
			info.append("دفاع جوي")
		if float(s2.get("coastal", 0.0)) > 0.0:
			info.append("صواريخ ساحلية على البارجة")
		info.append("المدنيون: كل خطأ ينقص نجمة")
		_label("  ·  ".join(info), 28, DIM, Rect2(400, y2 + 172, TEX.x - 460, 40), HORIZONTAL_ALIGNMENT_RIGHT)
		var st2 := progress.stage_state(s2) if progress else "open"
		var bt := {"open": ["ابدأ", "START"], "locked": ["مقفلة", "LOCKED"], "buy": ["افتح الفصل", "UNLOCK"], "soon": ["قريبًا", "SOON"]}[st2] as Array
		var b := _button("start" if st2 == "open" else ("buy" if st2 == "buy" else "none"), Rect2(70, y2 + 40, 300, 130))
		b.set_meta("accent", st2 == "open")
		_label(String(bt[0]), 50, GREEN if st2 == "open" else DIM, Rect2(70, y2 + 52, 300, 64))
		_label(String(bt[1]), 28, DIM, Rect2(70, y2 + 114, 300, 40))


func _page_briefing() -> void:
	var s := Campaign.get_stage(selected)
	var lines := brief_lines()
	_label("إحاطة المهمة · BRIEFING", 34, DIM, Rect2(60, 34, TEX.x - 120, 50), HORIZONTAL_ALIGNMENT_RIGHT)
	_label("%s · %s" % [s.get("ar", ""), s.get("en", "")], 58, TEXT, Rect2(60, 84, TEX.x - 120, 80), HORIZONTAL_ALIGNMENT_RIGHT)
	_bar(Rect2(60, 176, TEX.x - 120, 2), Color(FRAME, 0.4))
	if lines.is_empty():
		return
	var ln: Array = lines[clampi(brief_i, 0, lines.size() - 1)]
	var who := Campaign.speaker(String(ln[0]))
	var col: Color = who[4]
	# speaker badge: a ring with the initial, name and role
	var badge := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.18)
	sb.border_color = col
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(120)
	badge.add_theme_stylebox_override("panel", sb)
	badge.position = Vector2(TEX.x - 300, 230)
	badge.size = Vector2(220, 220)
	root.add_child(badge)
	_portrait(String(ln[0]), Vector2(TEX.x - 190, 340), 100.0)
	_label(String(who[0]), 46, col, Rect2(TEX.x - 760, 250, 440, 60), HORIZONTAL_ALIGNMENT_RIGHT)
	_label("%s · %s" % [who[2], who[3]], 28, DIM, Rect2(TEX.x - 860, 312, 540, 44), HORIZONTAL_ALIGNMENT_RIGHT)
	_label(String(who[1]), 28, DIM, Rect2(TEX.x - 860, 356, 540, 40), HORIZONTAL_ALIGNMENT_RIGHT)
	var t := _label(String(ln[1]), 46, TEXT, Rect2(100, 480, TEX.x - 200, 200), HORIZONTAL_ALIGNMENT_RIGHT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var e := _label(String(ln[2]), 30, DIM, Rect2(100, 690, TEX.x - 200, 100), HORIZONTAL_ALIGNMENT_RIGHT)
	e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	e.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# progress dots
	for k in lines.size():
		_rect(Rect2(TEX.x / 2.0 + (k - lines.size() * 0.5) * 40, 812, 24, 24), AMBER if k == brief_i else Color(DIM, 0.4))
	var last := brief_i >= lines.size() - 1
	var b := _button("brief_next", Rect2(70, 850, 460, 110))
	b.set_meta("accent", true)
	_label("ابدأ المهمة · START" if last else "التالي · NEXT", 42, GREEN, Rect2(70, 872, 460, 64))
	_button("brief_skip", Rect2(560, 850, 300, 110))
	_label("تخطّي · SKIP", 34, DIM, Rect2(560, 878, 300, 56))
	_button("brief_back", Rect2(TEX.x - 370, 850, 300, 110))
	_label("رجوع · BACK", 34, DIM, Rect2(TEX.x - 370, 878, 300, 56))


func _page_debrief() -> void:
	var won := String(debrief.get("result", "")) == "won"
	var s := Campaign.get_stage(String(debrief.get("id", selected)))
	_label("تمت المهمة · MISSION COMPLETE" if won else "فشلت المهمة · MISSION FAILED", 64, GREEN if won else RED, Rect2(60, 40, TEX.x - 120, 90))
	_label("%s · %s" % [s.get("ar", ""), s.get("en", "")], 40, TEXT, Rect2(60, 132, TEX.x - 120, 60))
	var n := int(debrief.get("stars", 0))
	_stars(n, 3, Vector2(TEX.x * 0.5, 280), 62.0)
	var why := {"time": "انتهى الوقت · Out of time", "civilians": "خسائر مدنية كثيرة · Too many civilian casualties", "ship": "البارجة تضررت · The battleship was hit too hard", "protect": "دمّرت منشأة لازم تبقى · A protected site was destroyed"}
	if not won:
		_label(String(why.get(debrief.get("reason", ""), "")), 36, RED, Rect2(60, 360, TEX.x - 120, 50))
	var rows := [
		["خسائر مدنية", "Civilian casualties", str(int(debrief.get("civ", 0))), RED if int(debrief.get("civ", 0)) > 0 else GREEN],
		["الوقت المتبقي", "Time left", Missions.clock(float(debrief.get("time_left", 0.0))), TEXT],
		["الطلقات", "Shots", str(int(debrief.get("shots", 0))), TEXT],
		["أُسقطت من صواريخنا", "Shot down by air defence", str(int(debrief.get("intercepted", 0))), TEXT],
		["هيكل البارجة", "Battleship hull", "%d%%" % int(debrief.get("hull", 100)), GREEN if float(debrief.get("hull", 100)) >= 50 else AMBER],
	]
	for k in rows.size():
		var y := 430 + k * 62
		_label("%s · %s" % [rows[k][0], rows[k][1]], 32, DIM, Rect2(TEX.x * 0.45, y, TEX.x * 0.5, 50), HORIZONTAL_ALIGNMENT_RIGHT)
		_label(String(rows[k][2]), 40, rows[k][3], Rect2(TEX.x * 0.2, y - 4, TEX.x * 0.22, 56), HORIZONTAL_ALIGNMENT_RIGHT)
	var line: Array = s.get("won" if won else "failed", ["", ""])
	if not String(line[0]).is_empty():
		var who := Campaign.speaker("salem")
		_label("%s: %s" % [who[0], line[0]], 34, who[4], Rect2(60, 750, TEX.x - 120, 50), HORIZONTAL_ALIGNMENT_RIGHT)
		_label(String(line[1]), 26, DIM, Rect2(60, 798, TEX.x - 120, 40), HORIZONTAL_ALIGNMENT_RIGHT)
	var has_next := won and String(debrief.get("next", "")) != ""
	if has_next:
		var b := _button("next", Rect2(70, 860, 420, 100))
		b.set_meta("accent", true)
		_label("المرحلة التالية · NEXT", 38, GREEN, Rect2(70, 878, 420, 64))
	_button("retry", Rect2(520 if has_next else 70, 860, 360, 100))
	_label("إعادة · RETRY", 36, TEXT, Rect2(520 if has_next else 70, 878, 360, 64))
	_button("campaign", Rect2(TEX.x - 430, 860, 360, 100))
	_label("الحملة · CAMPAIGN", 36, TEXT, Rect2(TEX.x - 430, 878, 360, 64))


func _page_pause() -> void:
	_label("إيقاف مؤقت · PAUSED", 70, TEXT, Rect2(60, 120, TEX.x - 120, 100))
	var ids := [["resume", "متابعة", "RESUME"], ["restart", "إعادة المرحلة", "RESTART"], ["campaign", "الحملة", "CAMPAIGN"]]
	for k in ids.size():
		var r := Rect2(TEX.x / 2.0 - 380, 300 + k * 190, 760, 160)
		var b := _button(ids[k][0], r)
		b.set_meta("accent", k == 0)
		_label(String(ids[k][1]), 52, GREEN if k == 0 else TEXT, Rect2(r.position.x, r.position.y + 18, r.size.x, 70))
		_label(String(ids[k][2]), 30, DIM, Rect2(r.position.x, r.position.y + 96, r.size.x, 44))


# --- widgets ---------------------------------------------------------------------------

func _rect(r: Rect2, c: Color) -> ColorRect:
	var b := ColorRect.new()
	b.color = c
	b.position = r.position
	b.size = r.size
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(b)
	return b


func _poly(pts: Array, c: Color, at: Vector2, k: float) -> void:
	var p := Polygon2D.new()
	var arr := PackedVector2Array()
	for q in pts:
		arr.append(at + (q as Vector2) * k)
	p.polygon = arr
	p.color = c
	root.add_child(p)


## A low-poly portrait of a team member (2D polygons), centred at c, radius r.
func _portrait(id: String, c: Vector2, r: float) -> void:
	var k := r / 100.0
	var uni := {"salem": Color(0.22, 0.30, 0.44), "reem": Color(0.20, 0.28, 0.40), "nasser": Color(0.27, 0.32, 0.25), "saqr": Color(0.20, 0.22, 0.20)}.get(id, Color(0.25, 0.3, 0.4)) as Color
	var skin := {"salem": Color(0.74, 0.56, 0.42), "reem": Color(0.84, 0.66, 0.52), "nasser": Color(0.66, 0.48, 0.36), "saqr": Color(0.70, 0.52, 0.38)}.get(id, Color(0.8, 0.6, 0.5)) as Color
	# shoulders and collar
	_poly([Vector2(-88, 100), Vector2(-80, 52), Vector2(-34, 30), Vector2(34, 30), Vector2(80, 52), Vector2(88, 100)], uni, c, k)
	_poly([Vector2(-20, 30), Vector2(0, 58), Vector2(20, 30)], uni.darkened(0.35), c, k)
	# neck and face (facets: a light and a shaded half)
	_poly([Vector2(-16, 14), Vector2(16, 14), Vector2(14, 36), Vector2(-14, 36)], skin.darkened(0.15), c, k)
	var face := [Vector2(-34, -40), Vector2(-38, -6), Vector2(-26, 18), Vector2(0, 28), Vector2(26, 18), Vector2(38, -6), Vector2(34, -40), Vector2(0, -52)]
	_poly(face, skin, c, k)
	_poly([Vector2(0, -52), Vector2(34, -40), Vector2(38, -6), Vector2(26, 18), Vector2(0, 28)], skin.darkened(0.1), c, k)
	# eyes and brows
	for sx in [-1.0, 1.0]:
		_poly([Vector2(sx * 10, -14), Vector2(sx * 22, -16), Vector2(sx * 22, -10), Vector2(sx * 10, -9)], Color(0.12, 0.10, 0.10), c, k)
		_poly([Vector2(sx * 8, -24), Vector2(sx * 26, -26), Vector2(sx * 26, -22), Vector2(sx * 8, -20)], Color(0.15, 0.11, 0.09), c, k)
	match id:
		"salem":
			# officer's peaked cap with a gold badge, moustache
			_poly([Vector2(-44, -40), Vector2(-40, -66), Vector2(0, -78), Vector2(40, -66), Vector2(44, -40)], uni.darkened(0.3), c, k)
			_poly([Vector2(-46, -40), Vector2(46, -40), Vector2(36, -30), Vector2(-36, -30)], Color(0.10, 0.10, 0.12), c, k)
			_poly([Vector2(-8, -64), Vector2(0, -72), Vector2(8, -64), Vector2(0, -54)], Color(0.95, 0.78, 0.30), c, k)
			_poly([Vector2(-18, 4), Vector2(0, 0), Vector2(18, 4), Vector2(12, 10), Vector2(-12, 10)], Color(0.16, 0.12, 0.10), c, k)
			_poly([Vector2(-70, 60), Vector2(-46, 52), Vector2(-46, 62), Vector2(-70, 70)], Color(0.95, 0.78, 0.30), c, k)
		"reem":
			# headscarf framing the face, falling over the shoulders
			_poly([Vector2(-46, 30), Vector2(-50, -20), Vector2(-36, -58), Vector2(0, -70), Vector2(36, -58), Vector2(50, -20), Vector2(46, 30), Vector2(30, 40), Vector2(36, -6), Vector2(32, -42), Vector2(0, -52), Vector2(-32, -42), Vector2(-36, -6), Vector2(-30, 40)], Color(0.16, 0.24, 0.36), c, k)
			_poly([Vector2(-30, 40), Vector2(-26, 18), Vector2(0, 30), Vector2(26, 18), Vector2(30, 40), Vector2(0, 56)], Color(0.14, 0.21, 0.32), c, k)
			_poly([Vector2(-6, 6), Vector2(6, 6), Vector2(4, 9), Vector2(-4, 9)], Color(0.55, 0.30, 0.28), c, k)
		"nasser":
			# short hair, headset with a microphone arm
			_poly([Vector2(-36, -40), Vector2(-30, -58), Vector2(0, -64), Vector2(30, -58), Vector2(36, -40), Vector2(0, -50)], Color(0.12, 0.10, 0.09), c, k)
			_poly([Vector2(-44, -60), Vector2(0, -74), Vector2(44, -60), Vector2(44, -54), Vector2(0, -68), Vector2(-44, -54)], Color(0.15, 0.15, 0.17), c, k)
			for sx in [-1.0, 1.0]:
				_poly([Vector2(sx * 36, -20), Vector2(sx * 48, -22), Vector2(sx * 48, 2), Vector2(sx * 36, 0)], Color(0.18, 0.18, 0.20), c, k)
			_poly([Vector2(44, 0), Vector2(20, 14), Vector2(18, 10), Vector2(42, -4)], Color(0.18, 0.18, 0.20), c, k)
			_poly([Vector2(-14, 6), Vector2(14, 6), Vector2(10, 10), Vector2(-10, 10)], Color(0.45, 0.28, 0.24), c, k)
		"saqr":
			# tactical cap, sunglasses, short beard
			_poly([Vector2(-40, -36), Vector2(-36, -62), Vector2(0, -72), Vector2(36, -62), Vector2(40, -36)], Color(0.30, 0.32, 0.24), c, k)
			_poly([Vector2(-40, -36), Vector2(50, -36), Vector2(56, -28), Vector2(-36, -30)], Color(0.24, 0.26, 0.20), c, k)
			_poly([Vector2(-30, -20), Vector2(-4, -20), Vector2(-6, -8), Vector2(-28, -8)], Color(0.06, 0.07, 0.09), c, k)
			_poly([Vector2(4, -20), Vector2(30, -20), Vector2(28, -8), Vector2(6, -8)], Color(0.06, 0.07, 0.09), c, k)
			_poly([Vector2(-30, 0), Vector2(-26, 18), Vector2(0, 30), Vector2(26, 18), Vector2(30, 0), Vector2(14, 12), Vector2(-14, 12)], Color(0.16, 0.12, 0.10), c, k)


## `total` stars centred at c, the first `lit` gold, the rest dim.
func _stars(lit: int, total: int, c: Vector2, r: float) -> void:
	var gap := r * 2.6
	for k in total:
		var p := Polygon2D.new()
		var pts := PackedVector2Array()
		for j in 10:
			var a := -PI * 0.5 + TAU * j / 10.0
			var rr := r if j % 2 == 0 else r * 0.42
			pts.append(Vector2(cos(a) * rr, sin(a) * rr))
		p.polygon = pts
		p.position = c + Vector2((k - (total - 1) * 0.5) * gap, 0)
		p.color = GOLD if k < lit else Color(DIM, 0.35)
		root.add_child(p)


func _bar(r: Rect2, c: Color) -> void:
	_rect(r, c)


func _frame(r: Rect2, c: Color, t: float) -> void:
	_rect(Rect2(r.position, Vector2(r.size.x, t)), c)
	_rect(Rect2(Vector2(r.position.x, r.end.y - t), Vector2(r.size.x, t)), c)
	_rect(Rect2(r.position, Vector2(t, r.size.y)), c)
	_rect(Rect2(Vector2(r.end.x - t, r.position.y), Vector2(t, r.size.y)), c)


func _label(t: String, size: int, c: Color, r: Rect2, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = t
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _button(id: String, r: Rect2) -> Panel:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	buttons.append({"id": id, "rect": r, "panel": p})
	return p


func _paint() -> void:
	for b in buttons:
		var p: Panel = b.panel
		var sb := StyleBoxFlat.new()
		var sel := bool(p.get_meta("sel", false))
		var accent := bool(p.get_meta("accent", false))
		sb.bg_color = CARD_SEL if sel else (CARD_HOVER if b.id == hover else CARD)
		sb.border_color = GREEN if accent else (AMBER if sel else Color(FRAME, 0.55 if b.id == hover else 0.25))
		sb.set_border_width_all(4 if (sel or accent or b.id == hover) else 2)
		sb.set_corner_radius_all(14)
		p.add_theme_stylebox_override("panel", sb)


# --- pointing --------------------------------------------------------------------------

## The button under a world ray: {id, point} ({} if the ray misses the screen; id "" off
## the buttons). Updates the hover.
func hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var res := {}
	if visible:
		var xf := global_transform
		var n := xf.basis.z.normalized()
		var dn := dir.dot(n)
		if absf(dn) > 1e-5:
			var t := (xf.origin - origin).dot(n) / dn
			if t > 0.0 and t < 8.0:
				var p := origin + dir * t
				var l := xf.affine_inverse() * p
				if absf(l.x) <= W * 0.5 and absf(l.y) <= H * 0.5:
					var px := Vector2((l.x / W + 0.5) * TEX.x, (0.5 - l.y / H) * TEX.y)
					res = {"id": "", "point": p}
					for b in buttons:
						if (b.rect as Rect2).has_point(px):
							res.id = b.id
							break
	var hv: String = res.get("id", "")
	if hv != hover:
		hover = hv
		_paint()
		_redraw()
	return res


## World centre of a button (tests).
func button_center(id: String) -> Vector3:
	for b in buttons:
		if b.id == id:
			var c: Vector2 = (b.rect as Rect2).get_center()
			return global_transform * Vector3((c.x / TEX.x - 0.5) * W, (0.5 - c.y / TEX.y) * H, 0.0)
	return Vector3.INF


func has_button(id: String) -> bool:
	for b in buttons:
		if b.id == id:
			return true
	return false


## Press a button: chapter tabs and stage cards are handled here, the rest is emitted.
func press(id: String) -> void:
	if id.begins_with("ch_"):
		chapter = int(id.substr(3))
		var list := Campaign.stages_of(chapter)
		if progress and not list.is_empty():
			selected = list[0].id
			for s in list:
				if progress.stage_state(s) == "open":
					selected = s.id
		_build()
		return
	if id.begins_with("st_"):
		selected = id.substr(3)
		_build()
		return
	if id == "brief_next":
		if brief_i < brief_lines().size() - 1:
			brief_i += 1
			_build()
			return
		pressed.emit("brief_start")
		return
	if id == "brief_skip":
		pressed.emit("brief_start")
		return
	if id == "none" or id == "":
		return
	pressed.emit(id)
