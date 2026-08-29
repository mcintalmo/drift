class_name TestHexUIMath
extends RefCounted

const HexGridControl = preload("res://scripts/ui/hex_grid_control.gd")
const HexItemData = preload("res://scripts/resources/hex_item_data.gd")
const HexInventoryComponent = preload("res://scripts/components/hex_inventory_component.gd")
const ContainerMountData = preload("res://scripts/resources/container_mount_data.gd")

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_axial_to_pixel_roundtrip())
	results.append(_test_six_step_rotation_closure())
	results.append(_test_hex_polygon_vertices_count())
	results.append(_test_quick_transfer_search())
	results.append(_test_multiple_identical_items_preserved())
	results.append(_test_heavy_cargo_com_shift())
	results.append(_test_multi_vault_auto_swapping())
	results.append(_test_standalone_backpack_display())
	results.append(_test_vault_to_backpack_switching())
	results.append(_test_tab_button_signal_binding())
	results.append(_test_single_crate_and_backpack_swapping())
	return results

func _test_axial_to_pixel_roundtrip() -> Dictionary:
	var grid_control: HexGridControl = HexGridControl.new()
	grid_control.size = Vector2(300, 300)
	grid_control.cell_radius = 25.0
	
	var test_coords: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(2, -3),
		Vector2i(-4, -2)
	]
	
	var all_matched: bool = true
	for coord: Vector2i in test_coords:
		var px: Vector2 = grid_control.hex_to_pixel(coord) + (grid_control.size * 0.5)
		var converted_back: Vector2i = grid_control.pixel_to_hex(px)
		if converted_back != coord:
			all_matched = false
			break
	
	grid_control.free()
	return {
		"name": "test_axial_to_pixel_roundtrip",
		"passed": all_matched,
		"message": "Axial coordinates successfully round-tripped through pixel space"
	}

func _test_six_step_rotation_closure() -> Dictionary:
	var item: HexItemData = HexItemData.new()
	# Asymmetric L-shape footprint
	var footprint: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	item.hex_footprint = footprint
	
	var initial_footprint: Array[Vector2i] = item.get_rotated_footprint(0)
	var rotated_6_times: Array[Vector2i] = item.get_rotated_footprint(6)
	
	var passed: bool = (initial_footprint == rotated_6_times)
	
	return {
		"name": "test_six_step_rotation_closure",
		"passed": passed,
		"message": "6-step 60-degree rotation exhibits closed 360-degree symmetry"
	}

func _test_hex_polygon_vertices_count() -> Dictionary:
	var grid_control: HexGridControl = HexGridControl.new()
	grid_control.cell_radius = 20.0
	
	var poly: PackedVector2Array = grid_control.get_hex_polygon(Vector2(50, 50), 20.0)
	
	var passed: bool = poly.size() == 6
	for pt: Vector2 in poly:
		var dist: float = pt.distance_to(Vector2(50, 50))
		if not is_equal_approx(dist, 20.0):
			passed = false
			break
	
	grid_control.free()
	return {
		"name": "test_hex_polygon_vertices_count",
		"passed": passed,
		"message": "Generated hexagon has exactly 6 vertices equidistant (20.0 px) from center"
	}

func _test_quick_transfer_search() -> Dictionary:
	var source_inv: HexInventoryComponent = HexInventoryComponent.new()
	var src_mount: ContainerMountData = ContainerMountData.new()
	src_mount.slot_layout = [Vector2i(0, 0), Vector2i(1, 0)]
	source_inv.container_mount = src_mount
	
	var target_inv: HexInventoryComponent = HexInventoryComponent.new()
	var tgt_mount: ContainerMountData = ContainerMountData.new()
	tgt_mount.slot_layout = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0)]
	target_inv.container_mount = tgt_mount
	
	var item: HexItemData = HexItemData.new()
	item.item_id = &"test_bar"
	item.mass_kg = 10.0
	var item_footprint: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
	item.hex_footprint = item_footprint
	
	source_inv.place_item(item, Vector2i(0, 0))
	
	# Simulate quick transfer search
	var transferred: bool = false
	for slot: Vector2i in target_inv.available_slots:
		for rot: int in range(6):
			if target_inv.can_place_item(item, slot, rot):
				source_inv.remove_item(item)
				target_inv.place_item(item, slot, rot)
				transferred = true
				break
		if transferred:
			break
	
	var passed: bool = transferred and target_inv.get_all_placed_items().has(item) and not source_inv.get_all_placed_items().has(item)
	
	source_inv.free()
	target_inv.free()
	
	return {
		"name": "test_quick_transfer_search",
		"passed": passed,
		"message": "Quick transfer algorithm placed item into target container across 6-rotation search"
	}

