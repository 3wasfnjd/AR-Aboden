class_name WebHud
extends CanvasLayer
## The web version's free play (build 19): no campaign, no story. The island on the table,
## every weapon of the battleship and the Viper's forces fighting back (tanks, APCs, mobile
## AA, mobile launchers, fighters, the SAM sites and coastal launchers).
##
## Screen: a top bar (destruction %, enemies left, the battleship's hull), the weapon bar
## at the bottom (tap / click a card or press 1-9, 0, -, =, the cards show ammo and
## reload), and buttons on the side: map 1 / 2, enemy forces on / off, reset, slow motion,
## zoom. Tap / click the island to fire the selected weapon at that spot; drag to orbit,
## two fingers or the wheel to zoom. The anti-air missile needs no target.

signal map_requested(id: int)

const BG := Color(0.04, 0.07, 0.10, 0.82)
const FRAME := Color(0.30, 0.85, 1.0)
const TEXT := Color(0.90, 0.96, 1.0)
const DIM := Color(0.62, 0.74, 0.82)
const AMBER := Color(1.0, 0.76, 0.30)
const RED := Color(1.0, 0.36, 0.28)
const GREEN := Color(0.45, 1.0, 0.55)
const KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL, KEY_BACKSLASH]
## The free-play enemy: every kind, fighters taking off every 25 s.
const SHORT := {"ballistic": "باليستي", "cruise": "كروز", "artillery": "مدفعية", "mlrs": "راجمة", "cluster": "عنقودي",
	"hypersonic": "فرط صوتي", "bunker": "خارق", "drone": "مسيّرة", "antiship": "مضاد سفن", "jet": "طائرة", "swarm": "سرب",
	"aa": "دفاع جوي", "nuke": "نووي", "atgm": "مضاد دروع", "glide": "انزلاقية", "torpedo": "طوربيد", "heli": "مروحية"}
## A real weapon of each kind (shown under its name).
const REAL := {"ballistic": "Iskander", "cruise": "Tomahawk", "hypersonic": "Kinzhal",
	"artillery": "M777 155mm", "mlrs": "HIMARS", "cluster": "ATACMS", "bunker": "GBU-57",
	"glide": "GBU-39", "jet": "F-15E", "heli": "AH-64 Apache", "drone": "Shahed-136",
	"swarm": "أسراب Lancet", "atgm": "Javelin", "antiship": "Harpoon", "torpedo": "Mk 48",
	"aa": "Patriot", "nuke": "B61"}
const GOLD := Color(0.886, 0.714, 0.361)
const PANEL := Color(0.035, 0.06, 0.09, 0.96)
const LINE := Color(0.30, 0.85, 1.0, 0.22)
## Sizes in the HUD's virtual screen (see _layout): a phone's finger and eye.
const FONT := 17
const ROW_H := 40.0
const BTN_H := 46.0
const BTN_W := 210.0
const MENU_W := 340.0
const CARD_W := 138.0
const CARD_H := 50.0
const HULL_W := 110.0
const REPAIR := 1.0               # % hull per second: the crew repairs the battleship in free play
const FORCES := {"tank": 2, "apc": 2, "spaa": 2, "mlauncher": 2, "fighter": 3, "air": 25.0}

var phys: PhysicsTest
var weapon := "ballistic"
var ammo := {}
var cooldown := {}
var _reload := {}
var hull := 100.0
var enemies_on := true
var sunk_t := 0.0
var _font: Font
var _cards := {}          # id -> {panel, name, ammo, bar}
var _top: Label
var _hull_bar: ColorRect
var _hull_lbl: Label
var _msg: Label
var _msg_t := 0.0
var _root: Control
var _btn_icon: TextureRect
var _icons := {}
var _grid: GridContainer
var _opt_map: Array
var _opt_enemy: Array
var _opt_cam: Array
var _opt_slow: Array
var _opt_night: Array
## The HUD sets the window's scaling itself (the web build); off for desktop previews.
var web_scaling := true
var map_id := 1
## Missile camera: a button switches the view between the free orbit and a camera riding
## just behind and above the newest shot; after the impact it holds on the blast a moment,
## then glides back to the orbit until the next launch.
var cam: OrbitCamera
var room: Room
var ocean: Ocean
var night := false
var missile_cam := false
var _btn_menu: Button
var _btn_weapons: Button
var _menu: Control
var _weapons: Control
var _chase_serial := -1
var _chase_dir := Vector3.FORWARD
var _chase_pos := Vector3.ZERO
var _chase_last := Vector3.ZERO     # the shot's last position (the blast is looked at)
var _chase_hold := 0.0
const CHASE_BACK := 7.0            # behind the shot, in shot lengths (a missile is ~3 mm)
const CHASE_UP := 0.6              # above it, part of the distance behind
const CHASE_HOLD := 2.2            # seconds on the blast after the impact


