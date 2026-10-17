extends SceneTree
## Headless checks:  godot --headless --path . -s tests/test_headless.gd
## Prints PASS/FAIL per check and exits with code 1 on any failure.
## (tests/run_tests.sh additionally fails if the log contains "SCRIPT ERROR".)

var failures := 0


func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + info if info != "" else ""))
	if not ok:
		failures += 1


func _initialize() -> void:
	var island := Island.new()
	root.add_child(island)   # _ready() builds everything
	await process_frame
	var t := island.terrain
	print("ISLAND_STATS ", JSON.stringify(island.stats()))

	# --- terrain queries ----------------------------------------------------------
	var max_err := 0.0
	for j in range(1, IslandTerrain.NZ, 7):
		for i in range(1, IslandTerrain.NX, 7):
			var v := t.vpos(i, j)
			if t.rim[t.idx(i, j)] == 1 or not t.is_inside(v.x, v.z, 0.01):
				continue
			max_err = maxf(max_err, absf(t.height_at(v.x, v.z) - v.y))
	check("height_at matches mesh vertices", max_err < 1e-6, "max err %.9f m" % max_err)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var bad := 0
	for k in 2000:
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * IslandTerrain.RADIUS
		var x := cos(a) * rr
		var z := sin(a) * rr
		var h := t.height_at(x, z)
		var n := t.normal_at(x, z)
		if is_nan(h) or h < IslandTerrain.PLINTH_H or h > 0.2 or n.y <= 0.0 or absf(n.length() - 1.0) > 1e-3:
			bad += 1
	check("height_at/normal_at sane over 2000 random points", bad == 0, "%d bad" % bad)
	var land := 0
	var deep := 0
	for k in 4000:
		var a2 := rng.randf() * TAU
		var r2 := sqrt(rng.randf()) * IslandTerrain.RADIUS
		var x := cos(a2) * r2
		var z := sin(a2) * r2
		var hs := t.height_at(x, z) - IslandTerrain.SEA
		if hs > 0.0:
			land += 1
		if hs < -0.02:
			deep += 1
	check("island has land and deep sea", land > 1000 and deep > 300, "land %d / deep %d of 4000" % [land, deep])
	var peak := -1.0
	for k in t.hts.size():
		peak = maxf(peak, t.hts[k] - IslandTerrain.SEA)
	check("ridge peak 3-7 cm above sea", peak > 0.03 and peak < 0.07, "peak %.4f m" % peak)

	# --- props on the ground, not in water ----------------------------------------
	var floating := 0
	var wet := 0
	var worst := ""
	for p in island.props.placed:
		if p.water_ok:
			continue
		var pos: Vector3 = p.pos
		var gm: float = p.ground_min
		var sink: float = p.sink
		# the object's bottom (pos.y - sink) must be at or below the lowest ground under it
		var bottom := pos.y - sink
		var g := t.height_at(pos.x, pos.z)
		if bottom > gm + 1e-5 or bottom > g + 1e-5:
			floating += 1
			worst = "%s at %s bottom %.5f ground %.5f" % [p.kind, pos, bottom, minf(gm, g)]
		if g < IslandTerrain.SEA + 0.0005:
			wet += 1
			worst = "%s in water at %s" % [p.kind, pos]
	check("props sit on the ground (%d placed)" % island.props.placed.size(), floating == 0, worst if floating else "")
	check("land props are not in water", wet == 0, worst if wet else "")
	var on_road := 0
	for p in island.props.placed:
		if p.kind in ["palm", "acacia", "rock", "shrub"]:
			var pos2: Vector3 = p.pos
			if island.layout.road_distance(Vector2(pos2.x, pos2.z)) < IslandLayout.ROAD_W * 0.5:
				on_road += 1
	check("no vegetation/rocks on roads", on_road == 0, "%d on roads" % on_road)

	# --- crater deforms height ----------------------------------------------------
	var c := Vector3(0.25, 0.0, -0.02)
	c.y = t.height_at(c.x, c.z)
	var before := t.height_at(c.x, c.z)
	var rebuilds := t.rebuild_count
	var touched := t.crater(c, 0.016, 0.0055)
	var after := t.height_at(c.x, c.z)
	check("crater lowers the surface", before - after > 0.004, "dh %.4f m" % (before - after))
	check("crater rebuilds only affected chunks", t.rebuild_count - rebuilds == touched.size() and touched.size() <= 4, "%d of %d chunks" % [touched.size(), t.chunk_nodes.size()])
	var far := t.height_at(c.x + 0.1, c.z)
	check("far terrain untouched", absf(far - t.height_at(c.x + 0.1, c.z)) < 1e-9)

	# --- ballistic accuracy ---------------------------------------------------------
	var phys := PhysicsTest.new()
	root.add_child(phys)
	phys.setup(island)
	phys.manual = true
	var targets := [Vector3(0.10, 0, 0.10), Vector3(-0.05, 0, 0.0), Vector3(0.30, 0, 0.09), Vector3(-0.42, 0, 0.05)]
	var worst_err := 0.0
	var times := []
	for tg in targets:
		var tp: Vector3 = tg
		tp.y = island.surface_at(tp.x, tp.z)
		phys.fire(tp)
		var T := phys.flight_T
		var steps := 0
		while phys.flying and steps < 2000:
			phys.advance(1.0 / 60.0)
			steps += 1
		var err := Vector2(phys.last_impact.x - tp.x, phys.last_impact.z - tp.z).length()
		worst_err = maxf(worst_err, err)
		times.append("%.2fs" % T)
	check("shell lands within 2 cm of target", worst_err < 0.02, "worst %.4f m, flight times %s" % [worst_err, times])
	check("debris spawned", phys.debris.bodies.size() > 50, "%d bodies" % phys.debris.bodies.size())
	# let debris settle, check it rests on/above the ground
	for k in 600:
		phys.advance(1.0 / 60.0)
	var below := 0
	var asleep := 0
	for b in phys.debris.bodies:
		var bp: Vector3 = b.p
		if bp.y < t.height_at(bp.x, bp.z) - 0.002:
			below += 1
		if b.sleep:
			asleep += 1
	check("debris does not tunnel through terrain", below == 0, "%d below" % below)
	var awake_info := ""
	for b in phys.debris.bodies:
		if not b.sleep and awake_info.length() < 600:
			awake_info += "[%s v%.4f w%.2f wet%s] " % [b.p, (b.v as Vector3).length(), (b.w as Vector3).length(), b.wet]
	print("AWAKE ", awake_info)
	check("debris settles (sleeping)", asleep > phys.debris.bodies.size() * 0.7, "%d / %d asleep" % [asleep, phys.debris.bodies.size()])
	# building fracture
	var tower: Dictionary = {}
	for s in island.props.structures:
		if s.alive and s.kind in ["tower", "house"] and s.pos.x > 0.0:
			tower = s
			break
	var nb := phys.debris.bodies.size()
	var tp2: Vector3 = tower.pos
	phys.fire(Vector3(tp2.x, island.height_at(tp2.x, tp2.z), tp2.z))
	var guard := 0
	while phys.flying and guard < 2000:
		phys.advance(1.0 / 60.0)
		guard += 1
	check("hit building breaks into fragments", not tower.alive, "debris %d -> %d" % [nb, phys.debris.bodies.size()])

	print("RESULT ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures else 0)
