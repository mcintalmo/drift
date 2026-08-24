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
@export var drop_off_coord: Vector2i = Vector2i(0, 0) # Sector Insertion / Drop-Off Zone (Valley Entrance)
@export var extraction_coord: Vector2i = Vector2i(18, -18) # Sector Extraction Terminal (Valley Exit)

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
	
	# 1. Pre-calculate the Macro Trans-Sector Railway Path from Entrance Boundary to Exit Boundary
	if is_procedural_railroad_enabled:
		var rail_start: Vector2i = get_railroad_entrance_boundary_coord()
		var rail_end: Vector2i = get_railroad_exit_boundary_coord()
		_plan_macro_railroad_corridor(rail_start, rail_end)
	
	# 2. Generate initial sector chunks
	generate_initial_sector()
	
	# 3. Spawn Mountain Tunnel Portals & Moving Train Convoy if active heist
	if is_procedural_railroad_enabled:
		_spawn_mountain_tunnel_portals()
		var is_active_rail: bool = biome_data.get("is_railroad_active") if "is_railroad_active" in biome_data else false
		if is_active_rail:
			_spawn_moving_train_convoy()

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
		
	if not biome_data:
		biome_data = load("res://resources/biomes/temperate_permafrost.tres")
		if not biome_data:
			biome_data = SectorBiomeDataClass.new()
		
	if is_procedural_railroad_enabled and _macro_railroad_path.is_empty():
		var rail_start: Vector2i = get_railroad_entrance_boundary_coord()
		var rail_end: Vector2i = get_railroad_exit_boundary_coord()
		_plan_macro_railroad_corridor(rail_start, rail_end)
		_spawn_mountain_tunnel_portals()
		var is_active_rail: bool = biome_data.get("is_railroad_active") if "is_railroad_active" in biome_data else false
		if is_active_rail:
			_spawn_moving_train_convoy()
		
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

## Exact continuous elevation height lookup matching HexWorldTile terrain calculation
func sample_terrain_surface_y(world_x: float, world_z: float) -> float:
	var base_noise: FastNoiseLite = FastNoiseLite.new()
	base_noise.seed = world_seed
	base_noise.frequency = biome_data.get("elevation_frequency") if "elevation_frequency" in biome_data else 0.022
	var amp: float = biome_data.get("elevation_amplitude") if "elevation_amplitude" in biome_data else 1.85
	
	var hill_noise: FastNoiseLite = FastNoiseLite.new()
	hill_noise.seed = world_seed + 7771
	hill_noise.frequency = 0.009
	var hill_amp: float = biome_data.get("plateau_tier_height_m") if "plateau_tier_height_m" in biome_data else 3.8
	
	var rolling_h: float = base_noise.get_noise_2d(world_x, world_z) * amp
	var hill_h: float = maxf(0.0, hill_noise.get_noise_2d(world_x, world_z) * hill_amp * 1.8)
	return rolling_h + hill_h

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
	
	# 1. Evaluate Valley Boundary Walls vs Void Drop-offs
	var boundary_flags: Dictionary = _evaluate_boundary_status(coord)
	var is_wall: bool = boundary_flags.get("is_wall", false)
	var is_void: bool = boundary_flags.get("is_void", false)
	
	# 2. Evaluate if adjacent to a chasm to form a natural Jump Ramp kicker
	var is_jump_ramp: bool = false
	var ramp_dir: Vector2 = Vector2.ZERO
	if not is_chasm and not is_hot_spring and not is_wall and not is_void:
		var ramp_info: Dictionary = _check_chasm_adjacency_ramp(coord)
		is_jump_ramp = ramp_info.get("is_ramp", false)
		ramp_dir = ramp_info.get("dir", Vector2.ZERO)
	
	# 3. Calculate distance to nearest railway line for subgrade embankment leveling
	var rail_proximity: Dictionary = _calculate_rail_proximity(coord)
	var dist_to_rail: float = rail_proximity.get("dist", 999.0)
	var rail_target_y: float = rail_proximity.get("y", 0.0)
	var is_rail_active: bool = biome_data.get("is_railroad_active") if "is_railroad_active" in biome_data else false
	
	var tile: Node3D = HexWorldTileClass.new()
	tile.name = "Tile_%d_%d" % [coord.x, coord.y]
	if _tiles_container:
		_tiles_container.add_child(tile)
	else:
		add_child(tile)
		
	if tile.has_method("initialize_tile"):
		tile.initialize_tile(
			coord, biome_data, world_seed,
			is_hot_spring, is_jump_ramp, ramp_dir,
			is_wall, is_void,
			dist_to_rail, rail_target_y, is_rail_active
		)
	_active_tiles[coord] = tile
	
	# If this tile is part of the macro trans-sector railroad, instantiate its 3D track piece
	if is_procedural_railroad_enabled and _macro_rail_segments.has(coord) and not is_void:
		_spawn_streamed_rail_segment_at(coord, tile)
		
	tile_spawned.emit(coord, tile)

