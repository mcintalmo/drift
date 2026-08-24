class_name HexSectorManager
extends Node3D

const HexWorldTileClass = preload("res://scripts/world/hex_world_tile.gd")
const SectorBiomeDataClass = preload("res://scripts/resources/sector_biome_data.gd")
const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal tile_spawned(coord: Vector2i, tile: Node3D)
signal tile_despawned(coord: Vector2i)
signal sector_generated(active_tile_count: int)
signal railroad_generated(path_length: int)

@export_group("Configuration")
@export var active_target: Node3D
@export var biome_data: Resource
@export var world_seed: int = 1337
@export_range(1, 6, 1) var render_radius_rings: int = 4
@export var is_dynamic_streaming_enabled: bool = true
@export var is_procedural_railroad_enabled: bool = true

@export_group("Macro Trans-Sector Objectives")
@export var drop_off_coord: Vector2i = Vector2i(0, 0) # Sector Insertion / Drop-Off Zone
@export var extraction_coord: Vector2i = Vector2i(18, -18) # Sector Extraction Terminal (~300m North-East)

@export_group("Isometric Frustum Streaming Extents")
@export var forward_render_depth_m: float = 58.0 # Deep render distance to the North (screen up)
@export var lateral_render_width_m: float = 34.0 # Lateral width (East / West)
@export var rear_render_depth_m: float = 22.0 # Render depth to the South (screen down)
@export var velocity_lead_seconds: float = 0.70 # Predictive forward tile spawning at speed

@export_group("Hysteresis & Despawn Buffers")
@export var despawn_buffer_margin_m: float = 25.0 # Extra safety padding before despawning tiles
@export var sled_proximity_immunity_radius_m: float = 38.0 # Sled safety bubble: tiles inside are immune to despawn

# Active Tile Registry: Vector2i(q, r) -> Node3D
var _active_tiles: Dictionary = {}
var _active_rail_segments: Dictionary = {} # Vector2i -> Node3D
var _hot_spring_registry: Dictionary = {} # Vector2i -> bool
var _chasm_registry: Dictionary = {} # Vector2i -> bool
var _current_center_coord: Vector2i = Vector2i(9999, 9999)
var _tiles_container: Node3D
var _rails_container: Node3D

# Macro Trans-Sector Corridor (Pure Math Registry)
var _macro_railroad_path: Array[Vector2i] = []
var _macro_rail_segments: Dictionary = {} # Vector2i -> { "next": Vector2i, "prev": Vector2i, "has_car": bool }

const SQRT_3: float = 1.7320508

# Standard 45-degree isometric view axes
const VIEW_FORWARD: Vector3 = Vector3(-0.7071068, 0.0, -0.7071068) # "North" (screen up)
const VIEW_RIGHT: Vector3 = Vector3(0.7071068, 0.0, -0.7071068) # "East" (screen right)

func _ready() -> void:
	if not _tiles_container:
		_tiles_container = Node3D.new()
		_tiles_container.name = "TilesContainer"
		add_child(_tiles_container)
	if not _rails_container:
		_rails_container = Node3D.new()
		_rails_container.name = "RailsContainer"
		add_child(_rails_container)
	
	if not biome_data:
		biome_data = load("res://resources/biomes/temperate_permafrost.tres")
		if not biome_data:
			biome_data = SectorBiomeDataClass.new()
	
	_resolve_initial_target()
	
	if GlobalEvents.instance:
		GlobalEvents.instance.pilot_mounted_sled.connect(func(sled: Node) -> void:
			if sled is Node3D:
				active_target = sled as Node3D
		)
		GlobalEvents.instance.pilot_dismounted_sled.connect(func(_sled: Node) -> void:
			var pilots: Array[Node] = get_tree().get_nodes_in_group(&"player_pilot")
			if not pilots.is_empty() and pilots[0] is Node3D:
				active_target = pilots[0] as Node3D
		)
	
	# 1. Pre-calculate the Macro Trans-Sector Railway Path from Drop-Off to Extraction
	if is_procedural_railroad_enabled:
		_plan_macro_railroad_corridor(drop_off_coord, extraction_coord)
	
	# 2. Generate initial sector chunks
	generate_initial_sector()