func _test_multiple_identical_items_preserved() -> Dictionary:
	var inv: HexInventoryComponent = HexInventoryComponent.new()
	var mount: ContainerMountData = ContainerMountData.new()
	mount.slot_layout = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0)]
	inv.container_mount = mount
	
	var scrap1: HexItemData = HexItemData.new()
	scrap1.item_id = &"item_scrap_metal"
	scrap1.hex_footprint = [Vector2i(0, 0)]
	scrap1.mass_kg = 15.0
	
	var scrap2: HexItemData = HexItemData.new()
	scrap2.item_id = &"item_scrap_metal" # Identical item_id
	scrap2.hex_footprint = [Vector2i(0, 0)]
	scrap2.mass_kg = 15.0
	
	inv.place_item(scrap1, Vector2i(0, 0))
	inv.place_item(scrap2, Vector2i(1, 0))
	
	var all_items: Array[HexItemData] = inv.get_all_placed_items()
	var passed: bool = (all_items.size() == 2 and all_items.has(scrap1) and all_items.has(scrap2))
	
	inv.free()
	return {
		"name": "test_multiple_identical_items_preserved",
		"passed": passed,
		"message": "Both scrap items with identical item_id are preserved in get_all_placed_items"
	}

func _test_heavy_cargo_com_shift() -> Dictionary:
	var inv: HexInventoryComponent = HexInventoryComponent.new()
	var mount: ContainerMountData = ContainerMountData.new()
	mount.tare_mass_kg = 10.0
	mount.slot_layout = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	inv.container_mount = mount
	
	# Place 65kg heavy plasma boomerang on the right side at (2, 0)
	var boom: HexItemData = HexItemData.new()
	boom.item_id = &"heavy_boom"
	boom.mass_kg = 65.0
	boom.hex_footprint = [Vector2i(0, 0)]
	inv.place_item(boom, Vector2i(2, 0))
	
	var com: Vector2 = inv.get_com_offset_2d()
	# Expect positive lateral X offset
	var passed: bool = com.x > 0.4
	
	inv.free()
	return {
		"name": "test_heavy_cargo_com_shift",
		"passed": passed,
		"message": "65kg heavy cargo shifted container COM lateral offset to +%.3fm" % com.x
	}

func _test_multi_vault_auto_swapping() -> Dictionary:
	var ui: HexInventoryUI = HexInventoryUI.new()
	
	# Simulate 2 discovered vault crates
	var crate1: GroundCrate = GroundCrate.new()
	crate1.name = "VaultCrate1"
	var crate2: GroundCrate = GroundCrate.new()
	crate2.name = "VaultCrate2"
	ui.discovered_crates = [crate1, crate2]
	
	# Initial configuration: Left has Vault 1 (idx 0), Right has Vault 2 (idx 1)
	ui.left_container_type = HexInventoryUI.ContainerType.GROUND_CRATE
	ui.selected_left_crate_idx = 0
	ui.right_container_type = HexInventoryUI.ContainerType.GROUND_CRATE
	ui.selected_right_crate_idx = 1
	
	# User on Left panel clicks Vault 2 (idx 1) -> Must SWAP!
	ui._set_left_container(HexInventoryUI.ContainerType.GROUND_CRATE, 1)
	
	var passed: bool = (
		ui.left_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and
		ui.selected_left_crate_idx == 1 and
		ui.right_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and
		ui.selected_right_crate_idx == 0
	)
	
	crate1.free()
	crate2.free()
	ui.free()
	
	return {
		"name": "test_multi_vault_auto_swapping",
		"passed": passed,
		"message": "Selecting active right container on left panel cleanly swapped Left (Vault 2) <-> Right (Vault 1)"
	}

