class_name TestCenterOfMass
extends RefCounted

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_empty_container_com())
	results.append(_test_asymmetrical_item_placement_shifts_com())
	results.append(_test_center_of_mass_aggregation())
	results.append(_test_mounted_pilot_impacts_sled_com())
	return results

func _test_empty_container_com() -> Dictionary:
	var container_comp: HexInventoryComponent = HexInventoryComponent.new()
	container_comp.container_mount = ContainerMountData.new()
	
	var com_2d: Vector2 = container_comp.get_com_offset_2d()
	var passed: bool = com_2d == Vector2.ZERO
	
	container_comp.free()
	return {
		"name": "test_empty_container_com",
		"passed": passed,
		"message": "Empty container COM is at (0, 0): offset = %s" % str(com_2d)
	}

func _test_asymmetrical_item_placement_shifts_com() -> Dictionary:
	var container_comp: HexInventoryComponent = HexInventoryComponent.new()
	container_comp.container_mount = ContainerMountData.new()
	
	var heavy_item: HexItemData = HexItemData.new()
	heavy_item.item_id = &"test_heavy"
	heavy_item.mass_kg = 50.0
	heavy_item.hex_footprint = [Vector2i(0, 0)]
	
	# Place at +1 q (to the right)
	var placed: bool = container_comp.place_item(heavy_item, Vector2i(1, 0))
	var com_2d: Vector2 = container_comp.get_com_offset_2d()
	
	var passed: bool = placed and (com_2d.x > 0.1)
	
	container_comp.free()
	return {
		"name": "test_asymmetrical_item_placement_shifts_com",
		"passed": passed,
		"message": "Heavy item at (1, 0) shifted COM_x rightward to %f m" % com_2d.x
	}

func _test_center_of_mass_aggregation() -> Dictionary:
	var com_comp: CenterOfMassComponent = CenterOfMassComponent.new()
	com_comp.sled_stats = SledStatsData.new()
	com_comp.sled_stats.chassis_base_mass_kg = 200.0
	com_comp.sled_stats.chassis_com_offset = Vector3(0.0, 0.2, 0.0)
	
	var container_comp: HexInventoryComponent = HexInventoryComponent.new()
	container_comp.container_mount = ContainerMountData.new()
	container_comp.container_mount.tare_mass_kg = 20.0
	com_comp.container_inventories = [container_comp]
	
	var heavy_item: HexItemData = HexItemData.new()
	heavy_item.mass_kg = 80.0
	heavy_item.hex_footprint = [Vector2i(0, 0)]
	container_comp.place_item(heavy_item, Vector2i(1, 0))
	
	com_comp.recalculate_com()
	
	var final_mass: float = com_comp.current_total_mass_kg
	var final_com: Vector3 = com_comp.current_com_offset_3d
	
	# Total mass should be 200 (chassis) + 20 (container tare) + 80 (item) = 300 kg
	var passed: bool = is_equal_approx(final_mass, 300.0) and (final_com.x > 0.05)
	
	com_comp.free()
	container_comp.free()
	return {
		"name": "test_center_of_mass_aggregation",
		"passed": passed,
		"message": "Aggregated mass = %f kg, COM = %s" % [final_mass, str(final_com)]
	}

func _test_mounted_pilot_impacts_sled_com() -> Dictionary:
	var com_comp: CenterOfMassComponent = CenterOfMassComponent.new()
	com_comp.sled_stats = SledStatsData.new()
	com_comp.sled_stats.chassis_base_mass_kg = 200.0
	com_comp.sled_stats.chassis_com_offset = Vector3(0.0, 0.2, 0.0)
	
	var pilot: CharacterBody3D = CharacterBody3D.new()
	var bp: HexInventoryComponent = HexInventoryComponent.new()
	bp.name = "BackpackInventoryComponent"
	bp.container_mount = ContainerMountData.new()
	pilot.add_child(bp)
	
	var heavy_item: HexItemData = HexItemData.new()
	heavy_item.mass_kg = 50.0
	heavy_item.hex_footprint = [Vector2i(0, 0)]
	bp.place_item(heavy_item, Vector2i(1, 0)) # 50kg on pilot's right side
	
	# Mount pilot into sled
	com_comp.set_mounted_pilot(pilot)
	
	var mounted_mass: float = com_comp.current_total_mass_kg
	var mounted_com_x: float = com_comp.current_com_offset_3d.x
	
	# Expected mass: 200 (chassis) + 75 (pilot body) + 50 (backpack) = 325 kg
	var mounted_pass: bool = is_equal_approx(mounted_mass, 325.0) and (mounted_com_x > 0.04)
	
	# Dismount pilot
	com_comp.clear_mounted_pilot()
	var unmounted_mass: float = com_comp.current_total_mass_kg
	var unmounted_com_x: float = com_comp.current_com_offset_3d.x
	
	var unmounted_pass: bool = is_equal_approx(unmounted_mass, 200.0) and is_zero_approx(unmounted_com_x)
	
	var passed: bool = mounted_pass and unmounted_pass
	
	com_comp.free()
	pilot.free()
	return {
		"name": "test_mounted_pilot_impacts_sled_com",
		"passed": passed,
		"message": "Mounted mass = %.1f kg, COM_x = %.3f m -> Dismounted mass = %.1f kg, COM_x = %.3f m" % [
			mounted_mass, mounted_com_x, unmounted_mass, unmounted_com_x
		]
	}