func setup(p: PhysicsTest) -> void:
	phys = p
	_font = _screen_font()
	for id in WeaponTable.ids():
		ammo[id] = int(WeaponTable.get_weapon(id).ammo)
		cooldown[id] = 0.0
		_reload[id] = 0.0
	_build()
	phys.forces.ship_damaged.connect(func(_q: Vector3, d: float) -> void: _hit(d))
	phys.resistance.ship_hit.connect(func(_q: Vector3) -> void: _hit(StageRun.HIT_DAMAGE))
	phys.resistance.intercepted.connect(func(_q: Vector3, _w: String) -> void: flash("أُسقط صاروخك · Shot down", AMBER))
	phys.forces.fighter_down.connect(func(_q: Vector3) -> void: flash("أسقطت طائرة معادية · Jet down", GREEN))
	phys.sortie_landed.connect(func(wid: String) -> void: ammo[wid] = mini(int(ammo[wid]) + 1, int(WeaponTable.get_weapon(wid).ammo)))
	# an aircraft shot down: a replacement lands on the deck a while later
	phys.jet_lost.connect(func(wid: String) -> void:
		flash("أُسقطت طائرتك · بديلة خلال 25 ثانية", RED)
		get_tree().create_timer(25.0).timeout.connect(func() -> void:
			ammo[wid] = mini(int(ammo[wid]) + 1, int(WeaponTable.get_weapon(wid).ammo))))
	start_enemy()
	select(weapon)


## Plain (bitmap) Cairo for the flat screen: the headset's MSDF glyphs left speckled
## edges on the phone's scaled canvas; the window's oversampling keeps these sharp.
static func _screen_font() -> Font:
	var latin: FontFile = load("res://assets/fonts/cairo-latin-500-normal.woff2")
	var arabic: FontFile = load("res://assets/fonts/cairo-arabic-500-normal.woff2")
	if latin == null:
		return null
	var f := latin.duplicate() as FontFile
	f.multichannel_signed_distance_field = false
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	if arabic:
		var ar := arabic.duplicate() as FontFile
		ar.multichannel_signed_distance_field = false
		ar.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		ar.hinting = TextServer.HINTING_LIGHT
		f.fallbacks = [ar]
	return f


## The Viper's forces and defences on (free play), or a quiet island.
func start_enemy() -> void:
	hull = 100.0
	if enemies_on:
		phys.forces.configure({"forces": FORCES})
		phys.resistance.configure({"sam": true, "coastal": 40.0})
	else:
		phys.forces.clear()
		phys.resistance.clear()


func _label(parent: Control, t: String, size: int, c: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _style(bg: Color, border: Color, w := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	return sb


func _button(parent: Control, t: String, cb: Callable, size := FONT) -> Button:
	var b := Button.new()
	b.text = t
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	_paint(b, false)
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## A button's look: `on` = the chosen option (amber frame, lit), else plain.
func _paint(b: Button, on: bool, edge := Color(0, 0, 0, 0)) -> void:
	var bc := edge if edge.a > 0.0 else (AMBER if on else Color(FRAME, 0.45))
	var bg := Color(0.12, 0.26, 0.34, 0.95) if on else BG
	b.add_theme_stylebox_override("normal", _style(bg, bc, 3 if on else 2))
	b.add_theme_stylebox_override("hover", _style(bg, bc, 3 if on else 2))
	b.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.32, 0.40, 0.95), FRAME, 3))


