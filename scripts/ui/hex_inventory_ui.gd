class_name HexInventoryUI
extends CanvasLayer

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

enum ContainerType {
	NONE = -1,
	GROUND_CRATE = 0,
	PILOT_BACKPACK = 1,
	SLED_CARGO_POD = 2
}

@export var is_open: bool = false

# Container Components
var discovered_crates: Array[GroundCrate] = []
var selected_left_crate_idx: int = 0
var selected_right_crate_idx: int = 0

var backpack_inventory: HexInventoryComponent = null
var sled_inventory: HexInventoryComponent = null
var sled_com_component: CenterOfMassComponent = null

var left_container_type: ContainerType = ContainerType.GROUND_CRATE
var right_container_type: ContainerType = ContainerType.SLED_CARGO_POD

# Focus & Drag State
var active_focus_panel: int = 0 # 0 = Left, 1 = Right
var held_item: HexItemData = null
var held_rotation_step: int = 0
var source_inv_for_drag: HexInventoryComponent = null
var source_slot_for_drag: Vector2i = Vector2i(-999, -999)

# Tab Styles
var active_tab_style: StyleBoxFlat
var inactive_tab_style: StyleBoxFlat

@onready var root_control: Control = $RootControl
@onready var left_grid_control: HexGridControl = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LeftContainer/HexGridControl
@onready var right_grid_control: HexGridControl = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RightContainer/HexGridControl
@onready var left_load_label: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LeftContainer/LeftLoadLabel
@onready var right_load_label: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RightContainer/RightLoadLabel

@onready var left_tab_bar: HBoxContainer = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LeftContainer/LeftTabBar
@onready var right_tab_bar: HBoxContainer = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RightContainer/RightTabBar

@onready var balance_title: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/BalanceTitle
@onready var com_widget: COMVisualizerWidget = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/COMVisualizerWidget
@onready var tooltip_name: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemNameLabel
@onready var tooltip_mass: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemMassLabel
@onready var tooltip_desc: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemDescLabel
@onready var floating_cursor_ghost: Control = $RootControl/FloatingCursorGhost

func _init() -> void:
	_init_tab_styles()

func _ready() -> void:
	if root_control:
		root_control.visible = is_open
	_init_tab_styles()
	if left_grid_control:
		_setup_grid_listeners(left_grid_control)
	if right_grid_control:
		_setup_grid_listeners(right_grid_control)
	if floating_cursor_ghost:
		floating_cursor_ghost.draw.connect(_on_draw_floating_ghost)

func _init_tab_styles() -> void:
	active_tab_style = StyleBoxFlat.new()
	active_tab_style.bg_color = Color(0.2, 0.45, 0.75, 0.95)
	active_tab_style.border_color = Color(0.5, 0.85, 1.0, 1.0)
	active_tab_style.set_border_width_all(1)
	active_tab_style.border_width_bottom = 2
	active_tab_style.set_corner_radius_all(4)
	
	inactive_tab_style = StyleBoxFlat.new()
	inactive_tab_style.bg_color = Color(0.12, 0.16, 0.22, 0.8)
	inactive_tab_style.border_color = Color(0.25, 0.35, 0.45, 0.6)
	inactive_tab_style.set_border_width_all(1)
	inactive_tab_style.set_corner_radius_all(4)

func _process(_delta: float) -> void:
	if is_open and held_item and floating_cursor_ghost and root_control:
		floating_cursor_ghost.position = root_control.get_local_mouse_position()
		floating_cursor_ghost.queue_redraw()

