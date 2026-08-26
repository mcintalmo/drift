class_name HexWorldTile
extends Node3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")
const SectorBiomeDataClass = preload("res://scripts/resources/sector_biome_data.gd")

@export var axial_coord: Vector2i = Vector2i.ZERO
@export var surface_type: StringName = &"pack"
@export var biome_data: Resource
@export var tile_outer_radius_m: float = 6.0
@export var base_elevation_m: float = 0.0
@export var is_hot_spring: bool = false
@export var is_glacial_chasm: bool = false
@export var is_jump_ramp: bool = false
@export var jump_ramp_direction: Vector2 = Vector2.ZERO
@export var is_boundary_wall: bool = false
@export var is_boundary_void: bool = false
@export var distance_to_rail_m: float = 999.0
@export var is_railroad_active: bool = false

var _static_body: StaticBody3D
var _mesh_instance: MeshInstance3D
var _spawned_props: Array[Node3D] = []
var _cached_corner_heights: Array[float] = []

const SQRT_3: float = 1.7320508

func _ready() -> void:
	if not _static_body:
		_build_tile_geometry([])

## Initializes the hex tile with boundary walls, void drop-offs, rail subgrade leveling, rolling terrain, and hot springs
func initialize_tile(
	coord: Vector2i,
	biome: Resource,
	seed_val: int,
	hot_spring_flag: bool = false,
	jump_ramp_flag: bool = false,
	ramp_dir: Vector2 = Vector2.ZERO,
	boundary_wall_flag: bool = false,
	boundary_void_flag: bool = false,
	dist_to_rail_m: float = 999.0,
	rail_target_y: float = 0.0,
	is_rail_active: bool = true
) -> void:
	axial_coord = coord
	biome_data = biome if biome else SectorBiomeDataClass.new()
	tile_outer_radius_m = biome_data.get("hex_cell_outer_radius_m") if "hex_cell_outer_radius_m" in biome_data else 6.0
	is_hot_spring = hot_spring_flag
	is_jump_ramp = jump_ramp_flag
	jump_ramp_direction = ramp_dir
	is_boundary_wall = boundary_wall_flag
	is_boundary_void = boundary_void_flag
	distance_to_rail_m = dist_to_rail_m
	is_railroad_active = is_rail_active
	
	# 3D world center coordinates in X-Z plane
	var world_x: float = tile_outer_radius_m * SQRT_3 * (float(coord.x) + float(coord.y) * 0.5)
	var world_z: float = tile_outer_radius_m * 1.5 * float(coord.y)
	
	# 1. Base rolling noise & grand hill swell (continuous in world space across all surface tiles)
	var base_noise: FastNoiseLite = FastNoiseLite.new()
	base_noise.seed = seed_val
	var freq: float = biome_data.get("elevation_frequency") if "elevation_frequency" in biome_data else 0.022
	var amp: float = biome_data.get("elevation_amplitude") if "elevation_amplitude" in biome_data else 1.85
	base_noise.frequency = freq
	
	var hill_noise: FastNoiseLite = FastNoiseLite.new()
	hill_noise.seed = seed_val + 7771
	hill_noise.frequency = 0.009
	var hill_amp: float = biome_data.get("plateau_tier_height_m") if "plateau_tier_height_m" in biome_data else 3.8
	
	# Calculate continuous surface elevation (smooth rolling terrain + grand hill swells)
	var rolling_h: float = base_noise.get_noise_2d(world_x, world_z) * amp
	var hill_h: float = maxf(0.0, hill_noise.get_noise_2d(world_x, world_z) * hill_amp * 1.8)
	base_elevation_m = rolling_h + hill_h
	
	# 2. Railroad Civil Engineering Subgrade Embankment Leveling
	if dist_to_rail_m < 5.5 and not is_boundary_wall and not is_boundary_void:
		var emb_weight: float = clampf(1.0 - (dist_to_rail_m / 5.5), 0.0, 1.0)
		var emb_raise: float = biome_data.get("rail_embankment_raise_m") if "rail_embankment_raise_m" in biome_data else 0.35
		if is_rail_active:
			# Active Line: Pristine, smoothly leveled and raised compacted subgrade shelf
			base_elevation_m = lerpf(base_elevation_m, rail_target_y + emb_raise, emb_weight * 0.85)
		else:
			# Inactive Line: Weathered embankment with snowdrift erosion humps
			var erosion_drift: float = base_noise.get_noise_2d(world_x * 2.2, world_z * 2.2) * 0.35
			base_elevation_m = lerpf(base_elevation_m, rail_target_y + emb_raise + erosion_drift, emb_weight * 0.65)
	
	# 3. Boundary Overrides (Valley Mountain Cliff Walls vs Plateau Void Drop-Offs)
	var chasm_offset_y: float = 0.0
	if is_boundary_wall:
		var wall_h: float = biome_data.get("valley_wall_height_m") if "valley_wall_height_m" in biome_data else 16.0
		base_elevation_m += wall_h
		surface_type = &"scree" # Dark granite rock mountain wall
	elif is_boundary_void:
		chasm_offset_y = -100.0 # Abyssal lethal void drop-off
		surface_type = &"black_ice"
	elif not is_hot_spring and not is_jump_ramp:
		# 4. Glacial Chasm Detection (Discrete sunken crevasse lake)
		var c_thresh: float = biome_data.get("chasm_threshold") if "chasm_threshold" in biome_data else -0.32
		var p_val: float = hill_noise.get_noise_2d(world_x, world_z)
		if p_val < c_thresh:
			is_glacial_chasm = true
			chasm_offset_y = -6.5
			surface_type = &"black_ice"
	
	position = Vector3(world_x, base_elevation_m + chasm_offset_y, world_z)
	
	if is_hot_spring:
		surface_type = &"slush"
	elif not is_boundary_wall and not is_boundary_void and not is_glacial_chasm:
		var surface_roll: float = absf(base_noise.get_noise_2d(world_x + 500.0, world_z + 500.0))
		if biome_data.has_method("sample_surface_type"):
			surface_type = biome_data.sample_surface_type(surface_roll)
		else:
			surface_type = &"pack"
	
	# Corner heights sample continuous world elevation + jump ramp kicker profile
	_cached_corner_heights = _compute_continuous_corner_heights(world_x, world_z, base_noise, amp, hill_noise, hill_amp)
	
	_build_tile_geometry(_cached_corner_heights)
	_spawn_procedural_features(seed_val)

