class_name ControlPanel
extends Node3D
## The tablet in the player's LEFT hand (Arabic + English): weapon selector (icon,
## name, ammo, cooldown bar), target readout (distance, flight time, locked), and
## buttons: slow motion, reset island, rotate the island left / right.
## Tapping: point the right controller ray at a button and pull the trigger
## (hit() + press()); the left stick Y flick also switches weapons (xr_game.gd).
## Built once from quads + Label3D; update() only touches what changed.

signal pressed(id: String)

const W := 0.17
const H := 0.125
const BG := Color(0.07, 0.08, 0.09, 0.82)
const BTN := Color(0.20, 0.22, 0.24, 0.9)
const BTN_ON := Color(0.85, 0.55, 0.18, 0.95)
const BTN_HOVER := Color(0.32, 0.36, 0.40, 0.95)

var buttons: Array[Dictionary] = []   # {id, rect: Rect2 (panel-local, metres), bg, mat}
var hover := ""
var selected := ""
var target_label: Label3D
var _weapon_ui := {}                  # id -> {ammo: Label3D, bar: MeshInstance3D}
var _slow_on := false
var _font: Font
var _texts := {}


func _ready() -> void:
	_font = XRGame.ui_font()
	var bg := _quad(Vector2(W, H), BG, Vector3(0, 0, -0.0005))
	bg.name = "Back"
	add_child(bg)
	_text("لوحة التحكم · Control panel", Vector3(0, H * 0.5 - 0.009, 0.0004), 30, Color(1, 0.92, 0.75))
	var x0 := -W * 0.5 + 0.004
	var bw := (W - 0.008 - 0.004 * 2) / 3.0
	for i in WeaponTable.IDS.size():
		var id: String = WeaponTable.IDS[i]
		var w := WeaponTable.get_weapon(id)
		var cx := x0 + bw * 0.5 + i * (bw + 0.004)
		var cy := 0.012
		_button("w_" + id, Rect2(cx - bw * 0.5, cy - 0.026, bw, 0.052))
		var icon := _icon(id)
		icon.position = Vector3(cx, cy + 0.012, 0.0006)
		add_child(icon)
		_text(String(w.name_ar), Vector3(cx, cy - 0.003, 0.0006), 24, Color(1, 1, 1))
		_text(String(w.name_en), Vector3(cx, cy - 0.011, 0.0006), 18, Color(0.8, 0.85, 0.9))
		var ammo := _text("×%d" % int(w.ammo), Vector3(cx + bw * 0.5 - 0.007, cy + 0.019, 0.0006), 20, Color(1, 0.9, 0.6))
		var bar_bg := _quad(Vector2(bw - 0.008, 0.0028), Color(0, 0, 0, 0.6), Vector3(cx, cy - 0.019, 0.0004))
		add_child(bar_bg)
		var bar := _quad(Vector2(bw - 0.008, 0.0028), Color(0.35, 0.85, 0.45, 0.95), Vector3(cx, cy - 0.019, 0.0006))
		add_child(bar)
		_weapon_ui[id] = {"ammo": ammo, "bar": bar, "bw": bw - 0.008, "cx": cx}
	target_label = _text("-", Vector3(0, -0.028, 0.0006), 20, Color(1, 0.85, 0.6))
	var names := [["slow", "حركة بطيئة", "Slow-mo"], ["reset", "إعادة الجزيرة", "Reset island"], ["rot_l", "< تدوير", "Rotate <"], ["rot_r", "تدوير >", "Rotate >"]]
	var gw := (W - 0.008 - 0.003 * 3) / 4.0
	for i in names.size():
		var cx := x0 + gw * 0.5 + i * (gw + 0.003)
		var cy := -H * 0.5 + 0.017
		_button(names[i][0], Rect2(cx - gw * 0.5, cy - 0.012, gw, 0.024))
		_text(names[i][1], Vector3(cx, cy + 0.003, 0.0006), 19, Color(1, 1, 1))
		_text(names[i][2], Vector3(cx, cy - 0.006, 0.0006), 16, Color(0.8, 0.85, 0.9))
	set_selected(WeaponTable.IDS[0])