func _on_draw_floating_ghost() -> void:
	if not held_item or not floating_cursor_ghost:
		return
	var color: Color = held_item.item_color if held_item.item_color != Color.TRANSPARENT else Color(0.85, 0.55, 0.2, 0.85)
	color.a = 0.75
	var rotated_pts: Array[Vector2i] = held_item.get_rotated_footprint(held_rotation_step)
	var radius: float = left_grid_control.cell_radius if left_grid_control else 24.0
	
	for offset_pt: Vector2i in rotated_pts:
		var center: Vector2 = left_grid_control.hex_to_pixel(offset_pt) if left_grid_control else Vector2(offset_pt.x * 24.0, offset_pt.y * 24.0)
		var poly: PackedVector2Array = left_grid_control.get_hex_polygon(center, radius * 0.85) if left_grid_control else PackedVector2Array()
		if not poly.is_empty():
			floating_cursor_ghost.draw_colored_polygon(poly, color)
			floating_cursor_ghost.draw_polyline(poly, Color(1, 1, 1, 0.8), 1.5, true)

func _setup_grid_listeners(grid: HexGridControl) -> void:
	if not grid:
		return
	grid.cell_clicked.connect(func(cell: Vector2i, button: int, is_shift: bool) -> void:
		_on_grid_cell_clicked(grid, cell, button, is_shift)
	)
	grid.cell_hovered.connect(func(cell: Vector2i) -> void:
		if held_item and grid.grid_inventory:
			var is_valid: bool = grid.grid_inventory.can_place_item(held_item, cell, held_rotation_step)
			grid.set_custom_drag_preview(held_item, held_rotation_step, cell, is_valid)
		elif grid.grid_inventory:
			var item: HexItemData = grid.grid_inventory.get_item_at(cell)
			_update_tooltip(item)
	)

func _on_grid_cell_clicked(grid: HexGridControl, cell: Vector2i, button: int, is_shift: bool) -> void:
	if not grid or not grid.grid_inventory:
		return
	
	active_focus_panel = 0 if grid == left_grid_control else 1
	_update_panel_focus()
	
	if button == MOUSE_BUTTON_RIGHT and held_item:
		_rotate_held_item()
		return
	
	if button == MOUSE_BUTTON_LEFT:
		if held_item:
			var target_cell: Vector2i = cell
			if not grid.grid_inventory.can_place_item(held_item, target_cell, held_rotation_step):
				if grid.grid_inventory.can_place_item(held_item, grid.hovered_cell, held_rotation_step):
					target_cell = grid.hovered_cell
			_try_drop_item(grid, target_cell)
		else:
			var item: HexItemData = grid.grid_inventory.get_item_at(cell)
			if not item and grid.grid_inventory.get_item_at(grid.hovered_cell):
				item = grid.grid_inventory.get_item_at(grid.hovered_cell)
				cell = grid.hovered_cell
			
			if item:
				if is_shift:
					_quick_transfer_item(item, grid.grid_inventory)
				else:
					_start_dragging(item, grid.grid_inventory, cell)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_inventory") or event.is_action_pressed(&"ui_cancel") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
		if is_open:
			if held_item:
				_cancel_drag()
			else:
				close_inventory()
		else:
			open_contextual_inventory()
	
	elif is_open:
		if event.is_action_pressed(&"pilot_lean_right") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_R):
			if held_item:
				_rotate_held_item()
		
		elif event.is_action_pressed(&"pilot_lean_left") or (event is InputEventKey and event.pressed and (event.physical_keycode == KEY_TAB or event.physical_keycode == KEY_Q or event.physical_keycode == KEY_E)):
			if right_container_type != ContainerType.NONE:
				active_focus_panel = 1 - active_focus_panel
			else:
				active_focus_panel = 0
			_update_panel_focus()
			var active_grid: HexGridControl = left_grid_control if active_focus_panel == 0 else right_grid_control
			if held_item and active_grid and active_grid.grid_inventory:
				var is_valid: bool = active_grid.grid_inventory.can_place_item(held_item, active_grid.cursor_cell, held_rotation_step)
				active_grid.set_custom_drag_preview(held_item, held_rotation_step, active_grid.cursor_cell, is_valid)

var is_pilot_mounted: bool = false