## Evaluates continuous rolling elevation and adds jump ramp kicker lip facing the chasm
func _compute_continuous_corner_heights(
	center_x: float,
	center_z: float,
	base_noise: FastNoiseLite,
	amp: float,
	hill_noise: FastNoiseLite,
	hill_amp: float
) -> Array[float]:
	var corner_heights: Array[float] = []
	
	for i: int in range(6):
		var angle_rad: float = deg_to_rad(60.0 * float(i) + 30.0)
		var corner_world_x: float = center_x + (tile_outer_radius_m * cos(angle_rad))
		var corner_world_z: float = center_z + (tile_outer_radius_m * sin(angle_rad))
		
		# Sample continuous rolling and hill elevation at this exact corner coordinate
		var corner_rolling: float = base_noise.get_noise_2d(corner_world_x, corner_world_z) * amp
		var corner_hill: float = maxf(0.0, hill_noise.get_noise_2d(corner_world_x, corner_world_z) * hill_amp * 1.8)
		var corner_world_elevation: float = corner_rolling + corner_hill
		
		if is_boundary_wall:
			var wall_h: float = biome_data.get("valley_wall_height_m") if "valley_wall_height_m" in biome_data else 16.0
			corner_world_elevation += wall_h
		
		var local_y: float = corner_world_elevation - base_elevation_m
		
		# Jump Ramp: elevate the lip facing the chasm (+1.5m kicker) with seamless approach grade
		if is_jump_ramp and jump_ramp_direction.length_squared() > 0.01:
			var corner_dir_2d: Vector2 = Vector2(cos(angle_rad), sin(angle_rad)).normalized()
			var ramp_dot: float = corner_dir_2d.dot(jump_ramp_direction.normalized())
			if ramp_dot > 0.1:
				local_y += ramp_dot * 1.50
				
		corner_heights.append(local_y)
		
	return corner_heights