## Computes the lateral meander offset of the canyon corridor at a given longitudinal distance
func get_canyon_meander_offset(along: float, axis_len: float) -> float:
	if axis_len <= 10.0:
		return 0.0
		
	# Smooth fade at entrance (0..60m) and exit (L-60m..L) so portals stay centered
	var t_start: float = clampf(along / 60.0, 0.0, 1.0)
	var t_end: float = clampf((axis_len - along) / 60.0, 0.0, 1.0)
	var envelope: float = smoothstep(0.0, 1.0, t_start) * smoothstep(0.0, 1.0, t_end)
	
	# Harmonic meander waves (sweeping S-curves across canyon)
	var wave1: float = sin(along * (TAU / 320.0)) * 28.0
	var wave2: float = sin(along * (TAU / 680.0) + 1.2) * 20.0
	var wave3: float = cos(along * (TAU / 180.0) + 0.6) * 8.0
	
	return (wave1 + wave2 + wave3) * envelope

## Evaluates whether a coordinate lies on the lateral boundary of the valley corridor
func _evaluate_boundary_status(coord: Vector2i) -> Dictionary:
	var mode: int = biome_data.get("boundary_mode") if "boundary_mode" in biome_data else SectorBiomeDataClass.BoundaryMode.VALLEY_CLIFF_FACES
	if mode == SectorBiomeDataClass.BoundaryMode.INFINITE_UNBOUNDED:
		return {"is_wall": false, "is_void": false}
		
	var w_pos: Vector3 = axial_to_world_pos(coord)
	var w_start: Vector3 = axial_to_world_pos(drop_off_coord)
	var w_end: Vector3 = axial_to_world_pos(extraction_coord)
	
	# Open entrance & exit passes (Drop-Off & Extraction zones are open in the valley floor)
	if w_pos.distance_to(w_start) <= 16.0 or w_pos.distance_to(w_end) <= 16.0:
		return {"is_wall": false, "is_void": false}
		
	var axis_vec: Vector3 = w_end - w_start
	var axis_len: float = axis_vec.length()
	if axis_len < 1.0:
		return {"is_wall": false, "is_void": false}
		
	var axis_dir: Vector3 = axis_vec / axis_len
	var lat_dir: Vector3 = Vector3(-axis_dir.z, 0.0, axis_dir.x)
	
	var rel: Vector3 = w_pos - w_start
	var along: float = rel.dot(axis_dir)
	var lat_val: float = rel.dot(lat_dir)
	
	var meander_center: float = get_canyon_meander_offset(along, axis_len)
	var lat_dist: float = absf(lat_val - meander_center)
	
	var valley_width_m: float = float(biome_data.get("valley_width_hexes") if "valley_width_hexes" in biome_data else 8) * 6.0 * SQRT_3 * 0.5
	var outside_corridor: bool = (lat_dist > valley_width_m) or (along < -18.0) or (along > axis_len + 18.0)
	
	if outside_corridor:
		if mode == SectorBiomeDataClass.BoundaryMode.VALLEY_CLIFF_FACES:
			return {"is_wall": true, "is_void": false}
		elif mode == SectorBiomeDataClass.BoundaryMode.PLATEAU_VOID_EDGES:
			return {"is_wall": false, "is_void": true}
			
	return {"is_wall": false, "is_void": false}

## Calculates perpendicular distance from tile center to nearest macro railroad path segment
func _calculate_rail_proximity(coord: Vector2i) -> Dictionary:
	if _macro_railroad_path.is_empty():
		return {"dist": 999.0, "y": 0.0}
		
	var w_pos: Vector3 = axial_to_world_pos(coord)
	var min_dist: float = 999.0
	var nearest_pos: Vector3 = Vector3.ZERO
	
	for r_coord: Vector2i in _macro_railroad_path:
		var r_pos: Vector3 = axial_to_world_pos(r_coord)
		var d: float = w_pos.distance_to(r_pos)
		if d < min_dist:
			min_dist = d
			nearest_pos = r_pos
			
	var target_y: float = sample_terrain_surface_y(nearest_pos.x, nearest_pos.z)
	return {"dist": min_dist, "y": target_y}