func open_contextual_inventory() -> void:
	if is_open:
		return
		
	_discover_scene_inventories()
	
	if not is_pilot_mounted:
		# On foot on the ground: Backpack is ALWAYS the Left container
		left_container_type = ContainerType.PILOT_BACKPACK
		selected_left_crate_idx = 0
		if not discovered_crates.is_empty():
			right_container_type = ContainerType.GROUND_CRATE
			selected_right_crate_idx = 0
		elif sled_inventory:
			right_container_type = ContainerType.SLED_CARGO_POD
			selected_right_crate_idx = 0
		else:
			right_container_type = ContainerType.NONE
			selected_right_crate_idx = -1
	else:
		# Mounted in sled
		left_container_type = ContainerType.PILOT_BACKPACK
		selected_left_crate_idx = 0
		if sled_inventory:
			right_container_type = ContainerType.SLED_CARGO_POD
			selected_right_crate_idx = 0
		elif not discovered_crates.is_empty():
			right_container_type = ContainerType.GROUND_CRATE
			selected_right_crate_idx = 0
		else:
			right_container_type = ContainerType.NONE
			selected_right_crate_idx = -1
	
	_refresh_container_panels()
	active_focus_panel = 0
	_update_panel_focus()
	
	is_open = true
	if root_control:
		root_control.visible = true

func close_inventory() -> void:
	if held_item:
		_cancel_drag()
	
	# Apply pseudo-gravity settling to all open containers
	if backpack_inventory:
		backpack_inventory.apply_pseudo_gravity_settling()
	if sled_inventory:
		sled_inventory.apply_pseudo_gravity_settling()
	for crate: GroundCrate in discovered_crates:
		if is_instance_valid(crate) and crate.inventory:
			crate.inventory.apply_pseudo_gravity_settling()
	
	if sled_com_component and is_instance_valid(sled_com_component):
		sled_com_component.recalculate_com()
	
	is_open = false
	if root_control:
		root_control.visible = false
	if left_grid_control:
		left_grid_control.clear_custom_drag_preview()
	if right_grid_control:
		right_grid_control.clear_custom_drag_preview()
	if floating_cursor_ghost:
		floating_cursor_ghost.queue_redraw()

func _discover_scene_inventories() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
		
	var pilot_nodes: Array[Node] = get_tree().get_nodes_in_group(&"player_pilot")
	var pilot: Pilot = pilot_nodes[0] as Pilot if not pilot_nodes.is_empty() else null
	
	discovered_crates.clear()
	backpack_inventory = null
	sled_inventory = null
	sled_com_component = null
	is_pilot_mounted = (pilot != null and pilot.is_mounted_in_sled)
	
	if pilot:
		backpack_inventory = pilot.get_node_or_null("BackpackInventoryComponent") as HexInventoryComponent
		
		# Only discover world crates when on foot (cannot access world crates from the sled)
		if not is_pilot_mounted:
			var crate_candidates: Array[Node] = get_tree().get_nodes_in_group(&"loot_crates")
			if crate_candidates.is_empty():
				crate_candidates = get_tree().root.find_children("*", "", true, false)
				
			for c: Node in crate_candidates:
				if c is GroundCrate and is_instance_valid(c):
					var crate: GroundCrate = c as GroundCrate
					# Only include breached / unlocked crates (UNLOOTED) in UI tabs
					if crate.crate_state != GroundCrate.CrateState.UNLOOTED:
						continue
					if crate.global_position.distance_to(pilot.global_position) <= 8.0:
						if not discovered_crates.has(crate):
							discovered_crates.append(crate)
							if not crate.crate_state_changed.is_connected(_on_crate_state_changed):
								crate.crate_state_changed.connect(_on_crate_state_changed)
						
			# Sort discovered crates by name for consistent UI tab ordering
			discovered_crates.sort_custom(func(a: GroundCrate, b: GroundCrate) -> bool:
				return a.name < b.name
			)
			
			if not discovered_crates.is_empty():
				selected_left_crate_idx = clampi(selected_left_crate_idx, 0, discovered_crates.size() - 1)
				selected_right_crate_idx = clampi(selected_right_crate_idx, 0, discovered_crates.size() - 1)
	
	var sled_nodes: Array[Node] = get_tree().get_nodes_in_group(&"player_sled")
	if not sled_nodes.is_empty() and is_instance_valid(sled_nodes[0]):
		var sled_node: Node3D = sled_nodes[0] as Node3D
		var is_mounted: bool = (pilot and pilot.is_mounted_in_sled)
		var is_near_sled: bool = is_mounted or (pilot and pilot.global_position.distance_to(sled_node.global_position) <= 4.0)
		
		if is_near_sled:
			sled_com_component = sled_node.get_node_or_null("CenterOfMassComponent") as CenterOfMassComponent
			if sled_com_component:
				sled_inventory = sled_com_component.get_node_or_null("CargoPodInventory") as HexInventoryComponent

