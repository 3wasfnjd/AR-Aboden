extends SceneTree
## Headless checks:  godot --headless --path . -s tests/test_headless.gd
## Prints PASS/FAIL per check and exits with code 1 on any failure.
## (tests/run_tests.sh additionally fails if the log contains "SCRIPT ERROR".)
## XR part (_xr_tests): placement maths, the XR rig headless, the MR/VR room switch,
## the Quest profile (merged vegetation, opaque sea, debris cap) and the physics test
## inside a moved / turned / scaled diorama.

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

	# --- no religious buildings, anywhere ----------------------------------------
	var forbidden := ["mosque", "minaret", "church", "chapel", "cathedral", "temple", "shrine", "synagogue", "dome"]
	var bad_kinds := []
	for st in island.props.structures:
		for f in forbidden:
			if (st.kind as String).to_lower().contains(f):
				bad_kinds.append(st.kind)
	for pl in island.props.placed:
		for f in forbidden:
			if (pl.kind as String).to_lower().contains(f):
				bad_kinds.append(pl.kind)
	check("no religious structure kinds placed", bad_kinds.is_empty(), str(bad_kinds))
	var src_hits := []
	for path in ["res://island/props.gd", "res://island/arch.gd", "res://island/layout.gd", "res://island/island.gd"]:
		var txt := FileAccess.get_file_as_string(path).to_lower()
		for f in ["mosque", "minaret", "church", "chapel", "cathedral", "temple", "shrine", "synagogue"]:
			if txt.contains(f):
				src_hits.append("%s:%s" % [path.get_file(), f])
	check("no religious building generators in source", src_hits.is_empty(), str(src_hits))
	# --- build 3: a full city + industry, every target destroyable --------------------
	var kinds := {}
	for st in island.props.structures:
		kinds[st.kind] = int(kinds.get(st.kind, 0)) + 1
	var need := ["skyscraper", "midrise", "house", "crude_tank", "column", "flare", "power_hall", "chimney", "cooling_tower", "desal", "water_tank", "sam", "tanker", "cargo", "frigate", "boat", "sts_crane", "jet", "has"]
	var missing := []
	for k in need:
		if int(kinds.get(k, 0)) == 0:
			missing.append(k)
	check("city, refinery, power, desalination, army and ships are all on the island", missing.is_empty() and int(kinds.get("skyscraper", 0)) >= 15 and int(kinds.get("house", 0)) >= 60, "missing %s, %s" % [missing, kinds])
	var untargeted := []
	for st in island.props.structures:
		if st.fragile and not IslandProps.TARGETS.has(st.kind):
			untargeted.append(st.kind)
		if IslandProps.TARGETS.has(st.kind) and not st.fragile:
			untargeted.append("solid " + st.kind)
	check("every destroyable structure counts for the destruction meter", untargeted.is_empty(), str(untargeted))
	var d0 := island.props.destruction()
	check("destruction meter starts at 0 %", d0.pct == 0.0 and int(d0.left) > 250, str(d0))

	# --- city life: cars + people move, die in a blast, flee from it ---------------
	var life := island.life
	var lb_c0 := life.a_pos.duplicate()
	for k in 60:
		life.step(1.0 / 60.0)
	var lb_moved := 0
	for i in life.agent_count():
		if life.a_pos[i].distance_to(lb_c0[i]) > 0.002:
			lb_moved += 1
	check("city life: cars and people move along the streets", life.nodes.size() > 30 and lb_moved > life.agent_count() * 0.8, "%d crossings, %d / %d moved" % [life.nodes.size(), lb_moved, life.agent_count()])
	var lb_p := life.a_pos[0]
	var lb_near := []
	for i in life.agent_count():
		var dd := Vector2(life.a_pos[i].x - lb_p.x, life.a_pos[i].z - lb_p.z).length()
		if dd > 0.03 and dd < 0.08:
			lb_near.append([i, dd])
	var lb_alive0 := life.alive_count()
	life.on_blast(lb_p, PhysicsTest.BLAST_R * 1.45)
	var lb_killed := lb_alive0 - life.alive_count()
	for k in 120:
		life.step(1.0 / 60.0)
	var lb_fled := 0
	for e in lb_near:
		var i2: int = e[0]
		if life.a_alive[i2] == 1 and Vector2(life.a_pos[i2].x - lb_p.x, life.a_pos[i2].z - lb_p.z).length() > float(e[1]):
			lb_fled += 1
	check("city life: the blast kills inside and the rest flee away from it", lb_killed >= 1 and life.a_alive[0] == 0 and lb_fled >= int(lb_near.size() * 0.6), "killed %d, fled %d / %d" % [lb_killed, lb_fled, lb_near.size()])
	life.spawn()
	check("city life: reset brings everyone back", life.alive_count() == life.agent_count())

	# --- missions: objectives, clock, stars, civilian losses ------------------------
	var ms := Missions.new()
	var empty_goals := []
	for md in Missions.LIST:
		ms.select(md.id)
		var pr0 := ms.progress(island.props)
		if int(pr0[1]) <= 0:
			empty_goals.append(md.id)
	check("every mission has targets on the island", empty_goals.is_empty(), str(empty_goals))
	check("mission selector cycles free play -> missions -> free play", Missions.cycle("", 1) == "precision" and Missions.cycle("precision", -1) == "" and Missions.cycle("total", 1) == "")
	island.reset_damage()
	ms.select("blackout")
	ms.start(island.props)
	ms.step(5.0, island.props)
	for st in island.props.structures:
		if IslandProps.TARGETS.has(st.kind) and IslandProps.TARGETS[st.kind][0] == "power":
			st.alive = false
	var ended := ms.step(1.0, island.props)
	check("mission: objective done fast with no civilian losses = 3 stars", ended and ms.result == "won" and ms.stars == 3 and int(ms.best.get("blackout", 0)) == 3, "%s %d stars" % [ms.result, ms.stars])
	island.reset_damage()
	ms.select("oil")
	ms.start(island.props)
	var hit_civ := 0
	for st in island.props.structures:
		if st.kind == "house" and hit_civ < 5:
			st.alive = false
			hit_civ += 1
	ms.step(100.0, island.props)
	for st in island.props.structures:
		if IslandProps.TARGETS.has(st.kind) and IslandProps.TARGETS[st.kind][0] == "oil":
			st.alive = false
	ms.step(1.0, island.props)
	check("mission: late and with civilian losses = 1 star", ms.result == "won" and ms.stars == 1 and ms.civilians(island.props) == 5, "%s %d stars, civ %d" % [ms.result, ms.stars, ms.civilians(island.props)])
	island.reset_damage()
	ms.select("fleet")
	ms.start(island.props)
	var steps_f := 0
	while ms.running and steps_f < 200:
		ms.step(1.0, island.props)
		steps_f += 1
	check("mission: time runs out = failed, no stars", ms.result == "failed" and ms.stars == 0 and ms.time_left == 0.0)
	island.reset_damage()

	# --- scale consistency (1:2000) -------------------------------------------------
	var rl := island.layout.runway_len * Scale.RATIO
	check("runway 600 m x 25 m", absf(rl - 600.0) < 1.0 and absf(island.layout.runway_w * Scale.RATIO - 25.0) < 0.5, "%.0f m x %.1f m" % [rl, island.layout.runway_w * Scale.RATIO])
	var storey_bad := 0
	for st in island.props.structures:
		if st.kind in ["house", "villa", "midrise", "skyscraper"]:
			var n: float = st.size.y / Toon.STOREY
			if absf(n - round(n)) > 0.01 or n < 0.99 or n > 30.5:
				storey_bad += 1
	check("buildings are whole toy storeys", storey_bad == 0, "%d off-grid" % storey_bad)
	# build 10: no palms, and no tree LOD swapping (it popped as the head moved)
	var lod_nodes := 0
	for mmi in island.props.find_children("MM_*", "MultiMeshInstance3D", false, false):
		if (mmi as MultiMeshInstance3D).visibility_range_end > 0.0 or (mmi as MultiMeshInstance3D).visibility_range_begin > 0.0:
			lod_nodes += 1
	check("no palm trees, no vegetation LOD swapping", not island.props.species.has("palm") and island.props.species.has("acacia") and lod_nodes == 0, "%s, %d LOD nodes" % [island.props.species.keys(), lod_nodes])

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

	# --- roads break inside a crater ---------------------------------------------
	var road_mi: MeshInstance3D = island.props.drape_mi[0]
	var tris_before := (road_mi.mesh as ArrayMesh).surface_get_array_len(0)
	var rp: Vector2 = island.layout.road_samples()[0][60]
	var rc := Vector3(rp.x, t.height_at(rp.x, rp.y), rp.y)
	t.crater(rc, 0.016, 0.0055)
	island.props.on_crater(rc, 0.016)
	await process_frame
	await process_frame   # re-drapes run one group per frame in IslandProps._process
	var road_mi2: MeshInstance3D = island.props.drape_mi[0]
	var tris_after := (road_mi2.mesh as ArrayMesh).surface_get_array_len(0)
	check("road ribbon is broken inside the crater", tris_after < tris_before, "%d -> %d verts" % [tris_before, tris_after])

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
	check("debris spawned", phys.debris.bodies.size() + phys.debris.settled_count() > 50, "%d live + %d settled" % [phys.debris.bodies.size(), phys.debris.settled_count()])
	# let debris settle, check it rests on/above the ground
	for k in 600:
		phys.advance(1.0 / 60.0)
	var below := 0
	var asleep := phys.debris.settled_count()
	for bp in phys.debris.all_positions():
		if bp.y < t.height_at(bp.x, bp.z) - 0.002:
			below += 1
	for b in phys.debris.bodies:
		if b.sleep:
			asleep += 1
	check("debris does not tunnel through terrain", below == 0, "%d below" % below)
	var awake_info := ""
	for b in phys.debris.bodies:
		if not b.sleep and awake_info.length() < 600:
			awake_info += "[%s v%.4f w%.2f wet%s] " % [b.p, (b.v as Vector3).length(), (b.w as Vector3).length(), b.wet]
	print("AWAKE ", awake_info)
	var total_d := phys.debris.bodies.size() + phys.debris.settled_count()
	check("debris settles (sleeping or baked into the static set)", asleep > total_d * 0.7 and phys.debris.settled_count() > 0, "%d / %d at rest (%d baked)" % [asleep, total_d, phys.debris.settled_count()])
	# debris lands on (not through) a standing building roof
	var roof_st: Dictionary = {}
	for st in island.props.structures:
		if st.alive and st.kind == "midrise":
			roof_st = st
			break
	var rpos: Vector3 = roof_st.pos
	var roof_y: float = rpos.y + roof_st.size.y
	phys.debris.clear()
	phys.debris.spawn(rpos + Vector3(0, roof_st.size.y + 0.01, 0), Basis(), Vector3(0.0006, 0.0006, 0.0006), Vector3.ZERO, Vector3.ZERO, Color.WHITE, 1)
	for k in 300:
		phys.advance(1.0 / 60.0)
	var by: float = phys.debris.all_positions()[0].y
	check("debris rests on a building roof", by > roof_y - 0.0005 and by < roof_y + 0.003, "body y %.4f, roof %.4f" % [by, roof_y])
	# building fracture
	var tower: Dictionary = {}
	for s in island.props.structures:
		if s.alive and s.kind in ["skyscraper", "house"] and s.pos.x > 0.0:
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
	var d1 := island.props.destruction()
	check("destruction meter rises after a hit", d1.pct > 0.0 and int(d1.left) < int(d0.left) and int(d1.cats.city[0]) > 0, "%.2f %%, left %d" % [d1.pct, d1.left])
	# a ship is a target too
	var ship: Dictionary = {}
	for s in island.props.structures:
		if s.alive and s.kind == "frigate":
			ship = s
			break
	var sp3: Vector3 = ship.pos
	phys.fire(Vector3(sp3.x, IslandTerrain.SEA, sp3.z))
	guard = 0
	while phys.flying and guard < 2000:
		phys.advance(1.0 / 60.0)
		guard += 1
	check("a warship hit at sea is destroyed (splash, no crater)", not ship.alive and phys.last_impact_kind == "water", "kind %s" % phys.last_impact_kind)

	# --- the player's warship behind the mountain; the nuclear test -----------------
	var shp := island.ship
	var sp0 := shp.position
	check("player warship floats in deep water behind the mountain (inside the dome)", island.props._hs(sp0.x, sp0.z) < -0.02 and sp0.z < -0.3 and Vector2(sp0.x, sp0.z).length() + PlayerShip.L * 0.5 < GlassDome.R, "at %s" % sp0)
	var lp_v := phys.default_origin("ballistic")
	var lp_g := phys.default_origin("artillery")
	check("shots leave the ship's launchers (cells for missiles, the bow gun for shells)", lp_v.distance_to(sp0) < 0.1 and lp_g.distance_to(sp0) < 0.1 and lp_v.distance_to(lp_g) > 0.02, "%s / %s" % [lp_v, lp_g])
	island.reset_damage()
	var ncen := Vector3(island.layout.town_center.x, 0, island.layout.town_center.y)
	ncen.y = island.height_at(ncen.x, ncen.z)
	var alive_city := 0
	for st in island.props.structures:
		if st.kind in Missions.CIVIL and Vector2(st.pos.x - ncen.x, st.pos.z - ncen.z).length() < 0.1:
			alive_city += 1
	var pct0 := float(island.props.destruction().pct)
	phys.fire(ncen, Vector3.INF, "nuke")
	var gn := 0
	while phys.flying and gn < 4000:
		phys.advance(1.0 / 60.0)
		gn += 1
	var left_city := 0
	for st in island.props.structures:
		if st.alive and Vector2(st.pos.x - ncen.x, st.pos.z - ncen.z).length() < 0.1 and IslandProps.TARGETS.has(st.kind):
			left_city += 1
	var pct1 := float(island.props.destruction().pct)
	check("nuclear test: mushroom cloud, everything within its radius destroyed", phys.last_impact_kind == "nuke" and left_city == 0 and alive_city > 50 and pct1 > pct0 + 25.0 and phys.fx.puffs.size() > 80 and island.life.alive_near(ncen, 0.12) == 0 and shp.visible, "kind %s, %d left of %d, %.0f%% -> %.0f%%, puffs %d" % [phys.last_impact_kind, left_city, alive_city, pct0, pct1, phys.fx.puffs.size()])
	for k in 200:
		phys.advance(1.0 / 60.0)
		await process_frame
	check("nuclear test: the destroyed tiles re-upload over the next frames", island.props._pending_tiles.is_empty())
	# strike jet: takes off from the deck, drops 4 bombs on the target, flies home, lands
	phys.reset_island()
	var tj := Vector3(0.10, 0, 0.02)
	tj.y = island.height_at(tj.x, tj.z)
	var landed := []
	var on_land := func(wid: String): landed.append(wid)
	phys.sortie_landed.connect(on_land)
	var n_j := phys.impact_count
	var plj := phys.fire(tj, Vector3.INF, "jet")
	var low_j := 0
	for k in 200:
		var pj := WeaponFlight.position_at(plj, float(plj.T) * k / 200.0)
		var gj := phys.surface(pj.x, pj.z)
		if k > 8 and k < 192 and gj > -INF and pj.y < gj + 0.015:
			low_j += 1
	var sj := 0
	while phys.flying and sj < 6000:
		phys.advance(1.0 / 60.0)
		sj += 1
	phys.sortie_landed.disconnect(on_land)
	var end_j := WeaponFlight.position_at(plj, float(plj.T))
	check("strike jet: 4 bombs on the target, back on the deck, a long trip", phys.impact_count - n_j == 4 and landed == ["jet"] and end_j.distance_to(phys.default_origin("jet")) < 0.003 and float(plj.T) > 6.0 and low_j == 0 and Vector2(phys.last_impact.x - tj.x, phys.last_impact.z - tj.z).length() < 0.04, "%d bombs, landed %s, T %.1f s, low %d" % [phys.impact_count - n_j, landed, plj.T, low_j])
	# every weapon from the ship stays under the glass dome, to targets all over the island
	var through := []
	for wid in WeaponTable.IDS:
		for tz in [Vector2(0.07, 0.05), Vector2(-0.3, 0.1), Vector2(0.33, 0.03), Vector2(-0.03, -0.16), Vector2(0.0, 0.3), Vector2(-0.4, -0.15)]:
			var tg3 := Vector3(tz.x, island.surface_at(tz.x, tz.y), tz.y)
			var pl3 := phys.plan(tg3, Vector3.INF, wid)
			for k in 64:
				var pp3 := WeaponFlight.position_at(pl3, float(pl3.T) * k / 64.0)
				if pp3.y > WeaponFlight.dome_ceiling(pp3.x, pp3.z) + WeaponFlight.DOME_MARGIN:
					through.append("%s->%s" % [wid, tz])
					break
	check("no shot from the ship goes through the glass dome", through.is_empty(), str(through))
	phys.reset_island()

	# everything stays under the glass dome: debris thrown hard and rising smoke
	phys.debris.clear()
	phys.fx.clear()
	for k in 30:
		phys.debris.spawn(Vector3(0.05 + k * 0.01, 0.15, 0.0), Basis(), Vector3(0.001, 0.001, 0.001), Vector3(0.3, 1.2, 0.2), Vector3.ZERO, Color.WHITE, 1)
	for k in 40:
		phys.fx.puff(Vector3(0.3 + k * 0.004, 0.2, 0.1), Vector3(0.1, 0.3, 0.0), 0.01, 0.04, 6.0, Color(0.5, 0.5, 0.5, 0.8), 3, 0.05, 0.2)
	var out := 0
	for f in 240:
		phys.advance(1.0 / 60.0)
		for p in phys.debris.all_positions():
			if (p as Vector3).y > WeaponFlight.dome_ceiling(p.x, p.z) + WeaponFlight.DOME_MARGIN + 0.001 or Vector2(p.x, p.z).length() > GlassDome.R:
				out += 1
		for q in phys.fx.puffs:
			var qp2: Vector3 = q.p
			if qp2.y > WeaponFlight.dome_ceiling(qp2.x, qp2.z) + WeaponFlight.DOME_MARGIN + 0.001 or Vector2(qp2.x, qp2.z).length() > GlassDome.R:
				out += 1
	check("debris and smoke stay inside the glass dome", out == 0, "%d samples outside" % out)
	phys.debris.clear()
	phys.fx.clear()
	_campaign_tests(island, phys)
	await _map2_tests()
	await _xr_tests(island, phys)

	print("RESULT ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures else 0)


# ======================================================================================
# XR / Quest build
# ======================================================================================

# ======================================================================================
# campaign: chapters, stages, progress, the purchase gate, civilians, stars, resistance
# ======================================================================================

func _campaign_tests(island: Island, phys: PhysicsTest) -> void:
	# every built stage has a reachable objective on this island and a briefing
	var bad: Array = []
	for c in Campaign.CHAPTERS:
		var list := Campaign.stages_of(int(c.n))
		if list.size() != (9 if int(c.n) == 0 else 5):
			bad.append("chapter %d has %d stages" % [c.n, list.size()])
		for s in list:
			if not Campaign.is_built(s):
				continue
			var run := StageRun.new()
			phys.forces.configure(s)
			run.start(s, island.props)
			run.forces = phys.forces
			var pr := run.progress(island.props)
			if int(pr[1]) <= 0 and not bool(s.get("survive", false)):
				bad.append("%s: no target on the island" % s.id)
			if int(c.n) > 0 and (not s.has("brief") or (s.brief as Array).is_empty() or not s.has("won") or not s.has("failed")):
				bad.append("%s: no briefing / debrief" % s.id)
			for line in s.get("brief", []):
				if not Campaign.TEAM.has(line[0]):
					bad.append("%s: unknown speaker %s" % [s.id, line[0]])
	check("campaign: 5 chapters, 5 stages each (9 drills), every built stage has targets and a briefing", bad.is_empty() and Campaign.CHAPTERS.size() == 5, str(bad))
	phys.forces.clear()
	check("campaign: chapters 0-1 free, 2-4 sold; chapters 0-2 built (chapter 2 on Crescent Island)", Campaign.chapter(1).free and Campaign.chapter(1).built and Campaign.chapter(2).built and int(Campaign.chapter(2).map) == 2 and not Campaign.chapter(2).free and not Campaign.chapter(4).free)

	# progress: order, the purchase gate, unlock_all
	var pg := Progress.new()
	var c1 := Campaign.stages_of(1)
	var ok_order := pg.stage_state(c1[0]) == "open" and pg.stage_state(c1[1]) == "locked" and pg.next_stage() == "c1s1"
	pg.best["c1s1"] = 2
	ok_order = ok_order and pg.stage_state(c1[1]) == "open" and pg.next_stage() == "c1s2"
	var c2 := Campaign.stages_of(2)
	var gate := pg.stage_state(c2[0]) == "buy" and pg.stage_state(Campaign.stages_of(3)[0]) == "soon" and not pg.owns(2) and pg.owns(1) and pg.owns(0)
	Progress.unlock_all = true
	gate = gate and pg.owns(3) and pg.stage_state(c1[4]) == "open"
	Progress.unlock_all = false
	check("progress: stages open in order, chapter 1 free, 2-4 need a purchase, unlock_all for tests", ok_order and gate)

	# stars from civilian casualties; failing on civilians, time and the ship's hull
	var st_ok := StageRun.stars_for(0) == 3 and StageRun.stars_for(1) == 2 and StageRun.stars_for(2) == 2 and StageRun.stars_for(3) == 1
	var run2 := StageRun.new()
	var s1 := Campaign.get_stage("c1s1")
	run2.start(s1, island.props, 100)
	run2.set_life_alive(97)
	var civ3 := run2.civilians(island.props) == 3
	run2.set_life_alive(94)
	run2.step(0.1, island.props)
	var civ_fail := run2.result == "failed" and run2.fail_reason == "civilians"
	var run3 := StageRun.new()
	run3.start(s1, island.props)
	for k in 4:
		run3.ship_hit()
	run3.step(0.1, island.props)
	var ship_fail := run3.result == "failed" and run3.fail_reason == "ship" and run3.hull == 0.0
	var run4 := StageRun.new()
	run4.start(s1, island.props)
	run4.step(9999.0, island.props)
	var time_fail := run4.fail_reason == "time"
	# winning: destroy the radar dome -> 3 stars with no casualties
	var run5 := StageRun.new()
	run5.start(s1, island.props)
	for stc in island.props.structures:
		if stc.kind == "radar_sphere":
			stc.alive = false
	run5.step(0.1, island.props)
	var won := run5.result == "won" and run5.stars == 3
	for stc in island.props.structures:
		if stc.kind == "radar_sphere":
			stc.alive = true
	check("stage rules: 0 civilians 3 stars, 1-2 two, 3+ one; fail on 6 civilians, the ship's hull or the clock",
		st_ok and civ3 and civ_fail and ship_fail and time_fail and won, "civ3 %s civ_fail %s ship %s time %s won %s" % [civ3, civ_fail, ship_fail, time_fail, won])

	# resistance: SAMs shoot down slow drones flying over them, coastal launchers hit the ship
	phys.reset_island()
	var res := phys.resistance
	res.configure({"sam": true, "coastal": 0.0})
	res.rng.seed = 1
	var sam_c := Vector3(-0.030, 0.0, -0.154)
	var tgt := Vector3(sam_c.x + 0.01, 0.0, sam_c.z + 0.02)
	tgt.y = island.surface_at(tgt.x, tgt.z)
	var downs := 0
	var lost := [0]
	var on_int := func(_p: Vector3, _w: String) -> void: lost[0] += 1
	res.intercepted.connect(on_int)
	for k in 6:
		phys.fire(tgt, Vector3.INF, "drone")
		for f in 72 * 10:
			phys.advance(1.0 / 72.0)
			if phys.flights.is_empty():
				break
	downs = res.shots_down
	res.intercepted.disconnect(on_int)
	var ok_sam: bool = downs >= 2 and downs == int(lost[0])
	res.configure({"sam": true, "coastal": 0.0})
	var art := 0
	var imp0 := phys.impact_count
	for k in 4:
		phys.fire(tgt, Vector3.INF, "artillery")
		for f in 72 * 5:
			phys.advance(1.0 / 72.0)
			if phys.flights.is_empty():
				break
	art = phys.impact_count - imp0
	check("air defence: SAMs shoot down drones over them (%d of 6), never artillery shells" % downs, ok_sam and art == 4 and res.shots_down == 0, "art impacts %d" % art)
	res.configure({"sam": false, "coastal": 5.0})
	var hits := [0]
	var kills := [0]
	var on_hit := func(_p: Vector3) -> void: hits[0] += 1
	var on_kill := func(_p: Vector3) -> void: kills[0] += 1
	res.ship_hit.connect(on_hit)
	res.ciws_kill.connect(on_kill)
	for f in 72 * 60:
		phys.advance(1.0 / 72.0)
	res.ship_hit.disconnect(on_hit)
	res.ciws_kill.disconnect(on_kill)
	check("coastal launchers fire at the battleship: some get through, the gun stops some", hits[0] >= 1 and kills[0] >= 1 and hits[0] + kills[0] >= 8, "hits %d gun kills %d" % [hits[0], kills[0]])
	# with every launcher destroyed nothing more comes
	for stc in island.props.structures:
		if stc.kind in Resistance.ENEMY_KINDS:
			stc.alive = false
	var none := not res.fire_coastal()
	for stc in island.props.structures:
		if stc.kind in Resistance.ENEMY_KINDS:
			stc.alive = true
	res.clear()
	phys.reset_island()
	check("no launchers left: no more enemy missiles", none)
	# --- build 18: the Viper's mobile forces ---------------------------------------
	phys.reset_island()
	var fo := phys.forces
	fo.configure({"forces": {"tank": 2, "apc": 1, "spaa": 1, "mlauncher": 1, "fighter": 2, "air": 6.0}})
	phys.resistance.configure({"sam": false, "coastal": 12.0})
	var p0s: Array = []
	for u in fo.units:
		p0s.append(u.p)
	var dmg := [0.0]
	var on_dmg := func(_p: Vector3, d: float) -> void: dmg[0] += d
	fo.ship_damaged.connect(on_dmg)
	var hits_f := [0]
	var on_hf := func(_p: Vector3) -> void: hits_f[0] += 1
	phys.resistance.ship_hit.connect(on_hf)
	var took_off := false
	var on_land_ok := true
	for f in 72 * 40:
		phys.advance(1.0 / 72.0)
		for u in fo.units:
			if u.kind == "fighter" and u.state != "parked":
				took_off = true
			if u.kind in EnemyForces.ARMOR and absf((u.p as Vector3).y - island.surface_at(u.p.x, u.p.z)) > 1e-4:
				on_land_ok = false
	var moved := 0
	for k in fo.units.size():
		if fo.units[k].kind in EnemyForces.ARMOR and (fo.units[k].p as Vector3).distance_to(p0s[k]) > 0.01:
			moved += 1
	fo.ship_damaged.disconnect(on_dmg)
	phys.resistance.ship_hit.disconnect(on_hf)
	check("enemy armour patrols on the ground (%d of 5 moved), tanks shell the ship (%.0f damage), fighters take off, launchers and jets fire missiles (%d hits)" % [moved, dmg[0], hits_f[0]],
		moved >= 4 and dmg[0] > 0.0 and took_off and hits_f[0] >= 1 and on_land_ok)
	# our anti-air missile homes on an airborne fighter and aa_downs it
	var aa_downs := [0]
	var on_aa_down := func(_p: Vector3) -> void: aa_downs[0] += 1
	fo.fighter_down.connect(on_aa_down)
	var air := fo.airborne()
	var fired_aa := false
	for f in 72 * 20:
		if not fired_aa and not fo.airborne().is_empty():
			fired_aa = fo.fire_aa(island.ship.launch_point("aa"))
		phys.advance(1.0 / 72.0)
		if aa_downs[0] > 0:
			break
	fo.fighter_down.disconnect(on_aa_down)
	var none_aa := false
	for u in fo.units:
		if u.kind == "fighter":
			u.state = "parked"
	none_aa = not fo.fire_aa(Vector3.ZERO)
	check("anti-air missile: homes on a fighter in the air and downs it; nothing in the air, no launch", fired_aa and aa_downs[0] == 1 and none_aa, "air %d" % air.size())
	# a blast kills the tank under it, leaving a wreck
	var tank: Dictionary = {}
	for u in fo.units:
		if u.kind == "tank" and u.alive:
			tank = u
	var tp: Vector3 = tank.p
	fo.on_blast(tp, 0.01)
	check("a blast on a tank destroys it", not tank.alive and fo.kills.get("tank", 0) >= 1)
	# the mobile anti-aircraft gun shoots at a slow drone passing over it
	fo.configure({"forces": {"spaa": 1}})
	var sp: Vector3 = fo.units[0].p
	var shot0 := phys.resistance.shots_down
	for k in 8:
		var dt_ := Vector3(sp.x + 0.03, 0.0, sp.z + 0.01)
		dt_.y = island.surface_at(dt_.x, dt_.z)
		phys.fire(dt_, Vector3.INF, "drone")
		for f in 72 * 9:
			phys.advance(1.0 / 72.0)
			if not phys.flying:
				break
	check("mobile anti-aircraft gun shoots down some drones passing over it (%d of 8)" % (phys.resistance.shots_down - shot0), phys.resistance.shots_down - shot0 >= 1)
	fo.clear()
	phys.resistance.clear()
	phys.reset_island()
	# survive and protect rules
	var rs := StageRun.new()
	rs.start(Campaign.get_stage("c2s5"), island.props)
	rs.step(10.0, island.props)
	var mid := rs.running
	rs.step(200.0, island.props)
	var rp := StageRun.new()
	rp.start(Campaign.get_stage("c2s4"), island.props)
	for stc in island.props.structures:
		if stc.kind == "desal":
			stc.alive = false
			break
	rp.step(0.1, island.props)
	for stc in island.props.structures:
		if stc.kind == "desal":
			stc.alive = true
	check("survive stage won by holding out; protect stage fails if the desalination plant is hit", mid and rs.result == "won" and rp.result == "failed" and rp.fail_reason == "protect")

	# the nuclear cloud rises to the top of the dome and stays under the glass
	phys.fx.clear()
	var np0 := Vector3(0.05, 0.0, 0.0)
	np0.y = island.surface_at(np0.x, np0.z)
	phys.fx.nuke(np0, 0.16)
	var top_n := 0.0
	var out_n := 0
	var top_t := 0.0
	for f in 60 * 12:
		phys.fx.step(1.0 / 60.0)
		for q in phys.fx.puffs:
			if int(q.kind) == 1:
				continue   # the flash and the fire glow: the cloud is the smoke
			var qp: Vector3 = q.p
			var t01: float = q.age / q.life
			var rad: float = lerpf(q.s0, q.s1, 1.0 - pow(1.0 - t01, 2.0)) * 0.7
			if qp.y + rad > top_n:
				top_n = qp.y + rad
				top_t = f / 60.0
			if qp.y > WeaponFlight.dome_ceiling(qp.x, qp.z) + WeaponFlight.DOME_MARGIN + 0.001:
				out_n += 1
	var dome_top := IslandTerrain.SEA + GlassDome.K * GlassDome.R
	check("nuclear cloud: rises over ~%.0f s to the top of the dome (%.3f of %.3f m) and stays under the glass" % [top_t, top_n - IslandTerrain.SEA, dome_top - IslandTerrain.SEA],
		top_n > dome_top - 0.03 and out_n == 0 and top_t > 3.0, "%d outside" % out_n)
	phys.fx.clear()
	# the drone swarm: six small drones from the stern ramp, spread over the target
	var stgt := Vector3(0.10, 0.0, 0.05)
	stgt.y = island.surface_at(stgt.x, stgt.z)
	var imp_s := phys.impact_count
	phys.fire(stgt, Vector3.INF, "swarm")
	var far_s := 0.0
	var pts_s: Array = []
	var on_imp := func(p: Vector3, _k: String) -> void: pts_s.append(p)
	phys.impacted.connect(on_imp)
	for f in 72 * 12:
		phys.advance(1.0 / 72.0)
		if not phys.flying:
			break
	phys.impacted.disconnect(on_imp)
	for q in pts_s:
		far_s = maxf(far_s, Vector2((q as Vector3).x - stgt.x, (q as Vector3).z - stgt.z).length())
	check("drone swarm: 6 drones, 6 small blasts within %.0f mm of the target (%d)" % [far_s * 1000.0, phys.impact_count - imp_s], phys.impact_count - imp_s == 6 and far_s < 0.035 and WeaponTable.IDS.has("swarm"))
	phys.reset_island()


## Crescent Island (map 2): builds, mirrored plan, the battleship in deep water, every
## chapter-2 objective present.
func _map2_tests() -> void:
	var m2 := Island.new()
	m2.map_id = 2
	root.add_child(m2)
	await process_frame
	var sp2 := m2.ship.position
	var deep := m2.terrain.height_at(sp2.x, sp2.z) < IslandTerrain.SEA - 0.006
	var m2p := PhysicsTest.new()
	root.add_child(m2p)
	m2p.setup(m2)
	m2p.manual = true
	var miss: Array = []
	for s in Campaign.stages_of(2):
		m2p.forces.configure(s)
		var r2 := StageRun.new()
		r2.start(s, m2.props)
		r2.forces = m2p.forces
		if int(r2.progress(m2.props)[1]) <= 0 and not bool(s.get("survive", false)):
			miss.append(s.id)
	var town2 := m2.layout.town_center
	check("map 2 (Crescent Island): mirrored plan (town at x %.2f), %d structures, ship in deep water, every chapter-2 objective on it %s" % [town2.x, m2.props.structures.size(), miss],
		m2.layout.mirror and town2.x < 0.0 and m2.props.structures.size() > 250 and deep and miss.is_empty())
	m2p.queue_free()
	m2.queue_free()
	await process_frame


func pulses_of(x: XRGame) -> int:
	return x.rig.pulses


func _near(a: float, b: float, eps := 1e-5) -> bool:
	return absf(a - b) <= eps


func _xr_tests(island: Island, phys: PhysicsTest) -> void:
	# --- placement maths --------------------------------------------------------------
	var P := Vector3(0.3, 0.74, -0.6)
	var xf := Placement.pinned_transform(P, 0.7, 0.8)
	var foot := xf * Vector3.ZERO
	check("pinned base sits on the plane height", _near(foot.y, 0.74) and foot.distance_to(P) < 1e-6, "base bottom y %.5f" % foot.y)
	var rim := xf * Vector3(Placement.OUTER_R, 0.0, 0.0)
	check("pinned base: scale applied", _near(rim.y, 0.74) and _near(Vector2(rim.x - P.x, rim.z - P.z).length(), Placement.OUTER_R * 0.8) and _near(xf.basis.get_scale().x, 0.8), "rim radius %.4f m" % Vector2(rim.x - P.x, rim.z - P.z).length())
	var front := xf.basis * Vector3(0, 0, 1)
	check("pinned base: rotation applied (front +Z turned 0.7 rad)", _near(atan2(front.x, front.z), 0.7), "yaw %.4f" % atan2(front.x, front.z))
	check("scale clamped to 0.4-1.5", _near(Placement.pinned_transform(P, 0.0, 3.0).basis.get_scale().x, 1.5) and _near(Placement.pinned_transform(P, 0.0, 0.1).basis.get_scale().x, 0.4))
	var eye := Vector3(1.0, 1.6, 0.5)
	var fy := Placement.facing_yaw(P, eye)
	var fdir := Placement.pinned_transform(P, fy, 1.0).basis * Vector3(0, 0, 1)
	var to_eye := Vector3(eye.x - P.x, 0, eye.z - P.z).normalized()
	check("placement faces the user", fdir.dot(to_eye) > 0.9999)
	var s := 1.0
	var yaw := 0.0
	for k in 600:
		var r := Placement.apply_stick(s, yaw, Vector2(0.0, 1.0), 1.0 / 72.0)
		s = r[0]
	var s_up := s
	for k in 1200:
		var r := Placement.apply_stick(s, yaw, Vector2(0.0, -1.0), 1.0 / 72.0)
		s = r[0]
	var r2 := Placement.apply_stick(1.0, 0.0, Vector2(1.0, 0.0), 0.5)
	var r3 := Placement.apply_stick(1.0, 0.0, Vector2(0.1, 0.1), 0.5)
	check("right stick: Y scales within 0.4-1.5, X turns, deadzone", _near(s_up, 1.5) and _near(s, 0.4) and float(r2[1]) < -0.5 and _near(float(r3[0]), 1.0) and _near(float(r3[1]), 0.0), "max %.2f min %.2f yaw %.2f" % [s_up, s, r2[1]])
	var vh := Placement.virtual_hit(Vector3(0, 1.2, 0), Vector3(0, -1, -1))
	var vf := Placement.virtual_hit(Vector3(0, 1.2, 0), Vector3(0, -1, -1), 0.0)
	check("virtual table plane at 0.75 m / floor fallback", not vh.is_empty() and _near((vh.p as Vector3).y, 0.75) and _near((vh.p as Vector3).z, -0.45) and not vf.is_empty() and _near((vf.p as Vector3).y, 0.0) and Placement.virtual_hit(Vector3(0, 1.2, 0), Vector3(0, 0.2, -1)).is_empty())
	var fp := Placement.float_point(Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.2, 1.6, 0.1)))
	check("unplaced model floats ahead at hand height", _near(fp.y, 1.6 - Placement.HAND_DROP) and _near(Vector2(fp.x - 0.2, fp.z - 0.1).length(), Placement.FLOAT_AHEAD))

	# --- real table plane (Meta scene stand-in) -> the base on it ---------------------
	var surf := SceneSurfaces.new()
	root.add_child(surf)
	surf.add_test_plane(Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0.0, 0.72, -0.8)), Vector2(1.4, 0.8), "table")
	surf.add_test_box(Transform3D(Basis(), Vector3(1.5, 0.22, -0.8)), Vector3(0.8, 0.44, 0.5), "storage")
	var th := surf.ray_surface(Vector3(0.1, 1.5, 0.0), Vector3(0.0, -1.0, -1.0))
	var bh := surf.ray_surface(Vector3(1.5, 1.5, 0.0), Vector3(0.0, -1.0, -0.6))
	var miss := surf.ray_surface(Vector3(3.0, 1.5, 0.0), Vector3(0.0, -1.0, -0.6))
	check("scene table plane / volume top is hit from above", not th.is_empty() and th.label == "table" and _near((th.p as Vector3).y, 0.72) and not bh.is_empty() and _near((bh.p as Vector3).y, 0.44) and miss.is_empty(), "%s / %s" % [th, bh])
	var dio := Node3D.new()
	dio.name = "TestDiorama"
	root.add_child(dio)
	dio.transform = Placement.pinned_transform(th.p, 1.1, 0.6)
	var foot_w := dio.global_transform * Vector3.ZERO
	var tp := Vector3(0.12, 0.0, 0.05)
	tp.y = island.height_at(tp.x, tp.z)
	var tw := dio.global_transform * tp
	check("diorama on the scene table: base bottom at the table top", _near(foot_w.y, 0.72), "y %.5f" % foot_w.y)
	check("diorama on the scene table: terrain height scaled", _near(tw.y - 0.72, tp.y * 0.6), "%.5f vs %.5f" % [tw.y - 0.72, tp.y * 0.6])
	# aiming: a world ray at a world point of the island returns that point (local)
	var eye_w := dio.global_transform * Vector3(0.0, 0.5, 0.6)
	var lr := Placement.local_ray(dio.global_transform, eye_w, (tw - eye_w).normalized())
	var aim_ok := false
	var aim_err := -1.0
	if not lr.is_empty():
		var o: Vector3 = lr[0]
		var d: Vector3 = lr[1]
		var hit: Variant = island.terrain.raycast(o + d * float(lr[2]), d, float(lr[3]) - float(lr[2]) + 0.004)
		if hit != null:
			aim_err = (hit as Vector3).distance_to(tp)
			aim_ok = aim_err < 0.003
	check("controller ray -> island-local aim point", aim_ok, "err %.5f m" % aim_err)
	check("ray missing the slab is rejected", Placement.local_ray(dio.global_transform, eye_w, Vector3.UP).is_empty())

	# --- XR rig + MR/VR switch, headless --------------------------------------------
	var room := Room.new()
	room.name = "Room"
	root.add_child(room)
	var dio2 := Node3D.new()
	root.add_child(dio2)
	var xg := XRGame.new()
	root.add_child(xg)
	xg.setup(room, dio2, island, phys)
	var started := xg.start()
	await process_frame
	check("XR rig loads headless (no runtime -> start() false, nodes built)", not started and xg.rig.is_inside_tree() and xg.rig.camera != null and xg.rig.hands.size() == 2 and xg.fps_label != null and xg.surfaces != null)
	var hint_nodes := xg.rig.camera.find_children("*", "Label3D", true, false)
	var uf := XRGame.ui_font() as FontFile
	check("no explanatory text in the view; UI font is MSDF (sharp) with Arabic", hint_nodes.is_empty() and uf != null and uf.multichannel_signed_distance_field and uf.fallbacks.size() == 1, "%d labels on the camera" % hint_nodes.size())
	var m := xg.set_mode("mr")
	var vp := xg.get_viewport()
	check("MR hides the fake room (table, walls, mug) and its sky", m == "mr" and not room.set_root.visible and room.env.background_mode == Environment.BG_COLOR and room.env.background_color.a == 0.0 and vp.transparent_bg and not room.env.glow_enabled and not room.fill.visible and room.find_child("Mug", true, false) != null)
	check("MR keeps one key light + ambient", room.sun.visible and room.sun.light_energy > 0.5 and room.env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and room.env.ambient_light_energy > 0.2)
	m = xg.set_mode("vr")
	check("VR fallback shows the fake room again", m == "vr" and room.set_root.visible and room.env.background_mode == Environment.BG_SKY and not vp.transparent_bg)
	room.apply_quest()
	var lit := 0
	for l in root.find_children("*", "Light3D", true, false):
		if (l as Light3D).shadow_enabled:
			lit += 1
	check("Quest lighting: no light casts shadows, no glow / fog / ssao", lit == 0 and not room.fill.visible and not room.env.glow_enabled and not room.env.fog_enabled and not room.env.ssao_enabled, "%d shadowed lights" % lit)
	xg.queue_free()
	room.queue_free()
	vp.transparent_bg = false

	# --- Quest profile: 2x2 vegetation tiles, no tufts, opaque sea, caps, no shadows -
	var main_gd: GDScript = load("res://main.gd")
	main_gd.apply_quest_profile()
	var qd := Node3D.new()
	qd.name = "QuestDiorama"
	root.add_child(qd)
	qd.transform = Placement.pinned_transform(Vector3(0.4, 0.75, -0.7), -2.3, 0.55)
	var qi := Island.new()
	qd.add_child(qi)
	await process_frame
	var mmis := qi.props.find_children("MM_*", "MultiMeshInstance3D", false, false)
	var tiles_ok := not qi.props.species.has("tuft")
	for mmi in mmis:
		var g := mmi as MultiMeshInstance3D
		if g.material_override is ShaderMaterial:
			tiles_ok = false
	check("Quest: 2x2 vegetation tiles, no grass tufts", tiles_ok and (qi.props.species["acacia"].hi as Array).size() == 4, "%d draw nodes, species %s" % [mmis.size(), qi.props.species.keys()])
	check("Quest: opaque sea variant", (qi.water.shader_mat.shader as Shader).resource_path.ends_with("water_opaque.gdshader"))
	var qp := PhysicsTest.new()
	qd.add_child(qp)
	qp.setup(qi)
	qp.manual = true
	main_gd.no_shadows(qd)
	var casters := 0
	for g2 in qd.find_children("*", "GeometryInstance3D", true, false):
		if (g2 as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters += 1
	check("Quest: no geometry casts shadows", casters == 0, "%d casters" % casters)
	# a shot from a hand in the room, into the moved / turned / scaled diorama
	var hand_w := Placement.pinned_transform(Vector3(0.4, 0.75, -0.7), -2.3, 0.55) * Vector3(0.1, 0.8, 1.2)
	var hand_l := qd.global_transform.affine_inverse() * hand_w
	var tgt := Vector3(0.10, 0.0, 0.10)
	tgt.y = qi.surface_at(tgt.x, tgt.z)
	qp.fire(tgt, hand_l, "ballistic")
	var origin_ok := qp.shell.position.distance_to(hand_l) < 1e-6 and qp.p0.distance_to(hand_l) < 1e-6 and (qp.shell.global_position).distance_to(hand_w) < 1e-5
	var steps := 0
	while qp.flying and steps < 3000:
		qp.advance(1.0 / 72.0)
		steps += 1
	var qerr := Vector2(qp.last_impact.x - tgt.x, qp.last_impact.z - tgt.z).length()
	check("shot launches at the hand (room) and lands on target in a moved diorama", origin_ok and qerr < 0.02, "err %.4f, origin %s" % [qerr, qp.p0])
	for k in 120:
		qp.debris.spawn(Vector3(0.1, 0.12, 0.1), Basis(), Vector3(0.001, 0.001, 0.001), Vector3.ZERO, Vector3.ZERO, Color.WHITE, 0)
	check("Quest: live debris capped (80)", qp.debris.bodies.size() <= 80 and DebrisSystem.cap == 80, "%d bodies" % qp.debris.bodies.size())
	for k in 40:
		qp.debris.spawn(Vector3(0.1, 0.3, 0.1), Basis(), Vector3(0.001, 0.001, 0.001), Vector3(0, 0.05, 0), Vector3.ZERO, Color.WHITE, 0)
	for k in 90:
		qp.advance(1.0 / 72.0)
	var aw := 0
	for b in qp.debris.bodies:
		if not b.sleep:
			aw += 1
	check("Quest: awake debris kept within the CPU budget (old ones frozen + baked)", aw <= DebrisSystem.max_awake, "%d awake (max %d), %d baked" % [aw, DebrisSystem.max_awake, qp.debris.settled_count()])
	qp.debris.clear()

	# --- each weapon from the hand lands within 2 cm of the locked target on land ---
	var land_targets := [Vector3(0.10, 0, 0.10), Vector3(-0.05, 0, 0.0), Vector3(0.24, 0, -0.02), Vector3(-0.30, 0, 0.12)]
	var weapon_info := []
	var worst := 0.0
	var cruise_low := 0
	for id in WeaponTable.IDS:
		qp.reset_island()   # every weapon on the same, undamaged targets
		for lt in land_targets:
			var tg: Vector3 = lt
			tg.y = qi.height_at(tg.x, tg.z)
			if tg.y < IslandTerrain.SEA + 0.0005:
				continue
			qp.last_impact = Vector3.INF
			var pl := qp.fire(tg, hand_l, id)
			if id == "cruise":
				# the cruise path stays above the terrain / sea all the way (but the final dive)
				var T: float = pl.T
				for kk in 400:
					var pp := WeaponFlight.position_at(pl, T * kk / 400.0)
					if Vector2(pp.x - tg.x, pp.z - tg.z).length() < 0.02:
						break
					var su := qp.surface(pp.x, pp.z)
					if su > -INF and pp.y < su + 0.001:
						cruise_low += 1
			var st2 := 0
			while qp.flying and st2 < 4000:
				qp.advance(1.0 / 72.0)
				st2 += 1
			# salvo / cluster weapons scatter on purpose: measured against their spread
			var e := Vector2(qp.last_impact.x - tg.x, qp.last_impact.z - tg.z).length() - float(WeaponTable.get_weapon(id).get("spread", 0.0))
			worst = maxf(worst, e)
			weapon_info.append("%s %.1fs %.4f" % [id, pl.T, e])
	check("every weapon lands within 2 cm of the locked target (spread weapons within their pattern)", worst < 0.02 and weapon_info.size() == WeaponTable.IDS.size() * 4, "worst %.4f m: %s" % [worst, weapon_info])
	# behaviours of the new weapons
	qp.reset_island()
	var tgw := Vector3(0.10, 0, 0.10)
	tgw.y = qi.height_at(tgw.x, tgw.z)
	var n_imp := qp.impact_count
	qp.fire(tgw, hand_l, "mlrs")
	var sw := 0
	var max_air := 0
	while qp.flying and sw < 4000:
		qp.advance(1.0 / 72.0)
		max_air = maxi(max_air, qp.flights.size())
		sw += 1
	check("MLRS fires a salvo of 8 rockets", qp.impact_count - n_imp == 8 and max_air >= 4, "%d impacts, %d in the air at once" % [qp.impact_count - n_imp, max_air])
	n_imp = qp.impact_count
	qp.fire(tgw, hand_l, "cluster")
	sw = 0
	while qp.flying and sw < 4000:
		qp.advance(1.0 / 72.0)
		sw += 1
	check("cluster missile opens and its 10 bomblets land", qp.impact_count - n_imp == 10, "%d impacts" % (qp.impact_count - n_imp))
	var t_h := float(qp.plan(tgw, hand_l, "hypersonic").T)
	var t_d := float(qp.plan(tgw, hand_l, "drone").T)
	check("hypersonic is the fastest, the drone the slowest", t_h < 1.2 and t_d > 3.0, "hypersonic %.2f s, drone %.2f s" % [t_h, t_d])
	var h0 := qi.height_at(tgw.x + 0.06, tgw.z)
	var tb := Vector3(tgw.x + 0.06, h0, tgw.z)
	qp.fire(tb, hand_l, "bunker")
	sw = 0
	while qp.flying and sw < 4000:
		qp.advance(1.0 / 72.0)
		sw += 1
	check("bunker buster digs a deep crater", h0 - qi.height_at(tb.x, tb.z) > 0.009, "%.4f m deep" % (h0 - qi.height_at(tb.x, tb.z)))
	check("cruise missile stays above the terrain along its path", cruise_low == 0, "%d low samples" % cruise_low)
	var fts := {}
	for id in WeaponTable.IDS:
		var tg2 := Vector3(0.10, 0, 0.10)
		tg2.y = qi.height_at(tg2.x, tg2.z)
		fts[id] = float(qp.plan(tg2, hand_l, id).T)
	check("flight times 1.5-3 s; artillery fastest, ballistic lofted longest", fts.artillery < fts.ballistic and fts.artillery >= 1.5 and fts.ballistic <= 3.0 and fts.cruise >= 1.5 and fts.cruise <= 3.0, str(fts))
	var bpl := qp.plan(Vector3(0.10, qi.height_at(0.10, 0.10), 0.10), hand_l, "ballistic")
	var apl := qp.plan(Vector3(0.10, qi.height_at(0.10, 0.10), 0.10), hand_l, "artillery")
	var apex_b := -INF
	var apex_a := -INF
	for kk in 100:
		apex_b = maxf(apex_b, WeaponFlight.position_at(bpl, bpl.T * kk / 100.0).y)
		apex_a = maxf(apex_a, WeaponFlight.position_at(apl, apl.T * kk / 100.0).y)
	check("ballistic arc is high (lofted), artillery arc low", apex_b > apex_a + 0.1, "apex %.3f vs %.3f" % [apex_b, apex_a])
	# a cruise missile into a hill it cannot climb (a 5 cm cliff, synthetic surface):
	# the planned path meets the cliff -> flagged, and the flight crosses the surface
	var cliff := func(x: float, _z: float) -> float: return 0.05 if x > 0.2 else 0.0
	var cw := WeaponTable.get_weapon("cruise")
	var hp := WeaponFlight.plan(cw, Vector3(-0.4, 0.02, 0.0), Vector3(0.45, 0.05, 0.0), cliff, PhysicsTest.G)
	var cross_x := INF
	for kk in 2000:
		var pp2 := WeaponFlight.position_at(hp, float(hp.T) * kk / 2000.0)
		if pp2.y < float(cliff.call(pp2.x, pp2.z)):
			cross_x = pp2.x
			break
	check("cruise missile into a hill too steep to climb hits the hill", hp.crash and cross_x > 0.199 and cross_x < 0.23, "crash %s at x %.3f" % [hp.crash, cross_x])
	# a cruise missile at a target behind a tower block (synthetic, 6 cm tall, 2 cm
	# wide): it climbs over the roof in time and dives onto the target beyond it
	var tower := func(x: float, z: float) -> float: return 0.06 if absf(x - 0.1) < 0.01 and absf(z) < 0.03 else -INF
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var tw_p := WeaponFlight.plan(cw, Vector3(-0.4, 0.02, 0.0), Vector3(0.14, 0.0, 0.0), flat, PhysicsTest.G, tower)
	var through := 0
	for kk in 2000:
		var pp3 := WeaponFlight.position_at(tw_p, float(tw_p.T) * kk / 2000.0)
		if pp3.y < float(tower.call(pp3.x, pp3.z)):
			through += 1
	var end3 := WeaponFlight.position_at(tw_p, float(tw_p.T))
	check("cruise missile climbs over a tower block to a target behind it", through == 0 and not tw_p.crash and end3.distance_to(Vector3(0.14, 0.0, 0.0)) < 1e-4, "%d samples inside the block" % through)
	# on the island: a cruise shot across the city never passes through a standing building
	var cc := Vector3(island.layout.town_center.x, 0, island.layout.town_center.y)
	var far_t := cc + (cc - phys.default_origin("cruise")).normalized() * 0.06
	far_t.y = island.height_at(far_t.x, far_t.z)
	var cp := phys.plan(far_t, Vector3.INF, "cruise")
	var in_bld := 0
	for kk in 1500:
		var q4 := WeaponFlight.position_at(cp, float(cp.T) * kk / 1500.0)
		if Vector2(q4.x - far_t.x, q4.z - far_t.z).length() > WeaponFlight.DIVE_LEN and q4.y < island.props.roof_at(q4.x, q4.z):
			in_bld += 1
	check("cruise missile over the city stays above the roofs (but the final dive)", in_bld == 0, "%d samples inside buildings" % in_bld)

	# --- land vs sea vs shallow impacts ------------------------------------------------
	var deep := Vector3(0.05, IslandTerrain.SEA, 0.40)
	var shallow := Vector3.INF
	for jj in range(-40, 41):
		for ii in range(-40, 41):
			var x := ii * 0.01
			var z := jj * 0.01
			if not qi.terrain.is_inside(x, z, 0.03):
				continue
			var dd := IslandTerrain.SEA - qi.height_at(x, z)
			if dd > 0.0004 and dd < PhysicsTest.SHALLOW * 0.7 and qi.height_at(x + 0.004, z) < IslandTerrain.SEA and qi.height_at(x - 0.004, z) < IslandTerrain.SEA:
				shallow = Vector3(x, IslandTerrain.SEA, z)
				break
		if shallow != Vector3.INF:
			break
	var cr0 := qi.props.craters.size()
	var h_deep := qi.height_at(deep.x, deep.z)
	qp.debris.clear()
	qp.fx.clear()
	qp.fire(deep, hand_l, "ballistic")
	var st3 := 0
	while qp.flying and st3 < 4000:
		qp.advance(1.0 / 72.0)
		st3 += 1
	check("sea impact: water splash, no crater / fire / debris, shell gone", qp.last_impact_kind == "water" and qi.props.craters.size() == cr0 and _near(qi.height_at(deep.x, deep.z), h_deep) and qp.debris.bodies.size() == 0 and qp.fx.ripples.size() >= 1 and qp.sfx.last_played == "thump" and not qp.flying and not qp.fx.flash_light.visible, "kind %s, ripples %d, sound %s" % [qp.last_impact_kind, qp.fx.ripples.size(), qp.sfx.last_played])
	var fire_puffs := 0
	for q in qp.fx.puffs:
		if q.kind >= 2:
			fire_puffs += 1
	check("sea impact: no fireball / smoke column", fire_puffs == 0, "%d fireball puffs" % fire_puffs)
	if shallow != Vector3.INF:
		qp.fire(shallow, hand_l, "artillery")
		st3 = 0
		while qp.flying and st3 < 4000:
			qp.advance(1.0 / 72.0)
			st3 += 1
		check("shallow water at the shore: small splash + wet sand mark, no crater", qp.last_impact_kind == "shallow" and qp.wet_mark_count() >= 1 and qi.props.craters.size() == cr0, "kind %s at %s" % [qp.last_impact_kind, shallow])
	else:
		check("found a shallow-water test point", false)
	var landp := Vector3(0.02, 0.0, 0.05)
	landp.y = qi.height_at(landp.x, landp.z)
	qp.fire(landp, hand_l, "artillery")
	st3 = 0
	while qp.flying and st3 < 4000:
		qp.advance(1.0 / 72.0)
		st3 += 1
	check("land impact: crater + explosion + boom", qp.last_impact_kind == "land" and qi.props.craters.size() == cr0 + 1 and qp.sfx.last_played == "boom" and qi.height_at(landp.x, landp.z) < landp.y - 0.001)
	# reset island: craters, buildings and debris gone
	qp.reset_island()
	var all_alive := true
	for st4 in qi.props.structures:
		if not st4.alive:
			all_alive = false
	check("reset island restores the terrain, buildings and clears debris", qi.props.craters.is_empty() and _near(qi.height_at(landp.x, landp.z), landp.y) and all_alive and qp.debris.settled_count() == 0 and qp.debris.bodies.is_empty())

	# --- XR flow without a headset ---------------------------------------------------
	var room2 := Room.new()
	root.add_child(room2)
	var xg2 := XRGame.new()
	root.add_child(xg2)
	xg2.setup(room2, qd, qi, qp)
	xg2.rig.sim = true
	xg2.set_mode("mr")
	xg2.surfaces.add_test_plane(Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0.0, 0.72, -0.8)), Vector2(1.4, 0.8), "table")
	var head := Transform3D(Basis(), Vector3(0.0, 1.6, 0.3))
	var hand := Vector3(0.15, 1.25, 0.1)
	var spot := Vector3(0.05, 0.72, -0.75)
	var sh := xg2.aim_surface(hand, (spot - hand).normalized())
	var unplaced := xg2.surface_label
	for k in 90:
		xg2.place_toward(sh, head, Vector2.ZERO, 1.0 / 72.0)
	var base_w := qd.global_transform * Vector3.ZERO
	check("XR placing: the base follows the reticle onto the scene table", sh.get("label", "") == "table" and base_w.distance_to(spot) < 0.002 and xg2.ghost.visible and xg2.contact.visible and unplaced == "", "base %s, label %s" % [base_w, sh.get("label", "")])
	for k in 72:
		xg2.place_toward(sh, head, Vector2(0.8, -1.0), 1.0 / 72.0)
	var k2 := qd.global_transform.basis.get_scale().x
	check("XR placing: stick shrinks and turns the model", k2 < 0.5 and k2 >= 0.4 and absf(xg2.user_yaw) > 1.0, "scale %.2f, turn %.2f rad" % [k2, xg2.user_yaw])
	xg2._on_button("right", "trigger", true)
	check("XR: trigger pins the model, panel shown", xg2.state == "pinned" and not xg2.ghost.visible and xg2.panel.visible)

	# pin stability: head and both controllers wander for 300 frames, nothing else
	var cam := xg2.rig.camera
	var ra: XRController3D = xg2.rig.hands["right"].aim
	var lg: XRController3D = xg2.rig.hands["left"].grip
	var la: XRController3D = xg2.rig.hands["left"].aim
	var rgp: XRController3D = xg2.rig.hands["right"].grip
	var pinned_xf := qd.global_transform
	var drift := 0
	for f in 300:
		var a := f * 0.05
		cam.transform = Transform3D(Basis(Vector3.UP, sin(a) * 1.2) * Basis(Vector3.RIGHT, -0.4 + 0.2 * cos(a * 0.7)), Vector3(0.6 * sin(a * 0.5), 1.5 + 0.1 * sin(a), 0.3 + 0.5 * cos(a * 0.5)))
		ra.transform = Transform3D(Basis(Vector3.UP, cos(a)) * Basis(Vector3.RIGHT, -0.6), cam.transform.origin + Vector3(0.2, -0.35, -0.2))
		rgp.transform = ra.transform
		lg.transform = Transform3D(Basis(Vector3.UP, -cos(a)), cam.transform.origin + Vector3(-0.2, -0.4, -0.25))
		la.transform = lg.transform
		await process_frame
		if qd.global_transform != pinned_xf:
			drift += 1
	check("pinned island bit-identical while head + controllers move (300 frames)", drift == 0 and qd.global_transform == pinned_xf, "%d frames drifted" % drift)
	# left stick X: smooth turn about its own centre, base fixed, ticks every 15 deg
	var p_before := pulses_of(xg2)
	var base_before := qd.global_transform.origin
	xg2.rig.sim_stick["left"] = Vector2(1.0, 0.0)
	for f in 72:
		await process_frame
	xg2.rig.sim_stick["left"] = Vector2.ZERO
	var turned := qd.global_transform
	var yaw_change := absf(wrapf(turned.basis.get_euler().y - pinned_xf.basis.get_euler().y, -PI, PI))
	var up_ok := turned.basis.y.normalized().dot(Vector3.UP) > 0.999999 and _near(turned.basis.get_scale().x, pinned_xf.basis.get_scale().x)
	check("left stick X turns the island about its centre (yaw only, base fixed)", turned.origin == base_before and up_ok and yaw_change > 0.5, "yaw %.2f rad, base %s" % [yaw_change, turned.origin])
	check("haptic tick every 15 deg while turning", pulses_of(xg2) - p_before >= int(yaw_change / (PI / 12.0)) - 1 and pulses_of(xg2) - p_before > 0, "%d ticks for %.0f deg" % [pulses_of(xg2) - p_before, rad_to_deg(yaw_change)])
	var idle_drift := 0
	for f in 120:
		await process_frame
		if qd.global_transform != turned:
			idle_drift += 1
	check("after turning, idle: no drift (120 frames)", idle_drift == 0)
	# panel rotate buttons
	var y0 := xg2.cur_yaw
	xg2._on_panel("rot_l")   # rotation stays on the stick / grip (and this id)
	check("panel rotate button turns 15 deg", _near(wrapf(xg2.cur_yaw - y0, -PI, PI), PI / 12.0, 1e-4) and qd.global_transform.origin == base_before)

	# zoom: left stick Y scales the scene, the foot stays put, clamped to 0.4-1.5
	var k0 := xg2.diorama.global_transform.basis.get_scale().x
	var foot0 := xg2.diorama.global_transform.origin
	xg2.rig.sim_stick["left"] = Vector2(0.0, 1.0)
	for f in 20:
		await process_frame
	xg2.rig.sim_stick["left"] = Vector2.ZERO
	await process_frame
	var k1 := xg2.diorama.global_transform.basis.get_scale().x
	xg2.scale_island(100.0)
	var kmax := xg2.diorama.global_transform.basis.get_scale().x
	xg2.scale_island(0.0001)
	var kmin := xg2.diorama.global_transform.basis.get_scale().x
	check("left stick Y zooms the island (foot fixed, 0.4x-1.5x)", k1 > k0 * 1.05 and xg2.diorama.global_transform.origin.is_equal_approx(foot0) and _near(kmax, 1.5) and _near(kmin, 0.4), "%.3f -> %.3f" % [k0, k1])
	xg2.place_scale = k0
	xg2.scale_island(1.0)
	# weapon switching: right stick Y flick and a tap with the right ray on the panel
	xg2.select_weapon("ballistic")
	xg2.rig.sim_stick["right"] = Vector2(0.0, 1.0)
	await process_frame
	await process_frame
	xg2.rig.sim_stick["right"] = Vector2.ZERO
	await process_frame
	var after_flick := xg2.weapon
	await process_frame   # panel placed at the left hand this frame
	var eye_p := xg2.rig.head_transform().origin
	var bc := xg2.panel.button_center("w_artillery")
	var ph := xg2.panel.hit(eye_p, (bc - eye_p).normalized())
	if not ph.is_empty() and ph.id != "":
		xg2.panel.press(ph.id)
	check("panel: right stick flick and right-ray tap switch the weapon", after_flick == "cruise" and ph.get("id", "") == "w_artillery" and xg2.weapon == "artillery" and qp.weapon == "artillery" and xg2.panel.selected == "artillery", "flick -> %s, tap -> %s" % [after_flick, ph.get("id", "")])

	# lock + fire: right ray on the island, right grip locks (red), trigger fires from the hand
	var tl := Vector3(0.1, 0.0, 0.1)
	tl.y = qi.surface_at(tl.x, tl.z)
	ra.global_transform = Transform3D(Basis(), qd.global_transform * Vector3(0.0, 0.7, 0.9))
	var eye2 := ra.global_transform.origin
	var wh: Variant = xg2.aim_at(eye2, ((qd.global_transform * tl) - eye2).normalized())
	check("right ray on the island: target marker + preview from the hand", wh != null and xg2.aim_target != null and (xg2.aim_target as Vector3).distance_to(tl) < 0.003 and qp.preview_mm.visible_instance_count > 10 and qp.marker.visible, "aim %s" % [xg2.aim_target])
	var p_first: Vector3 = WeaponFlight.position_at(qp.last_aim_plan, 0.0)   # first preview dot
	check("preview starts at the hand", p_first.distance_to(xg2.launch_point_local()) < 1e-4, "%s vs %s" % [p_first, xg2.launch_point_local()])
	xg2._on_button("right", "grip", true)
	check("right grip locks the target (marker red)", xg2.locked != null and (xg2.locked as Vector3).distance_to(tl) < 0.003 and qp.marker.material_override == qp._mat_lock)
	xg2.aim_at(eye2, Vector3(0.3, -0.2, -1.0).normalized())   # pointing elsewhere: lock kept
	xg2._panel_hit = {}
	var ammo0 := int(xg2.ammo["artillery"])
	xg2._on_button("right", "trigger", true)
	var launch_l := xg2.launch_point_local()
	check("trigger fires the selected weapon from the hand at the locked target", qp.flying and qp.p0.distance_to(launch_l) < 1e-5 and (qp.target as Vector3).distance_to(xg2.locked) < 1e-6 and int(xg2.ammo["artillery"]) == ammo0 - 1 and float(xg2.cooldown["artillery"]) > 0.0)
	var blocked := xg2.fire()
	check("cooldown blocks an immediate second shot", not blocked)
	var n := 0
	while qp.flying and n < 3000:
		qp.advance(1.0 / 72.0)
		n += 1
	check("locked shot lands within 2 cm", Vector2(qp.last_impact.x - tl.x, qp.last_impact.z - tl.z).length() < 0.02, "impact %s" % qp.last_impact)
	xg2._on_button("right", "ax", true)
	var slow := qp.slow_motion
	xg2._on_button("right", "ax", true)
	xg2._on_button("left", "stick", true)
	xg2._step_fps(0.3)
	check("A toggles slow motion, left stick click the FPS panel", slow and not qp.slow_motion and xg2.fps_label.visible and xg2.fps_label.text.contains("fps"), xg2.fps_label.text.replace("\n", " | "))
	xg2.panel.press("reset")
	check("panel reset island clears craters and the lock", qi.props.craters.is_empty() and xg2.locked == null)
	xg2._on_button("right", "by", true)
	# missions on the panel: pick one, START, the board shows it
	xg2.panel.press("m_next")
	var picked := xg2.missions.active
	xg2.panel.press("reset")
	await process_frame
	check("panel: mission picked, START runs it, board shown", picked == "precision" and xg2.missions.running and xg2.board.visible and xg2.board.title.text.contains("ضربة جراحية") and (xg2.panel._btn_labels["reset"][1] as Label3D).text == "START", "%s running %s" % [picked, xg2.missions.running])
	xg2._on_button("left", "ax", true)
	var hidden := not xg2.board.visible
	xg2._on_button("left", "ax", true)
	check("left X hides / shows the mission screen (on the dome glass)", hidden and xg2.board.visible and xg2.board.get_parent() == xg2.diorama)
	xg2.select_mission("")
	check("free play: the screen shows the island's destruction, RESET is back", xg2.board.title.text.contains("لعب حر") and (xg2.panel._btn_labels["reset"][1] as Label3D).text == "RESET")
	check("B un-pins (place again)", xg2.state == "placing" and not xg2.panel.visible)
	xg2.rig.sim = false
	xg2.set_mode("vr")
	xg2.queue_free()
	room2.queue_free()

	# --- build 14: the campaign in VR (operations room, big screen, stages) -----------
	XRGame.campaign_vr = true
	var room3 := Room.new()
	root.add_child(room3)
	var xg3 := XRGame.new()
	root.add_child(xg3)
	xg3.setup(room3, qd, qi, qp)
	xg3.progress = Progress.new()       # a fresh player
	xg3.rig.sim = true
	xg3.set_mode("vr")
	xg3._process(1.0 / 72.0)
	await process_frame
	var base3 := qd.global_transform * Vector3.ZERO
	check("VR campaign: ops room built, the island on the hologram table ahead, the campaign on the big screen",
		xg3.table_centre != Vector3.INF and xg3.flow == "menu" and xg3.screen.visible and xg3.screen.page == "campaign"
		and xg3.ops.get_child_count() >= 4 and absf(base3.y - OpsRoom.TABLE_H) < 1e-4 and not room3.set_root.visible
		and base3.distance_to(Vector3(0, OpsRoom.TABLE_H, -XRGame.TABLE_AHEAD)) < 1e-3, "base %s" % base3)
	var eye3 := xg3.rig.head_transform().origin
	var bc3 := xg3.screen.button_center("st_c1s1")
	var sh3 := xg3.screen.hit(eye3, (bc3 - eye3).normalized())
	xg3.screen.press("st_c1s2")
	var locked2 := xg3.screen.has_button("none") and not xg3.screen.has_button("start")
	xg3.screen.press("st_c1s1")
	xg3.screen.press("start")
	var briefed := xg3.flow == "briefing" and xg3.screen.page == "briefing"
	var nb := xg3.screen.brief_lines().size()
	for k in nb:
		xg3.screen.press("brief_next")
	check("campaign screen: the ray picks a stage card, stage 2 is locked, START opens the team's briefing, its last NEXT starts the stage",
		sh3.get("id", "") == "st_c1s1" and locked2 and briefed and nb == 3 and xg3.flow == "playing" and xg3.run.running and not xg3.screen.visible and xg3.panel.visible,
		"hit %s flow %s" % [sh3.get("id", ""), xg3.flow])
	xg3._on_button("left", "menu", true)
	var paused := xg3.flow == "paused" and qp.manual and xg3.screen.page == "pause"
	xg3._on_button("left", "menu", true)
	check("menu button pauses (simulation stops, pause page) and resumes", paused and xg3.flow == "playing" and not qp.manual)
	for stc in qi.props.structures:
		if stc.kind == "radar_sphere":
			stc.alive = false
	xg3._process(1.0 / 72.0)
	check("stage won: debrief with 3 stars, saved, stage 2 opens and NEXT is offered",
		xg3.flow == "debrief" and xg3.screen.page == "debrief" and xg3.progress.stars("c1s1") == 3 and xg3.progress.is_open("c1s2") and xg3.screen.has_button("next"))
	xg3._on_screen("next")
	var to2 := xg3.flow == "briefing" and xg3.screen.selected == "c1s2"
	xg3._on_screen("campaign")
	check("NEXT briefs stage 2; CAMPAIGN goes back to the map", to2 and xg3.flow == "menu" and xg3.screen.page == "campaign")
	# aim snap: pointing 1 cm off the radar dome during its stage aims at the dome itself
	xg3.start_stage("c1s1")
	var rd := Vector3.ZERO
	for stc in qi.props.structures:
		if stc.kind == "radar_sphere":
			rd = stc.pos
	var near_pt := Vector3(rd.x + 0.01, 0.0, rd.z)
	var sn := xg3._snap(near_pt)
	var far_pt := Vector3(rd.x + 0.05, 0.0, rd.z)
	var sf := xg3._snap(far_pt)
	check("aim snaps onto an objective within 1.6 cm, not beyond", xg3.snapped == false and Vector2(sn.x - rd.x, sn.z - rd.z).length() < 1e-4 and sf == far_pt)
	xg3.back_to_campaign()
	# civilians in the aimed blast turn the ring yellow
	var town := Vector3(qi.layout.town_center.x, 0.0, qi.layout.town_center.y)
	town.y = qi.surface_at(town.x, town.z)
	qp.show_marker(town, false, "ballistic")
	var warn := qp.last_marker_civilians > 0 and qp.marker.material_override == qp._mat_warn
	var far := Vector3(-0.056, 0.0, -0.160)
	far.y = qi.surface_at(far.x, far.z)
	qp.show_marker(far, false, "artillery")
	check("aiming ring turns yellow with civilians inside the blast (town %d), stays orange over the radar" % qp.last_marker_civilians, warn and qp.marker.material_override != qp._mat_warn)
	qp.hide_preview()
	# a chapter-2 stage builds Crescent Island in place of the first island, then plays
	Progress.unlock_all = true
	xg3.start_stage("c2s1")
	for k in 4:
		await process_frame
	var isl2: Island = xg3.island
	check("chapter 2 stage: the screen says LOADING, Crescent Island replaces the island on the table, the convoy is out",
		isl2.map_id == 2 and isl2.get_parent() == qd and qp.island == isl2 and xg3.flow == "playing" and qp.forces.alive(["apc", "tank"]) == 5 and xg3.run.progress(isl2.props)[1] == 5,
		"map %d flow %s parent %s phys %s alive %d prog %s" % [isl2.map_id, xg3.flow, isl2.get_parent() == qd, qp.island == isl2, qp.forces.alive(["apc", "tank"]), xg3.run.progress(isl2.props)])
	xg3.back_to_campaign()
	Progress.unlock_all = false
	xg3.rig.sim = false
	xg3.queue_free()
	room3.queue_free()
	XRGame.campaign_vr = false

	IslandProps.merged_veg = false
	IslandProps.tufts = true
	IslandProps.small_shadows = true
	IslandWater.opaque = false
	DebrisSystem.cap = DebrisSystem.MAX_BODIES
	DebrisSystem.max_awake = 400
	IslandTerrain.defer_meshes = false
	DebrisSystem.max_age = 6.0
	PhysicsTest.ejecta_scale = 1.0
	FxSystem.cap = FxSystem.MAX_PUFFS
