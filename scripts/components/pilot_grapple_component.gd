class_name PilotGrappleComponent
extends Node3D

signal grapple_fired(target_pos: Vector3)
signal grapple_latched(target_pos: Vector3, is_heavy: bool)
signal grapple_released

@export var max_range_meters: float = 16.0
@export var pull_speed_ms: float = 16.0
@export var crate_drag_force: float = 35.0
@export var cable_mesh: MeshInstance3D

var is_grappling: bool = false
var target_anchor_pos: Vector3 = Vector3.ZERO
var target_rigid_body: RigidBody3D = null
var is_target_heavy: bool = true

func _ready() -> void:
	if cable_mesh:
		cable_mesh.visible = false

func _process(_delta: float) -> void:
	if is_grappling and cable_mesh:
		var start_pos: Vector3 = global_position
		var end_pos: Vector3 = target_anchor_pos
		var to_target: Vector3 = end_pos - start_pos
		var dist: float = to_target.length()
		
		if dist > 0.1:
			cable_mesh.visible = true
			cable_mesh.global_position = start_pos + (to_target * 0.5)
			cable_mesh.look_at(end_pos, Vector3.UP)
			cable_mesh.scale = Vector3(0.06, 0.06, dist)
	elif cable_mesh:
		cable_mesh.visible = false

func fire_grapple(origin_pos: Vector3, look_dir: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	if is_grappling:
		release_grapple()
		return false
	
	# 1. First search for grapple anchors in forward cone
	var best_pos: Vector3 = Vector3.ZERO
	var best_dist: float = max_range_meters
	var found_anchor: bool = false
	
	var anchors: Array[Node] = get_tree().get_nodes_in_group(&"grapple_anchors") if is_inside_tree() else []
	for node: Node in anchors:
		if node is Node3D and is_instance_valid(node):
			var a_pos: Vector3 = (node as Node3D).global_position
			var to_a: Vector3 = a_pos - origin_pos
			var dist: float = to_a.length()
			if dist <= max_range_meters and dist < best_dist:
				var angle: float = rad_to_deg(look_dir.angle_to(to_a))
				if angle <= 60.0:
					best_dist = dist
					best_pos = a_pos
					found_anchor = true
					target_rigid_body = null
					is_target_heavy = true
	
	if found_anchor:
		target_anchor_pos = best_pos
		is_grappling = true
		grapple_fired.emit(target_anchor_pos)
		grapple_latched.emit(target_anchor_pos, is_target_heavy)
		return true
	
	# 2. Raycast fallback
	if space_state:
		var ray_end: Vector3 = origin_pos + (look_dir.normalized() * max_range_meters)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin_pos, ray_end)
		var result: Dictionary = space_state.intersect_ray(query)
		
		if not result.is_empty():
			target_anchor_pos = result.position
			var collider: Object = result.collider
			
			if collider is RigidBody3D:
				target_rigid_body = collider as RigidBody3D
				is_target_heavy = target_rigid_body.mass > 80.0
			else:
				target_rigid_body = null
				is_target_heavy = true
			
			is_grappling = true
			grapple_fired.emit(target_anchor_pos)
			grapple_latched.emit(target_anchor_pos, is_target_heavy)
			return true
	
	return false

func process_grapple(delta: float, pilot_global_pos: Vector3) -> Vector3:
	if not is_grappling:
		return Vector3.ZERO
	
	var to_target: Vector3 = target_anchor_pos - pilot_global_pos
	var dist: float = to_target.length()
	
	if dist <= 1.2 or dist > (max_range_meters * 1.35):
		release_grapple()
		return Vector3.ZERO
	
	var dir: Vector3 = to_target.normalized()
	
	if is_target_heavy:
		# Pull pilot toward target
		return dir * pull_speed_ms
	elif target_rigid_body:
		# Pull lightweight crate toward pilot
		var pull_crate_dir: Vector3 = (pilot_global_pos - target_rigid_body.global_position).normalized()
		target_rigid_body.apply_central_force(pull_crate_dir * crate_drag_force * delta * 60.0)
		return Vector3.ZERO
	
	return Vector3.ZERO

func release_grapple() -> void:
	if not is_grappling:
		return
	is_grappling = false
	target_rigid_body = null
	if cable_mesh:
		cable_mesh.visible = false
	grapple_released.emit()