func _on_crate_state_changed(_new_state: GroundCrate.CrateState) -> void:
	if is_open:
		_discover_scene_inventories()
		_refresh_container_panels()

func _are_containers_same(type_a: ContainerType, idx_a: int, type_b: ContainerType, idx_b: int) -> bool:
	if type_a == ContainerType.NONE or type_b == ContainerType.NONE:
		return false
	if type_a != type_b:
		return false
	if type_a == ContainerType.GROUND_CRATE:
		return idx_a == idx_b
	return true

func _on_left_tab_pressed(type: ContainerType, crate_idx: int) -> void:
	_set_left_container(type, crate_idx)

func _on_right_tab_pressed(type: ContainerType, crate_idx: int) -> void:
	_set_right_container(type, crate_idx)

func _set_left_container(type: ContainerType, crate_idx: int = -1) -> void:
	if held_item:
		_cancel_drag()
		
	# On sled, views are fixed to Backpack (Left) and Sled (Right)
	if is_pilot_mounted and type != ContainerType.PILOT_BACKPACK:
		return
		
	if type == ContainerType.SLED_CARGO_POD and sled_inventory == null:
		return
	if type == ContainerType.PILOT_BACKPACK and backpack_inventory == null:
		return
		
	var target_crate_idx: int = crate_idx if crate_idx >= 0 else selected_left_crate_idx
	
	# If already active on left: nothing to change
	if _are_containers_same(left_container_type, selected_left_crate_idx, type, target_crate_idx):
		return
		
	# If currently displayed on right: SWAP!
	if _are_containers_same(right_container_type, selected_right_crate_idx, type, target_crate_idx):
		var old_left_type: ContainerType = left_container_type
		var old_left_idx: int = selected_left_crate_idx
		
		left_container_type = right_container_type
		selected_left_crate_idx = selected_right_crate_idx
		
		right_container_type = old_left_type
		selected_right_crate_idx = old_left_idx
	else:
		left_container_type = type
		if crate_idx >= 0:
			selected_left_crate_idx = crate_idx
			
	_refresh_container_panels()

func _set_right_container(type: ContainerType, crate_idx: int = -1) -> void:
	if held_item:
		_cancel_drag()
		
	# On sled, views are fixed to Backpack (Left) and Sled (Right)
	if is_pilot_mounted and type != ContainerType.SLED_CARGO_POD:
		return
		
	if type == ContainerType.SLED_CARGO_POD and sled_inventory == null:
		return
	if type == ContainerType.PILOT_BACKPACK and backpack_inventory == null:
		return
		
	var target_crate_idx: int = crate_idx if crate_idx >= 0 else selected_right_crate_idx
	
	# If already active on right: nothing to change
	if _are_containers_same(right_container_type, selected_right_crate_idx, type, target_crate_idx):
		return
		
	# If currently displayed on left: SWAP!
	if _are_containers_same(left_container_type, selected_left_crate_idx, type, target_crate_idx):
		var old_right_type: ContainerType = right_container_type
		var old_right_idx: int = selected_right_crate_idx
		
		right_container_type = left_container_type
		selected_right_crate_idx = selected_left_crate_idx
		
		left_container_type = old_right_type
		selected_left_crate_idx = old_right_idx
	else:
		right_container_type = type
		if crate_idx >= 0:
			selected_right_crate_idx = crate_idx
			
	_refresh_container_panels()

