class_name HexSectorManager
extends Node3D

const HexWorldTileClass = preload("res://scripts/world/hex_world_tile.gd")
const SectorBiomeDataClass = preload("res://scripts/resources/sector_biome_data.gd")

signal tile_spawned(coord: Vector2i, tile: Node3D)
signal tile_despawned(coord: Vector2i)
signal sector_generated(active_tile_count: int)

@export_group("Configuration")
@export var active_target: Node3D
@export var biome_data: Resource
@export var world_seed: int = 1337
@export_range(1, 6, 1) var render_radius_rings: int = 4 # 4 rings = 61 hex tiles, 5 rings = 91 tiles
@export var is_dynamic_streaming_enabled: bool = true

# Active Tile Registry: Vector2i(q, r) -> Node3D
var _active_tiles: Dictionary = {}
var _hot_spring_registry: Dictionary = {} # Vector2i -> bool
var _current_center_coord: Vector2i = Vector2i(9999, 9999)
var _tiles_container: Node3D

const SQRT_3: float = 1.7320508

func _ready() -> void:
	if not _tiles_container:
		_tiles_container = Node3D.new()
		_tiles_container.name = "TilesContainer"
		add_child(_tiles_container)
	
	if not biome_data:
		biome_data = load("res://resources/biomes/temperate_permafrost.tres")
		if not biome_data:
			biome_data = SectorBiomeDataClass.new()
	
	if not active_target:
		var pilots: Array[Node] = get_tree().get_nodes_in_group(&"player_pilot")
		if not pilots.is_empty():
			active_target = pilots[0] as Node3D
		else:
			var sleds: Array[Node] = get_tree().get_nodes_in_group(&"player_sled")
			if not sleds.is_empty():
				active_target = sleds[0] as Node3D
	
	generate_initial_sector()

func _physics_process(_delta: float) -> void:
	if not is_dynamic_streaming_enabled or not active_target or not is_instance_valid(active_target):
		return
	
	var target_pos: Vector3 = active_target.global_position if active_target.is_inside_tree() else active_target.position
	var target_coord: Vector2i = world_pos_to_axial_coord(target_pos)
	
	if target_coord != _current_center_coord:
		_current_center_coord = target_coord
		_update_streaming_rings(target_coord)

## Generates concentric hex tiles around the center
func generate_initial_sector(center_coord: Vector2i = Vector2i.ZERO) -> void:
	if not _tiles_container:
		_tiles_container = Node3D.new()
		_tiles_container.name = "TilesContainer"
		add_child(_tiles_container)
		
	_current_center_coord = center_coord
	_update_streaming_rings(center_coord)
	sector_generated.emit(_active_tiles.size())

func _update_streaming_rings(center_coord: Vector2i) -> void:
	var needed_coords: Array[Vector2i] = get_hex_ring_cluster(center_coord, render_radius_rings)
	
	# 1. Spawn missing tiles
	for coord: Vector2i in needed_coords:
		if not _active_tiles.has(coord):
			_spawn_tile_at(coord)
	
	# 2. Despawn distant tiles
	var to_remove: Array[Vector2i] = []
	for coord: Vector2i in _active_tiles:
		if not needed_coords.has(coord):
			to_remove.append(coord)
	
	for coord: Vector2i in to_remove:
		_despawn_tile_at(coord)

func _spawn_tile_at(coord: Vector2i) -> void:
	var is_hot_spring: bool = _evaluate_hot_spring_spawn(coord)
	
	var tile: Node3D = HexWorldTileClass.new()
	tile.name = "Tile_%d_%d" % [coord.x, coord.y]
	if _tiles_container:
		_tiles_container.add_child(tile)
	else:
		add_child(tile)
		
	if tile.has_method("initialize_tile"):
		tile.initialize_tile(coord, biome_data, world_seed, is_hot_spring)
	_active_tiles[coord] = tile
	tile_spawned.emit(coord, tile)

func _evaluate_hot_spring_spawn(coord: Vector2i) -> bool:
	if _hot_spring_registry.has(coord):
		return _hot_spring_registry[coord]
	
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed + (coord.x * 524287) ^ (coord.y * 131071)
	
	var base_chance: float = biome_data.get("hot_spring_basin_chance") if "hot_spring_basin_chance" in biome_data else 0.07
	var cluster_boost: float = biome_data.get("hot_spring_cluster_boost") if "hot_spring_cluster_boost" in biome_data else 0.65
	
	# Check if any neighbor is already a hot spring to create natural oasis clusters
	var has_hot_spring_neighbor: bool = false
	var neighbors: Array[Vector2i] = [
		Vector2i(coord.x + 1, coord.y), Vector2i(coord.x + 1, coord.y - 1),
		Vector2i(coord.x, coord.y - 1), Vector2i(coord.x - 1, coord.y),
		Vector2i(coord.x - 1, coord.y + 1), Vector2i(coord.x, coord.y + 1)
	]
	
	for n: Vector2i in neighbors:
		if _hot_spring_registry.get(n, false) == true:
			has_hot_spring_neighbor = true
			break
	
	var effective_chance: float = cluster_boost if has_hot_spring_neighbor else base_chance
	var result: bool = rng.randf() < effective_chance
	_hot_spring_registry[coord] = result
	return result

func _despawn_tile_at(coord: Vector2i) -> void:
	if _active_tiles.has(coord):
		var tile: Node3D = _active_tiles[coord]
		if is_instance_valid(tile):
			tile.queue_free()
		_active_tiles.erase(coord)
		tile_despawned.emit(coord)

## Returns all axial coordinates within N concentric rings of a center coord
func get_hex_ring_cluster(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	for q: int in range(-radius, radius + 1):
		var r1: int = max(-radius, -q - radius)
		var r2: int = min(radius, -q + radius)
		for r: int in range(r1, r2 + 1):
			results.append(center + Vector2i(q, r))
	return results

## Converts world 3D position to the nearest axial hex tile coordinate (q, r)
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
