class_name HexInventoryUI
extends CanvasLayer

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

@export var is_open: bool = false

# Current active inventories
@export var source_container: HexInventoryComponent = null
@export var target_container: HexInventoryComponent = null

# Drag & Drop State
var held_item: HexItemData = null
var held_rotation_step: int = 0
var source_inv_for_drag: HexInventoryComponent = null
var source_slot_for_drag: Vector2i = Vector2i(-999, -999)

@onready var root_control: Control = $RootControl
@onready var left_grid_control: HexGridControl = $RootControl/PanelContainer/MarginContainer/HBoxContainer/LeftContainer/HexGridControl
@onready var right_grid_control: HexGridControl = $RootControl/PanelContainer/MarginContainer/HBoxContainer/RightContainer/HexGridControl
@onready var left_title: Label = $RootControl/PanelContainer/MarginContainer/HBoxContainer/LeftContainer/TitleLabel
@onready var right_title: Label = $RootControl/PanelContainer/MarginContainer/HBoxContainer/RightContainer/TitleLabel
@onready var com_widget: COMVisualizerWidget = $RootControl/PanelContainer/MarginContainer/HBoxContainer/CenterPanel/COMVisualizerWidget
@onready var tooltip_name: Label = $RootControl/PanelContainer/MarginContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemNameLabel
@onready var tooltip_mass: Label = $RootControl/PanelContainer/MarginContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemMassLabel
@onready var tooltip_desc: Label = $RootControl/PanelContainer/MarginContainer/HBoxContainer/CenterPanel/TooltipPanel/VBoxContainer/ItemDescLabel

func _ready() -> void:
	root_control.visible = is_open
	_setup_grid_listeners(left_grid_control)
	_setup_grid_listeners(right_grid_control)

func _setup_grid_listeners(grid: HexGridControl) -> void:
	grid.item_picked.connect(func(item: HexItemData, slot: Vector2i) -> void:
		_start_dragging(item, grid.grid_inventory, slot)
	)
	grid.cell_clicked.connect(func(cell: Vector2i, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT and held_item:
			_try_drop_item(grid, cell)
		elif button == MOUSE_BUTTON_RIGHT and held_item:
			_rotate_held_item()
	)
	grid.cell_hovered.connect(func(cell: Vector2i) -> void:
		if held_item and grid.grid_inventory:
			var is_valid: bool = grid.grid_inventory.can_place_item(held_item, cell, held_rotation_step)
			grid.set_custom_drag_preview(held_item, held_rotation_step, cell, is_valid)
		elif grid.grid_inventory:
			var item: HexItemData = grid.grid_inventory.get_item_at(cell)
			_update_tooltip(item)
	)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_inventory") or event.is_action_pressed(&"ui_cancel"):
		if is_open:
			if held_item:
				_cancel_drag()
			else:
				close_inventory()
		else:
			open_contextual_inventory()
	
	elif is_open and (event.is_action_pressed(&"pilot_lean_right") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_R)):
		if held_item:
			_rotate_held_item()

