class_name COMVisualizerWidget
extends Control

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

@export var current_com_offset: Vector2 = Vector2.ZERO
@export var current_mass_kg: float = 250.0
@export var max_offset_display_m: float = 0.6

@export_group("Thresholds")
@export var safe_threshold_m: float = 0.15
@export var warning_threshold_m: float = 0.28

var _target_com_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(160, 160)
	if GlobalEvents.instance:
		GlobalEvents.instance.inventory_updated.connect(func(_container_id: StringName, mass: float, com: Vector2) -> void:
			current_mass_kg = mass
			_target_com_offset = com
			queue_redraw()
		)

func _process(delta: float) -> void:
	if current_com_offset.distance_to(_target_com_offset) > 0.001:
		current_com_offset = current_com_offset.lerp(_target_com_offset, 8.0 * delta)
		queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var scale_px_per_m: float = (size.x * 0.4) / max_offset_display_m
	
	# 1. Draw vehicle outline (chassis frame)
	var hull_rect: Rect2 = Rect2(center.x - 22, center.y - 45, 44, 90)
	draw_rect(hull_rect, Color(0.15, 0.2, 0.25, 0.8), true, -1.0)
	draw_rect(hull_rect, Color(0.4, 0.5, 0.6, 0.9), false, 2.0)
	
	# Left and right runners
	draw_line(Vector2(center.x - 26, center.y - 50), Vector2(center.x - 26, center.y + 50), Color(0.6, 0.7, 0.8, 1.0), 3.0)
	draw_line(Vector2(center.x + 26, center.y - 50), Vector2(center.x + 26, center.y + 50), Color(0.6, 0.7, 0.8, 1.0), 3.0)
	
	# 2. Draw balance threshold rings
	draw_arc(center, safe_threshold_m * scale_px_per_m, 0, TAU, 32, Color(0.2, 0.8, 0.3, 0.4), 1.5)
	draw_arc(center, warning_threshold_m * scale_px_per_m, 0, TAU, 32, Color(0.9, 0.4, 0.2, 0.6), 1.5)
	
	# 3. Draw COM crosshair
	var crosshair_pos: Vector2 = center + Vector2(current_com_offset.x, current_com_offset.y) * scale_px_per_m
	var offset_dist: float = current_com_offset.length()
	
	var dot_color: Color = Color(0.2, 0.9, 0.3, 1.0)
	if offset_dist >= warning_threshold_m:
		dot_color = Color(1.0, 0.2, 0.2, 1.0)
	elif offset_dist >= safe_threshold_m:
		dot_color = Color(1.0, 0.75, 0.2, 1.0)
	
	# Draw crosshair lines
	draw_line(crosshair_pos + Vector2(-8, 0), crosshair_pos + Vector2(8, 0), dot_color, 2.0)
	draw_line(crosshair_pos + Vector2(0, -8), crosshair_pos + Vector2(0, 8), dot_color, 2.0)
	draw_circle(crosshair_pos, 4.0, dot_color)
	
	# Mass readout text
	var mass_text: String = "%d kg" % int(current_mass_kg)
	draw_string(ThemeDB.fallback_font, Vector2(center.x - 20, size.y - 6), mass_text, HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color(0.85, 0.9, 0.95, 0.9))
