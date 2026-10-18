class_name WeaponTable
extends RefCounted
## The military weapon data table: everything that makes one weapon differ from
## another lives here, so the set can later move into the AbodenBlaster kit
## (aboden-blaster-kit: AbodenBlaster.fire_at(origin, target_point)) unchanged.
##
## Units are diorama-local (1 unit = 1 m of the 1:2000 model at scale 1; the model may
## be scaled in the room). Gravity is the miniature gravity of fx/physics_test.gd.
##   arc         "lofted" ballistic (high), "low" ballistic (fast, flat), "cruise"
##               (drops low and follows the terrain / sea, see weapons/flight.gd)
##   flight      [min, max] flight time in s (ballistic: picked from the distance)
##   speed       cruise ground speed in units/s (cruise only; flight time follows)
##   cruise_alt  cruise height above the terrain / sea (cruise only)
##   blast       crater / blast radius factor (1.0 = PhysicsTest.CRATER_R 1.6 cm)
##   ejecta      soil chunks thrown on land
##   cooldown    s between two shots of this weapon
##   ammo        rounds when full; one round comes back every `reload` s
##   glow        re-entry glow on the way down (ballistic missile)
##   trail       smoke trail puff interval (s) and tint

const IDS := ["ballistic", "cruise", "artillery"]

const WEAPONS := {
	"ballistic": {
		"id": "ballistic", "name_ar": "صاروخ باليستي", "name_en": "Ballistic missile",
		"arc": "lofted", "flight": [2.6, 3.0], "blast": 1.45, "ejecta": 90,
		"cooldown": 4.0, "ammo": 6, "reload": 8.0, "glow": true,
		"trail": 0.016, "trail_col": Color(0.88, 0.86, 0.82, 0.6),
		"length": 0.0034, "radius": 0.0006, "col": Color(0.85, 0.86, 0.84),
	},
	"cruise": {
		"id": "cruise", "name_ar": "صاروخ كروز", "name_en": "Cruise missile",
		"arc": "cruise", "flight": [1.5, 3.0], "speed": 0.42, "cruise_alt": 0.006, "blast": 1.0, "ejecta": 60,
		"cooldown": 3.0, "ammo": 8, "reload": 6.0, "glow": false,
		"trail": 0.022, "trail_col": Color(0.92, 0.92, 0.90, 0.45),
		"length": 0.0028, "radius": 0.00045, "col": Color(0.55, 0.58, 0.55),
	},
	"artillery": {
		"id": "artillery", "name_ar": "قذيفة مدفعية", "name_en": "Artillery shell",
		"arc": "low", "flight": [1.5, 1.8], "blast": 0.6, "ejecta": 30,
		"cooldown": 0.8, "ammo": 30, "reload": 2.0, "glow": false,
		"trail": 0.03, "trail_col": Color(0.80, 0.79, 0.76, 0.35),
		"length": 0.0018, "radius": 0.00055, "col": Color(0.35, 0.36, 0.33),
	},
}


static func get_weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS["ballistic"])


static func next_id(id: String, step := 1) -> String:
	var i := IDS.find(id)
	return IDS[posmod(i + step, IDS.size())]
