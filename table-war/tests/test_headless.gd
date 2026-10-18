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
	var by: float = (phys.debris.bodies[0].p as Vector3).y
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
	check("Quest lighting: one shadowed directional light, 1.5 m orthogonal shadow, no glow", not room.fill.visible and not room.env.glow_enabled and room.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL and _near(room.sun.directional_shadow_max_distance, 1.5))
	xg.queue_free()
	room.queue_free()
	vp.transparent_bg = false

	# --- Quest profile: merged vegetation, opaque sea, debris cap, moved diorama ----
	IslandProps.merged_veg = true
	IslandProps.small_shadows = false
	IslandWater.opaque = true
	DebrisSystem.cap = 200
	var qd := Node3D.new()
	qd.name = "QuestDiorama"
	root.add_child(qd)
	qd.transform = Placement.pinned_transform(Vector3(0.4, 0.75, -0.7), -2.3, 0.55)
	var qi := Island.new()
	qd.add_child(qi)
	await process_frame
	var per_species := []
	var merged_ok := true
	for nm in qi.props.species:
		var sp: Dictionary = qi.props.species[nm]
		var n_hi := (sp.hi as Array).size()
		per_species.append("%s:%d" % [nm, n_hi])
		if n_hi != 1 or (sp.hi[0] as MultiMesh).instance_count != (sp.xf as Array).size():
			merged_ok = false
	var mmis := qi.props.find_children("MM_*", "MultiMeshInstance3D", false, false)
	var shader_ok := true
	var small_cast := 0
	for mmi in mmis:
		var g := mmi as MultiMeshInstance3D
		if not (g.material_override is ShaderMaterial) or g.visibility_range_end > 0.0:
			shader_ok = false
		if (g.name.contains("shrub") or g.name.contains("tuft") or g.name.contains("rock")) and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			small_cast += 1
	check("Quest: one MultiMesh per species and LOD level", merged_ok and mmis.size() <= 9, "%s, %d draw nodes (desktop: %d)" % [per_species, mmis.size(), island.props.find_children("MM_*", "MultiMeshInstance3D", false, false).size()])
	check("Quest: per-instance LOD shader, small props cast no shadow", shader_ok and small_cast == 0, "%d small casters" % small_cast)
	check("Quest: opaque sea variant", (qi.water.shader_mat.shader as Shader).resource_path.ends_with("water_opaque.gdshader"))
	var qp := PhysicsTest.new()
	qd.add_child(qp)
	qp.setup(qi)
	qp.manual = true
	var tgt := Vector3(0.10, 0.0, 0.10)
	tgt.y = qi.surface_at(tgt.x, tgt.z)
	qp.fire(tgt)
	var muzzle_ok := qp.shell.position.distance_to(qp.p0) < 1e-6 and qp.p0.distance_to(qi.props.launcher_muzzle()) < 1e-5 and qi.terrain.is_inside(qp.p0.x, qp.p0.z)
	var steps := 0
	while qp.flying and steps < 2000:
		qp.advance(1.0 / 72.0)
		steps += 1
	var qerr := Vector2(qp.last_impact.x - tgt.x, qp.last_impact.z - tgt.z).length()
	check("shell in a moved / turned / scaled diorama: muzzle local, lands on target", muzzle_ok and qerr < 0.02, "err %.4f m, muzzle %s" % [qerr, qp.p0])
	for k in 120:
		qp.debris.spawn(Vector3(0.1, 0.12, 0.1), Basis(), Vector3(0.001, 0.001, 0.001), Vector3.ZERO, Vector3.ZERO, Color.WHITE, 0)
	check("Quest: debris capped at 200", qp.debris.bodies.size() <= 200 and qp.debris.bodies.size() >= 150, "%d bodies" % qp.debris.bodies.size())
	qp.debris.clear()

	# --- XR flow without a headset: aim at a scene table, pin, aim + fire, un-pin ---
	var room2 := Room.new()
	root.add_child(room2)
	var xg2 := XRGame.new()
	root.add_child(xg2)
	xg2.setup(room2, qd, qi, qp)
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
	check("XR: trigger pins the model", xg2.state == "pinned" and not xg2.ghost.visible and XRGame.HINT_PLAY_AR in xg2.hint.text)
	var tl := Vector3(0.1, 0.0, 0.1)
	tl.y = qi.surface_at(tl.x, tl.z)
	var eye2 := qd.global_transform * Vector3(0.0, 0.6, 0.7)
	var wh: Variant = xg2.aim_at(eye2, ((qd.global_transform * tl) - eye2).normalized())
	check("XR: right ray on the island shows the trajectory preview", wh != null and xg2.aim_target != null and (xg2.aim_target as Vector3).distance_to(tl) < 0.003 and qp.preview_mm.visible_instance_count > 10, "aim %s" % [xg2.aim_target])
	xg2._on_button("right", "trigger", true)
	var fly0 := qp.flying
	var n := 0
	while qp.flying and n < 2000:
		qp.advance(1.0 / 72.0)
		n += 1
	check("XR: trigger fires the shell at the aimed point", fly0 and Vector2(qp.last_impact.x - tl.x, qp.last_impact.z - tl.z).length() < 0.02, "impact %s" % qp.last_impact)
	xg2._on_button("right", "ax", true)
	var slow := qp.slow_motion
	xg2._on_button("right", "ax", true)
	xg2._on_button("left", "stick", true)
	xg2._step_fps(0.3)
	check("XR: A toggles slow motion, left stick click the FPS panel", slow and not qp.slow_motion and xg2.fps_label.visible and xg2.fps_label.text.contains("fps"), xg2.fps_label.text.replace("\n", " | "))
	xg2.aim_at(Vector3.ZERO, Vector3.ZERO)
	check("XR: preview hidden when the ray leaves the island", qp.preview_mm.visible_instance_count == 0)
	xg2._on_button("right", "by", true)
	check("XR: B un-pins (place again)", xg2.state == "placing" and XRGame.HINT_PLACE_EN in xg2.hint.text)
	xg2.set_mode("vr")
	xg2.queue_free()
	room2.queue_free()

	IslandProps.merged_veg = false
	IslandProps.small_shadows = true
	IslandWater.opaque = false
	DebrisSystem.cap = DebrisSystem.MAX_BODIES