func _test_standalone_backpack_display() -> Dictionary:
	var ui: HexInventoryUI = HexInventoryUI.new()
	var bp_inv: HexInventoryComponent = HexInventoryComponent.new()
	ui.backpack_inventory = bp_inv
	ui.discovered_crates = []
	ui.sled_inventory = null
	
	# When no crates and no sleds are in range, opening contextual inventory sets Left=Backpack, Right=NONE
	ui.open_contextual_inventory()
	
	var passed: bool = (
		ui.left_container_type == HexInventoryUI.ContainerType.PILOT_BACKPACK and
		ui.right_container_type == HexInventoryUI.ContainerType.NONE and
		ui.selected_right_crate_idx == -1
	)
	
	bp_inv.free()
	ui.free()
	
	return {
		"name": "test_standalone_backpack_display",
		"passed": passed,
		"message": "When no secondary containers exist, Left shows Backpack and Right is NONE"
	}

func _test_vault_to_backpack_switching() -> Dictionary:
	var ui: HexInventoryUI = HexInventoryUI.new()
	var bp_inv: HexInventoryComponent = HexInventoryComponent.new()
	ui.backpack_inventory = bp_inv
	
	var crate1: GroundCrate = GroundCrate.new()
	crate1.name = "VaultCrate1"
	var crate2: GroundCrate = GroundCrate.new()
	crate2.name = "VaultCrate2"
	ui.discovered_crates = [crate1, crate2]
	
	# Start with Left=Vault 1, Right=Vault 2
	ui.left_container_type = HexInventoryUI.ContainerType.GROUND_CRATE
	ui.selected_left_crate_idx = 0
	ui.right_container_type = HexInventoryUI.ContainerType.GROUND_CRATE
	ui.selected_right_crate_idx = 1
	
	# 1. Switch Left to Backpack (Backpack is not on Right)
	ui._set_left_container(HexInventoryUI.ContainerType.PILOT_BACKPACK)
	var step1_ok: bool = (
		ui.left_container_type == HexInventoryUI.ContainerType.PILOT_BACKPACK and
		ui.right_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and
		ui.selected_right_crate_idx == 1
	)
	
	# 2. Click Vault 2 on Left (Vault 2 IS currently on Right -> SWAP!)
	ui._set_left_container(HexInventoryUI.ContainerType.GROUND_CRATE, 1)
	var step2_ok: bool = (
		ui.left_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and
		ui.selected_left_crate_idx == 1 and
		ui.right_container_type == HexInventoryUI.ContainerType.PILOT_BACKPACK
	)
	
	# 3. Click Backpack on Left (Backpack IS currently on Right -> SWAP!)
	ui._set_left_container(HexInventoryUI.ContainerType.PILOT_BACKPACK)
	var step3_ok: bool = (
		ui.left_container_type == HexInventoryUI.ContainerType.PILOT_BACKPACK and
		ui.right_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and
		ui.selected_right_crate_idx == 1
	)
	
	crate1.free()
	crate2.free()
	bp_inv.free()
	ui.free()
	
	var passed: bool = step1_ok and step2_ok and step3_ok
	return {
		"name": "test_vault_to_backpack_switching",
		"passed": passed,
		"message": "Seamlessly switched and swapped between Vaults and Backpack across Left & Right panels"
	}

