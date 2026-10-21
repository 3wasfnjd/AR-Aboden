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
##   salvo       rockets per trigger pull, landing within `spread` of the target (MLRS,
##               the drone swarm); salvo_gap s between two of them (0.09)
##   split       submunitions released at 62 % of the flight, falling within `spread`
##   crater_k    crater depth factor (bunker buster digs deep)
##   wings       draw wings on the body (cruise, drone, anti-ship)
##   sortie      strike jet: takes off from the ship, flies to the target at `cruise_alt`,
##               drops `bombs` within `spread`, flies home and lands (ammo = jets on
##               deck; a jet is back only when it has landed: reload 0)
##   nuke        nuclear test: everything within `nuke_r` is destroyed, mushroom cloud

const IDS := ["ballistic", "cruise", "artillery", "mlrs", "cluster", "hypersonic", "bunker", "drone", "antiship", "jet", "swarm", "aa", "nuke"]

const WEAPONS := {
	"ballistic": {
		"id": "ballistic", "name_ar": "صاروخ باليستي", "name_en": "Ballistic missile",
		"arc": "lofted", "flight": [2.6, 3.0], "blast": 1.45, "ejecta": 90,
		"cooldown": 4.0, "ammo": 6, "reload": 8.0, "glow": true,
		"trail": 0.016, "trail_col": Color(0.88, 0.86, 0.82, 0.6),
		"length": 0.0034, "radius": 0.0006, "col": Color(0.85, 0.86, 0.84),
	},
	"cruise": {
		"wings": true,
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
	"mlrs": {
		"id": "mlrs", "name_ar": "راجمة صواريخ", "name_en": "MLRS rocket salvo",
		"arc": "low", "flight": [1.4, 1.7], "blast": 0.5, "ejecta": 14,
		"cooldown": 6.0, "ammo": 4, "reload": 9.0, "glow": false, "salvo": 8, "spread": 0.035,
		"trail": 0.03, "trail_col": Color(0.85, 0.84, 0.80, 0.4),
		"length": 0.0016, "radius": 0.0003, "col": Color(0.48, 0.52, 0.38),
	},
	"cluster": {
		"id": "cluster", "name_ar": "صاروخ عنقودي", "name_en": "Cluster missile",
		"arc": "lofted", "flight": [2.6, 3.0], "blast": 0.45, "ejecta": 10,
		"cooldown": 7.0, "ammo": 3, "reload": 12.0, "glow": false, "split": 10, "spread": 0.045,
		"trail": 0.018, "trail_col": Color(0.88, 0.86, 0.82, 0.55),
		"length": 0.003, "radius": 0.0006, "col": Color(0.78, 0.72, 0.50),
	},
	"hypersonic": {
		"id": "hypersonic", "name_ar": "صاروخ فرط صوتي", "name_en": "Hypersonic missile",
		"arc": "lofted", "flight": [0.9, 1.1], "blast": 1.75, "ejecta": 90,
		"cooldown": 8.0, "ammo": 3, "reload": 14.0, "glow": true,
		"trail": 0.008, "trail_col": Color(0.95, 0.90, 0.85, 0.6),
		"length": 0.0036, "radius": 0.0005, "col": Color(0.22, 0.22, 0.26),
	},
	"bunker": {
		"id": "bunker", "name_ar": "خارق التحصينات", "name_en": "Bunker buster",
		"arc": "lofted", "flight": [3.2, 3.6], "blast": 1.15, "crater_k": 2.2, "ejecta": 110,
		"cooldown": 6.0, "ammo": 4, "reload": 10.0, "glow": false,
		"trail": 0.02, "trail_col": Color(0.82, 0.80, 0.76, 0.5),
		"length": 0.0032, "radius": 0.0007, "col": Color(0.40, 0.42, 0.36),
	},
	"drone": {
		"id": "drone", "name_ar": "مسيّرة انتحارية", "name_en": "Kamikaze drone",
		"arc": "cruise", "flight": [2.5, 8.0], "speed": 0.22, "cruise_alt": 0.02, "blast": 0.7, "ejecta": 30,
		"cooldown": 2.5, "ammo": 10, "reload": 5.0, "glow": false, "wings": true,
		"trail": 0.25, "trail_col": Color(0.9, 0.9, 0.9, 0.15),
		"length": 0.0026, "radius": 0.00045, "col": Color(0.86, 0.86, 0.82),
	},
	"swarm": {
		"id": "swarm", "name_ar": "سرب مسيّرات", "name_en": "Drone swarm",
		"arc": "cruise", "flight": [2.0, 9.0], "speed": 0.26, "cruise_alt": 0.016, "blast": 0.35, "ejecta": 8,
		"cooldown": 6.0, "ammo": 3, "reload": 12.0, "glow": false, "wings": true,
		"salvo": 6, "spread": 0.022, "salvo_gap": 0.22,
		"trail": 0.3, "trail_col": Color(0.9, 0.9, 0.9, 0.12),
		"length": 0.0017, "radius": 0.0003, "col": Color(0.74, 0.76, 0.72),
	},
	"aa": {
		"id": "aa", "name_ar": "صاروخ دفاع جوي", "name_en": "Anti-air missile",
		"arc": "lofted", "flight": [1.0, 1.4], "blast": 0.4, "ejecta": 6, "homing_air": true,
		"cooldown": 2.0, "ammo": 6, "reload": 10.0, "glow": false,
		"trail": 0.02, "trail_col": Color(0.92, 0.92, 0.90, 0.5),
		"length": 0.0024, "radius": 0.00035, "col": Color(0.92, 0.92, 0.88),
	},
	"antiship": {
		"id": "antiship", "name_ar": "صاروخ مضاد للسفن", "name_en": "Anti-ship missile",
		"arc": "cruise", "flight": [1.2, 3.0], "speed": 0.5, "cruise_alt": 0.0025, "blast": 1.3, "ejecta": 40,
		"cooldown": 5.0, "ammo": 4, "reload": 10.0, "glow": false, "wings": true,
		"trail": 0.02, "trail_col": Color(0.92, 0.92, 0.90, 0.45),
		"length": 0.003, "radius": 0.0005, "col": Color(0.60, 0.62, 0.66),
	},
	"jet": {
		"id": "jet", "name_ar": "طائرة هجومية", "name_en": "Strike jet",
		"arc": "sortie", "speed": 0.14, "cruise_alt": 0.10, "bombs": 4, "spread": 0.012, "blast": 0.8, "ejecta": 20,
		"cooldown": 2.0, "ammo": 2, "reload": 0.0, "glow": false, "wings": true, "jet": true,
		"trail": 0.07, "trail_col": Color(0.95, 0.95, 0.95, 0.25),
		"length": 0.008, "radius": 0.0008, "col": Color(0.62, 0.68, 0.74),
	},
	# what a strike jet drops: it does not count as a weapon of its own
	"jetbomb": {
		"id": "jetbomb", "name_ar": "قنبلة", "name_en": "Bomb",
		"arc": "lofted", "flight": [0.55, 0.7], "blast": 0.8, "ejecta": 18,
		"cooldown": 0.0, "ammo": 0, "reload": 0.0, "glow": false,
		"trail": 0.08, "trail_col": Color(0.8, 0.8, 0.8, 0.2),
		"length": 0.0014, "radius": 0.00045, "col": Color(0.35, 0.38, 0.32),
	},
	"nuke": {
		"id": "nuke", "name_ar": "قنبلة نووية", "name_en": "Nuclear missile",
		"arc": "lofted", "flight": [3.4, 3.8], "blast": 1.0, "ejecta": 20, "nuke": true, "nuke_r": 0.16,
		"cooldown": 30.0, "ammo": 1, "reload": 90.0, "glow": true,
		"trail": 0.012, "trail_col": Color(0.95, 0.95, 0.92, 0.6),
		"length": 0.0042, "radius": 0.0008, "col": Color(0.92, 0.92, 0.90),
	},
	# not selectable: the bomblets a cluster missile releases
	"submunition": {
		"id": "submunition", "name_ar": "قنيبلة", "name_en": "Submunition",
		"arc": "lofted", "flight": [0.55, 0.75], "blast": 0.42, "ejecta": 8,
		"cooldown": 0.0, "ammo": 0, "reload": 0.0, "glow": false,
		"trail": 0.06, "trail_col": Color(0.80, 0.78, 0.74, 0.3),
		"length": 0.0009, "radius": 0.0003, "col": Color(0.70, 0.66, 0.46),
	},
}


static func get_weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS["ballistic"])


static func next_id(id: String, step := 1) -> String:
	var i := IDS.find(id)
	return IDS[posmod(i + step, IDS.size())]
