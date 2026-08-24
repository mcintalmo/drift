class_name HexWorldTile
extends Node3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")
const SectorBiomeDataClass = preload("res://scripts/resources/sector_biome_data.gd")

@export var axial_coord: Vector2i = Vector2i.ZERO
@export var surface_type: StringName = &"pack"
@export var biome_data: Resource
@export var tile_outer_radius_m: float = 18.0
@export var base_elevation_m: float = 0.0

var _static_body: StaticBody3D
var _mesh_instance: MeshInstance3D
var _spawned_props: Array[Node3D] = []

const SQRT_3: float = 1.7320508

func _ready() -> void:
	if not _static_body:
		_build_tile_geometry()

## Generates and builds the hex tile mesh, collision, and procedural props
func initialize_tile(coord: Vector2i, biome: Resource, seed_val: int) -> void:
	axial_coord = coord
	biome_data = biome if biome else SectorBiomeDataClass.new()
	tile_outer_radius_m = biome_data.get("hex_cell_outer_radius_m") if "hex_cell_outer_radius_m" in biome_data else 18.0
	
	# Compute 3D world position from axial coordinates
	var world_x: float = tile_outer_radius_m * SQRT_3 * (float(coord.x) + float(coord.y) * 0.5)
	var world_z: float = tile_outer_radius_m * 1.5 * float(coord.y)
	
	# Elevation noise
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	var freq: float = biome_data.get("elevation_frequency") if "elevation_frequency" in biome_data else 0.025
	var amp: float = biome_data.get("elevation_amplitude") if "elevation_amplitude" in biome_data else 3.5
	noise.frequency = freq
	base_elevation_m = noise.get_noise_2d(world_x, world_z) * amp
	
	position = Vector3(world_x, base_elevation_m, world_z)
	
	# Determine surface type from deterministic roll
	var surface_roll: float = absf(noise.get_noise_2d(world_x + 500.0, world_z + 500.0))
	if biome_data.has_method("sample_surface_type"):
		surface_type = biome_data.sample_surface_type(surface_roll)
	else:
		surface_type = &"pack"
	
	_build_tile_geometry()
	_spawn_procedural_features(seed_val)

func _build_tile_geometry() -> void:
	# Clean up previous geometry
	if _static_body and is_instance_valid(_static_body):
		_static_body.queue_free()
	
	_static_body = StaticBody3D.new()
	_static_body.name = "TileBody"
	_static_body.collision_layer = 1
	_static_body.collision_mask = 6
	_static_body.set_meta(&"surface_type", surface_type)
	add_child(_static_body)
	
	# Generate 3D Hexagon Prism Mesh
	var hex_mesh: ArrayMesh = _generate_hexagon_prism_mesh(tile_outer_radius_m, 2.0)
	
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "TileMesh"
	_mesh_instance.mesh = hex_mesh
	_mesh_instance.material_override = _create_surface_material(surface_type)
	_static_body.add_child(_mesh_instance)
	
	# Create Convex Collision Shape
	var shape: ConvexPolygonShape3D = hex_mesh.create_convex_shape()
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "TileCollision"
	col.shape = shape
	_static_body.add_child(col)

func _create_surface_material(surface: StringName) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	match surface:
		&"black_ice", &"ice":
			mat.albedo_color = Color(0.35, 0.65, 0.85, 0.95)
			mat.roughness = 0.05
			mat.metallic = 0.4
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

