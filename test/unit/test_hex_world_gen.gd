class_name TestHexWorldGen
extends RefCounted

const HexSectorManager = preload("res://scripts/world/hex_sector_manager.gd")
const HexWorldTile = preload("res://scripts/world/hex_world_tile.gd")
const SectorBiomeData = preload("res://scripts/resources/sector_biome_data.gd")

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_axial_to_world_position_conversion())
	results.append(_test_hex_ring_cluster_generation())
	results.append(_test_biome_surface_sampling())
	results.append(_test_tile_mesh_and_collision_generation())
	results.append(_test_sector_manager_streaming_and_pooling())
	return results

func _test_axial_to_world_position_conversion() -> Dictionary:
	var mgr: HexSectorManager = HexSectorManager.new()
	mgr.biome_data = SectorBiomeData.new()
	mgr.biome_data.hex_cell_outer_radius_m = 20.0
	
	var coord: Vector2i = Vector2i(2, -1)
	var world_pos: Vector3 = mgr.axial_to_world_pos(coord)
	var round_trip_coord: Vector2i = mgr.world_pos_to_axial_coord(world_pos)
	
	var passed: bool = (round_trip_coord == coord) and (world_pos.z == -30.0)
	
	mgr.free()
	return {
		"name": "test_axial_to_world_position_conversion",
		"passed": passed,
		"message": "Axial (2, -1) -> World %s -> Axial %s (passed: %s)" % [str(world_pos), str(round_trip_coord), str(passed)]
	}

func _test_hex_ring_cluster_generation() -> Dictionary:
	var mgr: HexSectorManager = HexSectorManager.new()
	var ring0: Array[Vector2i] = mgr.get_hex_ring_cluster(Vector2i.ZERO, 0) # 1 tile
	var ring1: Array[Vector2i] = mgr.get_hex_ring_cluster(Vector2i.ZERO, 1) # 7 tiles
	var ring2: Array[Vector2i] = mgr.get_hex_ring_cluster(Vector2i.ZERO, 2) # 19 tiles
	var ring3: Array[Vector2i] = mgr.get_hex_ring_cluster(Vector2i.ZERO, 3) # 37 tiles
	
	var passed: bool = (ring0.size() == 1) and (ring1.size() == 7) and (ring2.size() == 19) and (ring3.size() == 37)
	
	mgr.free()
	return {
		"name": "test_hex_ring_cluster_generation",
		"passed": passed,
		"message": "Concentric rings count: R0=%d, R1=%d, R2=%d, R3=%d (expected 1, 7, 19, 37)" % [
			ring0.size(), ring1.size(), ring2.size(), ring3.size()
		]
	}

func _test_biome_surface_sampling() -> Dictionary:
	var biome: SectorBiomeData = SectorBiomeData.new()
	biome.surface_weights = {
		&"ice": 0.8,
		&"pack": 0.2
	}
	
	var sample_ice: StringName = biome.sample_surface_type(0.3)
	var sample_pack: StringName = biome.sample_surface_type(0.95)
	
	var passed: bool = (sample_ice == &"ice") and (sample_pack == &"pack")
	
	return {
		"name": "test_biome_surface_sampling",
		"passed": passed,
		"message": "Surface rolls: 0.3 -> %s (expected ice), 0.95 -> %s (expected pack)" % [
			sample_ice, sample_pack
		]
	}

func _test_tile_mesh_and_collision_generation() -> Dictionary:
	var tile: HexWorldTile = HexWorldTile.new()
	var biome: SectorBiomeData = SectorBiomeData.new()
	biome.hex_cell_outer_radius_m = 15.0
	
	tile.initialize_tile(Vector2i(1, 1), biome, 999)
	
	var body: StaticBody3D = tile.get_node_or_null("TileBody") as StaticBody3D
	var mesh_inst: MeshInstance3D = body.get_node_or_null("TileMesh") as MeshInstance3D if body else null
	var col_shape: CollisionShape3D = body.get_node_or_null("TileCollision") as CollisionShape3D if body else null
	
	var has_surface_meta: bool = body and body.has_meta(&"surface_type")
	var has_mesh: bool = mesh_inst and mesh_inst.mesh != null
	var has_col: bool = col_shape and col_shape.shape != null
	
	var passed: bool = has_surface_meta and has_mesh and has_col
	
	tile.free()
	return {
		"name": "test_tile_mesh_and_collision_generation",
		"passed": passed,
		"message": "Tile generated with mesh (%s), collision (%s), surface meta (%s)" % [
			str(has_mesh), str(has_col), str(has_surface_meta)
		]
	}

func _test_sector_manager_streaming_and_pooling() -> Dictionary:
	var mgr: HexSectorManager = HexSectorManager.new()
	mgr.biome_data = SectorBiomeData.new()
	mgr.render_radius_rings = 1 # 7 tiles
	mgr.is_dynamic_streaming_enabled = false
	
	mgr.generate_initial_sector(Vector2i(0, 0))
	var initial_count: int = mgr.get_active_tile_count()
	
	# Shift center to (5, 5)
	mgr.generate_initial_sector(Vector2i(5, 5))
	var shifted_count: int = mgr.get_active_tile_count()
	var center_tile_exists: bool = (mgr.get_active_tile(Vector2i(5, 5)) != null)
	var old_center_cleared: bool = (mgr.get_active_tile(Vector2i(0, 0)) == null)
	
	var passed: bool = (initial_count == 7) and (shifted_count == 7) and center_tile_exists and old_center_cleared
	
	mgr.free()
	return {
		"name": "test_sector_manager_streaming_and_pooling",
		"passed": passed,
		"message": "Chunk streaming: initial=%d, shifted=%d, old chunk pooled=%s" % [
			initial_count, shifted_count, str(old_center_cleared)
		]
	}
