class_name Progress
extends RefCounted
## The player's campaign progress: best stars per stage, which stages are open, and which
## chapters are owned. Saved in user://table_war_progress.json.
##
## Opening order: the first stage of a chapter opens when the chapter is playable (owned
## and built) and, from chapter 2 on, the last stage of the chapter before is won; every
## other stage opens when the one before it is won (at least one star).
##
## Paid chapters: chapters 0 and 1 are free, 2-4 are sold. owns() asks Store (the platform
## purchase); a test build sets Progress.unlock_all so every built chapter is open.

const SAVE_PATH := "user://table_war_progress.json"

## Test builds: every built chapter counts as owned and every stage as open.
static var unlock_all := false

var best := {}          # stage id -> stars (1..3)
var owned := {}         # chapter n -> true (bought)


func stars(id: String) -> int:
	return int(best.get(id, 0))


func total_stars(chapter_n := -1) -> int:
	var t := 0
	for id in best:
		var s := Campaign.get_stage(String(id))
		if chapter_n < 0 or int(s.get("chapter", -1)) == chapter_n:
			t += int(best[id])
	return t


func owns(chapter_n: int) -> bool:
	var c := Campaign.chapter(chapter_n)
	if c.is_empty():
		return false
	return bool(c.free) or unlock_all or bool(owned.get(chapter_n, false)) or Store.owns(chapter_n)


## "open", "locked" (an earlier stage first), "buy" (chapter not owned) or "soon" (not built).
func stage_state(s: Dictionary) -> String:
	var n := int(s.chapter)
	if not Campaign.is_built(s):
		return "soon"
	if not owns(n):
		return "buy"
	if unlock_all:
		return "open"
	var list := Campaign.stages_of(n)
	var i := list.find(s)
	if i < 0:
		for k in list.size():
			if list[k].id == s.id:
				i = k
	if i > 0:
		return "open" if stars(String(list[i - 1].id)) > 0 else "locked"
	if n <= 1:
		return "open"
	var prev := Campaign.stages_of(n - 1)
	return "open" if not prev.is_empty() and stars(String(prev[prev.size() - 1].id)) > 0 else "locked"


func is_open(id: String) -> bool:
	var s := Campaign.get_stage(id)
	return not s.is_empty() and stage_state(s) == "open"


## The next stage to play: the first open stage without stars, else the last open one.
func next_stage() -> String:
	var last := ""
	for c in Campaign.CHAPTERS:
		if int(c.n) == 0:
			continue
		for s in Campaign.stages_of(int(c.n)):
			if stage_state(s) == "open":
				last = s.id
				if stars(s.id) == 0:
					return s.id
	return last if last != "" else "c1s1"


## Record a result; returns true if it is a new best.
func record(id: String, st: int) -> bool:
	if st <= stars(id):
		return false
	best[id] = st
	save()
	return true


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	if typeof(d.get("best", null)) == TYPE_DICTIONARY:
		for k in d.best:
			best[str(k)] = clampi(int(d.best[k]), 0, 3)
	if typeof(d.get("owned", null)) == TYPE_ARRAY:
		for n in d.owned:
			owned[int(n)] = true


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"best": best, "owned": owned.keys()}))
