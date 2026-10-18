class_name Scale
extends RefCounted
## Model scale. 1 : 2000 -> one real metre = 0.5 mm on the table.
## Every prop size in the project is written as Scale.m(<real metres>) so the
## miniature stays proportionally consistent (see README scale table).

const RATIO := 2000.0
const STOREY := 3.5        # m, floor-to-floor
const PARAPET := 1.0       # m


static func m(real_metres: float) -> float:
	return real_metres / RATIO


static func storeys(n: float) -> float:
	return n * STOREY / RATIO