## Spawns multi-chord ground-conforming 3D rail pieces strictly on top of the undulating rolling terrain
func _spawn_streamed_rail_segment_at(coord: Vector2i, tile: Node3D) -> void:
	var seg_info: Dictionary = _macro_rail_segments[coord]
	var next_coord: Vector2i = seg_info.get("next", coord)
	if next_coord == coord:
		return
		
	var from_world_2d: Vector3 = axial_to_world_pos(coord)
	var to_world_2d: Vector3 = axial_to_world_pos(next_coord)
	
	var is_active: bool = biome_data.get("is_railroad_active") if "is_railroad_active" in biome_data else false
	
	var multi_segment_root: Node3D = Node3D.new()
	multi_segment_root.name = "RailSegmentGroup_%d_%d" % [coord.x, coord.y]
	
	# Subdivide into 4 multi-chord sub-segments so tracks hug convex hill crests and concave valleys perfectly
	var sub_steps: int = 4
	for s: int in range(sub_steps):
		var t1: float = float(s) / float(sub_steps)
		var t2: float = float(s + 1) / float(sub_steps)
		
		var p1: Vector3 = from_world_2d.lerp(to_world_2d, t1)
		var p2: Vector3 = from_world_2d.lerp(to_world_2d, t2)
		
		# Sample continuous terrain height at each sub-vertex (+0.14m above ground)
		p1.y = sample_terrain_surface_y(p1.x, p1.z) + 0.14
		p2.y = sample_terrain_surface_y(p2.x, p2.z) + 0.14
		
		# On inactive derelict lines, evaluate broken/blown track gaps (20% random chance)
		var is_broken: bool = false
		if not is_active:
			var rng_sub: RandomNumberGenerator = RandomNumberGenerator.new()
			rng_sub.seed = world_seed + (coord.x * 31337) ^ (coord.y * 7919) + (s * 101)
			is_broken = rng_sub.randf() < 0.22
			
		var sub_node: Node3D = _build_rail_sub_piece_3d(p1, p2, is_broken)
		multi_segment_root.add_child(sub_node)
	
	if _rails_container:
		_rails_container.add_child(multi_segment_root)
	else:
		tile.add_child(multi_segment_root)
	_active_rail_segments[coord] = multi_segment_root
	
	# Check if this segment carries an abandoned loot freight car (derelict tracks only)
	if not is_active and seg_info.get("has_car", false):
		var mid_2d: Vector3 = (from_world_2d + to_world_2d) * 0.5
		var dir_3d: Vector3 = (to_world_2d - from_world_2d).normalized()
		var car_pos: Vector3 = mid_2d
		car_pos.y = sample_terrain_surface_y(mid_2d.x, mid_2d.z) + 1.25
		
		var car_node: Node3D = _spawn_abandoned_train_car(car_pos, dir_3d)
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
	
	var w_start: Vector3 = axial_to_world_pos(start)
	var w_end: Vector3 = axial_to_world_pos(end)
	var axis_vec: Vector3 = w_end - w_start
	var axis_len: float = axis_vec.length()
	var axis_dir: Vector3 = axis_vec / axis_len if axis_len > 1.0 else Vector3.FORWARD
	var lat_dir: Vector3 = Vector3(-axis_dir.z, 0.0, axis_dir.x)
	var valley_width_m: float = float(biome_data.get("valley_width_hexes") if "valley_width_hexes" in biome_data else 10) * 6.0 * SQRT_3 * 0.5
	var max_lat_allowed: float = valley_width_m + 16.0
	
	var hill_noise: FastNoiseLite = FastNoiseLite.new()
	hill_noise.seed = world_seed + 7771
	hill_noise.frequency = 0.009
	var r_outer: float = biome_data.get("hex_cell_outer_radius_m") if "hex_cell_outer_radius_m" in biome_data else 6.0
	var c_thresh: float = biome_data.get("chasm_threshold") if "chasm_threshold" in biome_data else -0.32
	
	# 1. Register macro sector grid points within corridor
	for q: int in range(min_q, max_q + 1):
		for r: int in range(min_r, max_r + 1):
			var c: Vector2i = Vector2i(q, r)
			var w_pos: Vector3 = axial_to_world_pos(c)
			
			var rel: Vector3 = w_pos - w_start
			var along: float = rel.dot(axis_dir)
			var lat_val: float = rel.dot(lat_dir)
			var meander_center: float = get_canyon_meander_offset(along, axis_len)
			var lat_dist: float = absf(lat_val - meander_center)
			
			if lat_dist > max_lat_allowed and c != start and c != end:
				continue
				
			astar.add_point(id_counter, Vector2(w_pos.x, w_pos.z))
			
			var is_spring: bool = _evaluate_hot_spring_spawn(c)
			var p_val: float = hill_noise.get_noise_2d(w_pos.x, w_pos.z)
			var is_chasm: bool = (p_val < c_thresh) and not is_spring
			
			var base_weight: float = 1.0
			if is_spring:
				base_weight = 150.0 # Avoid hot springs
			elif is_chasm:
				base_weight = 80.0 # Avoid crevasses
				
			# Natural centerline tracking penalty creates winding tracks that follow the canyon meander
			var meander_weight: float = 1.0 + (lat_dist / (valley_width_m + 1.0)) * 2.0
			astar.set_point_weight_scale(id_counter, base_weight * meander_weight)
				
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