func open_contextual_inventory() -> void:
	# Search for nearby loot crate / sled / backpack
	var pilot_nodes: Array[Node] = get_tree().get_nodes_in_group(&"player_pilot")
	var pilot: Pilot = pilot_nodes[0] as Pilot if not pilot_nodes.is_empty() else null
	
	var crate_comp: HexInventoryComponent = null
	var sled_comp: HexInventoryComponent = null
	var backpack_comp: HexInventoryComponent = null
	
	if pilot:
		backpack_comp = pilot.get_node_or_null("BackpackInventoryComponent") as HexInventoryComponent
		
		# Check nearby crates
		var crates: Array[Node] = get_tree().get_nodes_in_group(&"loot_crates")
		if crates.is_empty():
			# Try finding GroundCrate nodes directly
			var all_crates: Array[Node] = get_tree().root.find_children("*Crate*", "GroundCrate", true, false)
			for c: Node in all_crates:
				if c is Node3D and is_instance_valid(c):
					if (c as Node3D).global_position.distance_to(pilot.global_position) <= 4.0:
						crate_comp = c.get_node_or_null("HexInventoryComponent") as HexInventoryComponent
						break
	
	# Check sled inventory
	var sled_nodes: Array[Node] = get_tree().get_nodes_in_group(&"player_sled")
	if not sled_nodes.is_empty() and sled_nodes[0] is Node:
		sled_comp = sled_nodes[0].get_node_or_null("CenterOfMassComponent/HexInventoryComponent") as HexInventoryComponent
	
	# Configure dual panels
	if crate_comp:
		source_container = crate_comp
		left_title.text = "GROUND CRATE"
	else:
		source_container = null
		left_title.text = "NO LOCAL CACHE"
	
	if sled_comp:
		target_container = sled_comp
		right_title.text = "SLED CARGO POD"
	elif backpack_comp:
		target_container = backpack_comp
		right_title.text = "PILOT BACKPACK"
	
	left_grid_control.set_inventory(source_container)
	right_grid_control.set_inventory(target_container)
	
	is_open = true
	root_control.visible = true

func close_inventory() -> void:
	if held_item:
		_cancel_drag()
	is_open = false
	root_control.visible = false
	left_grid_control.clear_custom_drag_preview()
	right_grid_control.clear_custom_drag_preview()

func _start_dragging(item: HexItemData, source_inv: HexInventoryComponent, source_slot: Vector2i) -> void:
	held_item = item
	held_rotation_step = item.rotation_step
	source_inv_for_drag = source_inv
	source_slot_for_drag = source_slot
	source_inv.remove_item(item)
	_update_tooltip(held_item)

func _rotate_held_item() -> void:
	if not held_item:
		return
	held_rotation_step = (held_rotation_step + 1) % 6
	# Update active grid previews
	if left_grid_control.is_mouse_inside and left_grid_control.grid_inventory:
		var is_valid: bool = left_grid_control.grid_inventory.can_place_item(held_item, left_grid_control.hovered_cell, held_rotation_step)
		left_grid_control.set_custom_drag_preview(held_item, held_rotation_step, left_grid_control.hovered_cell, is_valid)
	elif right_grid_control.is_mouse_inside and right_grid_control.grid_inventory:
		var is_valid: bool = right_grid_control.grid_inventory.can_place_item(held_item, right_grid_control.hovered_cell, held_rotation_step)
		right_grid_control.set_custom_drag_preview(held_item, held_rotation_step, right_grid_control.hovered_cell, is_valid)

func _try_drop_item(grid: HexGridControl, cell: Vector2i) -> void:
	if not held_item or not grid or not grid.grid_inventory:
		return
	
	if grid.grid_inventory.can_place_item(held_item, cell, held_rotation_step):
		grid.grid_inventory.place_item(held_item, cell, held_rotation_step)
		held_item = null
		source_inv_for_drag = null
		grid.clear_custom_drag_preview()
		_update_tooltip(null)
	else:
		# Invalid drop target
		pass

func _cancel_drag() -> void:
	if held_item and source_inv_for_drag:
		source_inv_for_drag.place_item(held_item, source_slot_for_drag, held_item.rotation_step)
	held_item = null
	source_inv_for_drag = null
	left_grid_control.clear_custom_drag_preview()
	right_grid_control.clear_custom_drag_preview()
	_update_tooltip(null)

func _update_tooltip(item: HexItemData) -> void:
	if item:
		tooltip_name.text = item.item_name
		tooltip_mass.text = "Mass: %.1f kg" % item.mass_kg
		tooltip_desc.text = "Hex Footprint: %d cells\nCategory: %s" % [item.hex_footprint.size(), item.item_id]
	else:
		tooltip_name.text = "NO SELECTION"
		tooltip_mass.text = "Mass: --"
		tooltip_desc.text = "Click an item to drag.\nPress [R] / [RMB] to rotate 60°."