func _generate_hexagon_prism_mesh(radius: float, depth: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var top_vertices: Array[Vector3] = []
	var bottom_vertices: Array[Vector3] = []
	
	for i: int in range(6):
		var angle_rad: float = deg_to_rad(60.0 * float(i) + 30.0)
		var vx: float = radius * cos(angle_rad)
		var vz: float = radius * sin(angle_rad)
		top_vertices.append(Vector3(vx, 0.0, vz))
		bottom_vertices.append(Vector3(vx, -depth, vz))
	
	var top_center: Vector3 = Vector3(0.0, 0.0, 0.0)
	var bottom_center: Vector3 = Vector3(0.0, -depth, 0.0)
	
	# Top Hexagon Fan (Upward Normal)
	for i: int in range(6):
		var next_i: int = (i + 1) % 6
		st.set_normal(Vector3.UP)
		st.add_vertex(top_center)
		st.set_normal(Vector3.UP)
		st.add_vertex(top_vertices[i])
		st.set_normal(Vector3.UP)
		st.add_vertex(top_vertices[next_i])
	
	# Side Facets
	for i: int in range(6):
		var next_i: int = (i + 1) % 6
		var t1: Vector3 = top_vertices[i]
		var t2: Vector3 = top_vertices[next_i]
		var b1: Vector3 = bottom_vertices[i]
		var b2: Vector3 = bottom_vertices[next_i]
		
		var side_normal: Vector3 = (t1 + t2).normalized()
		side_normal.y = 0.0
		side_normal = side_normal.normalized()
		
		# Quad Triangle 1
		st.set_normal(side_normal)
		st.add_vertex(t1)
		st.set_normal(side_normal)
		st.add_vertex(b1)
		st.set_normal(side_normal)
		st.add_vertex(t2)
		
		# Quad Triangle 2
		st.set_normal(side_normal)
		st.add_vertex(t2)
		st.set_normal(side_normal)
		st.add_vertex(b1)
		st.set_normal(side_normal)
		st.add_vertex(b2)
	
	return st.commit()

func _spawn_procedural_features(seed_val: int) -> void:
	for p: Node3D in _spawned_props:
		if is_instance_valid(p):
			p.queue_free()
	_spawned_props.clear()
	
	if not biome_data:
		return
	
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val + (axial_coord.x * 73856093) ^ (axial_coord.y * 19349663)
	
	var vent_chance: float = biome_data.get("geothermal_vent_chance") if "geothermal_vent_chance" in biome_data else 0.08
	var wreck_chance: float = biome_data.get("overturned_sled_wreck_chance") if "overturned_sled_wreck_chance" in biome_data else 0.08
	var corpo_chance: float = biome_data.get("abandoned_corpo_facility_chance") if "abandoned_corpo_facility_chance" in biome_data else 0.05
	var rail_chance: float = biome_data.get("railroad_corridor_chance") if "railroad_corridor_chance" in biome_data else 0.12
	var boulder_chance: float = biome_data.get("boulder_density") if "boulder_density" in biome_data else 0.2
	var pine_chance: float = biome_data.get("pine_tree_density") if "pine_tree_density" in biome_data else 0.25
	var crate_chance: float = biome_data.get("ground_crate_cache_chance") if "ground_crate_cache_chance" in biome_data else 0.15
	
	# 1. Geothermal Vent POI
	if rng.randf() < vent_chance:
		var vent_scene: PackedScene = load("res://scenes/world/ThermalVent.tscn")
		if vent_scene:
			var vent: Node3D = vent_scene.instantiate() as Node3D
			vent.position = Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
			add_child(vent)
			_spawned_props.append(vent)
			return # Exclusive POI for this tile
	
	# 2. Overturned Sled Wreck Scavenging Site
	if rng.randf() < wreck_chance:
		_spawn_overturned_sled_wreck(rng)
		return
	
	# 3. Abandoned Corpo Facility
	if rng.randf() < corpo_chance:
		_spawn_abandoned_corpo_outpost(rng)
		return
	
	# 4. Railroad Track Corridor
	if rng.randf() < rail_chance:
		_spawn_railroad_segment(rng)
	
	# 5. Natural Obstacles (Boulders & Petrified Pines)
	if rng.randf() < boulder_chance:
		_spawn_glacial_boulder(rng)
	if rng.randf() < pine_chance:
		_spawn_petrified_pine(rng)
	
	# 6. Scatter Ground Crates
	if rng.randf() < crate_chance:
		_spawn_loot_crate(rng)

func _spawn_overturned_sled_wreck(rng: RandomNumberGenerator) -> void:
	var wreck_node: Node3D = Node3D.new()
	wreck_node.name = "SledWreckSite"
	wreck_node.position = Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
	
	# Fallen Sled Hull (Tilted on side)
	var hull_mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.6, 0.8, 3.2)
	hull_mesh.mesh = box
	hull_mesh.rotation_degrees = Vector3(0, rng.randf_range(0, 360), 85) # Tilted on runner
	wreck_node.add_child(hull_mesh)
	
	# Scattered Crate 1
	var crate_scene: PackedScene = load("res://scenes/containers/GroundCrate.tscn")
	if crate_scene:
		var crate1: Node3D = crate_scene.instantiate() as Node3D
		crate1.position = Vector3(2.2, 0, 1.0)
		wreck_node.add_child(crate1)
		
		var crate2: Node3D = crate_scene.instantiate() as Node3D
		crate2.position = Vector3(-2.0, 0, -1.5)
		crate2.set("crate_variant", 1)
		wreck_node.add_child(crate2)
	
	add_child(wreck_node)
	_spawned_props.append(wreck_node)