func _test_tab_button_signal_binding() -> Dictionary:
	var ui: HexInventoryUI = HexInventoryUI.new()
	var left_bar: HBoxContainer = HBoxContainer.new()
	var right_bar: HBoxContainer = HBoxContainer.new()
	ui.left_tab_bar = left_bar
	ui.right_tab_bar = right_bar
	
	var crate1: GroundCrate = GroundCrate.new()
	crate1.name = "VaultCrate1"
	var crate2: GroundCrate = GroundCrate.new()
	crate2.name = "VaultCrate2"
	ui.discovered_crates = [crate1, crate2]
	
	var bp_inv: HexInventoryComponent = HexInventoryComponent.new()
	ui.backpack_inventory = bp_inv
	
	# Start Left=Vault 1 (0), Right=Vault 2 (1)
	ui.left_container_type = HexInventoryUI.ContainerType.GROUND_CRATE
	ui.selected_left_crate_idx = 0
	ui.right_container_type = HexInventoryUI.ContainerType.GROUND_CRATE
	ui.selected_right_crate_idx = 1
	
	ui._rebuild_tab_bar(left_bar, true)
	ui._rebuild_tab_bar(right_bar, false)
	
	# Left bar children: [CrateTab_0, CrateTab_1, BackpackTab]
	var btn_vault1: Button = left_bar.get_node_or_null("CrateTab_0") as Button
	var btn_vault2: Button = left_bar.get_node_or_null("CrateTab_1") as Button
	var btn_bp: Button = left_bar.get_node_or_null("BackpackTab") as Button
	
	# 1. Click Backpack button on Left bar
	btn_bp.emit_signal(&"pressed")
	var step1_ok: bool = (ui.left_container_type == HexInventoryUI.ContainerType.PILOT_BACKPACK and ui.right_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and ui.selected_right_crate_idx == 1)
	
	# 2. Click Vault 1 button on Left bar
	var btn_vault1_after: Button = left_bar.get_node_or_null("CrateTab_0") as Button
	btn_vault1_after.emit_signal(&"pressed")
	var step2_ok: bool = (ui.left_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and ui.selected_left_crate_idx == 0 and ui.right_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and ui.selected_right_crate_idx == 1)
	
	# 3. Click Vault 2 button on Left bar (Swap with Right!)
	var btn_vault2_after: Button = left_bar.get_node_or_null("CrateTab_1") as Button
	btn_vault2_after.emit_signal(&"pressed")
	var step3_ok: bool = (ui.left_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and ui.selected_left_crate_idx == 1 and ui.right_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and ui.selected_right_crate_idx == 0)
	
	crate1.free()
	crate2.free()
	bp_inv.free()
	left_bar.free()
	right_bar.free()
	ui.free()
	
	var passed: bool = step1_ok and step2_ok and step3_ok
	return {
		"name": "test_tab_button_signal_binding",
		"passed": passed,
		"message": "Button pressed signals with bound arguments correctly routed and executed without closure variable capture errors"
	}

func _test_single_crate_and_backpack_swapping() -> Dictionary:
	var ui: HexInventoryUI = HexInventoryUI.new()
	var left_bar: HBoxContainer = HBoxContainer.new()
	var right_bar: HBoxContainer = HBoxContainer.new()
	ui.left_tab_bar = left_bar
	ui.right_tab_bar = right_bar
	
	var crate1: GroundCrate = GroundCrate.new()
	crate1.name = "GroundCrate1"
	crate1.crate_state = GroundCrate.CrateState.LOCKED # Locked crate
	ui.discovered_crates = [crate1]
	
	var bp_inv: HexInventoryComponent = HexInventoryComponent.new()
	ui.backpack_inventory = bp_inv
	ui.sled_inventory = null
	
	# Open contextual inventory with 1 crate and backpack (no sled)
	ui.open_contextual_inventory()
	
	# Initial: Left=Crate, Right=Backpack
	var init_ok: bool = (
		ui.left_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and
		ui.selected_left_crate_idx == 0 and
		ui.right_container_type == HexInventoryUI.ContainerType.PILOT_BACKPACK
	)
	
	# Tab buttons created on Left: [CrateTab_0, BackpackTab]
	var btn_bp_left: Button = left_bar.get_node_or_null("BackpackTab") as Button
	var btn_crate_left: Button = left_bar.get_node_or_null("CrateTab_0") as Button
	
	# 1. Click Backpack on Left bar -> Must SWAP! Left=Backpack, Right=Crate
	btn_bp_left.emit_signal(&"pressed")
	var swap1_ok: bool = (
		ui.left_container_type == HexInventoryUI.ContainerType.PILOT_BACKPACK and
		ui.right_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and
		ui.selected_right_crate_idx == 0
	)
	
	# 2. Click Crate on Left bar -> Must SWAP back! Left=Crate, Right=Backpack
	var btn_crate_left_after: Button = left_bar.get_node_or_null("CrateTab_0") as Button
	btn_crate_left_after.emit_signal(&"pressed")
	var swap2_ok: bool = (
		ui.left_container_type == HexInventoryUI.ContainerType.GROUND_CRATE and
		ui.selected_left_crate_idx == 0 and
		ui.right_container_type == HexInventoryUI.ContainerType.PILOT_BACKPACK
	)
	
	crate1.free()
	bp_inv.free()
	left_bar.free()
	right_bar.free()
	ui.free()
	
	var passed: bool = init_ok and swap1_ok and swap2_ok
	return {
		"name": "test_single_crate_and_backpack_swapping",
		"passed": passed,
		"message": "Player with single crate (even locked) and backpack seamlessly switches and swaps between both containers"
	}
