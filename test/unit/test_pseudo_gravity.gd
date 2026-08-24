class_name TestPseudoGravity
extends RefCounted

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_single_item_falls_straight_down())
	results.append(_test_grounded_item_does_not_move())
	results.append(_test_stacked_items_settle_on_top())
	results.append(_test_multi_cell_polyomino_settles())
	return results

func _test_single_item_falls_straight_down() -> Dictionary:
	var container: HexInventoryComponent = HexInventoryComponent.new()
	var mount: ContainerMountData = ContainerMountData.new()
	container.container_mount = mount
	
	var item: HexItemData = HexItemData.new()
	item.item_id = &"floating_ingot"
	item.mass_kg = 18.0
	item.hex_footprint = [Vector2i(0, 0)]
	
	# Place at top-center (0, -2)
	container.place_item(item, Vector2i(0, -2))
	var start_pixel_x: float = container.axial_to_cartesian(Vector2i(0, -2)).x
	
	var moved: bool = container.apply_pseudo_gravity_settling()
	var final_slots: Array[Vector2i] = container.get_item_occupied_slots(item)
	var final_root: Vector2i = final_slots[0] if not final_slots.is_empty() else Vector2i(-999, -999)
	var final_pixel_x: float = container.axial_to_cartesian(final_root).x
	var lateral_drift: float = absf(final_pixel_x - start_pixel_x)
	
	# Final root should be at the bottom (r >= 0) and lateral drift should be minimal (<= 1 cell radius ~0.25m)
	var passed: bool = moved and (final_root.y > -2) and (lateral_drift <= 0.25)
	
	container.free()
	return {
		"name": "test_single_item_falls_straight_down",
		"passed": passed,
		"message": "Item at (0, -2) settled to %s (lateral drift = %.3f m)" % [str(final_root), lateral_drift]
	}

func _test_grounded_item_does_not_move() -> Dictionary:
	var container: HexInventoryComponent = HexInventoryComponent.new()
	var mount: ContainerMountData = ContainerMountData.new()
	container.container_mount = mount
	
	var item: HexItemData = HexItemData.new()
	item.item_id = &"bottom_ingot"
	item.mass_kg = 18.0
	item.hex_footprint = [Vector2i(0, 0)]
	
	# Place at bottom floor (-2, 2)
	container.place_item(item, Vector2i(-2, 2))
	
	var moved: bool = container.apply_pseudo_gravity_settling()
	var final_root: Vector2i = container.get_item_occupied_slots(item)[0]
	
	var passed: bool = not moved and (final_root == Vector2i(-2, 2))
	
	container.free()
	return {
		"name": "test_grounded_item_does_not_move",
		"passed": passed,
		"message": "Item at bottom floor (-2, 2) remained stationary (moved = %s)" % str(moved)
	}

func _test_stacked_items_settle_on_top() -> Dictionary:
	var container: HexInventoryComponent = HexInventoryComponent.new()
	var mount: ContainerMountData = ContainerMountData.new()
	container.container_mount = mount
	
	var bottom_item: HexItemData = HexItemData.new()
	bottom_item.item_id = &"base_ingot"
	bottom_item.mass_kg = 18.0
	bottom_item.hex_footprint = [Vector2i(0, 0)]
	container.place_item(bottom_item, Vector2i(0, 2))
	
	var top_item: HexItemData = HexItemData.new()
	top_item.item_id = &"top_ingot"
	top_item.mass_kg = 18.0
	top_item.hex_footprint = [Vector2i(0, 0)]
	container.place_item(top_item, Vector2i(0, -2))
	
	container.apply_pseudo_gravity_settling()
	
	var final_top_root: Vector2i = container.get_item_occupied_slots(top_item)[0]
	var final_bottom_root: Vector2i = container.get_item_occupied_slots(bottom_item)[0]
	
	var passed: bool = (final_bottom_root == Vector2i(0, 2)) and (final_top_root != Vector2i(0, -2)) and (final_top_root != final_bottom_root)
	
	container.free()
	return {
		"name": "test_stacked_items_settle_on_top",
		"passed": passed,
		"message": "Top item settled above base item to %s without overlapping base at %s" % [str(final_top_root), str(final_bottom_root)]
	}

func _test_multi_cell_polyomino_settles() -> Dictionary:
	var container: HexInventoryComponent = HexInventoryComponent.new()
	var mount: ContainerMountData = ContainerMountData.new()
	container.container_mount = mount
	
	var bar: HexItemData = HexItemData.new()
	bar.item_id = &"dual_rod"
	bar.mass_kg = 42.0
	bar.hex_footprint = [Vector2i(0, 0), Vector2i(1, 0)]
	
	# Place 2-hex bar at top (-1, -1)
	container.place_item(bar, Vector2i(-1, -1))
	
	var moved: bool = container.apply_pseudo_gravity_settling()
	var slots: Array[Vector2i] = container.get_item_occupied_slots(bar)
	
	var all_valid: bool = true
	for s: Vector2i in slots:
		if not mount.has_slot(s):
			all_valid = false
	
	var passed: bool = moved and all_valid and slots.size() == 2
	
	container.free()
	return {
		"name": "test_multi_cell_polyomino_settles",
		"passed": passed,
		"message": "2-hex bar settled downward cleanly to slots %s" % str(slots)
	}