func _build_tile_geometry(corner_heights: Array[float]) -> void:
	if _static_body and is_instance_valid(_static_body):
		_static_body.queue_free()
	
	_static_body = StaticBody3D.new()
	_static_body.name = "TileBody"
	_static_body.collision_layer = 1
	_static_body.collision_mask = 6
	_static_body.set_meta(&"surface_type", surface_type)
	if is_boundary_void:
		_static_body.set_meta(&"is_void_killzone", true)
	add_child(_static_body)
	
	# Massive 90.0m side skirts for boundary walls and 36.0m for general tiles guarantee ZERO gaps into deep chasms
	var depth: float = 90.0 if is_boundary_wall else 36.0
	var hex_mesh: ArrayMesh = _generate_model_c_mesh(tile_outer_radius_m, depth, corner_heights)
	
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "TileMesh"
	_mesh_instance.mesh = hex_mesh
	_mesh_instance.material_override = _create_surface_material(surface_type)
	_static_body.add_child(_mesh_instance)
	
	var shape: ConvexPolygonShape3D = hex_mesh.create_convex_shape()
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "TileCollision"
	col.shape = shape
	_static_body.add_child(col)

func _generate_model_c_mesh(radius: float, depth: float, corner_heights: Array[float]) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var top_vertices: Array[Vector3] = []
	var bottom_vertices: Array[Vector3] = []
	
	for i: int in range(6):
		var angle_rad: float = deg_to_rad(60.0 * float(i) + 30.0)
		var vx: float = radius * cos(angle_rad)
		var vz: float = radius * sin(angle_rad)
		var vy: float = corner_heights[i] if i < corner_heights.size() else 0.0
		top_vertices.append(Vector3(vx, vy, vz))
		bottom_vertices.append(Vector3(vx, -depth, vz))
	
	# Center Vertex: shallow basin if hot spring (-0.9m), slight rise if jump ramp (+0.4m), level otherwise
	var center_y: float = 0.0
	if is_hot_spring:
		center_y = -0.9
	elif is_jump_ramp:
		center_y = 0.40
		
	var top_center: Vector3 = Vector3(0.0, center_y, 0.0)
	var bottom_center: Vector3 = Vector3(0.0, -depth, 0.0)
	
	# Top Facets (6 triangles radiating from center)
	for i: int in range(6):
		var next_i: int = (i + 1) % 6
		var v1: Vector3 = top_center
		var v2: Vector3 = top_vertices[i]
		var v3: Vector3 = top_vertices[next_i]
		var face_normal: Vector3 = (v3 - v1).cross(v2 - v1).normalized()
		
		st.set_normal(face_normal)
		st.add_vertex(v1)
		st.set_normal(face_normal)
		st.add_vertex(v2)
		st.set_normal(face_normal)
		st.add_vertex(v3)
	
	# Side Skirts (100% straight vertical 90-degree cliff walls)
	for i: int in range(6):
		var next_i: int = (i + 1) % 6
		var t1: Vector3 = top_vertices[i]
		var t2: Vector3 = top_vertices[next_i]
		var b1: Vector3 = bottom_vertices[i]
		var b2: Vector3 = bottom_vertices[next_i]
		
		var side_normal: Vector3 = Vector3(t1.x + t2.x, 0.0, t1.z + t2.z).normalized()
		
		st.set_normal(side_normal)
		st.add_vertex(t1)
		st.set_normal(side_normal)
		st.add_vertex(b1)
		st.set_normal(side_normal)
		st.add_vertex(t2)
		
		st.set_normal(side_normal)
		st.add_vertex(t2)
		st.set_normal(side_normal)
		st.add_vertex(b1)
		st.set_normal(side_normal)
		st.add_vertex(b2)
	
	return st.commit()