func _refresh_container_panels() -> void:
	# 1. Bind left container
	var left_inv: HexInventoryComponent = _get_inventory_by_type(left_container_type, true)
	if left_grid_control:
		left_grid_control.set_inventory(left_inv)
		left_grid_control.visible = (left_inv != null)
	_update_load_label(left_load_label, left_inv, left_container_type, true)
	
	# 2. Bind right container
	var right_inv: HexInventoryComponent = _get_inventory_by_type(right_container_type, false)
	if right_grid_control:
		right_grid_control.set_inventory(right_inv)
		right_grid_control.visible = (right_inv != null)
	_update_load_label(right_load_label, right_inv, right_container_type, false)
	
	# 3. Rebuild tab bars
	_rebuild_tab_bar(left_tab_bar, true)
	_rebuild_tab_bar(right_tab_bar, false)
	
	# 4. Center Panel & COM visualizer
	if sled_com_component and is_instance_valid(sled_com_component) and sled_inventory != null:
		sled_com_component.recalculate_com()
		if balance_title:
			balance_title.text = "SLED BALANCE"
			balance_title.visible = true
		if com_widget:
			com_widget.update_com_data(
				sled_com_component.current_total_mass_kg,
				Vector2(sled_com_component.current_com_offset_3d.x, sled_com_component.current_com_offset_3d.y)
			)
			com_widget.visible = true
	elif backpack_inventory != null:
		if balance_title:
			balance_title.text = "PILOT BACKPACK"
			balance_title.visible = true
		if com_widget:
			var bp_mass: float = backpack_inventory.get_total_items_mass()
			var bp_com: Vector2 = backpack_inventory.get_com_offset_2d()
			com_widget.update_com_data(bp_mass, bp_com)
			com_widget.visible = true
	else:
		if balance_title:
			balance_title.visible = false
		if com_widget:
			com_widget.visible = false

