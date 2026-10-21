class_name PlayerShip
extends MeshInstance3D
## The player's warship: a big toy cruiser anchored in deep water behind the mountain.
## Every weapon launches from its own launcher on board (island-local points, so it
## moves / turns / scales with the diorama); the player's hand only aims.
## Not a target: strikes never hit it (it is not in IslandProps.structures).
##   vls     ballistic / hypersonic / cluster / bunker buster (vertical cells, forward)
##   box     cruise / anti-ship (angled box launchers, midships)
##   gun     artillery (bow turret)
##   pod     MLRS rocket pod (aft)
##   ramp    kamikaze drone (stern ramp)
##   silo    the nuclear missile (red hatch amidships)
##   deck    strike jets (flight deck aft; the parked jets show how many are aboard)

const POS := Vector2(0.17, -0.365)
## The web build's battleship (web_grand): GRAND times bigger, moored further out in the
## open sea, with a far richer superstructure (stacked bridge with radar arrays, two
## funnels, a lattice mast, two triple-gun bow turrets, close-in weapon domes, boats).
static var web_grand := false
const GRAND := 1.7
const GRAND_OUT := 0.13
## Where it lies on this map (IslandLayout.ship_pos; POS on the original map).
var pos := POS
const YAW := 0.0
const L := 0.17
const B := 0.028
const FB := 0.004                  # deck height above the water

## Launcher of each weapon, ship-local: [point, upward kick of the first metre].
const LAUNCHERS := {
	"vls": Vector3(0.040, FB + 0.0035, 0.0),
	"box": Vector3(-0.004, FB + 0.006, 0.0),
	"gun": Vector3(0.082, FB + 0.0045, 0.0),
	"pod": Vector3(-0.040, FB + 0.0065, 0.0),
	"ramp": Vector3(-0.080, FB + 0.0025, 0.0),
	"silo": Vector3(0.016, FB + 0.0012, 0.0),
	"deck": Vector3(-0.062, FB + 0.0028, 0.0),
	"tube": Vector3(0.020, FB - 0.002, B * 0.52),
}
const WEAPON_LAUNCHER := {
	"ballistic": "vls", "hypersonic": "vls", "cluster": "vls", "bunker": "vls",
	"cruise": "box", "antiship": "box", "artillery": "gun", "mlrs": "pod", "drone": "ramp", "swarm": "ramp", "aa": "vls", "nuke": "silo", "jet": "deck",
	"atgm": "box", "torpedo": "tube", "glide": "deck", "heli": "deck",
}

const HULL := Color(0.52, 0.57, 0.63)
const DECK := Color(0.40, 0.44, 0.48)
const DARK := Color(0.18, 0.20, 0.23)
const SUPER := Color(0.66, 0.70, 0.75)
const RED := Color(0.85, 0.18, 0.15)


