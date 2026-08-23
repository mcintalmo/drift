class_name HexInventoryComponent
extends Node

signal inventory_changed(items: Array[HexItemData])
signal item_added(item: HexItemData, root_coord: Vector2i)
signal item_removed(item: HexItemData)
signal item_placed(item: HexItemData, root_coord: Vector2i)

@export var container_mount: ContainerMountData
@export var hex_cell_size_m: float = 0.25

# Internal grid state: maps occupied Vector2i(q, r) to the placed HexItemData
var _grid_slots: Dictionary = {}
var _placed_items: Array[HexItemData] = []
var _item_root_coords: Dictionary = {} # HexItemData -> Vector2i

var available_slots: Array[Vector2i]:
	get:
		if container_mount:
			return container_mount.slot_layout.duplicate()
		return []

var placed_items: Dictionary:
	get:
		var map: Dictionary = {}
		for item: HexItemData in _placed_items:
			map[item.item_id] = item
		return map

const SQRT_3: float = 1.7320508

func _ready() -> void:
	if not container_mount:
		container_mount = ContainerMountData.new()

## Checks if an item can be placed at a root axial coordinate with a given rotation
func can_place_item(item: HexItemData, root_coord: Vector2i, rotation_step: int = 0) -> bool:
	if not item:
		return false
	if not container_mount:
		container_mount = ContainerMountData.new()
	
	# Check weight capacity
	var prospective_mass: float = get_total_items_mass() + item.mass_kg
	if prospective_mass > container_mount.max_weight_capacity_kg:
		return false
	
	var footprint: Array[Vector2i] = item.get_rotated_footprint(rotation_step)
	for offset: Vector2i in footprint:
		var target_coord: Vector2i = root_coord + offset
		# Must be within container layout
		if not container_mount.has_slot(target_coord):
			return false
		# Must not overlap already occupied slot
		if _grid_slots.has(target_coord):
			return false
	
	return true

## Places an item in the container at root_coord
func place_item(item: HexItemData, root_coord: Vector2i, rotation_step: int = 0) -> bool:
	if not can_place_item(item, root_coord, rotation_step):
		return false
	
	var footprint: Array[Vector2i] = item.get_rotated_footprint(rotation_step)
	for offset: Vector2i in footprint:
		var target_coord: Vector2i = root_coord + offset
		_grid_slots[target_coord] = item
	
	item.root_slot = root_coord
	item.rotation_step = rotation_step
	_placed_items.append(item)
	_item_root_coords[item] = root_coord
	
	item_added.emit(item, root_coord)
	item_placed.emit(item, root_coord)
	inventory_changed.emit(_placed_items)
	return true

## Removes an item from the container
func remove_item(item: HexItemData) -> bool:
	if not item in _placed_items:
		return false
	
	# Clear occupied slots
	var slots_to_erase: Array[Vector2i] = []
	for coord: Vector2i in _grid_slots:
		if _grid_slots[coord] == item:
			slots_to_erase.append(coord)
	
	for coord: Vector2i in slots_to_erase:
		_grid_slots.erase(coord)
	
	_placed_items.erase(item)
	_item_root_coords.erase(item)
	
	item_removed.emit(item)
	inventory_changed.emit(_placed_items)
	return true

func get_item_at(coord: Vector2i) -> HexItemData:
	return _grid_slots.get(coord, null)

func get_item_occupied_slots(item: HexItemData) -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	for coord: Vector2i in _grid_slots:
		if _grid_slots[coord] == item:
			slots.append(coord)
	return slots

## Returns the sum of all stored items' mass in kg
func get_total_items_mass() -> float:
	var total_mass: float = 0.0
	for item: HexItemData in _placed_items:
		total_mass += item.mass_kg
	return total_mass

## Returns composite mass including container tare
func get_total_composite_mass() -> float:
	var tare: float = container_mount.tare_mass_kg if container_mount else 0.0
	return tare + get_total_items_mass()

## Converts an axial hex coordinate (q, r) to 2D Cartesian offset (X=right, Y=fore/aft)
func axial_to_cartesian(coord: Vector2i) -> Vector2:
	var x: float = hex_cell_size_m * (SQRT_3 * coord.x + (SQRT_3 / 2.0) * coord.y)
	var y: float = hex_cell_size_m * (1.5 * coord.y)
	return Vector2(x, y)

## Computes 2D center-of-mass offset in meters relative to container center
func get_com_offset_2d() -> Vector2:
	var total_mass: float = get_total_composite_mass()
	if total_mass <= 0.0:
		return Vector2.ZERO
	
	var weighted_pos_sum: Vector2 = Vector2.ZERO
	
	# Account for container tare mass at its local offset
	if container_mount:
		weighted_pos_sum += container_mount.local_mount_offset * container_mount.tare_mass_kg
	
	for item: HexItemData in _placed_items:
		if not _item_root_coords.has(item):
			continue
		var root_coord: Vector2i = _item_root_coords[item]
		# Compute centroid of item's footprint
		var item_cells_pos_sum: Vector2 = Vector2.ZERO
		var cell_count: int = 0
		for offset: Vector2i in item.hex_footprint:
			item_cells_pos_sum += axial_to_cartesian(root_coord + offset)
			cell_count += 1
		
		var item_centroid: Vector2 = item_cells_pos_sum / maxf(1.0, float(cell_count))
		weighted_pos_sum += item_centroid * item.mass_kg
	
	return weighted_pos_sum / total_mass

func get_items() -> Array[HexItemData]:
	return _placed_items.duplicate()

func is_empty() -> bool:
	return _placed_items.is_empty()
