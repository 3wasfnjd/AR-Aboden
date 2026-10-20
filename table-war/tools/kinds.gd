extends SceneTree
## Lists the island's structure kinds: count and centre of each (planning stages).
func _initialize() -> void:
	var island := Island.new()
	root.add_child(island)
	await process_frame
	var by := {}
	for st in island.props.structures:
		if not by.has(st.kind):
			by[st.kind] = []
		by[st.kind].append(st.pos if st.has("pos") else Vector3.ZERO)
	for k in by:
		var c := Vector3.ZERO
		for p in by[k]:
			c += p
		c /= by[k].size()
		print("%-14s %3d  centre (%.3f, %.3f)" % [k, by[k].size(), c.x, c.z])
	print("ship ", island.ship.position, " town ", island.layout.town_center)
	quit()
