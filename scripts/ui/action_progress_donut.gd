class_name ActionProgressDonut
extends Control

signal channel_started(action_name: String, duration: float)
signal channel_progress_updated(progress: float, zoom_factor: float)
signal channel_completed(action_name: String)
signal channel_cancelled(action_name: String)

@export var ring_radius: float = 36.0
@export var ring_thickness: float = 6.0
@export var ring_color: Color = Color(0.12, 0.85, 0.95, 0.95) # Glowing Cyan-Amber
@export var bg_ring_color: Color = Color(0.15, 0.18, 0.22, 0.6)
@export var max_camera_zoom_in: float = 0.12 # 12% subtle camera zoom in during channel

var is_channeling: bool = false
var channel_duration: float = 1.0
var elapsed_time: float = 0.0
var current_action_name: String = ""
var _on_complete_callback: Callable
var _on_cancel_callback: Callable

# Origin point or target tracking
var target_node_3d: Node3D
var max_interact_distance_m: float = 4.0
var initial_player_pos: Vector3 = Vector3.ZERO
var player_ref: Node3D

func _ready() -> void:
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	if not is_channeling:
		return
		
	# 1. Check distance if player moved too far
	if player_ref and is_instance_valid(player_ref) and target_node_3d and is_instance_valid(target_node_3d):
		var p_pos: Vector3 = player_ref.global_position if player_ref.is_inside_tree() else player_ref.position
		var t_pos: Vector3 = target_node_3d.global_position if target_node_3d.is_inside_tree() else target_node_3d.position
		if p_pos.distance_to(t_pos) > max_interact_distance_m:
			cancel_channel()
			return
			
	elapsed_time += delta
	var progress: float = clampf(elapsed_time / channel_duration, 0.0, 1.0)
	var zoom_factor: float = progress * max_camera_zoom_in
	
	channel_progress_updated.emit(progress, zoom_factor)
	if is_inside_tree():
		queue_redraw()
	
	# Update screen position over target 3D node if camera is available
	if target_node_3d and is_instance_valid(target_node_3d) and is_inside_tree():
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			var t_pos: Vector3 = target_node_3d.global_position if target_node_3d.is_inside_tree() else target_node_3d.position
			if not cam.is_position_behind(t_pos):
				position = cam.unproject_position(t_pos + Vector3(0, 1.2, 0)) - size * 0.5
	
	if elapsed_time >= channel_duration:
		complete_channel()

func start_channel(
	action_name: String,
	duration: float,
	on_complete: Callable,
	on_cancel: Callable = Callable(),
	target_3d: Node3D = null,
	player: Node3D = null,
	max_dist: float = 4.0
) -> void:
	current_action_name = action_name
	channel_duration = maxf(0.1, duration)
	elapsed_time = 0.0
	_on_complete_callback = on_complete
	_on_cancel_callback = on_cancel
	target_node_3d = target_3d
	player_ref = player
	max_interact_distance_m = max_dist
	
	is_channeling = true
	visible = true
	set_process(true)
	channel_started.emit(action_name, channel_duration)
	if is_inside_tree():
		queue_redraw()

func complete_channel() -> void:
	if not is_channeling:
		return
	is_channeling = false
	set_process(false)
	visible = false
	
	var cb: Callable = _on_complete_callback
	var act: String = current_action_name
	channel_completed.emit(act)
	
	if cb.is_valid():
		cb.call()

func cancel_channel() -> void:
	if not is_channeling:
		return
	is_channeling = false
	set_process(false)
	visible = false
	
	var cb: Callable = _on_cancel_callback
	var act: String = current_action_name
	channel_cancelled.emit(act)
	
	if cb.is_valid():
		cb.call()
	if is_inside_tree():
		queue_redraw()

func _draw() -> void:
	if not is_channeling:
		return
		
	var center: Vector2 = size * 0.5
	if center == Vector2.ZERO:
		center = Vector2(ring_radius + ring_thickness, ring_radius + ring_thickness)
		
	# Draw Background Ring
	draw_arc(center, ring_radius, 0.0, TAU, 48, bg_ring_color, ring_thickness, true)
	
	# Draw Progress Arc
	var progress: float = clampf(elapsed_time / channel_duration, 0.0, 1.0)
	var end_angle: float = -PI * 0.5 + progress * TAU
	
	if progress > 0.01:
		draw_arc(center, ring_radius, -PI * 0.5, end_angle, 48, ring_color, ring_thickness, true)
		
	# Draw center pulse icon / dot
	var dot_radius: float = ring_radius * 0.28 * (1.0 + sin(elapsed_time * 8.0) * 0.15)
	draw_circle(center, dot_radius, ring_color)
