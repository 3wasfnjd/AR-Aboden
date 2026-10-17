class_name Island
extends Node3D
## Builds the whole diorama: terrain -> props (stamps AO) -> terrain mesh ->
## water -> base. Exposes the queries the physics test needs.

var layout := IslandLayout.new()
var terrain: IslandTerrain
var props: IslandProps
var water: IslandWater
var base: DioramaBase
var build_ms := 0


func _ready() -> void:
	build()


func build() -> void:
	var t0 := Time.get_ticks_msec()
	terrain = IslandTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(layout)
	props = IslandProps.new()
	props.name = "Props"
	add_child(props)
	props.build(terrain, layout)
	terrain.build_meshes()
	water = IslandWater.new()
	water.name = "Water"
	add_child(water)
	water.build(terrain)
	base = DioramaBase.new()
	base.name = "Base"
	add_child(base)
	base.build(terrain)
	build_ms = Time.get_ticks_msec() - t0


func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z)


## Surface the shell can hit: terrain or the sea.
func surface_at(x: float, z: float) -> float:
	return maxf(terrain.height_at(x, z), IslandTerrain.SEA)


func stats() -> Dictionary:
	var d := {
		"terrain_tris": terrain.triangle_count(),
		"terrain_chunks": terrain.chunk_nodes.size(),
		"water_tris": water.triangle_count(),
		"base_tris": base.tri_total,
		"structure_count": props.structure_count(),
		"build_ms": build_ms,
	}
	d.merge(props.triangle_stats())
	return d
