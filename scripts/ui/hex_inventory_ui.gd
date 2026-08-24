class_name HexInventoryUI
extends CanvasLayer

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

enum ContainerType {
	GROUND_CRATE = 0,
	PILOT_BACKPACK = 1,
	SLED_CARGO_POD = 2
}

@export var is_open: bool = false

# Container Components
var crate_inventory: HexInventoryComponent = null
var nearby_locked_crate: GroundCrate = null
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

@onready var left_crate_tab: Button = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LeftContainer/LeftTabBar/CrateTab
@onready var left_backpack_tab: Button = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LeftContainer/LeftTabBar/BackpackTab
@onready var left_sled_tab: Button = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LeftContainer/LeftTabBar/SledTab

@onready var right_crate_tab: Button = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RightContainer/RightTabBar/CrateTab
@onready var right_backpack_tab: Button = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RightContainer/RightTabBar/BackpackTab
@onready var right_sled_tab: Button = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RightContainer/RightTabBar/SledTab

@onready var com_widget: COMVisualizerWidget = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/COMVisualizerWidget
@onready var tooltip_name: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemNameLabel
@onready var tooltip_mass: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemMassLabel
@onready var tooltip_desc: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemDescLabel
@onready var floating_cursor_ghost: Control = $RootControl/FloatingCursorGhost

func _ready() -> void:
	root_control.visible = is_open
	_init_tab_styles()
	_setup_grid_listeners(left_grid_control)
	_setup_grid_listeners(right_grid_control)
	if floating_cursor_ghost:
		floating_cursor_ghost.draw.connect(_on_draw_floating_ghost)
	
	# Left tab signals
	if left_crate_tab:
		left_crate_tab.pressed.connect(func() -> void: _set_left_container(ContainerType.GROUND_CRATE))
	if left_backpack_tab:
		left_backpack_tab.pressed.connect(func() -> void: _set_left_container(ContainerType.PILOT_BACKPACK))
	if left_sled_tab:
		left_sled_tab.pressed.connect(func() -> void: _set_left_container(ContainerType.SLED_CARGO_POD))
	
	# Right tab signals
	if right_crate_tab:
		right_crate_tab.pressed.connect(func() -> void: _set_right_container(ContainerType.GROUND_CRATE))
	if right_backpack_tab:
		right_backpack_tab.pressed.connect(func() -> void: _set_right_container(ContainerType.PILOT_BACKPACK))
	if right_sled_tab:
		right_sled_tab.pressed.connect(func() -> void: _set_right_container(ContainerType.SLED_CARGO_POD))

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
	if is_open and held_item and floating_cursor_ghost:
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
		var center: Vector2 = left_grid_control.hex_to_pixel(offset_pt)
		var poly: PackedVector2Array = left_grid_control.get_hex_polygon(center, radius * 0.85)
		floating_cursor_ghost.draw_colored_polygon(poly, color)
		floating_cursor_ghost.draw_polyline(poly, Color(1, 1, 1, 0.8), 1.5, true)

func _setup_grid_listeners(grid: HexGridControl) -> void:
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
	if event.is_action_pressed(&"pause_inventory") or event.is_action_pressed(&"ui_cancel"):
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
		
		elif event.is_action_pressed(&"pilot_lean_left") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB):
			active_focus_panel = 1 - active_focus_panel
			_update_panel_focus()
			var active_grid: HexGridControl = left_grid_control if active_focus_panel == 0 else right_grid_control
			if held_item and active_grid and active_grid.grid_inventory:
				var is_valid: bool = active_grid.grid_inventory.can_place_item(held_item, active_grid.cursor_cell, held_rotation_step)
				active_grid.set_custom_drag_preview(held_item, held_rotation_step, active_grid.cursor_cell, is_valid)

func open_contextual_inventory() -> void:
	_discover_scene_inventories()
	
	if crate_inventory:
		left_container_type = ContainerType.GROUND_CRATE
		right_container_type = ContainerType.SLED_CARGO_POD if sled_inventory else ContainerType.PILOT_BACKPACK
	else:
		left_container_type = ContainerType.PILOT_BACKPACK
		right_container_type = ContainerType.SLED_CARGO_POD
	
	_refresh_container_panels()
	active_focus_panel = 0
	_update_panel_focus()
	
	is_open = true
	root_control.visible = true

