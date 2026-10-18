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
	var has_souq := false
	for st in island.props.structures:
		if st.kind == "souq":
			has_souq = true
	check("civic souq replaces the old landmark", has_souq)

	# --- scale consistency (1:2000) -------------------------------------------------
	var rl := island.layout.runway_len * Scale.RATIO
	check("runway 600 m x 25 m", absf(rl - 600.0) < 1.0 and absf(island.layout.runway_w * Scale.RATIO - 25.0) < 0.5, "%.0f m x %.1f m" % [rl, island.layout.runway_w * Scale.RATIO])
	var storey_bad := 0
	for st in island.props.structures:
		if st.kind in ["house", "courtyard", "midrise", "tower"]:
			var n: float = st.size.y / Scale.storeys(1.0)
			if absf(n - round(n)) > 0.01 or n < 1.0 or n > 16.5:
				storey_bad += 1
	check("buildings are whole storeys (3.5 m)", storey_bad == 0, "%d off-grid" % storey_bad)
	var palm_h := []
	var sp: Dictionary = island.props.species["palm"]
	for xf in (sp.xf as Array).slice(0, 50):
		palm_h.append((xf as Transform3D).basis.get_scale().y * 0.9 * Scale.RATIO)
	var pmin: float = palm_h.min()
	var pmax: float = palm_h.max()
	check("date palms 10-17 m tall", pmin > 10.0 and pmax < 17.0, "%.1f-%.1f m" % [pmin, pmax])

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

	await _xr_tests(island, phys)

	print("RESULT ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures else 0)


# ======================================================================================
# XR / Quest build
# ======================================================================================

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
	check("XR rig loads headless (no runtime -> start() false, nodes built)", not started and xg.rig.is_inside_tree() and xg.rig.camera != null and xg.rig.hands.size() == 2 and xg.hint != null and xg.fps_label != null and xg.surfaces != null)
	check("hint panel texts (Arabic + English)", XRGame.HINT_PLACE_AR.contains("الزناد للتثبيت") and XRGame.HINT_PLAY_EN.contains("slow motion") and XRGame.ui_font() != null)
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
	check("Quest: 2x2 vegetation tiles with LOD ranges, no grass tufts", tiles_ok and (qi.props.species["palm"].hi as Array).size() == 4, "%d draw nodes, species %s" % [mmis.size(), qi.props.species.keys()])
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
	check("Quest: live debris capped (120)", qp.debris.bodies.size() <= 120 and DebrisSystem.cap == 120, "%d bodies" % qp.debris.bodies.size())
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
			var e := Vector2(qp.last_impact.x - tg.x, qp.last_impact.z - tg.z).length()
			worst = maxf(worst, e)
			weapon_info.append("%s %.1fs %.4f" % [id, pl.T, e])
	check("every weapon lands within 2 cm of the locked target (from the hand)", worst < 0.02 and weapon_info.size() == 12, "worst %.4f m: %s" % [worst, weapon_info])
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
	check("XR: trigger pins the model, panel shown", xg2.state == "pinned" and not xg2.ghost.visible and XRGame.HINT_PLAY_AR in xg2.hint.text and xg2.panel.visible)

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
	xg2.panel.press("rot_l")
	check("panel rotate button turns 15 deg", _near(wrapf(xg2.cur_yaw - y0, -PI, PI), PI / 12.0, 1e-4) and qd.global_transform.origin == base_before)

	# weapon switching: left stick Y flick and a tap with the right ray on the panel
	xg2.select_weapon("ballistic")
	xg2.rig.sim_stick["left"] = Vector2(0.0, 1.0)
	await process_frame
	await process_frame
	xg2.rig.sim_stick["left"] = Vector2.ZERO
	await process_frame
	var after_flick := xg2.weapon
	await process_frame   # panel placed at the left hand this frame
	var eye_p := xg2.rig.head_transform().origin
	var bc := xg2.panel.button_center("w_artillery")
	var ph := xg2.panel.hit(eye_p, (bc - eye_p).normalized())
	if not ph.is_empty() and ph.id != "":
		xg2.panel.press(ph.id)
	check("panel: left stick flick and right-ray tap switch the weapon", after_flick == "cruise" and ph.get("id", "") == "w_artillery" and xg2.weapon == "artillery" and qp.weapon == "artillery" and xg2.panel.selected == "artillery", "flick -> %s, tap -> %s" % [after_flick, ph.get("id", "")])

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
	check("B un-pins (place again)", xg2.state == "placing" and XRGame.HINT_PLACE_EN in xg2.hint.text and not xg2.panel.visible)
	xg2.rig.sim = false
	xg2.set_mode("vr")
	xg2.queue_free()
	room2.queue_free()

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
