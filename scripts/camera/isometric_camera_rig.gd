class_name IsometricCameraRig
extends Node3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

@export_group("Target Tracking")
@export var target_node: Node3D
@export var follow_smooth_speed: float = 6.0
@export var base_camera_distance: float = 22.0

@export_group("Isometric Framing")
@export var isometric_pitch_deg: float = 35.0
@export var isometric_yaw_deg: float = 45.0
@export var max_velocity_lead_meters: float = 8.5
@export var velocity_lead_factor: float = 0.28

@export_group("Trauma & Screen Shake")
@export var trauma_decay_rate: float = 1.4
@export var max_shake_offset_meters: float = 0.85
@export var max_shake_rotation_deg: float = 2.5

@onready var camera_mount: Node3D = $CameraMount
@onready var camera_3d: Camera3D = $CameraMount/Camera3D

var _current_trauma: float = 0.0
var _shake_time: float = 0.0

func _ready() -> void:
	_apply_isometric_rotation()
	GlobalEvents.subscribe_sled_impact(func(intensity: float, _hit_pos: Vector3) -> void:
		var trauma_add: float = clampf(intensity / 25.0, 0.2, 1.0)
		add_trauma(trauma_add)
	)
	if GlobalEvents.instance:
		GlobalEvents.instance.pilot_mounted_sled.connect(func(sled: Node) -> void:
			if sled is Node3D:
				target_node = sled as Node3D
		)
		GlobalEvents.instance.pilot_dismounted_sled.connect(func(_sled: Node) -> void:
			var pilots: Array[Node] = get_tree().get_nodes_in_group(&"player_pilot")
			if not pilots.is_empty() and pilots[0] is Node3D:
				target_node = pilots[0] as Node3D
		)

func _process(delta: float) -> void:
	if not target_node:
		return
	
	# 1. Base Target Tracking with Velocity Leading
	var target_pos: Vector3 = target_node.global_position
	var lead_offset: Vector3 = Vector3.ZERO
	
	if target_node is CharacterBody3D:
		var vel: Vector3 = (target_node as CharacterBody3D).velocity
		var vel_mag: float = vel.length()
		if vel_mag > 0.1:
			var lead_dist: float = minf(vel_mag * velocity_lead_factor, max_velocity_lead_meters)
			lead_offset = vel.normalized() * lead_dist
	
	var desired_pos: Vector3 = target_pos + lead_offset
	global_position = global_position.lerp(desired_pos, follow_smooth_speed * delta)
	
	# 2. Update Trauma & Screen Shake
	_update_screen_shake(delta)

func add_trauma(amount: float) -> void:
	_current_trauma = clampf(_current_trauma + amount, 0.0, 1.0)

func _update_screen_shake(delta: float) -> void:
	if _current_trauma <= 0.0:
		if camera_3d:
			camera_3d.transform.origin = Vector3(0.0, 0.0, base_camera_distance)
			camera_3d.rotation.z = 0.0
		return
	
	_current_trauma = maxf(0.0, _current_trauma - trauma_decay_rate * delta)
	_shake_time += delta * 30.0
	
	# Trauma-squared calculation (Shake = Trauma^2)
	var shake_power: float = _current_trauma * _current_trauma
	var offset_x: float = sin(_shake_time * 1.3) * max_shake_offset_meters * shake_power
	var offset_y: float = cos(_shake_time * 1.7) * max_shake_offset_meters * shake_power
	var rot_z: float = sin(_shake_time * 2.1) * deg_to_rad(max_shake_rotation_deg) * shake_power
	
	if camera_3d:
		camera_3d.transform.origin = Vector3(offset_x, offset_y, base_camera_distance)
		camera_3d.rotation.z = rot_z

func _apply_isometric_rotation() -> void:
	if camera_mount:
		camera_mount.rotation_degrees = Vector3(-isometric_pitch_deg, isometric_yaw_deg, 0.0)
	if camera_3d:
		camera_3d.transform.origin = Vector3(0.0, 0.0, base_camera_distance)
		camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera_3d.fov = 42.0
