class_name Missions
extends RefCounted
## Missions: an objective on the island, a time limit, and up to three stars.
##   1 star   objective done before the time runs out
##   2 stars  ... with at least 40 % of the time left (or, for a precision strike,
##            in at most `par_shots` shots)
##   3 stars  ... and civilian losses within `civ_max` buildings
## Civilian losses = destroyed homes, flats, towers, malls and stadiums (IslandProps
## city kinds, not the TV tower / fort / lighthouse) since the mission started.
## Free play is mission "" (no timer, no objective). Best stars are kept per mission
## in user://table_war.json. Pure logic: tested headless (tests/test_headless.gd).

const LIST := [
	{"id": "precision", "ar": "ضربة جراحية", "en": "Surgical strike",
		"goal_ar": "دمّر برج الاتصالات", "goal_en": "Destroy the TV tower",
		"kinds": ["tv_tower"], "time": 60.0, "civ_max": 0, "par_shots": 1},
	{"id": "blackout", "ar": "إطفاء", "en": "Blackout",
		"goal_ar": "دمّر محطة الكهرباء", "goal_en": "Destroy the power station",
		"cats": ["power"], "time": 90.0, "civ_max": 2},
	{"id": "oil", "ar": "حظر النفط", "en": "Oil embargo",
		"goal_ar": "دمّر المصفاة", "goal_en": "Destroy the refinery",
		"cats": ["oil"], "time": 120.0, "civ_max": 2},
	{"id": "water", "ar": "قطع المياه", "en": "Dry taps",
		"goal_ar": "دمّر محطة التحلية", "goal_en": "Destroy the desalination plant",
		"cats": ["water"], "time": 60.0, "civ_max": 1},
	{"id": "fleet", "ar": "إغراق الأسطول", "en": "Sink the fleet",
		"goal_ar": "أغرق الفرقاطات", "goal_en": "Sink the frigates",
		"kinds": ["frigate"], "time": 90.0, "civ_max": 0},
	{"id": "port", "ar": "إغلاق الميناء", "en": "Close the port",
		"goal_ar": "دمّر الرافعات والسفن التجارية", "goal_en": "Destroy the cranes and merchant ships",
		"kinds": ["sts_crane", "rtg", "cargo", "tanker"], "time": 120.0, "civ_max": 3},
	{"id": "airbase", "ar": "سماء مفتوحة", "en": "Open skies",
		"goal_ar": "دمّر الطائرات والملاجئ وبرج المراقبة والرادار", "goal_en": "Destroy the jets, shelters, tower and radar",
		"kinds": ["jet", "has", "ctower", "mast", "radar_base"], "time": 150.0, "civ_max": 1},
	{"id": "army", "ar": "تحييد الدفاعات", "en": "Suppress the defences",
		"goal_ar": "دمّر الدفاع الجوي والدبابات والمخابئ", "goal_en": "Destroy the SAMs, tanks and bunkers",
		"kinds": ["sam", "tank_vehicle", "bunker", "radar_sphere", "silo", "silo_open", "launcher_truck"], "time": 150.0, "civ_max": 1},
	{"id": "total", "ar": "حرب شاملة", "en": "Total war",
		"goal_ar": "دمّر 70% من الجزيرة", "goal_en": "Destroy 70% of the island",
		"pct": 70.0, "time": 300.0, "civ_max": 9999},
]
const CIVIL := ["house", "villa", "midrise", "skyscraper", "mall", "stadium"]
const SAVE_PATH := "user://table_war.json"

var active := ""          # "" = free play
var running := false
var time_left := 0.0
var shots := 0
var result := ""          # "" while running / idle, "won" or "failed" when it ended
var stars := 0
var best := {}            # mission id -> best stars
var _civ0 := 0


static func get_def(id: String) -> Dictionary:
	for m in LIST:
		if m.id == id:
			return m
	return {}


## Next / previous entry of the selector: free play, then the missions in order.
static func cycle(id: String, step: int) -> String:
	var ids: Array = [""]
	for m in LIST:
		ids.append(m.id)
	var i := ids.find(id)
	return ids[posmod(i + step, ids.size())]


func select(id: String) -> void:
	active = id
	running = false
	result = ""
	stars = 0
	shots = 0
	time_left = float(get_def(id).get("time", 0.0))


## Start the selected mission on a freshly reset island.
func start(props: IslandProps) -> void:
	if active == "":
		return
	select(active)
	running = true
	_civ0 = civilian_losses(props)


func on_shot() -> void:
	if running:
		shots += 1


static func civilian_losses(props: IslandProps) -> int:
	var n := 0
	for st in props.structures:
		if not st.alive and st.kind in CIVIL:
			n += 1
	return n


## [destroyed, total] of the active objective (for "total": [pct, target pct]).
func progress(props: IslandProps) -> Array:
	var m := get_def(active)
	if m.is_empty():
		return [0, 0]
	if m.has("pct"):
		return [int(floor(float(props.destruction().pct))), int(m.pct)]
	var hit := 0
	var tot := 0
	for st in props.structures:
		var ok := false
		if m.has("kinds") and st.kind in m.kinds:
			ok = true
		if m.has("cats") and IslandProps.TARGETS.has(st.kind) and IslandProps.TARGETS[st.kind][0] in m.cats:
			ok = true
		if ok:
			tot += 1
			if not st.alive:
				hit += 1
	return [hit, tot]


func civilians(props: IslandProps) -> int:
	return civilian_losses(props) - _civ0


## Advance the clock and check the objective. Returns true on the frame it ends.
func step(dt: float, props: IslandProps) -> bool:
	if not running:
		return false
	time_left = maxf(time_left - dt, 0.0)
	var pr := progress(props)
	if int(pr[1]) > 0 and int(pr[0]) >= int(pr[1]):
		_finish(true, props)
		return true
	if time_left <= 0.0:
		_finish(false, props)
		return true
	return false


func _finish(won: bool, props: IslandProps) -> void:
	running = false
	result = "won" if won else "failed"
	stars = 0
	if won:
		var m := get_def(active)
		stars = 1
		if m.has("par_shots"):
			if shots <= int(m.par_shots) + 1:
				stars += 1
		elif time_left >= float(m.time) * 0.4:
			stars += 1
		if civilians(props) <= int(m.civ_max):
			stars += 1
		if stars > int(best.get(active, 0)):
			best[active] = stars
			save()


func load_best() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) == TYPE_DICTIONARY and typeof(d.get("best", null)) == TYPE_DICTIONARY:
		for k in d.best:
			best[str(k)] = int(d.best[k])


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"best": best}))


static func clock(t: float) -> String:
	var s := int(ceil(t))
	return "%02d:%02d" % [s / 60, s % 60]
