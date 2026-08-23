class_name HexInventoryUI
extends CanvasLayer

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

enum ContainerType {
	GROUND_CRATE,
	PILOT_BACKPACK,
	SLED_CARGO_POD
}

@export var is_open: bool = false

# Container Components
var crate_inventory: HexInventoryComponent = null
var backpack_inventory: HexInventoryComponent = null
var sled_inventory: HexInventoryComponent = null

var left_container_type: ContainerType = ContainerType.GROUND_CRATE
var right_container_type: ContainerType = ContainerType.SLED_CARGO_POD

# Focus & Drag State
var active_focus_panel: int = 0 # 0 = Left, 1 = Right
var held_item: HexItemData = null
var held_rotation_step: int = 0
var source_inv_for_drag: HexInventoryComponent = null
var source_slot_for_drag: Vector2i = Vector2i(-999, -999)

@onready var root_control: Control = $RootControl
@onready var left_grid_control: HexGridControl = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LeftContainer/HexGridControl
@onready var right_grid_control: HexGridControl = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RightContainer/HexGridControl
@onready var left_tab_btn: Button = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LeftContainer/Header/TabButton
@onready var right_tab_btn: Button = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RightContainer/Header/TabButton
@onready var com_widget: COMVisualizerWidget = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/COMVisualizerWidget
@onready var tooltip_name: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemNameLabel
@onready var tooltip_mass: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemMassLabel
@onready var tooltip_desc: Label = $RootControl/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemDescLabel
@onready var floating_cursor_ghost: Control = $RootControl/FloatingCursorGhost

func _ready() -> void:
	root_control.visible = is_open
	_setup_grid_listeners(left_grid_control)
	_setup_grid_listeners(right_grid_control)
	if floating_cursor_ghost:
		floating_cursor_ghost.draw.connect(_on_draw_floating_ghost)
	
	if left_tab_btn:
		left_tab_btn.pressed.connect(_cycle_left_container)
	if right_tab_btn:
		right_tab_btn.pressed.connect(_cycle_right_container)

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
			# Target cell or hovered fallback
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
		# Rotation via [R] or Lean Right [E]
		if event.is_action_pressed(&"pilot_lean_right") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_R):
			if held_item:
				_rotate_held_item()
		
		# Bumper Panel Switch [Q / E / Tab]
		elif event.is_action_pressed(&"pilot_lean_left") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB):
			active_focus_panel = 1 - active_focus_panel
			_update_panel_focus()
			# Update preview on the newly focused grid
			var active_grid: HexGridControl = left_grid_control if active_focus_panel == 0 else right_grid_control
			if held_item and active_grid and active_grid.grid_inventory:
				var is_valid: bool = active_grid.grid_inventory.can_place_item(held_item, active_grid.cursor_cell, held_rotation_step)
				active_grid.set_custom_drag_preview(held_item, held_rotation_step, active_grid.cursor_cell, is_valid)

func open_contextual_inventory() -> void:
	_discover_scene_inventories()
	
	# Determine smart default panels
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
	backpack_inventory = null
	sled_inventory = null
	
	if pilot:
		backpack_inventory = pilot.get_node_or_null("BackpackInventoryComponent") as HexInventoryComponent
		
		# Find nearest crate within 4.5m
		var all_crates: Array[Node] = get_tree().root.find_children("*Crate*", "GroundCrate", true, false)
		for c: Node in all_crates:
			if c is Node3D and is_instance_valid(c):
				if (c as Node3D).global_position.distance_to(pilot.global_position) <= 4.5:
					crate_inventory = c.get_node_or_null("HexInventoryComponent") as HexInventoryComponent
					break
	
	var sled_nodes: Array[Node] = get_tree().get_nodes_in_group(&"player_sled")
	if not sled_nodes.is_empty() and is_instance_valid(sled_nodes[0]):
		sled_inventory = sled_nodes[0].get_node_or_null("CenterOfMassComponent/CargoPodInventory") as HexInventoryComponent

func _refresh_container_panels() -> void:
	# Left container binding
	var left_inv: HexInventoryComponent = _get_inventory_by_type(left_container_type)
	left_grid_control.set_inventory(left_inv)
	if left_tab_btn:
		left_tab_btn.text = _get_type_title(left_container_type)
	
	# Right container binding
	var right_inv: HexInventoryComponent = _get_inventory_by_type(right_container_type)
	right_grid_control.set_inventory(right_inv)
	if right_tab_btn:
		right_tab_btn.text = _get_type_title(right_container_type)

func _get_inventory_by_type(type: ContainerType) -> HexInventoryComponent:
	match type:
		ContainerType.GROUND_CRATE: return crate_inventory
		ContainerType.PILOT_BACKPACK: return backpack_inventory
		ContainerType.SLED_CARGO_POD: return sled_inventory
	return null

func _get_type_title(type: ContainerType) -> String:
	match type:
		ContainerType.GROUND_CRATE: return "GROUND CRATE"
		ContainerType.PILOT_BACKPACK: return "PILOT BACKPACK"
		ContainerType.SLED_CARGO_POD: return "SLED CARGO POD"
	return "CONTAINER"

func _cycle_left_container() -> void:
	left_container_type = (left_container_type + 1) % 3 as ContainerType
	_refresh_container_panels()

func _cycle_right_container() -> void:
	right_container_type = (right_container_type + 1) % 3 as ContainerType
	_refresh_container_panels()

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
		tooltip_desc.text = "[A / LMB] Pick / Stamp\n[LB / RB / Q / E] Switch Panel\n[R / X] Rotate 60°\n[Shift+LMB / Y] Quick Loot"