func _resolve_initial_target() -> void:
	if not active_target:
		var sleds: Array[Node] = get_tree().get_nodes_in_group(&"player_sled")
		for s in sleds:
			if s is Node3D and s.get("is_occupied") == true:
				active_target = s as Node3D
				return
		var pilots: Array[Node] = get_tree().get_nodes_in_group(&"player_pilot")
		if not pilots.is_empty():
			active_target = pilots[0] as Node3D
		elif not sleds.is_empty():
			active_target = sleds[0] as Node3D

func _physics_process(_delta: float) -> void:
	if not is_dynamic_streaming_enabled:
		return
	
	var effective_target: Node3D = active_target
	if not effective_target or not is_instance_valid(effective_target):
		_resolve_initial_target()
		effective_target = active_target
		
	if not effective_target or not is_instance_valid(effective_target):
		return
		
	if "is_mounted_in_sled" in effective_target and effective_target.get("is_mounted_in_sled") == true:
		var current_sled: Node3D = effective_target.get("current_sled") as Node3D
		if current_sled and is_instance_valid(current_sled):
			effective_target = current_sled
	
	var target_pos: Vector3 = effective_target.global_position if effective_target.is_inside_tree() else effective_target.position
	
	# Add velocity predictive lead for spawning ahead
	var vel_offset: Vector3 = Vector3.ZERO
	if effective_target is CharacterBody3D:
		var v: Vector3 = (effective_target as CharacterBody3D).velocity
		if v.length() > 0.5:
			vel_offset = v.normalized() * minf(v.length() * velocity_lead_seconds, 22.0)
			
	var predictive_pos: Vector3 = target_pos + vel_offset
	var target_coord: Vector2i = world_pos_to_axial_coord(predictive_pos)
	
	if target_coord != _current_center_coord:
		_current_center_coord = target_coord
		_update_asymmetric_streaming_rings(target_pos, predictive_pos, target_coord)

## Generates concentric hex tiles around center
func generate_initial_sector(center_coord: Vector2i = Vector2i.ZERO) -> void:
	if not _tiles_container:
		_tiles_container = Node3D.new()
		_tiles_container.name = "TilesContainer"
		add_child(_tiles_container)
	if not _rails_container:
		_rails_container = Node3D.new()
		_rails_container.name = "RailsContainer"
		add_child(_rails_container)
		
	_current_center_coord = center_coord
	var center_world: Vector3 = axial_to_world_pos(center_coord)
	_update_asymmetric_streaming_rings(center_world, center_world, center_coord)
	
	sector_generated.emit(_active_tiles.size())

## Spawns tiles using predictive forward position and despawns only outside the wide real-position hysteresis envelope
func _update_asymmetric_streaming_rings(real_target_pos: Vector3, predictive_pos: Vector3, center_coord: Vector2i) -> void:
	# 1. Spawn envelope: Uses predictive_pos to spawn tiles ahead
	var needed_coords: Array[Vector2i] = get_asymmetric_isometric_cluster(predictive_pos, center_coord, forward_render_depth_m, lateral_render_width_m, rear_render_depth_m)
	
	# Pre-evaluate chasm map
	_pre_evaluate_chasm_map(needed_coords)
	
	for coord: Vector2i in needed_coords:
		if not _active_tiles.has(coord):
			_spawn_tile_at(coord)
	
	# 2. Despawn envelope with wide hysteresis buffer anchored to real_target_pos
	var max_fwd_despawn: float = forward_render_depth_m + despawn_buffer_margin_m
	var max_lat_despawn: float = lateral_render_width_m + despawn_buffer_margin_m
	var max_rear_despawn: float = rear_render_depth_m + despawn_buffer_margin_m
	
	var to_remove: Array[Vector2i] = []
	for coord: Vector2i in _active_tiles:
		var tile_world: Vector3 = axial_to_world_pos(coord)
		var rel_vec: Vector3 = tile_world - real_target_pos
		
		# Proximity Immunity Bubble
		var direct_dist: float = rel_vec.length()
		if direct_dist <= sled_proximity_immunity_radius_m:
			continue
			
		var d_forward: float = rel_vec.dot(VIEW_FORWARD)
		var d_lateral: float = absf(rel_vec.dot(VIEW_RIGHT))
		
		var outside_despawn_envelope: bool = (d_forward < -max_rear_despawn) or (d_forward > max_fwd_despawn) or (d_lateral > max_lat_despawn)
		if outside_despawn_envelope:
			to_remove.append(coord)
	
	for coord: Vector2i in to_remove:
		_despawn_tile_at(coord)

