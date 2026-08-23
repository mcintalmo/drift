class_name TestHexInventory
extends RefCounted

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_single_cell_placement())
	results.append(_test_multi_cell_placement_and_rotation())
	results.append(_test_overlapping_placement_rejected())
	results.append(_test_out_of_bounds_placement_rejected())
	results.append(_test_item_removal())
	return results

func _test_single_cell_placement() -> Dictionary:
	var container: HexInventoryComponent = HexInventoryComponent.new()
	container.container_mount = ContainerMountData.new()
	
	var item: HexItemData = HexItemData.new()
	item.item_id = &"item_scrap"
	item.mass_kg = 5.0
	item.hex_footprint = [Vector2i(0, 0)]
	
	var placed: bool = container.place_item(item, Vector2i(0, 0))
	var total_mass: float = container.get_total_items_mass()
	var passed: bool = placed and (total_mass == 5.0) and not container.is_empty()
	
	container.free()
	return {
		"name": "test_single_cell_placement",
		"passed": passed,
		"message": "Single cell placed successfully, total item mass = %f" % total_mass
	}

func _test_multi_cell_placement_and_rotation() -> Dictionary:
	var container: HexInventoryComponent = HexInventoryComponent.new()
	container.container_mount = ContainerMountData.new()
	
	var long_item: HexItemData = HexItemData.new()
	long_item.item_id = &"item_beam"
	long_item.mass_kg = 15.0
	long_item.hex_footprint = [Vector2i(0, 0), Vector2i(1, 0)] # 2-hex bar
	
	var rotated_footprint: Array[Vector2i] = long_item.get_rotated_footprint(1) # Rotated 60 degrees -> [ (0, 0), (0, 1) ]
	var placed: bool = container.place_item(long_item, Vector2i(0, 0), 1)
	
	var passed: bool = placed and rotated_footprint.size() == 2 and rotated_footprint[1] == Vector2i(0, 1)
	
	container.free()
	return {
		"name": "test_multi_cell_placement_and_rotation",
		"passed": passed,
		"message": "2-hex bar rotated and placed at (0, 0) and (0, 1)"
	}

func _test_overlapping_placement_rejected() -> Dictionary:
	var container: HexInventoryComponent = HexInventoryComponent.new()
	container.container_mount = ContainerMountData.new()
	
	var item_a: HexItemData = HexItemData.new()
	item_a.item_id = &"item_a"
	item_a.mass_kg = 5.0
	item_a.hex_footprint = [Vector2i(0, 0)]
	container.place_item(item_a, Vector2i(0, 0))
	
	var item_b: HexItemData = HexItemData.new()
	item_b.item_id = &"item_b"
	item_b.mass_kg = 5.0
	item_b.hex_footprint = [Vector2i(0, 0)]
	
	# Attempt to place on occupied slot (0, 0)
	var placed: bool = container.place_item(item_b, Vector2i(0, 0))
	var passed: bool = not placed
	
	container.free()
	return {
		"name": "test_overlapping_placement_rejected",
		"passed": passed,
		"message": "Overlapping item placement rejected as expected"
	}

func _test_out_of_bounds_placement_rejected() -> Dictionary:
	var container: HexInventoryComponent = HexInventoryComponent.new()
	container.container_mount = ContainerMountData.new()
	
	var item: HexItemData = HexItemData.new()
	item.item_id = &"item_out"
	item.mass_kg = 5.0
	item.hex_footprint = [Vector2i(0, 0)]
	
	# Attempt to place at (10, 10) which is outside layout
	var placed: bool = container.place_item(item, Vector2i(10, 10))
	var passed: bool = not placed
	
	container.free()
	return {
		"name": "test_out_of_bounds_placement_rejected",
		"passed": passed,
		"message": "Out of bounds slot (10, 10) rejected as expected"
	}

func _test_item_removal() -> Dictionary:
	var container: HexInventoryComponent = HexInventoryComponent.new()
	container.container_mount = ContainerMountData.new()
	
	var item: HexItemData = HexItemData.new()
	item.item_id = &"item_rem"
	item.mass_kg = 12.0
	item.hex_footprint = [Vector2i(0, 0)]
	
	container.place_item(item, Vector2i(0, 0))
	var removed: bool = container.remove_item(item)
	
	var passed: bool = removed and container.is_empty() and container.get_total_items_mass() == 0.0
	
	container.free()
	return {
		"name": "test_item_removal",
		"passed": passed,
		"message": "Item removed and slots cleared successfully"
	}