func _create_surface_material(surface: StringName) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	if is_boundary_wall:
		mat.albedo_color = Color(0.24, 0.22, 0.20, 1.0) # Jagged dark mountain granite
		mat.roughness = 0.95
		return mat
	elif is_hot_spring:
		mat.albedo_color = Color(0.72, 0.58, 0.35, 1.0) # Mineral sulfur earth rim
		mat.roughness = 0.95
		return mat
	elif is_glacial_chasm or is_boundary_void:
		mat.albedo_color = Color(0.12, 0.45, 0.70, 0.92) # Glassy turquoise frozen lake ice
		mat.roughness = 0.04
		mat.metallic = 0.65
		return mat
		
	match surface:
		&"black_ice", &"ice":
			mat.albedo_color = Color(0.20, 0.55, 0.80, 0.95)
			mat.roughness = 0.04
			mat.metallic = 0.6
		&"firn":
			mat.albedo_color = Color(0.75, 0.88, 0.98, 1.0)
			mat.roughness = 0.25
		&"powder":
			mat.albedo_color = Color(0.96, 0.98, 1.0, 1.0)
			mat.roughness = 0.95
		&"slush":
			mat.albedo_color = Color(0.65, 0.75, 0.80, 0.9)
			mat.roughness = 0.15
		&"snirt":
			mat.albedo_color = Color(0.48, 0.45, 0.42, 1.0)
			mat.roughness = 0.85
		&"scree":
			mat.albedo_color = Color(0.32, 0.30, 0.28, 1.0)
			mat.roughness = 0.9
		&"crust":
			mat.albedo_color = Color(0.85, 0.92, 0.96, 1.0)
			mat.roughness = 0.4
		_: # pack
			mat.albedo_color = Color(0.88, 0.92, 0.96, 1.0)
			mat.roughness = 0.65
	return mat

func _spawn_procedural_features(seed_val: int) -> void:
	for p: Node3D in _spawned_props:
		if is_instance_valid(p):
			p.queue_free()
	_spawned_props.clear()
	
	if is_boundary_wall or is_boundary_void:
		return
	
	if is_hot_spring:
		_setup_hot_spring_basin()
		return
	
	if is_glacial_chasm or is_jump_ramp or not biome_data:
		return
	
	# On active train lines, keep a strict 6.0m clearance zone completely clear of obstacles, debris, and crates
	if is_railroad_active and distance_to_rail_m < 6.0:
		return
	
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val + (axial_coord.x * 73856093) ^ (axial_coord.y * 19349663)
	
	var wreck_chance: float = biome_data.get("overturned_sled_wreck_chance") if "overturned_sled_wreck_chance" in biome_data else 0.03
	var corpo_chance: float = biome_data.get("abandoned_corpo_facility_chance") if "abandoned_corpo_facility_chance" in biome_data else 0.02
	var boulder_chance: float = biome_data.get("boulder_density") if "boulder_density" in biome_data else 0.08
	var pine_chance: float = biome_data.get("pine_tree_density") if "pine_tree_density" in biome_data else 0.14
	var crate_chance: float = biome_data.get("ground_crate_cache_chance") if "ground_crate_cache_chance" in biome_data else 0.08
	
	# 1. Overturned Sled Wreck
	if rng.randf() < wreck_chance:
		_spawn_overturned_sled_wreck(rng)
		return
	
	# 2. Abandoned Corpo Facility
	if rng.randf() < corpo_chance:
		_spawn_abandoned_corpo_outpost(rng)
		return
	
	# 3. Obstacles (Glacial Boulders & Petrified Pines)
	if rng.randf() < boulder_chance:
		_spawn_glacial_boulder(rng)
	if rng.randf() < pine_chance:
		_spawn_petrified_pine(rng)
	
	# 4. Scatter Ground Crates
	if rng.randf() < crate_chance:
		_spawn_loot_crate(rng)