## Computes asymmetric isometric hex cluster with extended render depth to the North
func get_asymmetric_isometric_cluster(center_world: Vector3, center_coord: Vector2i, fwd_depth: float = 58.0, lat_width: float = 34.0, rear_depth: float = 22.0) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	var scan_radius: int = 9
	
	for q: int in range(-scan_radius, scan_radius + 1):
		for r: int in range(-scan_radius, scan_radius + 1):
			var cand_coord: Vector2i = center_coord + Vector2i(q, r)
			var cand_world: Vector3 = axial_to_world_pos(cand_coord)
			var rel_vec: Vector3 = cand_world - center_world
			
			var d_forward: float = rel_vec.dot(VIEW_FORWARD)
			var d_lateral: float = absf(rel_vec.dot(VIEW_RIGHT))
			var direct_dist: float = rel_vec.length()
			
			var in_frustum: bool = (d_forward >= -rear_depth) and (d_forward <= fwd_depth) and (d_lateral <= lat_width)
			var in_proximity: bool = direct_dist <= 22.0
			
			if in_frustum or in_proximity:
				results.append(cand_coord)
				
	return results

func _pre_evaluate_chasm_map(coords: Array[Vector2i]) -> void:
	var hill_noise: FastNoiseLite = FastNoiseLite.new()
	hill_noise.seed = world_seed + 7771
	hill_noise.frequency = 0.009
	var r_outer: float = biome_data.get("hex_cell_outer_radius_m") if "hex_cell_outer_radius_m" in biome_data else 6.0
	var c_thresh: float = biome_data.get("chasm_threshold") if "chasm_threshold" in biome_data else -0.32
	
	for coord: Vector2i in coords:
		if not _chasm_registry.has(coord):
			var wx: float = r_outer * SQRT_3 * (float(coord.x) + float(coord.y) * 0.5)
			var wz: float = r_outer * 1.5 * float(coord.y)
			var p_val: float = hill_noise.get_noise_2d(wx, wz)
			_chasm_registry[coord] = (p_val < c_thresh)

func _spawn_tile_at(coord: Vector2i) -> void:
	var is_hot_spring: bool = _evaluate_hot_spring_spawn(coord)
	var is_chasm: bool = _chasm_registry.get(coord, false) and not is_hot_spring
	
	# Evaluate if adjacent to a chasm to form a natural Jump Ramp kicker
	var is_jump_ramp: bool = false
	var ramp_dir: Vector2 = Vector2.ZERO
	if not is_chasm and not is_hot_spring:
		var ramp_info: Dictionary = _check_chasm_adjacency_ramp(coord)
		is_jump_ramp = ramp_info.get("is_ramp", false)
		ramp_dir = ramp_info.get("dir", Vector2.ZERO)
	
	var tile: Node3D = HexWorldTileClass.new()
	tile.name = "Tile_%d_%d" % [coord.x, coord.y]
	if _tiles_container:
		_tiles_container.add_child(tile)
	else:
		add_child(tile)
		
	if tile.has_method("initialize_tile"):
		tile.initialize_tile(coord, biome_data, world_seed, is_hot_spring, is_jump_ramp, ramp_dir)
	_active_tiles[coord] = tile
	
	# If this tile is part of the macro trans-sector railroad, instantiate its 3D track piece
	if is_procedural_railroad_enabled and _macro_rail_segments.has(coord):
		_spawn_streamed_rail_segment_at(coord, tile)
		
	tile_spawned.emit(coord, tile)

