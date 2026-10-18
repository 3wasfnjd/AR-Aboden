extends SceneTree
## Per-component CPU profile of one flight + impact (headless, Quest profile).
func _initialize() -> void:
	(load("res://main.gd") as GDScript).apply_quest_profile()
	var dio := Node3D.new()
	root.add_child(dio)
	var island := Island.new()
	dio.add_child(island)
	await process_frame
	var phys := PhysicsTest.new()
	dio.add_child(phys)
	phys.setup(island)
	phys.manual = true
	# idle frames after loading (the ruin meshes are prepared then)
	for k in 90:
		await process_frame
	var hand := Vector3(-0.28, 0.42, 0.66)
	for wid in ["ballistic", "cruise", "artillery"]:
		var tgt: Vector3 = Vector3(0.08, 0, 0.07)
		tgt.y = island.surface_at(tgt.x, tgt.z)
		var t0 := Time.get_ticks_usec()
		phys.aim(tgt, hand, wid)
		var t_aim := Time.get_ticks_usec() - t0
		phys.fire(tgt, hand, wid)
		var acc := {"flights": 0, "debris": 0, "fx": 0, "frames": 0, "max": 0, "impact_frame": 0}
		for f in 72 * 6:
			var a := Time.get_ticks_usec()
			var was := phys.impact_count
			var dt := 1.0 / 72.0
			var steps := maxi(1, int(ceil(dt / (1.0 / 120.0))))
			for _i in steps:
				phys._step_flights(dt / steps)
			var b := Time.get_ticks_usec()
			phys.debris.step(dt)
			var c := Time.get_ticks_usec()
			phys.fx.step(dt)
			var d := Time.get_ticks_usec()
			phys.aim(tgt, hand, wid)
			var e := Time.get_ticks_usec()
			acc.flights += b - a
			acc.debris += c - b
			acc.fx += d - c
			acc["aim"] = int(acc.get("aim", 0)) + e - d
			acc.frames += 1
			acc.max = maxi(acc.max, e - a)
			if phys.impact_count != was:
				acc.impact_frame = b - a
			await process_frame
		print("PROF %s aim1 %dus  per-frame avg: flights %.0f debris %.0f fx %.0f aim %.0f us; max frame %d us, impact frame %d us" % [wid, t_aim, acc.flights / 432.0, acc.debris / 432.0, acc.fx / 432.0, acc.aim / 432.0, acc.max, acc.impact_frame])
	quit(0)
