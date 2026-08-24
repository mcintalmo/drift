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
	results.append(_test_adjacent_hex_vertex_exact_match())
	results.append(_test_hot_spring_basin_creation())
	results.append(_test_chasm_jump_ramp_generation())
	results.append(_test_procedural_connected_railroad())
	results.append(_test_sector_manager_streaming_and_pooling())
	return results

func _test_axial_to_world_position_conversion() -> Dictionary:
	var mgr: HexSectorManager = HexSectorManager.new()
	mgr.biome_data = SectorBiomeData.new()
	mgr.biome_data.hex_cell_outer_radius_m = 6.0
	
	var coord: Vector2i = Vector2i(2, -1)
	var world_pos: Vector3 = mgr.axial_to_world_pos(coord)
	var round_trip_coord: Vector2i = mgr.world_pos_to_axial_coord(world_pos)
	
	var passed: bool = (round_trip_coord == coord) and is_equal_approx(world_pos.z, -9.0)
	
	mgr.free()
	return {
		"name": "test_axial_to_world_position_conversion",
		"passed": passed,
		"message": "Axial (2, -1) [R=6m] -> World %s -> Axial %s (passed: %s)" % [str(world_pos), str(round_trip_coord), str(passed)]
	}

func _test_hex_ring_cluster_generation() -> Dictionary:
	var mgr: HexSectorManager = HexSectorManager.new()
	var ring0: Array[Vector2i] = mgr.get_hex_ring_cluster(Vector2i.ZERO, 0) # 1 tile
	var ring1: Array[Vector2i] = mgr.get_hex_ring_cluster(Vector2i.ZERO, 1) # 7 tiles
	var ring2: Array[Vector2i] = mgr.get_hex_ring_cluster(Vector2i.ZERO, 2) # 19 tiles
	var ring3: Array[Vector2i] = mgr.get_hex_ring_cluster(Vector2i.ZERO, 3) # 37 tiles
	var ring4: Array[Vector2i] = mgr.get_hex_ring_cluster(Vector2i.ZERO, 4) # 61 tiles
	
	var passed: bool = (ring0.size() == 1) and (ring1.size() == 7) and (ring2.size() == 19) and (ring3.size() == 37) and (ring4.size() == 61)
	
	mgr.free()
	return {
		"name": "test_hex_ring_cluster_generation",
		"passed": passed,
		"message": "Concentric rings count: R0=%d, R1=%d, R2=%d, R3=%d, R4=%d (expected 1, 7, 19, 37, 61)" % [
			ring0.size(), ring1.size(), ring2.size(), ring3.size(), ring4.size()
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

func _test_adjacent_hex_vertex_exact_match() -> Dictionary:
	var biome: SectorBiomeData = SectorBiomeData.new()
	biome.hex_cell_outer_radius_m = 6.0
	biome.elevation_amplitude = 1.85
	biome.elevation_frequency = 0.022
	
	var tile_a: HexWorldTile = HexWorldTile.new()
	tile_a.initialize_tile(Vector2i(0, 0), biome, 4281, false)
	
	var tile_b: HexWorldTile = HexWorldTile.new()
	tile_b.initialize_tile(Vector2i(1, 0), biome, 4281, false)
	
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 4281
	noise.frequency = biome.elevation_frequency
	var amp: float = biome.elevation_amplitude
	
	var corners_a: Array[float] = tile_a._compute_corner_heights(tile_a.position.x, tile_a.position.z, noise, amp)
	var corners_b: Array[float] = tile_b._compute_corner_heights(tile_b.position.x, tile_b.position.z, noise, amp)
	
	var world_y_a0: float = tile_a.position.y + corners_a[0]
	var world_y_b2: float = tile_b.position.y + corners_b[2]
	
	var world_y_a5: float = tile_a.position.y + corners_a[5]
	var world_y_b3: float = tile_b.position.y + corners_b[3]
	
	var delta_edge1: float = absf(world_y_a0 - world_y_b2)
	var delta_edge2: float = absf(world_y_a5 - world_y_b3)
	
	var passed: bool = (delta_edge1 < 0.0001) and (delta_edge2 < 0.0001)
	
	tile_a.free()
	tile_b.free()
	return {
		"name": "test_adjacent_hex_vertex_exact_match",
		"passed": passed,
		"message": "Continuous shared edges: Edge1 diff = %.6f m, Edge2 diff = %.6f m (Zero-Seam Match: %s)" % [
			delta_edge1, delta_edge2, str(passed)
		]
	}

func _test_hot_spring_basin_creation() -> Dictionary:
	var tile: HexWorldTile = HexWorldTile.new()
	var biome: SectorBiomeData = SectorBiomeData.new()
	biome.hex_cell_outer_radius_m = 6.0
	
	tile.initialize_tile(Vector2i(1, 0), biome, 1337, true)
	
	var is_hot_spring_flag: bool = tile.is_hot_spring
	var is_in_vent_group: bool = tile.is_in_group(&"thermal_vents")
	var warmth_inside: float = tile.get_temperature_contribution(tile.position)
	var warmth_far: float = tile.get_temperature_contribution(tile.position + Vector3(25, 0, 0))
	
	var passed: bool = is_hot_spring_flag and is_in_vent_group and (warmth_inside == 45.0) and (warmth_far == 0.0)
	
	tile.free()
	return {
		"name": "test_hot_spring_basin_creation",
		"passed": passed,
		"message": "Hot spring basin: is_hot_spring=%s, in_group=%s, warmth inside=%.1f C, far=%.1f C" % [
			str(is_hot_spring_flag), str(is_in_vent_group), warmth_inside, warmth_far
		]
	}

func _test_chasm_jump_ramp_generation() -> Dictionary:
	var tile: HexWorldTile = HexWorldTile.new()
	var biome: SectorBiomeData = SectorBiomeData.new()
	biome.hex_cell_outer_radius_m = 6.0
	
	# Initialize tile as a jump ramp pointing East (Vector2(1, 0))
	tile.initialize_tile(Vector2i(0, 0), biome, 1337, false, true, Vector2(1, 0))
	
	var is_ramp_flag: bool = tile.is_jump_ramp
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 1337
	noise.frequency = biome.elevation_frequency
	var corners: Array[float] = tile._compute_corner_heights(tile.position.x, tile.position.z, noise, biome.elevation_amplitude)
	
	# East corner (index 0 at +30 deg) should have positive kicker elevation compared to approach
	var east_kicker: float = corners[0]
	var west_approach: float = corners[3]
	
	var passed: bool = is_ramp_flag and (east_kicker > west_approach)
	
	tile.free()
	return {
		"name": "test_chasm_jump_ramp_generation",
		"passed": passed,
		"message": "Chasm Jump Ramp: is_ramp=%s, East Kicker Lip=%.2f m > West Approach=%.2f m" % [
			str(is_ramp_flag), east_kicker, west_approach
		]
	}

func _test_procedural_connected_railroad() -> Dictionary:
	var mgr: HexSectorManager = HexSectorManager.new()
	mgr.biome_data = SectorBiomeData.new()
	mgr.render_radius_rings = 2 # 19 tiles
	mgr.is_procedural_railroad_enabled = true
	mgr.is_dynamic_streaming_enabled = false
	
	mgr.generate_initial_sector(Vector2i.ZERO)
	var rail_path: Array[Vector2i] = mgr.get_railroad_path()
	
	var passed: bool = rail_path.size() >= 3
	
	mgr.free()
	return {
		"name": "test_procedural_connected_railroad",
		"passed": passed,
		"message": "Procedural connected railroad corridor generated with %d consecutive hex nodes" % rail_path.size()
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