func _spawn_streamed_rail_segment_at(coord: Vector2i, tile: Node3D) -> void:
	var seg_info: Dictionary = _macro_rail_segments[coord]
	var next_coord: Vector2i = seg_info.get("next", coord)
	if next_coord == coord:
		return
		
	var from_pos: Vector3 = axial_to_world_pos(coord)
	var to_pos: Vector3 = axial_to_world_pos(next_coord)
	
	# Sample continuous terrain height at start and end nodes
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = world_seed
	noise.frequency = biome_data.elevation_frequency if "elevation_frequency" in biome_data else 0.022
	var amp: float = biome_data.elevation_amplitude if "elevation_amplitude" in biome_data else 1.85
	
	var hill_noise: FastNoiseLite = FastNoiseLite.new()
	hill_noise.seed = world_seed + 7771
	hill_noise.frequency = 0.009
	var hill_amp: float = 3.8
	
	from_pos.y = noise.get_noise_2d(from_pos.x, from_pos.z) * amp + hill_noise.get_noise_2d(from_pos.x, from_pos.z) * hill_amp
	to_pos.y = noise.get_noise_2d(to_pos.x, to_pos.z) * amp + hill_noise.get_noise_2d(to_pos.x, to_pos.z) * hill_amp
	
	var rail_node: Node3D = _build_rail_segment_3d(from_pos, to_pos)
	if _rails_container:
		_rails_container.add_child(rail_node)
	else:
		tile.add_child(rail_node)
	_active_rail_segments[coord] = rail_node
	
	# Check if this segment carries an abandoned loot freight car
	if seg_info.get("has_car", false):
		var dir_3d: Vector3 = (to_pos - from_pos).normalized()
		var mid_pos: Vector3 = (from_pos + to_pos) * 0.5
		var car_node: Node3D = _spawn_abandoned_train_car(mid_pos, dir_3d)
		if _rails_container:
			_rails_container.add_child(car_node)
		else:
			tile.add_child(car_node)

func _despawn_tile_at(coord: Vector2i) -> void:
	if _active_tiles.has(coord):
		var tile: Node3D = _active_tiles[coord]
		if is_instance_valid(tile):
			tile.queue_free()
		_active_tiles.erase(coord)
		
		# Clean up streamed 3D rail segment
		if _active_rail_segments.has(coord):
			var rail: Node3D = _active_rail_segments[coord]
			if is_instance_valid(rail):
				rail.queue_free()
			_active_rail_segments.erase(coord)
			
		tile_despawned.emit(coord)