func build() -> void:
	name = "PlayerShip"
	var mb := MeshBuilder.new()
	Toon._hull(mb, L, B, FB, HULL, DECK)
	# superstructure: bridge block, funnel, mast with radar panels
	mb.box(Vector3(-0.012, FB + 0.0045, 0), Vector3(0.034, 0.009, B * 0.62), SUPER)
	mb.box(Vector3(-0.006, FB + 0.0105, 0), Vector3(0.016, 0.004, B * 0.5), SUPER.lightened(0.08))
	mb.box(Vector3(0.0, FB + 0.0105, 0), Vector3(0.004, 0.0022, B * 0.48), Color(0.25, 0.40, 0.55))
	mb.cylinder(Vector3(-0.004, FB + 0.0125, 0), 0.0009, 0.0004, 0.016, 6, DARK)
	mb.box(Vector3(-0.004, FB + 0.024, 0), Vector3(0.0008, 0.0035, 0.008), DARK)
	mb.box(Vector3(-0.024, FB + 0.011, 0), Vector3(0.008, 0.007, 0.007), DARK.lightened(0.15))
	# bow gun turret + barrel
	mb.cylinder(Vector3(0.068, FB, 0), 0.0045, 0.004, 0.0035, 12, SUPER)
	mb.box(Vector3(0.076, FB + 0.0025, 0), Vector3(0.012, 0.0009, 0.0009), DARK)
	# forward vertical launch cells (4 x 6 hatches)
	mb.box(Vector3(0.040, FB + 0.0012, 0), Vector3(0.018, 0.0024, B * 0.5), DECK.darkened(0.1))
	for i in 4:
		for j in 6:
			mb.box(Vector3(0.033 + i * 0.0045, FB + 0.0025, (j - 2.5) * 0.0022), Vector3(0.0036, 0.0002, 0.0018), DARK)
	# nuclear silo hatch (red) between the cells and the bridge
	mb.cylinder(Vector3(0.016, FB, 0), 0.004, 0.004, 0.0012, 14, RED, true, RED.darkened(0.2))
	mb.cylinder(Vector3(0.016, FB + 0.0012, 0), 0.0012, 0.0012, 0.0002, 10, Color(1.0, 0.85, 0.2))
	# angled box launchers (cruise / anti-ship), both sides
	for side in [-1.0, 1.0]:
		var saved := mb.xform
		mb.xform = saved * Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(30.0)), Vector3(-0.004, FB + 0.003, side * B * 0.3))
		for k in 2:
			mb.box(Vector3(0, 0, (k - 0.5) * 0.0032), Vector3(0.014, 0.0028, 0.003), Color(0.46, 0.50, 0.44))
		mb.xform = saved
	# aft rocket pod (MLRS) on a turntable
	mb.cylinder(Vector3(-0.040, FB, 0), 0.0035, 0.0035, 0.0018, 10, SUPER)
	var saved2 := mb.xform
	mb.xform = saved2 * Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(40.0)), Vector3(-0.040, FB + 0.0045, 0))
	mb.box(Vector3.ZERO, Vector3(0.012, 0.005, 0.007), Color(0.46, 0.50, 0.38))
	for i in 3:
		for j in 3:
			mb.box(Vector3(0.0061, (i - 1) * 0.0015, (j - 1) * 0.002), Vector3(0.0002, 0.0011, 0.0011), DARK)
	mb.xform = saved2
	# stern drone ramp + two parked drones
	mb.box(Vector3(-0.074, FB + 0.0012, 0), Vector3(0.018, 0.0016, B * 0.55), DECK.lightened(0.1))
	for side in [-1.0, 1.0]:
		mb.box(Vector3(-0.082, FB + 0.0024, side * 0.006), Vector3(0.004, 0.0006, 0.0010), Color(0.86, 0.86, 0.82))
		mb.box(Vector3(-0.082, FB + 0.0026, side * 0.006), Vector3(0.0012, 0.0004, 0.006), Color(0.86, 0.86, 0.82))
	# flight deck markings for the strike jets
	mb.box(Vector3(-0.062, FB + 0.0025, 0), Vector3(0.028, 0.0002, B * 0.62), Color(0.30, 0.33, 0.36))
	mb.box(Vector3(-0.062, FB + 0.0027, 0), Vector3(0.026, 0.0001, 0.0006), Color(0.95, 0.85, 0.30))
	# flag on the mast and a hull number band
	mb.box(Vector3(0.05, FB - 0.0018, B * 0.5 + 0.0002), Vector3(0.012, 0.0022, 0.0002), Color(0.95, 0.95, 0.93))
	if web_grand:
		_grand_details(mb)
	mesh = mb.commit(null, MeshBuilder.vc_material(0.6))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	transform = Transform3D(Basis(Vector3.UP, YAW), Vector3(pos.x, IslandTerrain.SEA, pos.y))
	if web_grand:
		var out := pos + pos.normalized() * GRAND_OUT
		transform = Transform3D(Basis(Vector3.UP, YAW).scaled(Vector3.ONE * GRAND), Vector3(out.x, IslandTerrain.SEA, out.y))
	# the two strike jets parked on the flight deck
	var w := WeaponTable.get_weapon("jet")
	var jm := MeshBuilder.new()
	var Lj: float = w.length
	var rj: float = w.radius
	jm.box(Vector3.ZERO, Vector3(Lj, rj * 1.6, rj * 1.6), w.col)
	jm.box(Vector3(-Lj * 0.05, 0, 0), Vector3(Lj * 0.12, rj * 0.4, Lj * 0.75), w.col)
	jm.box(Vector3(-Lj * 0.42, rj * 1.2, 0), Vector3(Lj * 0.15, rj * 1.8, rj * 0.4), (w.col as Color).darkened(0.15))
	jm.box(Vector3(Lj * 0.25, rj * 0.9, 0), Vector3(Lj * 0.15, rj * 0.6, rj * 0.9), Color(0.25, 0.35, 0.45))
	var jmesh := jm.commit(null, MeshBuilder.vc_material(0.5))
	for k in 2:
		var j := MeshInstance3D.new()
		j.name = "ParkedJet%d" % k
		j.mesh = jmesh
		j.position = Vector3(-0.066 + k * 0.009, FB + 0.0035, (k - 0.5) * 0.011)
		j.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(j)
		parked.append(j)


var parked: Array[MeshInstance3D] = []