func close_inventory() -> void:
	if held_item:
		_cancel_drag()
	
	# Apply pseudo-gravity settling to all open containers
	if backpack_inventory:
		backpack_inventory.apply_pseudo_gravity_settling()
	if sled_inventory:
		sled_inventory.apply_pseudo_gravity_settling()
	if crate_inventory:
		crate_inventory.apply_pseudo_gravity_settling()
	
	if sled_com_component and is_instance_valid(sled_com_component):
		sled_com_component.recalculate_com()
	
	is_open = false
	root_control.visible = false
	left_grid_control.clear_custom_drag_preview()
	right_grid_control.clear_custom_drag_preview()
	if floating_cursor_ghost:
		floating_cursor_ghost.queue_redraw()

func _discover_scene_inventories() -> void:
	var pilot_nodes: Array[Node] = get_tree().get_nodes_in_group(&"player_pilot")
	var pilot: Pilot = pilot_nodes[0] as Pilot if not pilot_nodes.is_empty() else null
	
	crate_inventory = null
	nearby_locked_crate = null
	backpack_inventory = null
	sled_inventory = null
	sled_com_component = null
	
	if pilot:
		backpack_inventory = pilot.get_node_or_null("BackpackInventoryComponent") as HexInventoryComponent
		
		var all_crates: Array[Node] = get_tree().root.find_children("*Crate*", "GroundCrate", true, false)
		for c: Node in all_crates:
			if c is GroundCrate and is_instance_valid(c):
				var crate: GroundCrate = c as GroundCrate
				if crate.global_position.distance_to(pilot.global_position) <= 4.5:
					if not crate.is_locked:
						crate_inventory = crate.get_node_or_null("HexInventoryComponent") as HexInventoryComponent
						break
					else:
						nearby_locked_crate = crate
	
	var sled_nodes: Array[Node] = get_tree().get_nodes_in_group(&"player_sled")
	if not sled_nodes.is_empty() and is_instance_valid(sled_nodes[0]):
		var sled_node: Node3D = sled_nodes[0] as Node3D
		var is_mounted: bool = (pilot and pilot.is_mounted_in_sled)
		var is_near_sled: bool = is_mounted or (pilot and pilot.global_position.distance_to(sled_node.global_position) <= 4.0)
		
		if is_near_sled:
			sled_com_component = sled_node.get_node_or_null("CenterOfMassComponent") as CenterOfMassComponent
			if sled_com_component:
				sled_inventory = sled_com_component.get_node_or_null("CargoPodInventory") as HexInventoryComponent

func _set_left_container(type: ContainerType) -> void:
	left_container_type = type
	if right_container_type == left_container_type:
		for alt: int in [ContainerType.SLED_CARGO_POD, ContainerType.PILOT_BACKPACK, ContainerType.GROUND_CRATE]:
			if alt != int(left_container_type):
				right_container_type = alt as ContainerType
				break
	_refresh_container_panels()

func _set_right_container(type: ContainerType) -> void:
	right_container_type = type
	if left_container_type == right_container_type:
		for alt: int in [ContainerType.GROUND_CRATE, ContainerType.PILOT_BACKPACK, ContainerType.SLED_CARGO_POD]:
			if alt != int(right_container_type):
				left_container_type = alt as ContainerType
				break
	_refresh_container_panels()

func _refresh_container_panels() -> void:
	# 1. Bind left container
	var left_inv: HexInventoryComponent = _get_inventory_by_type(left_container_type)
	left_grid_control.set_inventory(left_inv)
	_update_load_label(left_load_label, left_inv, left_container_type)
	
	# 2. Bind right container
	var right_inv: HexInventoryComponent = _get_inventory_by_type(right_container_type)
	right_grid_control.set_inventory(right_inv)
	_update_load_label(right_load_label, right_inv, right_container_type)
	
	# 3. Update tab buttons
	_update_tab_buttons()
	
	# 4. Explicitly update Sled COM visualizer
	if sled_com_component and is_instance_valid(sled_com_component):
		sled_com_component.recalculate_com()
		if com_widget:
			com_widget.update_com_data(
				sled_com_component.current_total_mass_kg,
				Vector2(sled_com_component.current_com_offset_3d.x, sled_com_component.current_com_offset_3d.y)
			)