## Pre-plans the Macro Trans-Sector Railway Path (A* on deterministic math across the continent)
func _plan_macro_railroad_corridor(start: Vector2i, end: Vector2i) -> void:
	_macro_railroad_path.clear()
	_macro_rail_segments.clear()
	
	var astar: AStar2D = AStar2D.new()
	var coord_to_id: Dictionary = {}
	var id_to_coord: Dictionary = {}
	var id_counter: int = 0
	
	var min_q: int = mini(start.x, end.x) - 4
	var max_q: int = maxi(start.x, end.x) + 4
	var min_r: int = mini(start.y, end.y) - 4
	var max_r: int = maxi(start.y, end.y) + 4
	
	var hill_noise: FastNoiseLite = FastNoiseLite.new()
	hill_noise.seed = world_seed + 7771
	hill_noise.frequency = 0.009
	var r_outer: float = biome_data.get("hex_cell_outer_radius_m") if "hex_cell_outer_radius_m" in biome_data else 6.0
	var c_thresh: float = biome_data.get("chasm_threshold") if "chasm_threshold" in biome_data else -0.32
	
	# 1. Register macro sector grid points
	for q: int in range(min_q, max_q + 1):
		for r: int in range(min_r, max_r + 1):
			var c: Vector2i = Vector2i(q, r)
			var w_pos: Vector3 = axial_to_world_pos(c)
			astar.add_point(id_counter, Vector2(w_pos.x, w_pos.z))
			
			var is_spring: bool = _evaluate_hot_spring_spawn(c)
			var p_val: float = hill_noise.get_noise_2d(w_pos.x, w_pos.z)
			var is_chasm: bool = (p_val < c_thresh) and not is_spring
			
			if is_spring:
				astar.set_point_weight_scale(id_counter, 150.0) # Avoid hot springs
			elif is_chasm:
				astar.set_point_weight_scale(id_counter, 80.0) # Avoid crevasses
			else:
				astar.set_point_weight_scale(id_counter, 1.0)
				
			coord_to_id[c] = id_counter
			id_to_coord[id_counter] = c
			id_counter += 1
	
	# 2. Connect neighboring hex edges in A* graph
	var neighbors_offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
	]
	
	for c: Vector2i in coord_to_id:
		var u_id: int = coord_to_id[c]
		for offset: Vector2i in neighbors_offsets:
			var n_coord: Vector2i = c + offset
			if coord_to_id.has(n_coord):
				var v_id: int = coord_to_id[n_coord]
				if not astar.are_points_connected(u_id, v_id):
					astar.connect_points(u_id, v_id)
	
	if not coord_to_id.has(start) or not coord_to_id.has(end):
		return
		
	var start_id: int = coord_to_id[start]
	var end_id: int = coord_to_id[end]
	
	var path_ids: PackedInt64Array = astar.get_id_path(start_id, end_id)
	if path_ids.is_empty():
		return
		
	for p_id: int in path_ids:
		_macro_railroad_path.append(id_to_coord[p_id])
		
	# 3. Store macro segment connections and place abandoned train cars at milestones
	var total_nodes: int = _macro_railroad_path.size()
	for idx: int in range(total_nodes - 1):
		var cur_c: Vector2i = _macro_railroad_path[idx]
		var next_c: Vector2i = _macro_railroad_path[idx + 1]
		var has_car: bool = (idx == int(total_nodes * 0.35)) or (idx == int(total_nodes * 0.70))
		
		_macro_rail_segments[cur_c] = {
			"next": next_c,
			"has_car": has_car
		}
		
	railroad_generated.emit(_macro_railroad_path.size())

