extends SceneTree
## Soak test (headless): keep the trajectory preview on and fire every 2 s for N
## simulated seconds, logging per-second CPU frame time and object / memory counts, so
## anything that accumulates over time shows up as a trend.
##   godot --headless --xr-mode off --path . -s tools/soak.gd -- --seconds=240 [--quest]
## Prints one SOAK line per simulated second and a SOAK_SUMMARY line at the end.

func _initialize() -> void:
	var seconds := 240
	var quest := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			seconds = int(a.substr(10))
		if a == "--quest":
			quest = true
	if quest:
		var m: GDScript = load("res://main.gd")
		m.apply_quest_profile()
	var dio := Node3D.new()
	root.add_child(dio)
	var island := Island.new()
	dio.add_child(island)
	await process_frame
	var phys := PhysicsTest.new()
	dio.add_child(phys)
	phys.setup(island)
	phys.manual = true
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var weapons: Array = []
	if ClassDB.class_exists("WeaponTable") or ResourceLoader.exists("res://weapons/weapon_table.gd"):
		weapons = (load("res://weapons/weapon_table.gd") as GDScript).get("IDS")
	var fps := 72
	var frame := 0
	var shots := 0
	var first := {}
	var last := {}
	var worst_frame := 0.0
	for sec in seconds:
		var t_sum := 0.0
		var t_max := 0.0
		for f in fps:
			var t0 := Time.get_ticks_usec()
			# the hand sweeps: the preview target moves a little every frame
			var a := frame * 0.013
			var aim := Vector3(0.12 * cos(a) + 0.02, 0.0, 0.10 * sin(a * 1.3))
			aim.y = island.surface_at(aim.x, aim.z)
			# XR aiming cost: the controller ray clipped to the slab, marched on the terrain
			var hand := Vector3(-0.28, 0.42, 0.66)
			var lr := Placement.local_ray(Transform3D(), hand, (aim - hand).normalized())
			if not lr.is_empty():
				island.terrain.raycast((lr[0] as Vector3) + (lr[1] as Vector3) * float(lr[2]), lr[1], float(lr[3]) - float(lr[2]) + 0.004)
			if not phys.flying:
				phys.aim(aim)
			if frame % (fps * 2) == 0:
				var tgt := Vector3(rng.randf_range(-0.42, 0.42), 0.0, rng.randf_range(-0.3, 0.3))
				tgt.y = island.surface_at(tgt.x, tgt.z)
				if weapons.is_empty():
					phys.fire(tgt)
				else:
					phys.call("fire", tgt, phys.call("default_origin"), weapons[shots % weapons.size()])
				shots += 1
			phys.advance(1.0 / fps)
			var dt := (Time.get_ticks_usec() - t0) / 1000.0
			t_sum += dt
			t_max = maxf(t_max, dt)
			frame += 1
			await process_frame
		worst_frame = maxf(worst_frame, t_max)
		var d := {
			"s": sec + 1,
			"ms_avg": snappedf(t_sum / fps, 0.01),
			"ms_max": snappedf(t_max, 0.1),
			"debris": phys.debris.bodies.size(),
			"settled": phys.debris.call("settled_count") if phys.debris.has_method("settled_count") else 0,
			"puffs": phys.fx.puffs.size(),
			"craters": island.props.craters.size(),
			"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		}
		if sec == 9:
			first = d
		last = d
		print("SOAK ", JSON.stringify(d))
	print("SOAK_SUMMARY ", JSON.stringify({"shots": shots, "after_10s": first, "end": last, "worst_frame_ms": snappedf(worst_frame, 0.1)}))
	quit(0)