## A row of the settings: its name, then two options side by side.
func _choice(parent: Control, title: String, a: String, b: String, cb: Callable) -> Array:
	var row := HBoxContainer.new()
	row.layout_direction = Control.LAYOUT_DIRECTION_RTL
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var l := _label(row, title, FONT, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	l.custom_minimum_size = Vector2(104, 0)
	var ba := _button(row, a, cb.bind(0))
	var bb := _button(row, b, cb.bind(1))
	ba.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return [ba, bb]


## A full-screen dimmed layer with a centred panel; a tap outside the panel closes it.
func _modal(root: Control, title: String) -> Array:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	root.add_child(dim)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
			dim.visible = false)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(cc)
	var panel := PanelContainer.new()
	var sb := _style(PANEL, Color(FRAME, 0.45), 1)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	cc.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.layout_direction = Control.LAYOUT_DIRECTION_RTL
	col.add_child(head)
	var bar := ColorRect.new()
	bar.color = GOLD
	bar.custom_minimum_size = Vector2(4, 22)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(bar)
	var t := _label(head, title, FONT + 3, TEXT, HORIZONTAL_ALIGNMENT_LEFT)   # RTL row: "left" is its start
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x := _button(head, "إغلاق", func() -> void: dim.visible = false, FONT - 2)
	x.custom_minimum_size = Vector2(70, ROW_H - 8)
	var sep := ColorRect.new()
	sep.color = LINE
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sep)
	return [dim, col, panel]


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root
	# top bar: destruction and enemies (right), the battleship's hull (left)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style(BG, Color(FRAME, 0.35)))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 6
	top.offset_right = -6
	top.offset_top = 6
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	top.add_child(row)
	var hb := VBoxContainer.new()
	hb.add_theme_constant_override("separation", 1)
	row.add_child(hb)
	_hull_lbl = _label(hb, "البارجة 100%", FONT - 2, GREEN)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.15, 0.2, 0.24)
	bar_bg.custom_minimum_size = Vector2(HULL_W, 6)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(bar_bg)
	_hull_bar = ColorRect.new()
	_hull_bar.color = GREEN
	_hull_bar.size = Vector2(HULL_W, 6)
	_hull_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_hull_bar)
	_top = _label(row, "", FONT - 1, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# message line under the bar
	_msg = _label(root, "", FONT, AMBER)
	_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_msg.add_theme_constant_override("outline_size", 5)
	_msg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_msg.offset_top = 50
	_msg.offset_bottom = 96
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# two buttons at the bottom: the settings (left) and the weapons (right)
	_btn_menu = _button(root, "الإعدادات", toggle_menu, FONT + 1)
	_btn_weapons = _button(root, "", toggle_weapons, FONT + 1)
	for b in [_btn_menu, _btn_weapons]:
		(b as Button).add_theme_constant_override("outline_size", 0)
	# the settings, centred
	var m := _modal(root, "الإعدادات")
	_menu = m[0]
	var mc: VBoxContainer = m[1]
	(m[2] as Control).custom_minimum_size = Vector2(MENU_W, 0)
	_opt_map = _choice(mc, "الخريطة", "جزيرة السبخة", "جزيرة الهلال", func(i: int) -> void:
		_menu.visible = false
		map_requested.emit(i + 1))
	_opt_enemy = _choice(mc, "القوات المعادية", "تعمل", "متوقفة", func(i: int) -> void:
		if (i == 0) != enemies_on:
			toggle_enemy())
	_opt_cam = _choice(mc, "الكاميرا", "حرة", "فوق الصاروخ", func(i: int) -> void:
		if (i == 1) != missile_cam:
			toggle_cam())
	_opt_night = _choice(mc, "الوقت", "نهار", "ليل", func(i: int) -> void:
		if (i == 1) != night:
			toggle_night())
	_opt_slow = _choice(mc, "السرعة", "عادية", "بطيئة", func(i: int) -> void:
		if (i == 1) != phys.slow_motion:
			toggle_slow())
	var rs := _button(mc, "إعادة الجزيرة من جديد", func() -> void:
		_menu.visible = false
		reset())
	_paint(rs, false, Color(RED, 0.7))
	_label(mc, "اضغط على الجزيرة للإطلاق · اسحب للتدوير · إصبعين للتقريب", FONT - 3, DIM)
	# the weapons, centred: a grid of cards (name, ammo, a reload bar)
	var wm := _modal(root, "الأسلحة")
	_weapons = wm[0]
	var wc: VBoxContainer = wm[1]
	_grid = GridContainer.new()
	_grid.layout_direction = Control.LAYOUT_DIRECTION_RTL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	wc.add_child(_grid)
	for id in WeaponTable.ids():
		var w := WeaponTable.get_weapon(id)
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(CARD_W, CARD_H)
		card.pressed.connect(func() -> void:
			select(id)
			_weapons.visible = false)
		_grid.add_child(card)
		# icon at the right (Arabic reading), the name and a real example beside it,
		# the ammo at the left, a thin reload bar along the bottom
		var ic := TextureRect.new()
		ic.texture = _icon(id)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		ic.offset_left = -38
		ic.offset_right = -6
		ic.offset_top = 7
		ic.offset_bottom = -9
		card.add_child(ic)
		var nm := _label(card, String(SHORT.get(id, w.name_ar)), FONT - 1, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		nm.set_anchors_preset(Control.PRESET_FULL_RECT)
		nm.offset_right = -42
		nm.offset_top = 2
		nm.offset_bottom = -CARD_H * 0.42
		nm.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		var rl := _label(card, String(REAL.get(id, "")), FONT - 5, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		rl.set_anchors_preset(Control.PRESET_FULL_RECT)
		rl.offset_right = -42
		rl.offset_top = CARD_H * 0.55
		rl.offset_bottom = -6
		rl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		var am := _label(card, "", FONT, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
		am.set_anchors_preset(Control.PRESET_FULL_RECT)
		am.offset_left = 10
		am.offset_bottom = -4
		var cb := ColorRect.new()
		cb.color = Color(FRAME, 0.55)
		cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		cb.offset_left = 10
		cb.offset_right = -10
		cb.offset_top = -5
		cb.offset_bottom = -3
		card.add_child(cb)
		_cards[id] = {"panel": card, "ammo": am, "bar": cb}
	# the weapons button shows the chosen weapon's icon
	_btn_icon = TextureRect.new()
	_btn_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_btn_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_btn_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn_icon.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_btn_icon.offset_left = -44
	_btn_icon.offset_right = -10
	_btn_icon.offset_top = 6
	_btn_icon.offset_bottom = -6
	_btn_weapons.add_child(_btn_icon)
	for st in ["normal", "hover", "pressed"]:
		var sbw := _btn_weapons.get_theme_stylebox(st).duplicate() as StyleBoxFlat
		sbw.content_margin_right = 50
		_btn_weapons.add_theme_stylebox_override(st, sbw)
	get_tree().root.size_changed.connect(_layout)
	_layout()


## Phone first: the HUD is laid out in a small virtual screen (640 x 360 landscape,
## 360 x 640 portrait) that the window scales up, so text and buttons keep a finger's
## size on any phone. Portrait: the weapon grid gets 2 columns, the 3D view keeps its
## width (the island stays whole).
func _layout() -> void:
	var win := get_tree().root
	var real := Vector2(win.size)
	var portrait := real.y > real.x
	if web_scaling:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		win.content_scale_size = Vector2i(360, 640) if portrait else Vector2i(640, 360)
	if cam:
		cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	_grid.columns = 2 if portrait else 4
	for id in _cards:
		(_cards[id].panel as Control).custom_minimum_size = Vector2(162.0 if portrait else CARD_W, CARD_H)
	var vw := _root.get_viewport_rect().size.x if is_inside_tree() else 640.0
	var bw := minf(BTN_W, (vw - 18.0) * 0.5)
	_btn_menu.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_btn_menu.offset_left = 6
	_btn_menu.offset_right = 6 + bw
	_btn_menu.offset_top = -8 - BTN_H
	_btn_menu.offset_bottom = -8
	_btn_weapons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_btn_weapons.offset_left = -6 - bw
	_btn_weapons.offset_right = -6
	_btn_weapons.offset_top = -8 - BTN_H
	_btn_weapons.offset_bottom = -8


func _icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path := "res://assets/icons/%s.svg" % id
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


func _refresh_menu() -> void:
	_paint(_opt_map[0], map_id == 1)
	_paint(_opt_map[1], map_id == 2)
	_paint(_opt_enemy[0], enemies_on)
	_paint(_opt_enemy[1], not enemies_on)
	_paint(_opt_cam[0], not missile_cam)
	_paint(_opt_cam[1], missile_cam)
	_paint(_opt_night[0], not night)
	_paint(_opt_night[1], night)
	_paint(_opt_slow[0], not phys.slow_motion)
	_paint(_opt_slow[1], phys.slow_motion)


func select(id: String) -> void:
	weapon = id
	phys.weapon = id
	for k in _cards:
		var p: Button = _cards[k].panel
		var on := String(k) == id
		_paint(p, on, RED if k == "nuke" and not on else Color(0, 0, 0, 0))
	if _btn_icon:
		_btn_icon.texture = _icon(id)
	if id == "aa":
		flash("صاروخ الدفاع الجوي يلاحق أقرب طائرة: اضغط في أي مكان", DIM)


func flash(t: String, c := AMBER) -> void:
	_msg.text = t
	_msg.add_theme_color_override("font_color", c)
	_msg_t = 2.5


## Fire the selected weapon at an island-local point (from its launcher on the ship).
func try_fire(tgt: Vector3) -> bool:
	if sunk_t > 0.0:
		return false
	var w := WeaponTable.get_weapon(weapon)
	if float(cooldown[weapon]) > 0.0 or int(ammo[weapon]) <= 0:
		flash("السلاح يعيد التعبئة · Reloading", DIM)
		return false
	if weapon == "aa":
		if not phys.forces.fire_aa(phys.default_origin("aa")):
			flash("ما فيه طائرة معادية في الجو · No enemy jet in the air", DIM)
			return false
	else:
		phys.fire(tgt, Vector3.INF, weapon)
	ammo[weapon] = int(ammo[weapon]) - 1
	cooldown[weapon] = float(w.cooldown)
	return true


func _hit(dmg: float) -> void:
	if sunk_t > 0.0:
		return
	hull = maxf(hull - dmg, 0.0)
	if hull <= 0.0:
		sunk_t = 4.0
		flash("البارجة غرقت! نبدأ من جديد · The battleship is sunk", RED)


func toggle_enemy() -> void:
	enemies_on = not enemies_on
	start_enemy()
	_refresh_menu()


func toggle_slow() -> void:
	phys.set_slow_motion(not phys.slow_motion)
	_refresh_menu()


func toggle_menu() -> void:
	_menu.visible = not _menu.visible
	_weapons.visible = false
	_refresh_menu()


func toggle_weapons() -> void:
	_weapons.visible = not _weapons.visible
	_menu.visible = false


func toggle_night() -> void:
	night = not night
	if room:
		room.set_night(night)
	if ocean and ocean.mesh:
		var om := ocean.mesh.surface_get_material(0) as StandardMaterial3D
		if om:
			om.albedo_color = Color(0.42, 0.46, 0.58) if night else Color.WHITE   # the open sea under the moon
	_refresh_menu()


func toggle_cam() -> void:
	missile_cam = not missile_cam
	_refresh_menu()
	_chase_serial = -1
	_chase_hold = 0.0


## The flight the missile camera rides: the one it is on while it flies, else the newest.
func _chase_flight() -> Dictionary:
	var best := {}
	for f in phys.flights:
		if int(f.serial) == _chase_serial:
			return f
		if best.is_empty() or int(f.serial) > int(best.serial):
			best = f
	return best


func _step_cam(dt: float) -> void:
	if cam == null:
		return
	var want := 0.0
	if missile_cam:
		var f := _chase_flight()
		var k := phys.global_basis.get_scale().x
		if not f.is_empty():
			var node: Node3D = f.slot.node
			var p := node.global_position
			var v := phys.global_basis * WeaponFlight.velocity_at(f.plan, f.t)
			if v.length() > 1e-5:
				var d := v.normalized()
				if int(f.serial) != _chase_serial:
					_chase_dir = d   # a new shot: no swing from the old one's heading
				else:
					_chase_dir = _chase_dir.slerp(d, clampf(dt * 5.0, 0.0, 1.0)).normalized()
			# look between the heading and the target: the shot in front, where it goes beyond
			var to_t: Vector3 = (phys.to_global(f.tgt) - p)
			var aim := (_chase_dir + to_t.normalized() * 0.6).normalized() if to_t.length() > 1e-4 else _chase_dir
			if absf(aim.y) > 0.97:
				aim = (aim + Vector3(-cam.global_basis.z.x, 0, -cam.global_basis.z.z) * 0.3).normalized()
			var back := maxf(float((f.w as Dictionary).length) * CHASE_BACK, 0.024) * k
			# terrain-following shots skim the roofs: ride higher over them
			var up_k := CHASE_UP * (2.2 if str((f.plan as Dictionary).get("type", "")) == "cruise" else 1.0)
			var eye := p - aim * back + Vector3.UP * back * up_k
			_chase_pos = eye if int(f.serial) != _chase_serial else _chase_pos.lerp(eye, clampf(dt * 10.0, 0.0, 1.0))
			_chase_serial = int(f.serial)
			_chase_last = p
			_chase_hold = CHASE_HOLD
			var look := p + aim * back * 1.5
			cam.chase_xf = Transform3D(Basis.looking_at(look - _chase_pos, Vector3.UP), _chase_pos)
			want = 1.0
		elif _chase_hold > 0.0:
			_chase_hold -= dt
			_chase_serial = -1
			cam.chase_xf = Transform3D(Basis.looking_at(_chase_last - _chase_pos, Vector3.UP), _chase_pos)
			want = 1.0
	# ride in quickly, glide back to the orbit slowly
	var rate := 4.0 if want > cam.chase_blend else 1.2
	cam.chase_blend = move_toward(cam.chase_blend, want, dt * rate)
	cam.near = 0.0015 if cam.chase_blend > 0.3 else 0.01
	cam.apply()


func reset() -> void:
	phys.reset_island()
	for id in WeaponTable.ids():
		ammo[id] = int(WeaponTable.get_weapon(id).ammo)
		cooldown[id] = 0.0
	if phys.island.ship:
		phys.island.ship.set_jets_aboard(int(ammo["jet"]))
	start_enemy()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var i := KEYS.find(k.keycode)
	if i >= 0 and i < WeaponTable.ids().size():
		select(WeaponTable.ids()[i])
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if phys == null:
		return
	var dt := minf(delta, 0.05)
	_step_cam(dt)
	for id in WeaponTable.ids():
		var w := WeaponTable.get_weapon(id)
		cooldown[id] = maxf(float(cooldown[id]) - dt, 0.0)
		if int(ammo[id]) < int(w.ammo) and float(w.reload) > 0.0:
			_reload[id] = float(_reload[id]) + dt
			if float(_reload[id]) >= float(w.reload):
				_reload[id] = 0.0
				ammo[id] = int(ammo[id]) + 1
		var c: Dictionary = _cards[id]
		(c.ammo as Label).text = "%d" % int(ammo[id])
		(c.ammo as Label).add_theme_color_override("font_color", AMBER if int(ammo[id]) > 0 else RED)
		var f := 1.0 - float(cooldown[id]) / maxf(float(w.cooldown), 0.01)
		(c.bar as ColorRect).scale.x = clampf(f, 0.0, 1.0)
	_btn_weapons.text = "%s  ·  %d      " % [String(SHORT.get(weapon, weapon)), int(ammo[weapon])]
	var d := phys.island.props.destruction()
	var left := phys.forces.alive(EnemyForces.KINDS)
	_top.text = "تدمير %d%%  ·  قوات معادية %d" % [int(d.pct), left]
	_hull_lbl.text = "البارجة %d%%" % int(hull)
	_hull_lbl.add_theme_color_override("font_color", GREEN if hull >= 50 else (AMBER if hull > 25 else RED))
	_hull_bar.size.x = HULL_W * hull / 100.0
	_hull_bar.color = GREEN if hull >= 50 else (AMBER if hull > 25 else RED)
	if sunk_t <= 0.0 and hull < 100.0:
		hull = minf(hull + REPAIR * dt, 100.0)
	if _msg_t > 0.0:
		_msg_t -= dt
		if _msg_t <= 0.0:
			_msg.text = ""
	if sunk_t > 0.0:
		sunk_t -= dt
		if sunk_t <= 0.0:
			reset()
