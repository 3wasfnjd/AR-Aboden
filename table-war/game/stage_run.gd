class_name StageRun
extends RefCounted
## One play of a stage: its objective, clock, civilian casualties, the battleship's hull
## and the stars. Pure rules (the world is read through IslandProps / CityLife counts the
## caller passes in): tested headless.
##
## Civilian casualties = destroyed civilian buildings (CIVIL kinds) + civilian boats sunk
## + people and cars killed in the city since the stage started.
## Stars (only when the objective is done in time and the ship still floats):
##   3 stars   no civilian casualties
##   2 stars   1-2 casualties
##   1 star    3 or more (below the fail limit)
## The stage FAILS when casualties reach civ_fail (default Campaign.CIV_FAIL), when the
## time runs out, or when the battleship's hull reaches 0.

const CIVIL := ["house", "villa", "midrise", "skyscraper", "mall", "stadium"]
const CIVIL_BOATS := ["boat"]
const HULL_MAX := 100.0
const HIT_DAMAGE := 25.0         # an enemy anti-ship missile that gets through

var stage := {}
var running := false
var result := ""                 # "", "won", "failed"
var fail_reason := ""            # "time", "civilians", "ship"
var stars := 0
var time_left := 0.0
var shots := 0
var hull := HULL_MAX
var intercepted := 0             # our missiles shot down by their air defence
var enemy_shots := 0             # their missiles at the ship
var enemy_hits := 0
var _civ_struct0 := 0
var _life0 := 0
var civ_life := 0                # people / cars killed since the start (set by the caller)


func start(s: Dictionary, props: IslandProps, life_alive := 0) -> void:
	stage = s
	running = true
	result = ""
	fail_reason = ""
	stars = 0
	shots = 0
	hull = HULL_MAX
	intercepted = 0
	enemy_shots = 0
	enemy_hits = 0
	time_left = float(s.get("time", 120.0))
	_civ_struct0 = civil_destroyed(props)
	_life0 = life_alive
	civ_life = 0


static func civil_destroyed(props: IslandProps) -> int:
	var n := 0
	for st in props.structures:
		if not st.alive and (st.kind in CIVIL or st.kind in CIVIL_BOATS):
			n += 1
	return n


## Tell the run how many city people / cars are alive now.
func set_life_alive(alive: int) -> void:
	civ_life = maxi(_life0 - alive, 0)


func civilians(props: IslandProps) -> int:
	return civil_destroyed(props) - _civ_struct0 + civ_life


func civ_fail() -> int:
	return int(stage.get("civ_fail", Campaign.CIV_FAIL))


## [destroyed, total] of the objective (for "pct": [pct, target]).
func progress(props: IslandProps) -> Array:
	if stage.has("pct"):
		return [int(floor(float(props.destruction().pct))), int(stage.pct)]
	var hit := 0
	var tot := 0
	for st in props.structures:
		var ok := false
		if stage.has("kinds") and st.kind in stage.kinds:
			ok = true
		if stage.has("cats") and IslandProps.TARGETS.has(st.kind) and IslandProps.TARGETS[st.kind][0] in stage.cats:
			ok = true
		if ok:
			tot += 1
			if not st.alive:
				hit += 1
	return [hit, tot]


func is_target(kind: String) -> bool:
	if stage.has("kinds") and kind in stage.kinds:
		return true
	return stage.has("cats") and IslandProps.TARGETS.has(kind) and IslandProps.TARGETS[kind][0] in stage.cats


func on_shot() -> void:
	if running:
		shots += 1


## An enemy missile reached the battleship.
func ship_hit(dmg := HIT_DAMAGE) -> void:
	if running:
		enemy_hits += 1
		hull = maxf(hull - dmg, 0.0)


## Stars for `civ` casualties (when won).
static func stars_for(civ: int) -> int:
	if civ <= 0:
		return 3
	if civ <= 2:
		return 2
	return 1


## Advance the clock and check the end. Returns true on the frame the stage ends.
func step(dt: float, props: IslandProps) -> bool:
	if not running:
		return false
	time_left = maxf(time_left - dt, 0.0)
	var civ := civilians(props)
	if civ >= civ_fail():
		return _finish(false, "civilians", civ)
	if hull <= 0.0:
		return _finish(false, "ship", civ)
	var pr := progress(props)
	if int(pr[1]) > 0 and int(pr[0]) >= int(pr[1]):
		return _finish(true, "", civ)
	if time_left <= 0.0:
		return _finish(false, "time", civ)
	return false


func _finish(won: bool, why: String, civ: int) -> bool:
	running = false
	result = "won" if won else "failed"
	fail_reason = why
	stars = stars_for(civ) if won else 0
	return true


## Abandon a running stage (back to the menu).
func abort() -> void:
	running = false
	result = ""