func _build_rail_segment_3d(from_pos: Vector3, to_pos: Vector3) -> Node3D:
	var segment: Node3D = Node3D.new()
	segment.name = "RailSegment"
	
	var mid_pos: Vector3 = (from_pos + to_pos) * 0.5 + Vector3(0, 0.08, 0)
	var dir_3d: Vector3 = (to_pos - from_pos).normalized()
	var track_len: float = from_pos.distance_to(to_pos) * 1.02
	
	segment.position = mid_pos
	var rot_y: float = atan2(dir_3d.x, dir_3d.z)
	var pitch_x: float = -asin(clampf(dir_3d.y, -0.9, 0.9))
	segment.rotation = Vector3(pitch_x, rot_y, 0)
	
	# Gravel Ballast Bed
	var ballast: MeshInstance3D = MeshInstance3D.new()
	var ballast_box: BoxMesh = BoxMesh.new()
	ballast_box.size = Vector3(2.6, 0.12, track_len)
	ballast.mesh = ballast_box
	var ballast_mat: StandardMaterial3D = StandardMaterial3D.new()
	ballast_mat.albedo_color = Color(0.35, 0.33, 0.32, 1.0)
	ballast_mat.roughness = 0.95
	ballast.material_override = ballast_mat
	segment.add_child(ballast)
	
	# Wood Ties
	var tie_count: int = 5
	for t: int in range(tie_count):
		var tie_z: float = -track_len * 0.5 + (float(t) + 0.5) * (track_len / float(tie_count))
		var tie: MeshInstance3D = MeshInstance3D.new()
		var tie_box: BoxMesh = BoxMesh.new()
		tie_box.size = Vector3(2.2, 0.10, 0.28)
		tie.mesh = tie_box
		tie.position = Vector3(0, 0.06, tie_z)
		var tie_mat: StandardMaterial3D = StandardMaterial3D.new()
		tie_mat.albedo_color = Color(0.28, 0.22, 0.18, 1.0)
		tie_mat.roughness = 0.9
		tie.material_override = tie_mat
		segment.add_child(tie)
	
	# Steel Rails (Pair)
	var steel_mat: StandardMaterial3D = StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.65, 0.68, 0.72, 1.0)
	steel_mat.metallic = 0.8
	steel_mat.roughness = 0.25
	
	for rail_x: float in [-0.75, 0.75]:
		var rail: MeshInstance3D = MeshInstance3D.new()
		var rail_box: BoxMesh = BoxMesh.new()
		rail_box.size = Vector3(0.10, 0.16, track_len)
		rail.mesh = rail_box
		rail.position = Vector3(rail_x, 0.14, 0)
		rail.material_override = steel_mat
		segment.add_child(rail)
	
	return segment

func _spawn_abandoned_train_car(pos: Vector3, forward_dir: Vector3) -> Node3D:
	var car: StaticBody3D = StaticBody3D.new()
	car.name = "AbandonedRailCar"
	car.position = pos + Vector3(0, 1.4, 0)
	
	var rot_y: float = atan2(forward_dir.x, forward_dir.z)
	var pitch_x: float = -asin(clampf(forward_dir.y, -0.9, 0.9))
	car.rotation = Vector3(pitch_x, rot_y, 0)
	car.collision_layer = 1
	car.collision_mask = 6
	
	var car_mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(2.2, 2.0, 5.5)
	car_mesh.mesh = box
	var rust_mat: StandardMaterial3D = StandardMaterial3D.new()
	rust_mat.albedo_color = Color(0.55, 0.28, 0.20, 1.0)
	rust_mat.metallic = 0.5
	rust_mat.roughness = 0.75
	car_mesh.material_override = rust_mat
	car.add_child(car_mesh)
	
	var col: CollisionShape3D = CollisionShape3D.new()
	var col_shape: BoxShape3D = BoxShape3D.new()
	col_shape.size = Vector3(2.2, 2.0, 5.5)
	col.shape = col_shape
	car.add_child(col)
	
	# Loot Crate inside freight car
	var crate_scene: PackedScene = load("res://scenes/containers/GroundCrate.tscn")
	if crate_scene:
		var crate: Node3D = crate_scene.instantiate() as Node3D
		crate.position = Vector3(0, 0.1, 1.2)
		car.add_child(crate)
	
	return car

func _check_chasm_adjacency_ramp(coord: Vector2i) -> Dictionary:
	var neighbors_offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
	]
	
	var my_pos: Vector3 = axial_to_world_pos(coord)
	
	for offset: Vector2i in neighbors_offsets:
		var n_coord: Vector2i = coord + offset
		if _chasm_registry.get(n_coord, false) == true:
			var chasm_pos: Vector3 = axial_to_world_pos(n_coord)
			var dir_3d: Vector3 = (chasm_pos - my_pos).normalized()
			return {
				"is_ramp": true,
				"dir": Vector2(dir_3d.x, dir_3d.z)
			}
			
	return {"is_ramp": false, "dir": Vector2.ZERO}

