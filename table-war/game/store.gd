class_name Store
extends RefCounted
## Chapter purchases (placeholder). The store build will ask the Meta platform
## (Godot Meta Toolkit, in-app purchases: one SKU per chapter, "tw_chapter_2" ...) and
## cache the answer here; until then nothing is bought and owns() is false, so only the
## free chapters (0 and 1) are open unless Progress.unlock_all is set (test builds).

const SKUS := {2: "tw_chapter_2", 3: "tw_chapter_3", 4: "tw_chapter_4"}

static var purchased := {}   # chapter n -> true, filled from the platform at start


static func owns(chapter_n: int) -> bool:
	return bool(purchased.get(chapter_n, false))


static func sku(chapter_n: int) -> String:
	return String(SKUS.get(chapter_n, ""))