func _grand_details(mb: MeshBuilder) -> void:
	var steel := SUPER.darkened(0.05)
	var glass := Color(0.20, 0.34, 0.48)
	var array := Color(0.24, 0.30, 0.36)
	# stacked bridge: three decks narrowing upwards, window bands, phased-array radar
	# panels on its four faces
	mb.box(Vector3(-0.010, FB + 0.0135, 0), Vector3(0.022, 0.004, B * 0.42), steel)
	mb.box(Vector3(-0.009, FB + 0.0170, 0), Vector3(0.015, 0.003, B * 0.32), steel.lightened(0.06))
	mb.box(Vector3(0.0, FB + 0.0152, 0), Vector3(0.0045, 0.0016, B * 0.40), glass)
	mb.box(Vector3(-0.0015, FB + 0.0182, 0), Vector3(0.0045, 0.0012, B * 0.30), glass)
	for face in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var c := Vector3(-0.009, FB + 0.0135, 0) + Vector3(face.x * 0.0112, 0, face.z * B * 0.212)
		var sz := Vector3(0.0003, 0.0034, 0.0068) if face.x != 0.0 else Vector3(0.0085, 0.0034, 0.0003)
		mb.box(c, sz, array)
	# lattice mast with yardarms and a radar dish on top
	mb.cylinder(Vector3(-0.009, FB + 0.0185, 0), 0.0012, 0.0005, 0.016, 6, DARK)
	for k in 3:
		mb.box(Vector3(-0.009, FB + 0.024 + k * 0.004, 0), Vector3(0.0006, 0.0005, 0.011 - k * 0.003), DARK)
	mb.cylinder(Vector3(-0.009, FB + 0.0345, 0), 0.0028, 0.0028, 0.0006, 12, Color(0.80, 0.82, 0.85))
	# two funnels with dark caps
	for fx in [-0.022, -0.030]:
		mb.cylinder(Vector3(fx, FB + 0.0085, 0), 0.0028, 0.0024, 0.009, 10, steel)
		mb.cylinder(Vector3(fx, FB + 0.0175, 0), 0.0024, 0.0024, 0.0012, 10, DARK)
	# two triple-gun bow turrets (the rear one superfiring over the front one)
	for t in [[0.068, FB + 0.0005, 0.0048], [0.055, FB + 0.0040, 0.0046]]:
		var x: float = t[0]
		var y: float = t[1]
		mb.cylinder(Vector3(x, y, 0), float(t[2]), float(t[2]) * 0.9, 0.0036, 14, SUPER)
		mb.box(Vector3(x - 0.001, y + 0.0022, 0), Vector3(0.0075, 0.0028, 0.0072), SUPER.lightened(0.05))
		for b in 3:
			mb.box(Vector3(x + 0.0085, y + 0.0024, (b - 1) * 0.0019), Vector3(0.012, 0.0007, 0.0007), DARK)
	mb.cylinder(Vector3(0.055, FB, 0), 0.0036, 0.0036, 0.0040, 12, SUPER.darkened(0.05))    # barbette under the upper turret
	# close-in weapon domes (white) at the corners of the superstructure
	for c in [Vector3(0.006, FB + 0.0105, B * 0.30), Vector3(0.006, FB + 0.0105, -B * 0.30),
			Vector3(-0.036, FB + 0.0085, B * 0.28), Vector3(-0.036, FB + 0.0085, -B * 0.28)]:
		mb.cylinder(c, 0.0016, 0.0016, 0.0016, 10, Color(0.88, 0.89, 0.90))
		mb.cylinder(c + Vector3(0, 0.0016, 0), 0.0016, 0.0002, 0.0018, 10, Color(0.92, 0.93, 0.94))
	# lifeboats hung along both sides of the superstructure
	for sd in [-1.0, 1.0]:
		for k in 3:
			mb.box(Vector3(-0.026 + k * 0.009, FB + 0.0068, sd * B * 0.36), Vector3(0.0065, 0.0016, 0.0022), Color(0.95, 0.55, 0.15))
	# helicopter pad circle on the flight deck
	mb.cylinder(Vector3(-0.062, FB + 0.0028, 0), 0.0075, 0.0075, 0.00012, 20, Color(0.95, 0.95, 0.92))
	mb.cylinder(Vector3(-0.062, FB + 0.0029, 0), 0.0068, 0.0068, 0.00012, 20, Color(0.30, 0.33, 0.36))


## Show as many parked jets as are aboard.
func set_jets_aboard(n: int) -> void:
	for k in parked.size():
		parked[k].visible = k < n


## Island-local launch point of a weapon (its launcher on board).
func launch_point(wid: String) -> Vector3:
	var key: String = WEAPON_LAUNCHER.get(wid, "vls")
	if bool(WeaponTable.get_weapon(wid).get("jet", false)):
		key = "deck"    # every aircraft (the jet-dropped bunker buster too) leaves the deck
	return transform * (LAUNCHERS[key] as Vector3)