func _rebuild_tab_bar(tab_bar: HBoxContainer, is_left: bool) -> void:
	if not tab_bar:
		return
		
	# Clear existing tab buttons immediately
	for child: Node in tab_bar.get_children():
		tab_bar.remove_child(child)
		child.queue_free()
		
	var active_type: ContainerType = left_container_type if is_left else right_container_type
	var selected_crate_idx: int = selected_left_crate_idx if is_left else selected_right_crate_idx
	
	var other_type: ContainerType = right_container_type if is_left else left_container_type
	var other_crate_idx: int = selected_right_crate_idx if is_left else selected_left_crate_idx
	
	# If mounted in sled, views are fixed: Left is Backpack, Right is Sled
	if is_pilot_mounted:
		if is_left and backpack_inventory != null:
			var bp_btn: Button = Button.new()
			bp_btn.name = "BackpackTab"
			bp_btn.custom_minimum_size = Vector2(0, 26)
			bp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bp_btn.text = "Backpack"
			bp_btn.focus_mode = Control.FOCUS_NONE
			bp_btn.add_theme_stylebox_override(&"normal", active_tab_style)
			bp_btn.add_theme_stylebox_override(&"hover", active_tab_style)
			bp_btn.add_theme_stylebox_override(&"pressed", active_tab_style)
			tab_bar.add_child(bp_btn)
		elif not is_left and sled_inventory != null:
			var sled_btn: Button = Button.new()
			sled_btn.name = "SledTab"
			sled_btn.custom_minimum_size = Vector2(0, 26)
			sled_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sled_btn.text = "Sled"
			sled_btn.focus_mode = Control.FOCUS_NONE
			sled_btn.add_theme_stylebox_override(&"normal", active_tab_style)
			sled_btn.add_theme_stylebox_override(&"hover", active_tab_style)
			sled_btn.add_theme_stylebox_override(&"pressed", active_tab_style)
			tab_bar.add_child(sled_btn)
		return
	
	# If this is the right panel and no secondary containers exist (no crates, no sled), don't show tabs on right
	if not is_left and discovered_crates.is_empty() and sled_inventory == null:
		return
		
	# 1. Add discovered Crate tabs (excluding whichever crate is currently active on the other panel)
	for i: int in range(discovered_crates.size()):
		var crate: GroundCrate = discovered_crates[i]
		if not is_instance_valid(crate):
			continue
			
		# Do not show option if this crate is already selected on the opposite panel
		if other_type == ContainerType.GROUND_CRATE and other_crate_idx == i:
			continue
			
		var is_this_active: bool = (active_type == ContainerType.GROUND_CRATE and selected_crate_idx == i)
		
		var btn: Button = Button.new()
		btn.name = "CrateTab_%d" % i
		btn.custom_minimum_size = Vector2(0, 26)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = _format_crate_tab_name(crate, i)
		btn.focus_mode = Control.FOCUS_NONE
		
		btn.add_theme_stylebox_override(&"normal", active_tab_style if is_this_active else inactive_tab_style)
		btn.add_theme_stylebox_override(&"hover", active_tab_style if is_this_active else inactive_tab_style)
		btn.add_theme_stylebox_override(&"pressed", active_tab_style)
		
		if is_left:
			btn.pressed.connect(_on_left_tab_pressed.bind(ContainerType.GROUND_CRATE, i))
		else:
			btn.pressed.connect(_on_right_tab_pressed.bind(ContainerType.GROUND_CRATE, i))
		tab_bar.add_child(btn)
		
	# 2. Add Backpack Tab (exclude if already selected on the opposite panel)
	if backpack_inventory != null:
		if other_type != ContainerType.PILOT_BACKPACK:
			var is_backpack_active: bool = (active_type == ContainerType.PILOT_BACKPACK)
			var bp_btn: Button = Button.new()
			bp_btn.name = "BackpackTab"
			bp_btn.custom_minimum_size = Vector2(0, 26)
			bp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bp_btn.text = "Backpack"
			bp_btn.focus_mode = Control.FOCUS_NONE
			bp_btn.add_theme_stylebox_override(&"normal", active_tab_style if is_backpack_active else inactive_tab_style)
			bp_btn.add_theme_stylebox_override(&"hover", active_tab_style if is_backpack_active else inactive_tab_style)
			bp_btn.add_theme_stylebox_override(&"pressed", active_tab_style)
			if is_left:
				bp_btn.pressed.connect(_on_left_tab_pressed.bind(ContainerType.PILOT_BACKPACK, -1))
			else:
				bp_btn.pressed.connect(_on_right_tab_pressed.bind(ContainerType.PILOT_BACKPACK, -1))
			tab_bar.add_child(bp_btn)
	
	# 3. Add Sled Tab ONLY if sled is within interaction range (exclude if already selected on opposite panel)
	if sled_inventory != null:
		if other_type != ContainerType.SLED_CARGO_POD:
			var is_sled_active: bool = (active_type == ContainerType.SLED_CARGO_POD)
			var sled_btn: Button = Button.new()
			sled_btn.name = "SledTab"
			sled_btn.custom_minimum_size = Vector2(0, 26)
			sled_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sled_btn.text = "Sled"
			sled_btn.focus_mode = Control.FOCUS_NONE
			sled_btn.add_theme_stylebox_override(&"normal", active_tab_style if is_sled_active else inactive_tab_style)
			sled_btn.add_theme_stylebox_override(&"hover", active_tab_style if is_sled_active else inactive_tab_style)
			sled_btn.add_theme_stylebox_override(&"pressed", active_tab_style)
			if is_left:
				sled_btn.pressed.connect(_on_left_tab_pressed.bind(ContainerType.SLED_CARGO_POD, -1))
			else:
				sled_btn.pressed.connect(_on_right_tab_pressed.bind(ContainerType.SLED_CARGO_POD, -1))
			tab_bar.add_child(sled_btn)

