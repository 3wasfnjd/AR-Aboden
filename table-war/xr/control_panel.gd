class_name ControlPanel
extends Node3D
## The fire-control tablet in the player's LEFT hand (build 3: military styling).
##   header      COMMAND title + system status (READY / RELOADING / LOCKED)
##   destruction island destroyed %, bar, targets left, and one chip per target
##               category (city, oil, power, water, port, military, navy): hit / total
##   weapons     three cards: silhouette, Arabic name, English code, ammo pips,
##               reload bar and status
##   target      range, flight time, LOCKED
##   buttons     slow motion, reset island, rotate island left / right
## Tapping: point the right controller ray at a button and pull the trigger
## (hit() + press()); the left stick Y flick also switches weapons (xr_game.gd).
## Built once from quads + Label3D (MSDF font: crisp at any distance); the update
## calls only touch what changed.

signal pressed(id: String)

const W := 0.21
const H := 0.125
const BG := Color(0.035, 0.05, 0.04)
const FRAME := Color(0.40, 0.85, 0.45, 0.95)
const FRAME_DIM := Color(0.20, 0.38, 0.22)
const AMBER := Color(1.0, 0.72, 0.22)
const ALERT := Color(1.0, 0.22, 0.16)
const TEXT := Color(0.86, 1.0, 0.86)
const TEXT_DIM := Color(0.55, 0.75, 0.56)
const CARD := Color(0.07, 0.11, 0.08)
const CARD_ON := Color(0.30, 0.22, 0.05)
const CARD_HOVER := Color(0.12, 0.20, 0.13)
const BTN := Color(0.09, 0.14, 0.10)
const BTN_ON := Color(0.55, 0.38, 0.06)
const BTN_HOVER := Color(0.16, 0.26, 0.17)
const PIP_MAX := 10
const CAT_INFO := {
	"city": ["مدينة", "CITY"], "oil": ["نفط", "OIL"], "power": ["كهرباء", "POWER"], "water": ["تحلية", "WATER"],
	"port": ["ميناء", "PORT"], "military": ["عسكري", "MIL"], "navy": ["سفن", "NAVY"],
}
const CODES := {"ballistic": "BM-1  BALLISTIC", "cruise": "CM-2  CRUISE", "artillery": "AR-3  ARTILLERY"}

var buttons: Array[Dictionary] = []   # {id, rect: Rect2 (panel-local, metres), bg, mat, kind}
var hover := ""
var selected := ""
var target_label: Label3D
var status_label: Label3D
var pct_label: Label3D
var left_label: Label3D
var meter_bar: MeshInstance3D
var _cat_ui := {}                     # cat -> {label: Label3D, bar: MeshInstance3D, w, x0}
var _weapon_ui := {}                  # id -> {pips: [MeshInstance3D], bar, bw, cx, state: Label3D}
var _slow_on := false
var _font: Font