func _build_rail_sub_piece_3d(from_pos: Vector3, to_pos: Vector3, is_broken: bool = false) -> Node3D:
	var segment: Node3D = Node3D.new()
	segment.name = "RailSubPiece"
	
	var mid_pos: Vector3 = (from_pos + to_pos) * 0.5
	var dir_3d: Vector3 = (to_pos - from_pos).normalized()
	var track_len: float = from_pos.distance_to(to_pos) * 1.04
	
	segment.position = mid_pos
	var rot_y: float = atan2(dir_3d.x, dir_3d.z)
	var pitch_x: float = -asin(clampf(dir_3d.y, -0.9, 0.9))
	segment.rotation = Vector3(pitch_x, rot_y, 0)
	
	# Gravel Ballast Bed (Embeds -0.22m into snow surface to avoid any gaps under rails)
	var ballast: MeshInstance3D = MeshInstance3D.new()
	var ballast_box: BoxMesh = BoxMesh.new()
	ballast_box.size = Vector3(2.5, 0.28, track_len)
	ballast.mesh = ballast_box
	ballast.position = Vector3(0, -0.06, 0)
	var ballast_mat: StandardMaterial3D = StandardMaterial3D.new()
	ballast_mat.albedo_color = Color(0.35, 0.33, 0.32, 1.0) if not is_broken else Color(0.42, 0.38, 0.35, 1.0)
	ballast_mat.roughness = 0.95
	ballast.material_override = ballast_mat
	segment.add_child(ballast)
	
	if is_broken:
		# Weathered broken gap with twisted metal, missing ties, and a snowdrift mound
		var drift: MeshInstance3D = MeshInstance3D.new()
		var drift_sphere: SphereMesh = SphereMesh.new()
		drift_sphere.radius = 1.1
		drift_sphere.height = 0.6
		drift.mesh = drift_sphere
		drift.position = Vector3(0, 0.05, 0)
		var snow_mat: StandardMaterial3D = StandardMaterial3D.new()
		snow_mat.albedo_color = Color(0.92, 0.95, 0.98, 1.0)
		drift.material_override = snow_mat
		segment.add_child(drift)
		
		# Single twisted bent rail fragment
		var rail_twist: MeshInstance3D = MeshInstance3D.new()
		var twist_box: BoxMesh = BoxMesh.new()
		twist_box.size = Vector3(0.12, 0.18, track_len * 0.45)
		rail_twist.mesh = twist_box
		rail_twist.position = Vector3(0.75, 0.22, -track_len * 0.2)
		rail_twist.rotation_degrees = Vector3(15, -12, 20)
		var rust_mat: StandardMaterial3D = StandardMaterial3D.new()
		rust_mat.albedo_color = Color(0.52, 0.30, 0.22, 1.0)
		rust_mat.metallic = 0.6
		rust_mat.roughness = 0.8
		rail_twist.material_override = rust_mat
		segment.add_child(rail_twist)
		return segment
	
	# Wood Ties (Ties along this sub-piece)
	var tie: MeshInstance3D = MeshInstance3D.new()
	var tie_box: BoxMesh = BoxMesh.new()
	tie_box.size = Vector3(2.2, 0.12, 0.32)
	tie.mesh = tie_box
	tie.position = Vector3(0, 0.08, 0)
	var tie_mat: StandardMaterial3D = StandardMaterial3D.new()
	tie_mat.albedo_color = Color(0.28, 0.22, 0.18, 1.0)
	tie_mat.roughness = 0.9
	tie.material_override = tie_mat
	segment.add_child(tie)
	
	# Steel Rails (Pair sitting firmly on top of ties)
	var steel_mat: StandardMaterial3D = StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.70, 0.72, 0.76, 1.0)
	steel_mat.metallic = 0.85
	steel_mat.roughness = 0.25
	
	for rail_x: float in [-0.75, 0.75]:
		var rail: MeshInstance3D = MeshInstance3D.new()
		var rail_box: BoxMesh = BoxMesh.new()
		rail_box.size = Vector3(0.12, 0.18, track_len)
		rail.mesh = rail_box
		rail.position = Vector3(rail_x, 0.18, 0)
		rail.material_override = steel_mat
		segment.add_child(rail)
	
	return segment