func _format_crate_tab_name(crate: GroundCrate, idx: int) -> String:
	if crate.name.begins_with("VaultCrate"):
		var suffix: String = crate.name.replace("VaultCrate", "")
		return "Vault %s" % suffix
	return "Crate #%d" % (idx + 1)

func _update_load_label(lbl: Label, inv: HexInventoryComponent, type: ContainerType, is_left: bool) -> void:
	if not lbl:
		return
	if type == ContainerType.NONE or not inv:
		if type == ContainerType.NONE:
			lbl.text = ""
			return
		if type == ContainerType.GROUND_CRATE:
			lbl.text = "NO CRATE ATTACHED"
			lbl.add_theme_color_override(&"font_color", Color(0.6, 0.6, 0.6, 0.8))
		else:
			lbl.text = "NO CONTAINER ATTACHED"
			lbl.add_theme_color_override(&"font_color", Color(0.6, 0.6, 0.6, 0.8))
		return
	
	var mass: float = inv.get_total_items_mass()
	var tier: StringName = inv.get_encumbrance_tier()
	
	match tier:
		&"overburdened":
			lbl.text = "Payload: %.1f kg [OVERBURDENED - High Tipping Risk]" % mass
			lbl.add_theme_color_override(&"font_color", Color(1.0, 0.25, 0.2, 1.0))
		&"encumbered":
			lbl.text = "Payload: %.1f kg [HEAVY LOAD - Reduced Agility]" % mass
			lbl.add_theme_color_override(&"font_color", Color(1.0, 0.75, 0.2, 1.0))
		_:
			lbl.text = "Payload: %.1f kg [NOMINAL LOAD]" % mass
			lbl.add_theme_color_override(&"font_color", Color(0.3, 0.85, 0.4, 1.0))

func _get_inventory_by_type(type: ContainerType, is_left: bool) -> HexInventoryComponent:
	match type:
		ContainerType.GROUND_CRATE:
			var idx: int = selected_left_crate_idx if is_left else selected_right_crate_idx
			if idx >= 0 and idx < discovered_crates.size():
				var crate: GroundCrate = discovered_crates[idx]
				if is_instance_valid(crate) and crate.crate_state == GroundCrate.CrateState.UNLOOTED:
					return crate.get_node_or_null("HexInventoryComponent") as HexInventoryComponent
			return null
		ContainerType.PILOT_BACKPACK:
			return backpack_inventory
		ContainerType.SLED_CARGO_POD:
			return sled_inventory
		ContainerType.NONE:
			return null
	return null

func _update_panel_focus() -> void:
	if right_container_type == ContainerType.NONE:
		active_focus_panel = 0
	if left_grid_control:
		left_grid_control.is_active_focus = (active_focus_panel == 0)
		left_grid_control.queue_redraw()
	if right_grid_control:
		right_grid_control.is_active_focus = (active_focus_panel == 1 and right_container_type != ContainerType.NONE)
		right_grid_control.queue_redraw()

func _start_dragging(item: HexItemData, source_inv: HexInventoryComponent, source_slot: Vector2i) -> void:
	held_item = item
	held_rotation_step = item.rotation_step
	source_inv_for_drag = source_inv
	source_slot_for_drag = source_slot
	source_inv.remove_item(item)
	if left_grid_control:
		left_grid_control.queue_redraw()
	if right_grid_control:
		right_grid_control.queue_redraw()
	_refresh_container_panels()
	_update_tooltip(held_item)