## Evaluates hot spring spawning: 0% chance on adjacent hexes, 10% on 1-hex separated spaces (Ring 2)
func _evaluate_hot_spring_spawn(coord: Vector2i) -> bool:
	if _hot_spring_registry.has(coord):
		return _hot_spring_registry[coord]
	
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + (coord.x * 524287) ^ (coord.y * 131071)
	
	# 1. Check immediate adjacent neighbors (Distance 1)
	var adjacent_offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
	]
	for offset: Vector2i in adjacent_offsets:
		if _hot_spring_registry.get(coord + offset, false) == true:
			_hot_spring_registry[coord] = false
			return false
			
	# 2. Check 1-hex separated neighbors (Distance 2)
	var ring2_offsets: Array[Vector2i] = [
		Vector2i(2, 0), Vector2i(2, -1), Vector2i(2, -2), Vector2i(1, -2),
		Vector2i(0, -2), Vector2i(-1, -1), Vector2i(-2, 0), Vector2i(-2, 1),
		Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 1)
	]
	var has_distance2_spring: bool = false
	for offset: Vector2i in ring2_offsets:
		if _hot_spring_registry.get(coord + offset, false) == true:
			has_distance2_spring = true
			break
			
	var base_chance: float = biome_data.get("hot_spring_basin_chance") if "hot_spring_basin_chance" in biome_data else 0.01
	var cluster_boost: float = biome_data.get("hot_spring_cluster_boost") if "hot_spring_cluster_boost" in biome_data else 0.10
	
	var effective_chance: float = cluster_boost if has_distance2_spring else base_chance
	var result: bool = rng.randf() < effective_chance
	_hot_spring_registry[coord] = result
	return result

## Returns all axial coordinates within N concentric rings of a center coord
func get_hex_ring_cluster(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	for q: int in range(-radius, radius + 1):
		var r1: int = max(-radius, -q - radius)
		var r2: int = min(radius, -q + radius)
		for r: int in range(r1, r2 + 1):
			results.append(center + Vector2i(q, r))
	return results

## Converts world 3D position to nearest axial hex tile coordinate (q, r)
func world_pos_to_axial_coord(world_pos: Vector3) -> Vector2i:
	var r_outer: float = 6.0
	if biome_data and "hex_cell_outer_radius_m" in biome_data:
		r_outer = float(biome_data.get("hex_cell_outer_radius_m"))
	var q_frac: float = (sqrt(3.0) / 3.0 * world_pos.x - 1.0 / 3.0 * world_pos.z) / r_outer
	var r_frac: float = (2.0 / 3.0 * world_pos.z) / r_outer
	return _axial_round(q_frac, r_frac)

## Converts axial hex tile coordinate (q, r) to center 3D world position
func axial_to_world_pos(coord: Vector2i) -> Vector3:
	var r_outer: float = 6.0
	if biome_data and "hex_cell_outer_radius_m" in biome_data:
		r_outer = float(biome_data.get("hex_cell_outer_radius_m"))
	var x: float = r_outer * SQRT_3 * (float(coord.x) + float(coord.y) * 0.5)
	var z: float = r_outer * 1.5 * float(coord.y)
	return Vector3(x, 0.0, z)

func _axial_round(q_frac: float, r_frac: float) -> Vector2i:
	var s_frac: float = -q_frac - r_frac
	var q_round: int = int(round(q_frac))
	var r_round: int = int(round(r_frac))
	var s_round: int = int(round(s_frac))
	
	var q_diff: float = absf(float(q_round) - q_frac)
	var r_diff: float = absf(float(r_round) - r_frac)
	var s_diff: float = absf(float(s_round) - s_frac)
	
	if q_diff > r_diff and q_diff > s_diff:
		q_round = -r_round - s_round
	elif r_diff > s_diff:
		r_round = -q_round - s_round
	
	return Vector2i(q_round, r_round)

func get_active_tile(coord: Vector2i) -> Node3D:
	return _active_tiles.get(coord, null)

func get_active_tile_count() -> int:
	return _active_tiles.size()

func get_railroad_path() -> Array[Vector2i]:
	return _macro_railroad_path