func _spawn_abandoned_train_car(pos: Vector3, forward_dir: Vector3) -> Node3D:
	var car: StaticBody3D = StaticBody3D.new()
	car.name = "AbandonedRailCar"
	car.position = pos
	
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

func get_active_moving_train() -> Node:
	return _moving_train_instance

## Generates a smooth 3D Curve3D spline matching the multi-chord track geometry
func get_macro_railroad_curve() -> Curve3D:
	var curve: Curve3D = Curve3D.new()
	if _macro_railroad_path.is_empty():
		return curve
		
	var sub_steps: int = 4
	for idx: int in range(_macro_railroad_path.size() - 1):
		var cur_c: Vector2i = _macro_railroad_path[idx]
		var next_c: Vector2i = _macro_railroad_path[idx + 1]
		var p_start_2d: Vector3 = axial_to_world_pos(cur_c)
		var p_end_2d: Vector3 = axial_to_world_pos(next_c)
		
		for s: int in range(sub_steps):
			var t: float = float(s) / float(sub_steps)
			var pt: Vector3 = p_start_2d.lerp(p_end_2d, t)
			pt.y = sample_terrain_surface_y(pt.x, pt.z) + 0.35 + 0.16 # Positioned directly on rails
			curve.add_point(pt)
			
	# Add final endpoint
	var last_c: Vector2i = _macro_railroad_path.back()
	var last_pt: Vector3 = axial_to_world_pos(last_c)
	last_pt.y = sample_terrain_surface_y(last_pt.x, last_pt.z) + 0.35 + 0.16
	curve.add_point(last_pt)
	
	return curve

var _moving_train_instance: Node = null

func _spawn_moving_train_convoy() -> void:
	if _macro_railroad_path.is_empty():
		return
		
	var curve: Curve3D = get_macro_railroad_curve()
	if curve.get_point_count() < 2:
		return
		
	var train_node: MovingTrain = MovingTrain.new()
	train_node.name = "MovingTrainConvoy"
	
	# Load train scenes
	var loco_scene: PackedScene = load("res://scenes/entities/train/ArmoredLocomotive.tscn")
	var boxcar_scene: PackedScene = load("res://scenes/entities/train/ArmoredBoxcar.tscn")
	
	var cars: Array[TrainCar] = []
	if loco_scene:
		var loco: TrainCar = loco_scene.instantiate() as TrainCar
		loco.name = "ArmoredLocomotive"
		train_node.add_child(loco)
		cars.append(loco)
	if boxcar_scene:
		var car1: TrainCar = boxcar_scene.instantiate() as TrainCar
		car1.name = "ArmoredBoxcar_1"
		train_node.add_child(car1)
		cars.append(car1)
		
		var car2: TrainCar = boxcar_scene.instantiate() as TrainCar
		car2.name = "ArmoredBoxcar_2"
		train_node.add_child(car2)
		cars.append(car2)
		
	add_child(train_node)
	train_node.initialize_train_on_path(curve, cars)
	_moving_train_instance = train_node

## Computes the boundary hex coordinate for the railroad entrance (in cliff face behind Drop-Off)
func get_railroad_entrance_boundary_coord() -> Vector2i:
	var step_dir: Vector2i = Vector2i(sign(extraction_coord.x - drop_off_coord.x), sign(extraction_coord.y - drop_off_coord.y))
	if step_dir == Vector2i.ZERO:
		step_dir = Vector2i(1, -1)
	return drop_off_coord - step_dir * 4

## Computes the boundary hex coordinate for the railroad exit (in cliff face past Extraction)
func get_railroad_exit_boundary_coord() -> Vector2i:
	var step_dir: Vector2i = Vector2i(sign(extraction_coord.x - drop_off_coord.x), sign(extraction_coord.y - drop_off_coord.y))
	if step_dir == Vector2i.ZERO:
		step_dir = Vector2i(1, -1)
	return extraction_coord + step_dir * 4