func _rotate_held_item() -> void:
	if not held_item:
		return
	held_rotation_step = (held_rotation_step + 1) % 6
	var active_grid: HexGridControl = left_grid_control if active_focus_panel == 0 else right_grid_control
	if active_grid and active_grid.grid_inventory:
		var slot: Vector2i = active_grid.hovered_cell if active_grid.is_mouse_inside else active_grid.cursor_cell
		var is_valid: bool = active_grid.grid_inventory.can_place_item(held_item, slot, held_rotation_step)
		active_grid.set_custom_drag_preview(held_item, held_rotation_step, slot, is_valid)

func _try_drop_item(grid: HexGridControl, cell: Vector2i) -> void:
	if not held_item or not grid or not grid.grid_inventory:
		return
	
	if grid.grid_inventory.can_place_item(held_item, cell, held_rotation_step):
		var dropped_item: HexItemData = held_item
		var rot: int = held_rotation_step
		held_item = null
		source_inv_for_drag = null
		grid.grid_inventory.place_item(dropped_item, cell, rot)
		if left_grid_control:
			left_grid_control.clear_custom_drag_preview()
			left_grid_control.queue_redraw()
		if right_grid_control:
			right_grid_control.clear_custom_drag_preview()
			right_grid_control.queue_redraw()
		_refresh_container_panels()
		if floating_cursor_ghost:
			floating_cursor_ghost.queue_redraw()
		_update_tooltip(null)

func _quick_transfer_item(item: HexItemData, source_inv: HexInventoryComponent) -> void:
	var destination: HexInventoryComponent = null
	var left_inv: HexInventoryComponent = _get_inventory_by_type(left_container_type, true)
	var right_inv: HexInventoryComponent = _get_inventory_by_type(right_container_type, false)
	
	if source_inv == left_inv:
		destination = right_inv
	else:
		destination = left_inv
	
	if not destination:
		return
	
	for slot: Vector2i in destination.available_slots:
		for rot: int in range(6):
			if destination.can_place_item(item, slot, rot):
				source_inv.remove_item(item)
				destination.place_item(item, slot, rot)
				if left_grid_control:
					left_grid_control.queue_redraw()
				if right_grid_control:
					right_grid_control.queue_redraw()
				_refresh_container_panels()
				_update_tooltip(null)
				return

func _cancel_drag() -> void:
	if held_item and source_inv_for_drag:
		source_inv_for_drag.place_item(held_item, source_slot_for_drag, held_item.rotation_step)
	held_item = null
	source_inv_for_drag = null
	if left_grid_control:
		left_grid_control.clear_custom_drag_preview()
		left_grid_control.queue_redraw()
	if right_grid_control:
		right_grid_control.clear_custom_drag_preview()
		right_grid_control.queue_redraw()
	_refresh_container_panels()
	if floating_cursor_ghost:
		floating_cursor_ghost.queue_redraw()
	_update_tooltip(null)

func _update_tooltip(item: HexItemData) -> void:
	if not tooltip_name or not tooltip_mass or not tooltip_desc:
		return
	if item:
		tooltip_name.text = item.item_name
		tooltip_mass.text = "Mass: %.1f kg" % item.mass_kg
		tooltip_desc.text = "%s\nFootprint: %d cells\n[Shift+LMB / Y] Quick Loot\n[R / X] Rotate 60°" % [item.description, item.hex_footprint.size()]
	else:
		tooltip_name.text = "NO SELECTION"
		tooltip_mass.text = "Mass: --"
		tooltip_desc.text = "[A / LMB] Pick / Stamp\n[LB / RB] Switch Panel\n[R / X] Rotate 60°\n[Y / Shift+LMB] Quick Loot"