func _spawn_abandoned_corpo_outpost(rng: RandomNumberGenerator) -> void:
	var outpost: Node3D = Node3D.new()
	outpost.name = "CorpoOutpost"
	outpost.position = Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
	
	# Rusted Steel Wall Barrier
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 6
	var wall_mesh: MeshInstance3D = MeshInstance3D.new()
	var wall_box: BoxMesh = BoxMesh.new()
	wall_box.size = Vector3(6.0, 3.5, 0.8)
	wall_mesh.mesh = wall_box
	wall.add_child(wall_mesh)
	
	var wall_col: CollisionShape3D = CollisionShape3D.new()
	var col_shape: BoxShape3D = BoxShape3D.new()
	col_shape.size = Vector3(6.0, 3.5, 0.8)
	wall_col.shape = col_shape
	wall.add_child(wall_col)
	outpost.add_child(wall)
	
	# High-tier Vault Crate
	var crate_scene: PackedScene = load("res://scenes/containers/GroundCrate.tscn")
	if crate_scene:
		var vault_crate: Node3D = crate_scene.instantiate() as Node3D
		vault_crate.position = Vector3(0, 0, 1.8)
		vault_crate.set("crate_variant", 2)
		outpost.add_child(vault_crate)
	
	# Sentry Drone Patrol
	var drone_scene: PackedScene = load("res://scenes/enemies/CorpoDrone.tscn")
	if drone_scene:
		var drone: Node3D = drone_scene.instantiate() as Node3D
		drone.position = Vector3(0, 4.0, 0)
		outpost.add_child(drone)
	
	add_child(outpost)
	_spawned_props.append(outpost)

func _spawn_railroad_segment(rng: RandomNumberGenerator) -> void:
	var rail_node: Node3D = Node3D.new()
	rail_node.name = "RailCorridor"
	rail_node.position = Vector3(0, 0.05, 0)
	rail_node.rotation_degrees.y = 30.0 * float(rng.randi_range(0, 5))
	
	# Tie Bed
	var tie_bed: MeshInstance3D = MeshInstance3D.new()
	var tie_box: BoxMesh = BoxMesh.new()
	tie_box.size = Vector3(3.8, 0.08, tile_outer_radius_m * 2.0)
	tie_bed.mesh = tie_box
	rail_node.add_child(tie_bed)
	
	# Left & Right Steel Rails
	for x_off: float in [-1.2, 1.2]:
		var rail: MeshInstance3D = MeshInstance3D.new()
		var rail_box: BoxMesh = BoxMesh.new()
		rail_box.size = Vector3(0.15, 0.2, tile_outer_radius_m * 2.0)
		rail.mesh = rail_box
		rail.position = Vector3(x_off, 0.1, 0)
		rail_node.add_child(rail)
	
	add_child(rail_node)
	_spawned_props.append(rail_node)

func _spawn_glacial_boulder(rng: RandomNumberGenerator) -> void:
	var boulder: StaticBody3D = StaticBody3D.new()
	boulder.name = "GlacialBoulder"
	boulder.position = Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
	boulder.collision_layer = 1
	boulder.collision_mask = 6
	
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	var rad: float = rng.randf_range(1.2, 2.5)
	sphere.radius = rad
	sphere.height = rad * 1.8
	mesh_inst.mesh = sphere
	mesh_inst.position.y = rad * 0.7
	boulder.add_child(mesh_inst)
	
	var col: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = rad
	col.shape = sphere_shape
	col.position.y = rad * 0.7
	boulder.add_child(col)
	
	add_child(boulder)
	_spawned_props.append(boulder)

func _spawn_petrified_pine(rng: RandomNumberGenerator) -> void:
	var tree: StaticBody3D = StaticBody3D.new()
	tree.name = "PetrifiedPine"
	tree.position = Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
	tree.collision_layer = 1
	tree.collision_mask = 6
	
	var trunk: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.5
	cyl.height = 5.0
	trunk.mesh = cyl
	trunk.position.y = 2.5
	tree.add_child(trunk)
	
	var col: CollisionShape3D = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = 0.4
	cyl_shape.height = 5.0
	col.shape = cyl_shape
	col.position.y = 2.5
	tree.add_child(col)
	
	add_child(tree)
	_spawned_props.append(tree)

func _spawn_loot_crate(rng: RandomNumberGenerator) -> void:
	var crate_scene: PackedScene = load("res://scenes/containers/GroundCrate.tscn")
	if crate_scene:
		var crate: Node3D = crate_scene.instantiate() as Node3D
		crate.position = Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
		add_child(crate)
		_spawned_props.append(crate)