func _setup_hot_spring_basin() -> void:
	add_to_group(&"thermal_vents")
	
	var basin_node: Node3D = Node3D.new()
	basin_node.name = "HotSpringBasin"
	
	var min_rim_y: float = 0.0
	if not _cached_corner_heights.is_empty():
		min_rim_y = _cached_corner_heights[0]
		for h: float in _cached_corner_heights:
			min_rim_y = minf(min_rim_y, h)
	
	var water_y: float = min_rim_y - 0.22
	
	# Steaming Turquoise Water Surface Plane
	var water_mesh: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = tile_outer_radius_m * 0.70
	cyl.bottom_radius = tile_outer_radius_m * 0.70
	cyl.height = 0.08
	water_mesh.mesh = cyl
	water_mesh.position.y = water_y
	
	var water_mat: StandardMaterial3D = StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.10, 0.85, 0.80, 0.90)
	water_mat.roughness = 0.08
	water_mat.metallic = 0.15
	water_mesh.material_override = water_mat
	basin_node.add_child(water_mesh)
	
	# Glowing Warm Amber-Orange Light
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.05, 1.0)
	light.light_energy = 4.5
	light.omni_range = tile_outer_radius_m * 2.2
	light.position.y = water_y + 0.8
	basin_node.add_child(light)
	
	# Dense Steam Particles
	var steam: CPUParticles3D = CPUParticles3D.new()
	steam.amount = 32
	steam.lifetime = 2.8
	var p_mesh: SphereMesh = SphereMesh.new()
	p_mesh.radius = 0.4
	p_mesh.height = 0.8
	var steam_mat: StandardMaterial3D = StandardMaterial3D.new()
	steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam_mat.albedo_color = Color(0.95, 0.98, 1.0, 0.38)
	p_mesh.material = steam_mat
	steam.mesh = p_mesh
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	steam.emission_sphere_radius = tile_outer_radius_m * 0.50
	steam.direction = Vector3(0, 1, 0)
	steam.spread = 22.0
	steam.gravity = Vector3(0, 1.4, 0)
	steam.initial_velocity_min = 1.8
	steam.initial_velocity_max = 3.8
	steam.scale_amount_min = 0.7
	steam.scale_amount_max = 2.4
	steam.position.y = water_y + 0.05
	basin_node.add_child(steam)
	
	add_child(basin_node)
	_spawned_props.append(basin_node)

## Thermal vent temperature contribution query
func get_temperature_contribution(pos: Vector3) -> float:
	if not is_hot_spring:
		return 0.0
	var origin: Vector3 = global_position if is_inside_tree() else position
	var dist: float = origin.distance_to(pos)
	var max_r: float = tile_outer_radius_m * 1.5
	if dist <= max_r:
		var falloff: float = 1.0 - (dist / max_r)
		return 45.0 * falloff
	return 0.0

func _spawn_overturned_sled_wreck(rng: RandomNumberGenerator) -> void:
	var wreck_node: Node3D = Node3D.new()
	wreck_node.name = "SledWreckSite"
	wreck_node.position = Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
	
	var hull_mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.2, 0.6, 2.4)
	hull_mesh.mesh = box
	hull_mesh.rotation_degrees = Vector3(0, rng.randf_range(0, 360), 85)
	wreck_node.add_child(hull_mesh)
	
	var crate_scene: PackedScene = load("res://scenes/containers/GroundCrate.tscn")
	if crate_scene:
		var crate1: Node3D = crate_scene.instantiate() as Node3D
		crate1.position = Vector3(1.5, 0, 0.6)
		wreck_node.add_child(crate1)
	
	add_child(wreck_node)
	_spawned_props.append(wreck_node)

