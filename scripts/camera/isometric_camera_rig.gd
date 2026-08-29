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
@export var occluded_transparency_alpha: float = 0.18
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

# Tracked occluder meshes: MeshInstance3D -> { "material": StandardMaterial3D, "proxy": MeshInstance3D }
var _occluded_meshes: Dictionary = {}

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

## Line-of-sight raycasting with shadow-proxy preservation and smooth non-dithered alpha transparency
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
	
	var sled_basis: Basis = target_node.global_transform.basis
	var sled_forward: Vector3 = -sled_basis.z.normalized()
	var sled_right: Vector3 = sled_basis.x.normalized()
	
	# Ray targets strictly placed ON the sled's physical hull bounds
	var ray_targets: Array[Dictionary] = [
		{"pos": target_center, "weight": 1.0}, # Direct central chassis core
		{"pos": target_center + sled_forward * 0.7, "weight": 0.90}, # Sled nose
		{"pos": target_center - sled_forward * 0.7, "weight": 0.90}, # Sled tail
		{"pos": target_center + sled_right * 0.35, "weight": 0.85}, # Right rail
		{"pos": target_center - sled_right * 0.35, "weight": 0.85}, # Left rail
		{"pos": target_center + Vector3(0, 0.45, 0), "weight": 0.90} # Pilot cabin height
	]
	
	var active_mesh_weights: Dictionary = {} # MeshInstance3D -> max_weight
	
	var base_exclude: Array[RID] = []
	if target_node is CollisionObject3D:
		base_exclude.append((target_node as CollisionObject3D).get_rid())
	
	for entry: Dictionary in ray_targets:
		var ray_dest: Vector3 = entry["pos"]
		var ray_weight: float = entry["weight"]
		var ray_dist: float = cam_pos.distance_to(ray_dest)
		
		var exclude_list: Array[RID] = base_exclude.duplicate()
		
		for _hit_step in range(8):
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
			
			# 1. Reject ground/floor surfaces beneath and around sled
			var is_floor_contact: bool = (hit_normal.y > floor_normal_threshold_y) and (hit_pos.y <= sled_floor_y + min_occlusion_clearance_y_m)
			if is_floor_contact:
				continue
			
			# 2. Reject hits below the minimum vertical clearance threshold
			if hit_pos.y <= sled_floor_y + 0.15:
				continue
			
			# 3. Must be situated in the foreground between camera and target
			if hit_dist < (ray_dist - 1.6):
				if collider is Node:
					var meshes: Array[MeshInstance3D] = []
					_collect_mesh_instances(collider as Node, meshes)
					for mi: MeshInstance3D in meshes:
						var prev_w: float = active_mesh_weights.get(mi, 0.0)
						active_mesh_weights[mi] = maxf(prev_w, ray_weight)
			else:
				break
	
	# Register newly discovered occluding meshes with dedicated SHADOWS_ONLY shadow proxies
	for mi: MeshInstance3D in active_mesh_weights:
		if not is_instance_valid(mi):
			continue
		if not _occluded_meshes.has(mi):
			var mat: StandardMaterial3D = _get_or_create_standard_material(mi)
			if mat:
				# Spawn dedicated shadow proxy to guarantee 100% solid shadow casting
				var shadow_proxy: MeshInstance3D = MeshInstance3D.new()
				shadow_proxy.name = "OcclusionShadowProxy"
				shadow_proxy.mesh = mi.mesh
				shadow_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				mi.add_child(shadow_proxy)
				
				# Configure main visual mesh to clean smooth alpha without dither noise
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				
				_occluded_meshes[mi] = {
					"material": mat,
					"proxy": shadow_proxy
				}
	
	# Smoothly interpolate alpha for all tracked meshes
	var to_remove: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in _occluded_meshes:
		if not is_instance_valid(mi):
			to_remove.append(mi)
			continue
			
		var data: Dictionary = _occluded_meshes[mi]
		var mat: StandardMaterial3D = data.get("material", null)
		var proxy: MeshInstance3D = data.get("proxy", null)
		
		if not mat or not is_instance_valid(mat):
			to_remove.append(mi)
			continue
			
		var is_occluding: bool = active_mesh_weights.has(mi)
		var target_alpha: float = 1.0
		var speed: float = fade_out_speed
		
		if is_occluding:
			var weight: float = active_mesh_weights[mi]
			target_alpha = lerpf(1.0, occluded_transparency_alpha, weight)
			speed = fade_in_speed
			
		var current_a: float = mat.albedo_color.a
		var new_a: float = move_toward(current_a, target_alpha, speed * delta)
		mat.albedo_color.a = new_a
		
		# Fully restored back to 1.0 -> clean up shadow proxy and restore standard rendering
		if not is_occluding and new_a >= 0.99:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = 1.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if proxy and is_instance_valid(proxy):
				proxy.queue_free()
			to_remove.append(mi)
			
	for mi: MeshInstance3D in to_remove:
		_occluded_meshes.erase(mi)

func _collect_mesh_instances(node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if not node:
		return
		
	# If collider is a sub-body of a HexWorldTile (e.g. TileBody), collect from the root tile so terrain + water basin fade together
	var root_target: Node = node
	if root_target.get_parent() is HexWorldTile:
		root_target = root_target.get_parent()
		
	_collect_mesh_instances_recursive(root_target, out_meshes)

func _collect_mesh_instances_recursive(node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if not node:
		return
		
	# 1. Exclude crates: loot crates must always remain 100% opaque
	if node is GroundCrate or node.is_in_group(&"loot_crates") or node.name.begins_with("VaultCrate") or node.name.begins_with("GroundCrate"):
		return
		
	# 2. Exclude doors ONLY while locked/interactable; once open/unlocked, allow them to fade with the car
	if node.name.ends_with("SlidingDoor") or node.name.ends_with("Lock") or node.name == "MagneticLock":
		var car: Node = _find_parent_train_car(node)
		if car and int(car.get("car_state")) == 0: # CarState.LOCKED
			return
			
	if node.is_in_group(&"interactable_doors") or node.get_meta("opaque_interactable", false):
		return
		
	if node is MeshInstance3D and node.name != "OcclusionShadowProxy":
		if not out_meshes.has(node as MeshInstance3D):
			out_meshes.append(node as MeshInstance3D)
			
	for child: Node in node.get_children():
		_collect_mesh_instances_recursive(child, out_meshes)

func _find_parent_train_car(node: Node) -> Node:
	var cur: Node = node
	while cur:
		if cur is TrainCar or cur.has_method("breach_doors"):
			return cur
		cur = cur.get_parent()
	return null

func _get_or_create_standard_material(mi: MeshInstance3D) -> StandardMaterial3D:
	var mat: Material = mi.material_override
	if not mat and mi.mesh:
		mat = mi.mesh.surface_get_material(0)
		if mat is StandardMaterial3D:
			mat = (mat as StandardMaterial3D).duplicate()
			mi.material_override = mat
	return mat as StandardMaterial3D if mat is StandardMaterial3D else null

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