func _ready() -> void:
	_font = XRGame.ui_font()
	var bg := _quad(Vector2(W, H), BG, Vector3(0, 0, -0.0006))
	bg.name = "Back"
	add_child(bg)
	_frame(Rect2(-W * 0.5, -H * 0.5, W, H), FRAME, 0.0006)
	_brackets()
	# --- header -----------------------------------------------------------------
	var top := H * 0.5
	_text("القيادة والسيطرة", Vector3(W * 0.5 - 0.006, top - 0.008, 0.0004), 40, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("FIRE CONTROL", Vector3(-W * 0.5 + 0.006, top - 0.008, 0.0004), 34, TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	status_label = _text("READY · جاهز", Vector3(0, top - 0.008, 0.0004), 30, FRAME)
	_line(Vector2(-W * 0.5 + 0.004, top - 0.0145), Vector2(W * 0.5 - 0.004, top - 0.0145), FRAME_DIM)
	# --- destruction meter ---------------------------------------------------------
	var my := top - 0.026
	pct_label = _text("0%", Vector3(-W * 0.5 + 0.022, my - 0.002, 0.0004), 80, ALERT)
	_text("تدمير الجزيرة", Vector3(W * 0.5 - 0.006, my + 0.003, 0.0004), 32, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("ISLAND DESTROYED", Vector3(-W * 0.5 + 0.044, my + 0.003, 0.0004), 26, TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	var bar_w := W - 0.05
	var bar_x0 := -W * 0.5 + 0.044
	add_child(_quad(Vector2(bar_w, 0.0035), Color(0.15, 0.04, 0.03), Vector3(bar_x0 + bar_w * 0.5, my - 0.0045, 0.0002)))
	meter_bar = _quad(Vector2(bar_w, 0.0035), ALERT, Vector3(bar_x0 + bar_w * 0.5, my - 0.0045, 0.0004))
	meter_bar.set_meta("w", bar_w)
	meter_bar.set_meta("x0", bar_x0)
	add_child(meter_bar)
	left_label = _text("", Vector3(W * 0.5 - 0.006, my - 0.0095, 0.0004), 24, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	# category chips
	var cats: Array = IslandProps.CATEGORIES
	var cw := (W - 0.012) / cats.size()
	var cy := my - 0.0175
	for i in cats.size():
		var c: String = cats[i]
		var cx := W * 0.5 - 0.006 - cw * (i + 0.5)   # right to left (Arabic reading order)
		add_child(_quad(Vector2(cw - 0.0015, 0.0085), CARD, Vector3(cx, cy, 0.0001)))
		_text(String(CAT_INFO[c][0]), Vector3(cx, cy + 0.0018, 0.0004), 22, TEXT)
		var lb := _text("0/0", Vector3(cx, cy - 0.0016, 0.0004), 20, TEXT_DIM)
		var bw := cw - 0.004
		add_child(_quad(Vector2(bw, 0.0009), Color(0, 0, 0), Vector3(cx, cy - 0.0034, 0.0003)))
		var bar := _quad(Vector2(bw, 0.0009), ALERT, Vector3(cx, cy - 0.0034, 0.0005))
		add_child(bar)
		_cat_ui[c] = {"label": lb, "bar": bar, "w": bw, "cx": cx}
	_line(Vector2(-W * 0.5 + 0.004, cy - 0.0062), Vector2(W * 0.5 - 0.004, cy - 0.0062), FRAME_DIM)
	# --- weapon cards (right to left) ---------------------------------------------
	var n: int = WeaponTable.IDS.size()
	var gap := 0.003
	var bw2 := (W - 0.012 - gap * (n - 1)) / n
	var wy := cy - 0.0062 - 0.0215
	for i in n:
		var id: String = WeaponTable.IDS[i]
		var w := WeaponTable.get_weapon(id)
		var cx2 := W * 0.5 - 0.006 - bw2 * 0.5 - i * (bw2 + gap)
		_button("w_" + id, Rect2(cx2 - bw2 * 0.5, wy - 0.02, bw2, 0.04), "card")
		_frame(Rect2(cx2 - bw2 * 0.5, wy - 0.02, bw2, 0.04), FRAME_DIM, 0.0003)
		var icon := _icon(id)
		icon.position = Vector3(cx2 - bw2 * 0.28, wy + 0.008, 0.0006)
		add_child(icon)
		_text(String(w.name_ar), Vector3(cx2 + bw2 * 0.42, wy + 0.012, 0.0006), 30, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(String(CODES.get(id, id.to_upper())), Vector3(cx2 + bw2 * 0.42, wy + 0.0055, 0.0006), 20, TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		# ammo pips
		var pips: Array = []
		var np := mini(int(w.ammo), PIP_MAX)
		var pw := (bw2 - 0.016) / PIP_MAX
		for k in np:
			var pip := _quad(Vector2(pw * 0.7, 0.0024), AMBER, Vector3(cx2 + bw2 * 0.5 - 0.004 - pw * (k + 0.5), wy - 0.004, 0.0006))
			add_child(pip)
			pips.append(pip)
		var ammo_txt := _text("×%d" % int(w.ammo), Vector3(cx2 - bw2 * 0.5 + 0.004, wy - 0.004, 0.0006), 22, AMBER, HORIZONTAL_ALIGNMENT_LEFT)
		var rb := bw2 - 0.008
		add_child(_quad(Vector2(rb, 0.0016), Color(0, 0, 0), Vector3(cx2, wy - 0.0105, 0.0004)))
		var bar2 := _quad(Vector2(rb, 0.0016), FRAME, Vector3(cx2, wy - 0.0105, 0.0006))
		add_child(bar2)
		var st := _text("READY · جاهز", Vector3(cx2, wy - 0.0155, 0.0006), 20, FRAME)
		_weapon_ui[id] = {"pips": pips, "ammo": ammo_txt, "bar": bar2, "bw": rb, "cx": cx2, "state": st, "max": int(w.ammo)}
	# --- target readout ------------------------------------------------------------
	var ty := -H * 0.5 + 0.0235
	target_label = _text("-", Vector3(0, ty, 0.0006), 26, AMBER)
	# --- buttons ------------------------------------------------------------------
	var names := [["slow", "بطيء", "SLOW-MO"], ["reset", "إعادة", "RESET"], ["rot_l", "< تدوير", "ROTATE <"], ["rot_r", "تدوير >", "ROTATE >"]]
	var gw := (W - 0.012 - 0.003 * 3) / 4.0
	var by := -H * 0.5 + 0.0105
	for i in names.size():
		var cx3 := W * 0.5 - 0.006 - gw * 0.5 - i * (gw + 0.003)
		_button(names[i][0], Rect2(cx3 - gw * 0.5, by - 0.0075, gw, 0.015), "btn")
		_frame(Rect2(cx3 - gw * 0.5, by - 0.0075, gw, 0.015), FRAME_DIM, 0.0003)
		_text(names[i][1], Vector3(cx3, by + 0.002, 0.0006), 26, TEXT)
		_text(names[i][2], Vector3(cx3, by - 0.0035, 0.0006), 18, TEXT_DIM)
	set_selected(WeaponTable.IDS[0])


# ------------------------------------------------------------------------------------
# building blocks
# ------------------------------------------------------------------------------------

## Opaque, unshaded: the layers (back, cards, bars) sort by depth, never by the
## transparent-object order (which hid bars behind their cards at some angles).
func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	c.a = 1.0
	m.albedo_color = c
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


func _line(a: Vector2, b: Vector2, c: Color, t := 0.0004) -> void:
	var mid := (a + b) * 0.5
	var d := b - a
	var mi := _quad(Vector2(maxf(absf(d.x), t), maxf(absf(d.y), t)), c, Vector3(mid.x, mid.y, 0.0003))
	add_child(mi)


func _frame(r: Rect2, c: Color, t: float) -> void:
	_line(r.position, Vector2(r.end.x, r.position.y), c, t)
	_line(Vector2(r.position.x, r.end.y), r.end, c, t)
	_line(r.position, Vector2(r.position.x, r.end.y), c, t)
	_line(Vector2(r.end.x, r.position.y), r.end, c, t)


## Corner brackets outside the frame (targeting-display look).
func _brackets() -> void:
	var L := 0.012
	var o := 0.0025
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var cx: float = sx * (W * 0.5 + o)
			var cy: float = sy * (H * 0.5 + o)
			_line(Vector2(cx, cy), Vector2(cx - sx * L, cy), FRAME, 0.0012)
			_line(Vector2(cx, cy), Vector2(cx, cy - sy * L), FRAME, 0.0012)


func _text(t: String, pos: Vector3, size: int, c: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label3D:
	var l := Label3D.new()
	l.font = _font
	l.text = t
	l.font_size = size
	l.pixel_size = 0.0001
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	l.horizontal_alignment = align
	l.render_priority = 7
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


func _button(id: String, r: Rect2, kind: String) -> void:
	var mi := _quad(r.size, CARD if kind == "card" else BTN, Vector3(r.get_center().x, r.get_center().y, 0.0))
	mi.name = "Btn_" + id
	add_child(mi)
	buttons.append({"id": id, "rect": r, "bg": mi, "mat": mi.material_override, "kind": kind})


## Weapon silhouettes: ballistic = tall finned rocket, cruise = winged missile,
## artillery = shell with a driving band.
func _icon(id: String) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector2, b: Vector2, c: Vector2):
		for v in [a, b, c]:
			st.add_vertex(Vector3(v.x, v.y, 0))
	var s := 0.0062
	match id:
		"ballistic":
			tri.call(Vector2(0, s * 1.5), Vector2(-s * 0.28, s * 0.85), Vector2(s * 0.28, s * 0.85))
			tri.call(Vector2(-s * 0.28, s * 0.85), Vector2(-s * 0.28, -s), Vector2(s * 0.28, s * 0.85))
			tri.call(Vector2(s * 0.28, s * 0.85), Vector2(-s * 0.28, -s), Vector2(s * 0.28, -s))
			tri.call(Vector2(-s * 0.28, -s * 0.35), Vector2(-s * 0.75, -s * 1.05), Vector2(-s * 0.28, -s))
			tri.call(Vector2(s * 0.28, -s * 0.35), Vector2(s * 0.28, -s), Vector2(s * 0.75, -s * 1.05))
		"cruise":
			tri.call(Vector2(s * 1.6, 0), Vector2(s * 1.05, s * 0.2), Vector2(s * 1.05, -s * 0.2))
			tri.call(Vector2(s * 1.05, s * 0.2), Vector2(-s * 1.4, s * 0.2), Vector2(s * 1.05, -s * 0.2))
			tri.call(Vector2(s * 1.05, -s * 0.2), Vector2(-s * 1.4, s * 0.2), Vector2(-s * 1.4, -s * 0.2))
			tri.call(Vector2(s * 0.2, s * 0.2), Vector2(-s * 0.35, s * 0.95), Vector2(-s * 0.35, s * 0.2))
			tri.call(Vector2(s * 0.2, -s * 0.2), Vector2(-s * 0.35, -s * 0.2), Vector2(-s * 0.35, -s * 0.95))
			tri.call(Vector2(-s * 1.1, s * 0.2), Vector2(-s * 1.45, s * 0.6), Vector2(-s * 1.4, s * 0.2))
		_:
			tri.call(Vector2(0, s * 1.2), Vector2(-s * 0.42, s * 0.3), Vector2(s * 0.42, s * 0.3))
			tri.call(Vector2(-s * 0.42, s * 0.3), Vector2(-s * 0.42, -s * 0.9), Vector2(s * 0.42, s * 0.3))
			tri.call(Vector2(s * 0.42, s * 0.3), Vector2(-s * 0.42, -s * 0.9), Vector2(s * 0.42, -s * 0.9))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = TEXT
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 6
	var mi := MeshInstance3D.new()
	mi.name = "Icon_" + id
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------------------------
# state
# ------------------------------------------------------------------------------------

func set_selected(id: String) -> void:
	selected = id
	_paint()


func _paint() -> void:
	for b in buttons:
		var on: bool = (b.id == "w_" + selected) or (b.id == "slow" and _slow_on)
		var card: bool = b.kind == "card"
		var c: Color
		if on:
			c = CARD_ON if card else BTN_ON
		elif b.id == hover:
			c = CARD_HOVER if card else BTN_HOVER
		else:
			c = CARD if card else BTN
		(b.mat as StandardMaterial3D).albedo_color = c


func _set_text(l: Label3D, t: String) -> void:
	if l.text != t:
		l.text = t


func _set_bar(bar: MeshInstance3D, cx: float, w: float, f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	bar.visible = f > 0.002
	bar.scale = Vector3(maxf(f, 0.001), 1, 1)
	bar.position.x = cx - w * 0.5 * (1.0 - f)


## Panel state: ammo {id: int}, cooldown {id: 0..1 remaining}, target text, slow motion.
func update_state(ammo: Dictionary, cool: Dictionary, target_text: String, slow: bool) -> void:
	for id in _weapon_ui:
		var ui: Dictionary = _weapon_ui[id]
		var a := int(ammo.get(id, 0))
		var mx: int = ui.max
		var pips: Array = ui.pips
		# one pip per round (or per tenth of the magazine when it holds more than 10)
		var lit := a if mx <= PIP_MAX else int(ceil(float(a) / mx * PIP_MAX))
		for k in pips.size():
			(pips[k] as MeshInstance3D).visible = k < lit
		_set_text(ui.ammo, "×%d" % a)
		var f := 1.0 - clampf(float(cool.get(id, 0.0)), 0.0, 1.0)
		_set_bar(ui.bar, float(ui.cx), float(ui.bw), f)
		var ready := f >= 1.0 and a > 0
		((ui.bar as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = FRAME if ready else AMBER
		var st: Label3D = ui.state
		if a <= 0:
			_set_text(st, "EMPTY · فارغ")
			st.modulate = ALERT
		elif ready:
			_set_text(st, "READY · جاهز")
			st.modulate = FRAME
		else:
			_set_text(st, "RELOAD · تعبئة")
			st.modulate = AMBER
	_set_text(target_label, target_text)
	var locked := target_text.contains("LOCKED")
	target_label.modulate = ALERT if locked else AMBER
	var sw: Dictionary = _weapon_ui.get(selected, {})
	if locked:
		_set_text(status_label, "LOCKED · مقفل")
		status_label.modulate = ALERT
	elif not sw.is_empty() and (sw.state as Label3D).text.begins_with("READY"):
		_set_text(status_label, "READY · جاهز")
		status_label.modulate = FRAME
	else:
		_set_text(status_label, "STANDBY · انتظار")
		status_label.modulate = AMBER
	if slow != _slow_on:
		_slow_on = slow
		_paint()


## Destruction meter: IslandProps.destruction() -> {pct, left, cats}.
func update_destruction(d: Dictionary) -> void:
	var pct: float = d.get("pct", 0.0)
	_set_text(pct_label, "%d%%" % int(floor(pct)) if pct < 99.95 else "100%")
	_set_bar(meter_bar, float(meter_bar.get_meta("x0")) + float(meter_bar.get_meta("w")) * 0.5, float(meter_bar.get_meta("w")), pct / 100.0)
	var left := int(d.get("left", 0))
	_set_text(left_label, "أهداف متبقية %d · TARGETS LEFT %d" % [left, left] if left > 0 else "تم تدمير الجزيرة · ISLAND DESTROYED")
	var cats: Dictionary = d.get("cats", {})
	for c in _cat_ui:
		var ui: Dictionary = _cat_ui[c]
		var v: Array = cats.get(c, [0, 0])
		_set_text(ui.label, "%d/%d" % [int(v[0]), int(v[1])])
		_set_bar(ui.bar, float(ui.cx), float(ui.w), float(v[0]) / maxf(float(v[1]), 1.0))


## The button under a world ray, or "" (also updates the hover highlight).
## Returns {id, point} with point the world hit, or {} when the ray misses the panel.
func hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var xf := global_transform
	var n := xf.basis.z.normalized()
	var dn := dir.dot(n)
	var res := {}
	if absf(dn) > 1e-5:
		var t := (xf.origin - origin).dot(n) / dn
		if t > 0.0 and t < 2.0:
			var p := origin + dir * t
			var l := xf.affine_inverse() * p
			if absf(l.x) <= W * 0.5 and absf(l.y) <= H * 0.5:
				res = {"id": "", "point": p}
				for b in buttons:
					if (b.rect as Rect2).has_point(Vector2(l.x, l.y)):
						res.id = b.id
						break
	var hv: String = res.get("id", "")
	if hv != hover:
		hover = hv
		_paint()
	return res


func press(id: String) -> void:
	if id.begins_with("w_"):
		set_selected(id.substr(2))
	pressed.emit(id)


## World centre of a button (tests / screenshots).
func button_center(id: String) -> Vector3:
	for b in buttons:
		if b.id == id:
			var c: Vector2 = (b.rect as Rect2).get_center()
			return global_transform * Vector3(c.x, c.y, 0.0)
	return global_position