func _spawn_abandoned_corpo_outpost(rng: RandomNumberGenerator) -> void:
	var outpost: Node3D = Node3D.new()
	outpost.name = "CorpoOutpost"
	outpost.position = Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
	
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 6
	var wall_mesh: MeshInstance3D = MeshInstance3D.new()
	var wall_box: BoxMesh = BoxMesh.new()
	wall_box.size = Vector3(3.5, 2.5, 0.6)
	wall_mesh.mesh = wall_box
	wall.add_child(wall_mesh)
	
	var wall_col: CollisionShape3D = CollisionShape3D.new()
	var col_shape: BoxShape3D = BoxShape3D.new()
	col_shape.size = Vector3(3.5, 2.5, 0.6)
	wall_col.shape = col_shape
	wall.add_child(wall_col)
	outpost.add_child(wall)
	
	var crate_scene: PackedScene = load("res://scenes/containers/GroundCrate.tscn")
	if crate_scene:
		var vault_crate: Node3D = crate_scene.instantiate() as Node3D
		vault_crate.position = Vector3(0, 0, 1.2)
		vault_crate.set("crate_variant", 2)
		outpost.add_child(vault_crate)
	
	add_child(outpost)
	_spawned_props.append(outpost)

func _spawn_glacial_boulder(rng: RandomNumberGenerator) -> void:
	var boulder: StaticBody3D = StaticBody3D.new()
	boulder.name = "GlacialBoulder"
	var bx: float = rng.randf_range(-2.2, 2.2)
	var bz: float = rng.randf_range(-2.2, 2.2)
	boulder.position = Vector3(bx, 0, bz)
	boulder.collision_layer = 1
	boulder.collision_mask = 6
	
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	var rad: float = rng.randf_range(0.8, 1.6)
	sphere.radius = rad
	sphere.height = rad * 1.8
	mesh_inst.mesh = sphere
	mesh_inst.position.y = rad * 0.6
	boulder.add_child(mesh_inst)
	
	var col: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = rad
	col.shape = sphere_shape
	col.position.y = rad * 0.6
	boulder.add_child(col)
	
	add_child(boulder)
	boulder.add_to_group(&"boulders")
	_spawned_props.append(boulder)

func _spawn_petrified_pine(rng: RandomNumberGenerator) -> void:
	var tree: StaticBody3D = StaticBody3D.new()
	tree.name = "PetrifiedPine"
	tree.add_to_group(&"trees")
	var tx: float = rng.randf_range(-2.5, 2.5)
	var tz: float = rng.randf_range(-2.5, 2.5)
	tree.position = Vector3(tx, 0, tz)
	tree.collision_layer = 1
	tree.collision_mask = 6
	
	var trunk: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.40
	cyl.height = 4.8
	trunk.mesh = cyl
	trunk.position.y = 1.6
	tree.add_child(trunk)
	
	var collar: MeshInstance3D = MeshInstance3D.new()
	var collar_cyl: CylinderMesh = CylinderMesh.new()
	collar_cyl.top_radius = 0.50
	collar_cyl.bottom_radius = 0.75
	collar_cyl.height = 0.4
	collar.mesh = collar_cyl
	collar.position.y = 0.1
	var snow_mat: StandardMaterial3D = StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.92, 0.95, 0.98, 1.0)
	collar.material_override = snow_mat
	tree.add_child(collar)
	
	var col: CollisionShape3D = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = 0.40
	cyl_shape.height = 4.8
	col.shape = cyl_shape
	col.position.y = 1.6
	tree.add_child(col)
	
	add_child(tree)
	_spawned_props.append(tree)

func _spawn_loot_crate(rng: RandomNumberGenerator) -> void:
	var crate_scene: PackedScene = load("res://scenes/containers/GroundCrate.tscn")
	if crate_scene:
		var crate: Node3D = crate_scene.instantiate() as Node3D
		crate.position = Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-2.0, 2.0))
		add_child(crate)
		_spawned_props.append(crate)
