class_name SectorBiomeData
extends Resource

@export_group("Identification")
@export var biome_id: StringName = &"temperate_permafrost"
@export var biome_name: String = "Temperate Permafrost"
@export_multiline var description: String = "Outer rim tundra with packed powder trails, scattered frozen pines, and abandoned scavenger wrecks."

@export_group("Climate & Thermal Profile")
@export var base_ambient_temp_c: float = -14.0
@export var min_storm_temp_c: float = -38.0
@export var blizzard_frequency: float = 0.35 # 0.0 (rare) to 1.0 (constant)
@export var base_smog_index: float = 0.1

@export_group("Terrain & Elevation Tuning")
@export var hex_cell_outer_radius_m: float = 6.0
@export var elevation_amplitude: float = 2.8
@export var elevation_frequency: float = 0.035
@export var cliff_height_threshold_m: float = 1.8 # Drops > this threshold become vertical low-poly cliffs

@export_group("Surface Distribution Weights")
## Keyed by StringName: pack, powder, ice, firn, slush, snirt, scree, crust
@export var surface_weights: Dictionary = {
	&"pack": 0.45,
	&"powder": 0.25,
	&"ice": 0.12,
	&"firn": 0.08,
	&"crust": 0.05,
	&"snirt": 0.03,
	&"scree": 0.02
}

@export_group("Obstacle Density (Per Hex Tile)")
@export_range(0.0, 1.0, 0.05) var boulder_density: float = 0.15
@export_range(0.0, 1.0, 0.05) var pine_tree_density: float = 0.20
@export_range(0.0, 1.0, 0.05) var industrial_debris_density: float = 0.08
@export_range(0.0, 0.5, 0.02) var crevasse_chasm_chance: float = 0.05

@export_group("POI Spawn Probabilities (Per Hex Tile)")
@export_range(0.0, 0.3, 0.01) var overturned_sled_wreck_chance: float = 0.05
@export_range(0.0, 0.3, 0.01) var abandoned_corpo_facility_chance: float = 0.03
@export_range(0.0, 0.3, 0.01) var hot_spring_basin_chance: float = 0.07
@export_range(0.0, 1.0, 0.05) var hot_spring_cluster_boost: float = 0.65
@export_range(0.0, 0.4, 0.02) var railroad_corridor_chance: float = 0.08
@export_range(0.0, 0.4, 0.02) var ground_crate_cache_chance: float = 0.12

## Helper to choose surface type based on weighted distribution and a normalized 0..1 roll
func sample_surface_type(roll_val: float) -> StringName:
	var total_weight: float = 0.0
	for w: float in surface_weights.values():
		total_weight += w
	
	if total_weight <= 0.0:
		return &"pack"
	
	var target: float = clampf(roll_val, 0.0, 1.0) * total_weight
	var accum: float = 0.0
	for surface_key: StringName in surface_weights:
		accum += float(surface_weights[surface_key])
		if target <= accum:
			return surface_key
	
	return &"pack"
