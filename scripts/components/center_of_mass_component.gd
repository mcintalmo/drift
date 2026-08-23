class_name CenterOfMassComponent
extends Node

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal com_updated(com_offset_3d: Vector3, total_mass_kg: float)

@export_group("Dependencies")
@export var sled_stats: SledStatsData
@export var drift_component: InertialDriftComponent
@export var container_inventories: Array[HexInventoryComponent] = []

var current_total_mass_kg: float = 220.0
var current_com_offset_3d: Vector3 = Vector3(0.0, 0.25, 0.0)

func _ready() -> void:
	if not sled_stats:
		sled_stats = SledStatsData.new()
	
	# Connect existing exported containers
	for container: HexInventoryComponent in container_inventories:
		if is_instance_valid(container):
			if not container.inventory_changed.is_connected(_on_container_inventory_changed):
				container.inventory_changed.connect(_on_container_inventory_changed)
	
	recalculate_com()

func register_container(container: HexInventoryComponent) -> void:
	if container:
		if not container in container_inventories:
			container_inventories.append(container)
		if not container.inventory_changed.is_connected(_on_container_inventory_changed):
			container.inventory_changed.connect(_on_container_inventory_changed)
		recalculate_com()

func unregister_container(container: HexInventoryComponent) -> void:
	if container in container_inventories:
		if container.inventory_changed.is_connected(_on_container_inventory_changed):
			container.inventory_changed.disconnect(_on_container_inventory_changed)
		container_inventories.erase(container)
		recalculate_com()

func _on_container_inventory_changed(_items: Array[HexItemData]) -> void:
	recalculate_com()

## Recalculates total mass and composite 3D Center of Mass offset (Paradigm A Vertical Orientation)
func recalculate_com() -> void:
	var base_mass: float = sled_stats.chassis_base_mass_kg if sled_stats else 220.0
	var base_com: Vector3 = sled_stats.chassis_com_offset if sled_stats else Vector3(0.0, 0.25, 0.0)
	
	var total_mass: float = base_mass
	var weighted_pos_sum: Vector3 = base_com * base_mass
	
	for container: HexInventoryComponent in container_inventories:
		if not is_instance_valid(container):
			continue
		var container_mass: float = container.get_total_composite_mass()
		var com_2d: Vector2 = container.get_com_offset_2d()
		
		# Paradigm A: X = Lateral width, Y = Physical Height (Top of grid raises COM height, Bottom lowers COM height)
		var container_com_3d: Vector3 = Vector3(com_2d.x, 0.25 - com_2d.y, 0.0)
		weighted_pos_sum += container_com_3d * container_mass
		total_mass += container_mass
	
	current_total_mass_kg = total_mass
	current_com_offset_3d = weighted_pos_sum / maxf(1.0, total_mass)
	
	# Update InertialDriftComponent if attached
	if drift_component:
		drift_component.current_total_mass_kg = current_total_mass_kg
		drift_component.external_com_lateral_offset_m = current_com_offset_3d.x
		drift_component.external_com_height_m = current_com_offset_3d.y
	
	com_updated.emit(current_com_offset_3d, current_total_mass_kg)
	GlobalEvents.emit_inventory_updated(&"sled_composite", current_total_mass_kg, Vector2(current_com_offset_3d.x, current_com_offset_3d.y))

func get_lateral_com_bias() -> float:
	return current_com_offset_3d.x

func get_com_height() -> float:
	return current_com_offset_3d.y
