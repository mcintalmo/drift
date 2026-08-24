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

@export_group("Terrain & Prop See-Through Occlusion")
@export var is_terrain_see_through_enabled: bool = true
@export var occluded_transparency_alpha: float = 0.28
@export var fade_in_speed: float = 12.0
@export var fade_out_speed: float = 6.0

@export_group("Trauma & Screen Shake")
@export var trauma_decay_rate: float = 1.4
@export var max_shake_offset_meters: float = 0.85
@export var max_shake_rotation_deg: float = 2.5

@onready var camera_mount: Node3D = $CameraMount
@onready var camera_3d: Camera3D = $CameraMount/Camera3D

var _current_trauma: float = 0.0
var _shake_time: float = 0.0
# Registry of currently tracked occluder materials: StandardMaterial3D -> float (current_alpha)
var _occluded_materials: Dictionary = {}

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

func _physics_process(delta: float) -> void:
	if is_terrain_see_through_enabled and target_node and camera_3d:
		_update_terrain_occlusion(delta)

## Casts multi-ray bundle from camera to target and smoothly fades occluding terrain and props
func _update_terrain_occlusion(delta: float) -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not space_state:
		return
	
	var cam_pos: Vector3 = camera_3d.global_position
	var target_pos: Vector3 = target_node.global_position + Vector3(0, 0.6, 0)
	var cam_to_target_dist: float = cam_pos.distance_to(target_pos)
	
	if cam_to_target_dist < 1.0:
		return
	
	# Multi-ray sample offsets around the player/sled
	var sample_offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(-0.8, 0, 0),
		Vector3(0.8, 0, 0),
		Vector3(0, 0.8, 0)
	]
	
	var currently_hit_materials: Array[StandardMaterial3D] = []
	
	for offset: Vector3 in sample_offsets:
		var ray_target: Vector3 = target_pos + offset
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cam_pos, ray_target, 1) # Layer 1 = World Terrain & Props
		if target_node is CollisionObject3D:
			query.exclude = [ (target_node as CollisionObject3D).get_rid() ]
		
		var result: Dictionary = space_state.intersect_ray(query)
		if not result.is_empty():
			var hit_pos: Vector3 = result.get("position", Vector3.ZERO)
			var hit_dist: float = cam_pos.distance_to(hit_pos)
			
			# If the hit is between camera and target (with margin)
			if hit_dist < (cam_to_target_dist - 1.2):
				var collider: Object = result.get("collider")
				if collider is Node:
					_collect_mesh_materials(collider as Node, currently_hit_materials)
	
	# Register newly occluding materials
	for mat: StandardMaterial3D in currently_hit_materials:
		if not _occluded_materials.has(mat):
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_occluded_materials[mat] = mat.albedo_color.a
	
	# Smoothly update alpha for all tracked materials
	var to_remove: Array[StandardMaterial3D] = []
	for mat: StandardMaterial3D in _occluded_materials:
		if not is_instance_valid(mat):
			to_remove.append(mat)
			continue
			
		var is_still_occluding: bool = currently_hit_materials.has(mat)
		var target_alpha: float = occluded_transparency_alpha if is_still_occluding else 1.0
		var current_a: float = mat.albedo_color.a
		var speed: float = fade_in_speed if is_still_occluding else fade_out_speed
		
		var new_a: float = move_toward(current_a, target_alpha, speed * delta)
		mat.albedo_color.a = new_a
		_occluded_materials[mat] = new_a
		
		if not is_still_occluding and new_a >= 0.99:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = 1.0
			to_remove.append(mat)
			
	for mat: StandardMaterial3D in to_remove:
		_occluded_materials.erase(mat)

func _collect_mesh_materials(node: Node, out_materials: Array[StandardMaterial3D]) -> void:
	# Check node and its direct children / parents for MeshInstance3D
	var mesh_instances: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		mesh_instances.append(node as MeshInstance3D)
	else:
		for child in node.get_children():
			if child is MeshInstance3D:
				mesh_instances.append(child as MeshInstance3D)
		if node.get_parent() is Node3D:
			for sibling in node.get_parent().get_children():
				if sibling is MeshInstance3D:
					mesh_instances.append(sibling as MeshInstance3D)
	
	for mi: MeshInstance3D in mesh_instances:
		var mat: Material = mi.material_override
		if not mat and mi.mesh:
			mat = mi.mesh.surface_get_material(0)
		if mat is StandardMaterial3D and not out_materials.has(mat as StandardMaterial3D):
			out_materials.append(mat as StandardMaterial3D)

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