func _spawn_mountain_tunnel_portals() -> void:
	if _macro_railroad_path.is_empty():
		return
		
	var start_coord: Vector2i = _macro_railroad_path.front()
	var exit_coord: Vector2i = _macro_railroad_path.back()
	
	var start_pos: Vector3 = axial_to_world_pos(start_coord)
	start_pos.y = sample_terrain_surface_y(start_pos.x, start_pos.z)
	var exit_pos: Vector3 = axial_to_world_pos(exit_coord)
	exit_pos.y = sample_terrain_surface_y(exit_pos.x, exit_pos.z)
	
	var fwd_start: Vector3 = Vector3(0, 0, 1)
	if _macro_railroad_path.size() >= 2:
		var p1: Vector3 = axial_to_world_pos(_macro_railroad_path[1])
		fwd_start = (p1 - start_pos).normalized()
		
	var fwd_exit: Vector3 = Vector3(0, 0, 1)
	if _macro_railroad_path.size() >= 2:
		var p_prev: Vector3 = axial_to_world_pos(_macro_railroad_path[_macro_railroad_path.size() - 2])
		fwd_exit = (exit_pos - p_prev).normalized()
	
	var entrance_portal: StaticBody3D = _create_tunnel_portal_mesh("EntranceCavePortal", start_pos, fwd_start)
	var exit_portal: StaticBody3D = _create_tunnel_portal_mesh("ExtractionTunnelPortal", exit_pos, -fwd_exit)
	
	if _rails_container:
		_rails_container.add_child(entrance_portal)
		_rails_container.add_child(exit_portal)
	else:
		add_child(entrance_portal)
		add_child(exit_portal)

func _create_tunnel_portal_mesh(p_name: String, pos: Vector3, forward_dir: Vector3 = Vector3.FORWARD) -> StaticBody3D:
	var portal: StaticBody3D = StaticBody3D.new()
	portal.name = p_name
	portal.position = pos
	
	if forward_dir.length_squared() > 0.01:
		var rot_y: float = atan2(forward_dir.x, forward_dir.z)
		portal.rotation = Vector3(0, rot_y, 0)
	
	portal.collision_layer = 1
	portal.collision_mask = 7
	
	# Heavy Arch Stone Frame (11m wide, 9m high, 6.5m deep) to embed seamlessly into 16m cliff faces
	var arch_mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(11.0, 9.0, 6.5)
	arch_mesh.mesh = box
	arch_mesh.position.y = 4.5
	var rock_mat: StandardMaterial3D = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.16, 0.18, 0.20, 1.0)
	rock_mat.roughness = 0.95
	arch_mesh.material_override = rock_mat
	portal.add_child(arch_mesh)
	
	# Cavern Mouth Inset (Pitch Black Interior Cavity)
	var cavern_mouth: MeshInstance3D = MeshInstance3D.new()
	var mouth_box: BoxMesh = BoxMesh.new()
	mouth_box.size = Vector3(6.0, 6.0, 1.2)
	cavern_mouth.mesh = mouth_box
	cavern_mouth.position = Vector3(0, 3.2, 3.26)
	var black_mat: StandardMaterial3D = StandardMaterial3D.new()
	black_mat.albedo_color = Color(0.01, 0.01, 0.02, 1.0)
	black_mat.roughness = 1.0
	cavern_mouth.material_override = black_mat
	portal.add_child(cavern_mouth)
	
	# Red Industrial Warning Beacons on Arch Corners
	for light_x: float in [-3.5, 3.5]:
		var light_mesh: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.22
		cyl.height = 0.45
		light_mesh.mesh = cyl
		light_mesh.position = Vector3(light_x, 6.2, 3.3)
		var warn_mat: StandardMaterial3D = StandardMaterial3D.new()
		warn_mat.albedo_color = Color(1.0, 0.25, 0.05, 1.0)
		warn_mat.emission_enabled = true
		warn_mat.emission = Color(1.0, 0.2, 0.0, 1.0)
		warn_mat.emission_energy_multiplier = 4.5
		light_mesh.material_override = warn_mat
		portal.add_child(light_mesh)
	
	# Solid Wall Collider
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(11.0, 9.0, 6.5)
	col.shape = shape
	col.position.y = 4.5
	portal.add_child(col)
	
	return portal