func _quad(size: Vector2, c: Color, pos: Vector3) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.render_priority = 5
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _text(t: String, pos: Vector3, size: int, c: Color) -> Label3D:
	var l := Label3D.new()
	l.font = _font
	l.text = t
	l.font_size = size
	l.pixel_size = 0.00016
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	l.render_priority = 7
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


func _button(id: String, r: Rect2) -> void:
	var mi := _quad(r.size, BTN, Vector3(r.get_center().x, r.get_center().y, 0.0))
	mi.name = "Btn_" + id
	add_child(mi)
	buttons.append({"id": id, "rect": r, "bg": mi, "mat": mi.material_override})


## Small flat icons: ballistic = tall rocket, cruise = winged arrow, artillery = shell.
func _icon(id: String) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector2, b: Vector2, c: Vector2):
		for v in [a, b, c]:
			st.add_vertex(Vector3(v.x, v.y, 0))
	var s := 0.006
	match id:
		"ballistic":
			tri.call(Vector2(0, s * 1.4), Vector2(-s * 0.35, s * 0.6), Vector2(s * 0.35, s * 0.6))
			tri.call(Vector2(-s * 0.35, s * 0.6), Vector2(-s * 0.35, -s), Vector2(s * 0.35, s * 0.6))
			tri.call(Vector2(s * 0.35, s * 0.6), Vector2(-s * 0.35, -s), Vector2(s * 0.35, -s))
			tri.call(Vector2(-s * 0.35, -s * 0.4), Vector2(-s * 0.8, -s), Vector2(-s * 0.35, -s))
			tri.call(Vector2(s * 0.35, -s * 0.4), Vector2(s * 0.35, -s), Vector2(s * 0.8, -s))
		"cruise":
			tri.call(Vector2(s * 1.6, 0), Vector2(s * 1.0, s * 0.25), Vector2(s * 1.0, -s * 0.25))
			tri.call(Vector2(s * 1.0, s * 0.25), Vector2(-s * 1.4, s * 0.25), Vector2(s * 1.0, -s * 0.25))
			tri.call(Vector2(s * 1.0, -s * 0.25), Vector2(-s * 1.4, s * 0.25), Vector2(-s * 1.4, -s * 0.25))
			tri.call(Vector2(s * 0.2, s * 0.25), Vector2(-s * 0.4, s * 0.9), Vector2(-s * 0.4, s * 0.25))
			tri.call(Vector2(s * 0.2, -s * 0.25), Vector2(-s * 0.4, -s * 0.25), Vector2(-s * 0.4, -s * 0.9))
		_:
			var n := 16
			for k in n:
				var a0 := TAU * k / n
				var a1 := TAU * (k + 1) / n
				tri.call(Vector2.ZERO, Vector2(cos(a1), sin(a1)) * s * 0.7, Vector2(cos(a0), sin(a0)) * s * 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.95, 0.9, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 6
	var mi := MeshInstance3D.new()
	mi.name = "Icon_" + id
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func set_selected(id: String) -> void:
	selected = id
	_paint()


func _paint() -> void:
	for b in buttons:
		var on: bool = (b.id == "w_" + selected) or (b.id == "slow" and _slow_on)
		var c := BTN_ON if on else (BTN_HOVER if b.id == hover else BTN)
		(b.mat as StandardMaterial3D).albedo_color = c


func _set_text(l: Label3D, t: String) -> void:
	if l.text != t:
		l.text = t


## Panel state: ammo {id: int}, cooldown {id: 0..1 remaining}, target text, slow motion.
func update_state(ammo: Dictionary, cool: Dictionary, target_text: String, slow: bool) -> void:
	for id in _weapon_ui:
		var ui: Dictionary = _weapon_ui[id]
		_set_text(ui.ammo, "×%d" % int(ammo.get(id, 0)))
		var f := 1.0 - clampf(float(cool.get(id, 0.0)), 0.0, 1.0)
		var bar: MeshInstance3D = ui.bar
		bar.scale = Vector3(maxf(f, 0.001), 1, 1)
		bar.position.x = float(ui.cx) - float(ui.bw) * 0.5 * (1.0 - f)
		(bar.material_override as StandardMaterial3D).albedo_color = Color(0.35, 0.85, 0.45, 0.95) if f >= 1.0 else Color(0.9, 0.6, 0.2, 0.95)
	_set_text(target_label, target_text)
	if slow != _slow_on:
		_slow_on = slow
		_paint()


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
