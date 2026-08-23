class_name HexGridControl
extends Control

signal cell_clicked(cell: Vector2i, mouse_button: int, is_shift: bool)
signal cell_hovered(cell: Vector2i)

@export var cell_radius: float = 24.0
@export var grid_inventory: HexInventoryComponent

@export_group("Visual Styling")
@export var cell_fill_color: Color = Color(0.12, 0.16, 0.2, 0.85)
@export var cell_border_color: Color = Color(0.25, 0.35, 0.45, 0.9)
@export var hover_highlight_color: Color = Color(0.3, 0.8, 1.0, 0.4)
@export var valid_drop_color: Color = Color(0.2, 0.9, 0.3, 0.5)
@export var invalid_drop_color: Color = Color(0.9, 0.2, 0.2, 0.5)

var hovered_cell: Vector2i = Vector2i(-999, -999)
var is_mouse_inside: bool = false

# Ghost preview for dragged items
var preview_item: HexItemData = null
var preview_rotation_step: int = 0
var preview_root_cell: Vector2i = Vector2i(-999, -999)
var is_preview_valid: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(280, 240)
	mouse_entered.connect(func() -> void: is_mouse_inside = true)
	mouse_exited.connect(func() -> void:
		is_mouse_inside = false
		hovered_cell = Vector2i(-999, -999)
		queue_redraw()
	)
	
	if grid_inventory:
		grid_inventory.item_placed.connect(func(_it: HexItemData, _slot: Vector2i) -> void: queue_redraw())
		grid_inventory.item_removed.connect(func(_it: HexItemData) -> void: queue_redraw())

func set_inventory(inv: HexInventoryComponent) -> void:
	grid_inventory = inv
	if grid_inventory:
		grid_inventory.item_placed.connect(func(_it: HexItemData, _slot: Vector2i) -> void: queue_redraw())
		grid_inventory.item_removed.connect(func(_it: HexItemData) -> void: queue_redraw())
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local_pos: Vector2 = (event as InputEventMouseMotion).position
		var cell: Vector2i = pixel_to_hex(local_pos)
		if cell != hovered_cell:
			hovered_cell = cell
			cell_hovered.emit(cell)
			queue_redraw()
	
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			var cell: Vector2i = pixel_to_hex(mb.position)
			cell_clicked.emit(cell, mb.button_index, mb.shift_pressed)

func _draw() -> void:
	if not grid_inventory:
		return
	
	var grid_origin: Vector2 = size * 0.5
	
	# 1. Draw empty grid cells
	for slot: Vector2i in grid_inventory.available_slots:
		var center: Vector2 = grid_origin + hex_to_pixel(slot)
		var poly: PackedVector2Array = get_hex_polygon(center, cell_radius)
		draw_colored_polygon(poly, cell_fill_color)
		draw_polyline(poly, cell_border_color, 1.5, true)
	
	# 2. Draw placed items
	var drawn_items: Array[HexItemData] = []
	for item_id: StringName in grid_inventory.placed_items:
		var item: HexItemData = grid_inventory.placed_items[item_id]
		if not drawn_items.has(item):
			drawn_items.append(item)
			_draw_item(item, grid_origin)
	
	# 3. Draw hover highlight
	if is_mouse_inside and grid_inventory.available_slots.has(hovered_cell):
		var hover_center: Vector2 = grid_origin + hex_to_pixel(hovered_cell)
		var hover_poly: PackedVector2Array = get_hex_polygon(hover_center, cell_radius)
		draw_colored_polygon(hover_poly, hover_highlight_color)
		draw_polyline(hover_poly, Color(0.5, 0.9, 1.0, 1.0), 2.0, true)
	
	# 4. Draw drag ghost preview
	if preview_item and is_mouse_inside and grid_inventory.available_slots.has(preview_root_cell):
		_draw_preview_ghost(grid_origin)

func _draw_item(item: HexItemData, grid_origin: Vector2) -> void:
	var color: Color = item.item_color if item.item_color != Color.TRANSPARENT else Color(0.85, 0.55, 0.2, 0.85)
	var slots: Array[Vector2i] = grid_inventory.get_item_occupied_slots(item)
	
	for slot: Vector2i in slots:
		var center: Vector2 = grid_origin + hex_to_pixel(slot)
		var poly: PackedVector2Array = get_hex_polygon(center, cell_radius * 0.92)
		draw_colored_polygon(poly, color)
		draw_polyline(poly, Color(1, 1, 1, 0.6), 1.5, true)
	
	# Draw item name on root cell
	var root_center: Vector2 = grid_origin + hex_to_pixel(item.root_slot)
	draw_string(ThemeDB.fallback_font, root_center + Vector2(-18, 4), item.item_name.substr(0, 4), HORIZONTAL_ALIGNMENT_CENTER, 36, 11, Color.WHITE)

func _draw_preview_ghost(grid_origin: Vector2) -> void:
	var ghost_color: Color = valid_drop_color if is_preview_valid else invalid_drop_color
	var rotated_pts: Array[Vector2i] = preview_item.get_rotated_footprint(preview_rotation_step)
	
	for offset_pt: Vector2i in rotated_pts:
		var target_cell: Vector2i = preview_root_cell + offset_pt
		var center: Vector2 = grid_origin + hex_to_pixel(target_cell)
		var poly: PackedVector2Array = get_hex_polygon(center, cell_radius * 0.92)
		draw_colored_polygon(poly, ghost_color)
		draw_polyline(poly, Color.WHITE, 2.0, true)

func set_custom_drag_preview(item: HexItemData, rotation_step: int, root_cell: Vector2i, is_valid: bool) -> void:
	preview_item = item
	preview_rotation_step = rotation_step
	preview_root_cell = root_cell
	is_preview_valid = is_valid
	queue_redraw()

func clear_custom_drag_preview() -> void:
	preview_item = null
	queue_redraw()

# Hex Math Calculations
func hex_to_pixel(hex: Vector2i) -> Vector2:
	var q: float = float(hex.x)
	var r: float = float(hex.y)
	var x: float = cell_radius * sqrt(3.0) * (q + r * 0.5)
	var y: float = cell_radius * 1.5 * r
	return Vector2(x, y)

func pixel_to_hex(pixel_pos: Vector2) -> Vector2i:
	var grid_origin: Vector2 = size * 0.5
	var rel_pos: Vector2 = pixel_pos - grid_origin
	var q_frac: float = (sqrt(3.0) / 3.0 * rel_pos.x - 1.0 / 3.0 * rel_pos.y) / cell_radius
	var r_frac: float = (2.0 / 3.0 * rel_pos.y) / cell_radius
	return _axial_round(q_frac, r_frac)

func _axial_round(q_frac: float, r_frac: float) -> Vector2i:
	var s_frac: float = -q_frac - r_frac
	var q_round: int = int(round(q_frac))
	var r_round: int = int(round(r_frac))
	var s_round: int = int(round(s_frac))
	
	var q_diff: float = absf(float(q_round) - q_frac)
	var r_diff: float = absf(float(r_round) - r_frac)
	var s_diff: float = absf(float(s_round) - s_frac)
	
	if q_diff > r_diff and q_diff > s_diff:
		q_round = -r_round - s_round
	elif r_diff > s_diff:
		r_round = -q_round - s_round
	
	return Vector2i(q_round, r_round)

func get_hex_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(6):
		var angle_rad: float = deg_to_rad(60.0 * float(i) + 30.0)
		var pt: Vector2 = center + Vector2(radius * cos(angle_rad), radius * sin(angle_rad))
		points.append(pt)
	return points
