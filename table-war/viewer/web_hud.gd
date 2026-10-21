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
	"aa": "دفاع جوي", "nuke": "نووي"}
const LIST_W := 250.0             # the weapon list's width
const ROW_H := 40.0
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
var _btn_enemy: Button
var _btn_slow: Button
var map_id := 1
## Missile camera: a button switches the view between the free orbit and a camera riding
## just behind and above the newest shot; after the impact it holds on the blast a moment,
## then glides back to the orbit until the next launch.
var cam: OrbitCamera
var missile_cam := false
var _btn_cam: Button
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
	_font = XRGame.ui_font()
	for id in WeaponTable.IDS:
		ammo[id] = int(WeaponTable.get_weapon(id).ammo)
		cooldown[id] = 0.0
		_reload[id] = 0.0
	_build()
	phys.forces.ship_damaged.connect(func(_q: Vector3, d: float) -> void: _hit(d))
	phys.resistance.ship_hit.connect(func(_q: Vector3) -> void: _hit(StageRun.HIT_DAMAGE))
	phys.resistance.intercepted.connect(func(_q: Vector3, _w: String) -> void: flash("أُسقط صاروخك · Shot down", AMBER))
	phys.forces.fighter_down.connect(func(_q: Vector3) -> void: flash("أسقطت طائرة معادية · Jet down", GREEN))
	phys.sortie_landed.connect(func(wid: String) -> void: ammo[wid] = mini(int(ammo[wid]) + 1, int(WeaponTable.get_weapon(wid).ammo)))
	start_enemy()
	select(weapon)


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
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
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


func _button(parent: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_stylebox_override("normal", _style(BG, Color(FRAME, 0.5)))
	b.add_theme_stylebox_override("hover", _style(Color(0.08, 0.18, 0.25, 0.9), FRAME))
	b.add_theme_stylebox_override("pressed", _style(Color(0.10, 0.25, 0.32, 0.95), FRAME))
	b.custom_minimum_size = Vector2(200, 52)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style(BG, Color(FRAME, 0.35)))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)
	var title := _label(row, "حرب البارجة · لعب حر", 28, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top = _label(row, "", 22, DIM)
	_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := VBoxContainer.new()
	hb.custom_minimum_size = Vector2(190, 0)
	row.add_child(hb)
	_hull_lbl = _label(hb, "البارجة 100%", 20, GREEN)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.15, 0.2, 0.24)
	bar_bg.custom_minimum_size = Vector2(190, 8)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(bar_bg)
	_hull_bar = ColorRect.new()
	_hull_bar.color = GREEN
	_hull_bar.size = Vector2(190, 8)
	_hull_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_hull_bar)
	# side buttons (left edge)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	side.offset_left = 10
	side.offset_top = -190
	root.add_child(side)
	_button(side, "جزيرة السبخة", func() -> void: map_requested.emit(1))
	_button(side, "جزيرة الهلال", func() -> void: map_requested.emit(2))
	_btn_enemy = _button(side, "القوات المعادية: تعمل", toggle_enemy)
	_button(side, "إعادة الجزيرة", reset)
	_btn_slow = _button(side, "حركة بطيئة", toggle_slow)
	_btn_cam = _button(side, "الكاميرا: حرة", toggle_cam)
	# message line
	_msg = _label(root, "", 30, AMBER)
	_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg.offset_top = 84
	_msg.offset_left = -400
	_msg.offset_right = 400
	# weapon list (right edge): one row per weapon, the name, the key and the ammo,
	# a thin reload bar under it; scrolls on a short screen
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(BG, Color(FRAME, 0.35)))
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -LIST_W - 10
	panel.offset_right = -10
	panel.offset_top = 74
	panel.offset_bottom = -36
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_label(col, "الأسلحة · Weapons", 22, FRAME)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in WeaponTable.IDS.size():
		var id: String = WeaponTable.IDS[i]
		var w := WeaponTable.get_weapon(id)
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(0, ROW_H)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(select.bind(id))
		list.add_child(card)
		var nm := _label(card, String(SHORT.get(id, w.name_ar)), 22, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		nm.set_anchors_preset(Control.PRESET_FULL_RECT)
		nm.offset_right = -12
		nm.offset_bottom = -5
		var am := _label(card, "", 20, AMBER, HORIZONTAL_ALIGNMENT_LEFT)
		am.set_anchors_preset(Control.PRESET_FULL_RECT)
		am.offset_left = 40
		am.offset_bottom = -5
		var key := _label(card, ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "\\"][i] if i < 13 else "", 15, DIM, HORIZONTAL_ALIGNMENT_LEFT)
		key.set_anchors_preset(Control.PRESET_FULL_RECT)
		key.offset_left = 12
		key.offset_bottom = -5
		var cb := ColorRect.new()
		cb.color = Color(FRAME, 0.7)
		cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		cb.offset_left = 8
		cb.offset_right = -8
		cb.offset_top = -6
		cb.offset_bottom = -3
		card.add_child(cb)
		_cards[id] = {"panel": card, "ammo": am, "bar": cb}
	var help := _label(root, "اضغط على الجزيرة للإطلاق · اسحب للتدوير · إصبعين للتقريب", 18, DIM)
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_right = -LIST_W - 20
	help.offset_top = -38
	help.offset_bottom = -8


func select(id: String) -> void:
	weapon = id
	phys.weapon = id
	for k in _cards:
		var p: Button = _cards[k].panel
		var on := String(k) == id
		var bc := RED if k == "nuke" else (AMBER if on else Color(FRAME, 0.35))
		p.add_theme_stylebox_override("normal", _style(Color(0.10, 0.22, 0.30, 0.92) if on else BG, bc, 3 if on else 2))
		p.add_theme_stylebox_override("hover", _style(Color(0.10, 0.22, 0.30, 0.92), FRAME, 3))
		p.add_theme_stylebox_override("pressed", _style(Color(0.12, 0.28, 0.36, 0.95), FRAME, 3))
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
	_btn_enemy.text = "القوات المعادية: تعمل" if enemies_on else "القوات المعادية: متوقفة"
	start_enemy()


func toggle_slow() -> void:
	phys.set_slow_motion(not phys.slow_motion)
	_btn_slow.text = "سرعة عادية" if phys.slow_motion else "حركة بطيئة"


func toggle_cam() -> void:
	missile_cam = not missile_cam
	_btn_cam.text = "الكاميرا: فوق الصاروخ" if missile_cam else "الكاميرا: حرة"
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
	for id in WeaponTable.IDS:
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
	if i >= 0 and i < WeaponTable.IDS.size():
		select(WeaponTable.IDS[i])
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if phys == null:
		return
	var dt := minf(delta, 0.05)
	_step_cam(dt)
	for id in WeaponTable.IDS:
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
	var d := phys.island.props.destruction()
	var left := phys.forces.alive(EnemyForces.KINDS)
	_top.text = "تدمير الجزيرة %d%%   ·   قوات معادية %d   ·   %s" % [int(d.pct), left, Campaign.map_name(map_id)]
	_hull_lbl.text = "البارجة %d%%" % int(hull)
	_hull_lbl.add_theme_color_override("font_color", GREEN if hull >= 50 else (AMBER if hull > 25 else RED))
	_hull_bar.size.x = 190.0 * hull / 100.0
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