func _update_tab_buttons() -> void:
	var crate_available: bool = (crate_inventory != null)
	var crate_btn_text: String = "Crate" if not nearby_locked_crate else "Crate [LOCKED]"
	
	if left_crate_tab:
		left_crate_tab.text = crate_btn_text
	if right_crate_tab:
		right_crate_tab.text = crate_btn_text
	
	_apply_tab_style(left_crate_tab, left_container_type == ContainerType.GROUND_CRATE, crate_available and right_container_type != ContainerType.GROUND_CRATE)
	_apply_tab_style(left_backpack_tab, left_container_type == ContainerType.PILOT_BACKPACK, backpack_inventory != null and right_container_type != ContainerType.PILOT_BACKPACK)
	_apply_tab_style(left_sled_tab, left_container_type == ContainerType.SLED_CARGO_POD, sled_inventory != null and right_container_type != ContainerType.SLED_CARGO_POD)
	
	_apply_tab_style(right_crate_tab, right_container_type == ContainerType.GROUND_CRATE, crate_available and left_container_type != ContainerType.GROUND_CRATE)
	_apply_tab_style(right_backpack_tab, right_container_type == ContainerType.PILOT_BACKPACK, backpack_inventory != null and left_container_type != ContainerType.PILOT_BACKPACK)
	_apply_tab_style(right_sled_tab, right_container_type == ContainerType.SLED_CARGO_POD, sled_inventory != null and left_container_type != ContainerType.SLED_CARGO_POD)

func _apply_tab_style(btn: Button, is_active: bool, is_available: bool) -> void:
	if not btn:
		return
	btn.visible = is_available or is_active or (nearby_locked_crate != null and btn.name.begins_with("Crate"))
	btn.disabled = not is_available and not is_active
	btn.add_theme_stylebox_override(&"normal", active_tab_style if is_active else inactive_tab_style)

func _update_load_label(lbl: Label, inv: HexInventoryComponent, type: ContainerType) -> void:
	if not lbl:
		return
	if not inv:
		if type == ContainerType.GROUND_CRATE and nearby_locked_crate:
			lbl.text = "CRATE LOCKED - BREACH LOCK TO ACCESS"
			lbl.add_theme_color_override(&"font_color", Color(1.0, 0.3, 0.3, 1.0))
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

func _get_inventory_by_type(type: ContainerType) -> HexInventoryComponent:
	match type:
		ContainerType.GROUND_CRATE: return crate_inventory
		ContainerType.PILOT_BACKPACK: return backpack_inventory
		ContainerType.SLED_CARGO_POD: return sled_inventory
	return null

func _update_panel_focus() -> void:
	left_grid_control.is_active_focus = (active_focus_panel == 0)
	right_grid_control.is_active_focus = (active_focus_panel == 1)
	left_grid_control.queue_redraw()
	right_grid_control.queue_redraw()

func _start_dragging(item: HexItemData, source_inv: HexInventoryComponent, source_slot: Vector2i) -> void:
	held_item = item
	held_rotation_step = item.rotation_step
	source_inv_for_drag = source_inv
	source_slot_for_drag = source_slot
	source_inv.remove_item(item)
	left_grid_control.queue_redraw()
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
		left_grid_control.clear_custom_drag_preview()
		right_grid_control.clear_custom_drag_preview()
		left_grid_control.queue_redraw()
		right_grid_control.queue_redraw()
		_refresh_container_panels()
		if floating_cursor_ghost:
			floating_cursor_ghost.queue_redraw()
		_update_tooltip(null)

func _quick_transfer_item(item: HexItemData, source_inv: HexInventoryComponent) -> void:
	var destination: HexInventoryComponent = null
	var left_inv: HexInventoryComponent = _get_inventory_by_type(left_container_type)
	var right_inv: HexInventoryComponent = _get_inventory_by_type(right_container_type)
	
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
				left_grid_control.queue_redraw()
				right_grid_control.queue_redraw()
				_refresh_container_panels()
				_update_tooltip(null)
				return

func _cancel_drag() -> void:
	if held_item and source_inv_for_drag:
		source_inv_for_drag.place_item(held_item, source_slot_for_drag, held_item.rotation_step)
	held_item = null
	source_inv_for_drag = null
	left_grid_control.clear_custom_drag_preview()
	right_grid_control.clear_custom_drag_preview()
	left_grid_control.queue_redraw()
	right_grid_control.queue_redraw()
	_refresh_container_panels()
	if floating_cursor_ghost:
		floating_cursor_ghost.queue_redraw()
	_update_tooltip(null)

func _update_tooltip(item: HexItemData) -> void:
	if item:
		tooltip_name.text = item.item_name
		tooltip_mass.text = "Mass: %.1f kg" % item.mass_kg
		tooltip_desc.text = "%s\nFootprint: %d cells\n[Shift+LMB / Y] Quick Loot\n[R / X] Rotate 60°" % [item.description, item.hex_footprint.size()]
	else:
		tooltip_name.text = "NO SELECTION"
		tooltip_mass.text = "Mass: --"
		tooltip_desc.text = "[A / LMB] Pick / Stamp\n[LB / RB] Switch Panel\n[R / X] Rotate 60°\n[Y / Shift+LMB] Quick Loot"
