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
@export var sight_cylinder_radius_m: float = 1.6
@export var fade_in_speed: float = 10.0
@export var fade_out_speed: float = 5.0
@export var min_occlusion_clearance_y_m: float = 0.35
@export var floor_normal_threshold_y: float = 0.55

@export_group("Trauma & Screen Shake")
@export var trauma_decay_rate: float = 1.4
@export var max_shake_offset_meters: float = 0.85
@export var max_shake_rotation_deg: float = 2.5

@onready var camera_mount: Node3D = $CameraMount
@onready var camera_3d: Camera3D = $CameraMount/Camera3D

var _current_trauma: float = 0.0
var _shake_time: float = 0.0

# Tracked occluder materials: StandardMaterial3D -> float (current_alpha)
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

## Multi-piercing line-of-sight raycasting with ground filtering and shadow depth preservation
func _update_terrain_occlusion(delta: float) -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not space_state:
		return
	
	var cam_pos: Vector3 = camera_3d.global_position
	var target_center: Vector3 = target_node.global_position + Vector3(0, 0.7, 0)
	var sled_floor_y: float = target_node.global_position.y
	var cam_to_target_dist: float = cam_pos.distance_to(target_center)
	
	if cam_to_target_dist < 1.0:
		return
	
	# Camera view-plane basis for spatial cylinder rays around current sled position
	var cam_right: Vector3 = camera_3d.global_transform.basis.x.normalized()
	var cam_up: Vector3 = camera_3d.global_transform.basis.y.normalized()
	
	# Spatial cylinder ray targets: Center core (1.0 weight) + radial proximity envelope
	var ray_targets: Array[Dictionary] = [
		{"pos": target_center, "weight": 1.0} # Direct center sightline
	]
	
	# 6-point radial proximity ring elevated above floor
	var r: float = sight_cylinder_radius_m
	for i: int in range(6):
		var angle_rad: float = deg_to_rad(60.0 * float(i))
		var offset_3d: Vector3 = (cam_right * (cos(angle_rad) * r)) + (cam_up * (sin(angle_rad) * (r * 0.75)))
		ray_targets.append({
			"pos": target_center + offset_3d,
			"weight": 0.85
		})
	
	# Map to aggregate maximum occlusion weight per material: StandardMaterial3D -> max_weight
	var active_materials_weight: Dictionary = {}
	
	var base_exclude: Array[RID] = []
	if target_node is CollisionObject3D:
		base_exclude.append((target_node as CollisionObject3D).get_rid())
	
	for entry: Dictionary in ray_targets:
		var ray_dest: Vector3 = entry["pos"]
		var ray_weight: float = entry["weight"]
		var ray_dist: float = cam_pos.distance_to(ray_dest)
		
		# Piercing multi-hit raycast strictly along this line of sight
		var exclude_list: Array[RID] = base_exclude.duplicate()
		
		for _hit_step in range(8): # Pierces through all cascaded hills/props along line of sight
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cam_pos, ray_dest, 1) # Layer 1 = World Terrain & Props
			query.exclude = exclude_list
			
			var result: Dictionary = space_state.intersect_ray(query)
			if result.is_empty():
				break
				
			var hit_pos: Vector3 = result.get("position", Vector3.ZERO)
			var hit_normal: Vector3 = result.get("normal", Vector3.UP)
			var hit_dist: float = cam_pos.distance_to(hit_pos)
			var collider: Object = result.get("collider")
			
			if collider is CollisionObject3D:
				exclude_list.append((collider as CollisionObject3D).get_rid())
			
			# 1. Reject ground/floor surfaces beneath and around sled (prevents floor from fading in corners)
			var is_floor_contact: bool = (hit_normal.y > floor_normal_threshold_y) and (hit_pos.y <= sled_floor_y + min_occlusion_clearance_y_m)
			if is_floor_contact:
				continue
			
			# 2. Reject hits below the minimum vertical clearance threshold
			if hit_pos.y <= sled_floor_y + 0.15:
				continue
			
			# 3. Must be situated significantly between camera and target (at least 1.4m away from target)
			if hit_dist < (ray_dist - 1.4):
				if collider is Node:
					var mats: Array[StandardMaterial3D] = []
					_collect_mesh_materials(collider as Node, mats)
					for m: StandardMaterial3D in mats:
						var prev_w: float = active_materials_weight.get(m, 0.0)
						active_materials_weight[m] = maxf(prev_w, ray_weight)
			else:
				break
	
	# Register newly discovered occluding materials with DEPTH_DRAW_ALWAYS to preserve full 3D shadow casting
	for mat: StandardMaterial3D in active_materials_weight:
		if not _occluded_materials.has(mat):
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS # Keeps shadow depth intact!
			_occluded_materials[mat] = 1.0
	
	# Smoothly interpolate alpha based on proximity weight
	var to_remove: Array[StandardMaterial3D] = []
	for mat: StandardMaterial3D in _occluded_materials:
		if not is_instance_valid(mat):
			to_remove.append(mat)
			continue
			
		var is_occluding: bool = active_materials_weight.has(mat)
		var target_alpha: float = 1.0
		var speed: float = fade_out_speed
		
		if is_occluding:
			var weight: float = active_materials_weight[mat]
			target_alpha = lerpf(1.0, occluded_transparency_alpha, weight)
			speed = fade_in_speed
			
		var current_a: float = mat.albedo_color.a
		var new_a: float = move_toward(current_a, target_alpha, speed * delta)
		mat.albedo_color.a = new_a
		
		if not is_occluding and new_a >= 0.99:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			mat.albedo_color.a = 1.0
			to_remove.append(mat)
			
	for mat: StandardMaterial3D in to_remove:
		_occluded_materials.erase(mat)

func _collect_mesh_materials(node: Node, out_materials: Array[StandardMaterial3D]) -> void:
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
