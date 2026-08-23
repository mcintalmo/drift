class_name COMVisualizerWidget
extends Control

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

@export var current_com_offset: Vector2 = Vector2.ZERO
@export var current_mass_kg: float = 220.0
@export var max_offset_display_m: float = 0.5

@export_group("Thresholds")
@export var safe_threshold_m: float = 0.12
@export var warning_threshold_m: float = 0.25

var _target_com_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(180, 180)
	if GlobalEvents.instance:
		GlobalEvents.instance.inventory_updated.connect(func(_container_id: StringName, mass: float, com: Vector2) -> void:
			current_mass_kg = mass
			_target_com_offset = com
			queue_redraw()
		)

func _process(delta: float) -> void:
	if current_com_offset.distance_to(_target_com_offset) > 0.001:
		current_com_offset = current_com_offset.lerp(_target_com_offset, 10.0 * delta)
		queue_redraw()

func _draw() -> void:
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.44)
	var scale_px_per_m: float = (size.x * 0.36) / max_offset_display_m
	
	# 1. Draw vehicle outline (chassis frame)
	var hull_rect: Rect2 = Rect2(center.x - 24, center.y - 45, 48, 90)
	draw_rect(hull_rect, Color(0.12, 0.16, 0.22, 0.9), true, -1.0)
	draw_rect(hull_rect, Color(0.35, 0.5, 0.65, 0.9), false, 2.0)
	
	# Left and right runners
	draw_line(Vector2(center.x - 28, center.y - 48), Vector2(center.x - 28, center.y + 48), Color(0.6, 0.75, 0.9, 1.0), 3.0)
	draw_line(Vector2(center.x + 28, center.y - 48), Vector2(center.x + 28, center.y + 48), Color(0.6, 0.75, 0.9, 1.0), 3.0)
	
	# 2. Draw balance threshold rings
	draw_arc(center, safe_threshold_m * scale_px_per_m, 0, TAU, 32, Color(0.2, 0.85, 0.3, 0.4), 1.5)
	draw_arc(center, warning_threshold_m * scale_px_per_m, 0, TAU, 32, Color(0.95, 0.4, 0.2, 0.6), 1.5)
	
	# Center anchor cross
	draw_line(center + Vector2(-4, 0), center + Vector2(4, 0), Color(1, 1, 1, 0.3), 1.0)
	draw_line(center + Vector2(0, -4), center + Vector2(0, 4), Color(1, 1, 1, 0.3), 1.0)
	
	# 3. Draw COM crosshair
	var crosshair_pos: Vector2 = center + Vector2(current_com_offset.x, current_com_offset.y) * scale_px_per_m
	var offset_dist: float = current_com_offset.length()
	
	var dot_color: Color = Color(0.2, 0.9, 0.3, 1.0)
	if offset_dist >= warning_threshold_m:
		dot_color = Color(1.0, 0.2, 0.2, 1.0)
	elif offset_dist >= safe_threshold_m:
		dot_color = Color(1.0, 0.75, 0.2, 1.0)
	
	draw_line(crosshair_pos + Vector2(-9, 0), crosshair_pos + Vector2(9, 0), dot_color, 2.0)
	draw_line(crosshair_pos + Vector2(0, -9), crosshair_pos + Vector2(0, 9), dot_color, 2.0)
	draw_circle(crosshair_pos, 5.0, dot_color)
	
	# 4. Draw Lateral Bias Balance Bar at bottom
	var bar_y: float = size.y - 28.0
	var bar_width: float = size.x - 30.0
	var bar_x: float = 15.0
	var bar_center_x: float = size.x * 0.5
	
	# Bar track
	draw_line(Vector2(bar_x, bar_y), Vector2(bar_x + bar_width, bar_y), Color(0.25, 0.35, 0.45, 0.8), 4.0)
	draw_line(Vector2(bar_center_x, bar_y - 4), Vector2(bar_center_x, bar_y + 4), Color(1, 1, 1, 0.6), 2.0)
	
	# Indicator pip
	var lat_normalized: float = clampf(current_com_offset.x / max_offset_display_m, -1.0, 1.0)
	var pip_x: float = bar_center_x + (lat_normalized * (bar_width * 0.5))
	draw_circle(Vector2(pip_x, bar_y), 4.5, dot_color)
	
	# Readout text
	var stats_text: String = "%d kg | Lat: %+.2fm" % [int(current_mass_kg), current_com_offset.x]
	draw_string(ThemeDB.fallback_font, Vector2(10, size.y - 8), stats_text, HORIZONTAL_ALIGNMENT_CENTER, int(size.x - 20), 10, Color(0.85, 0.9, 0.95, 0.9))
