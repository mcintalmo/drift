class_name PilotGrappleComponent
extends Node3D

const GrappleAnchorClass = preload("res://scripts/components/grapple_anchor_component.gd")

signal grapple_fired(target_pos: Vector3)
signal grapple_latched(target_pos: Vector3, is_heavy: bool)
signal grapple_released

@export var max_range_meters: float = 28.0
@export var pull_speed_ms: float = 22.0
@export var crate_drag_force: float = 45.0
@export var cable_mesh: MeshInstance3D

var is_grappling: bool = false
var target_anchor_pos: Vector3 = Vector3.ZERO
var target_anchor: GrappleAnchorComponent = null
var target_node: Node3D = null
var target_rigid_body: RigidBody3D = null
var local_hit_offset: Vector3 = Vector3.ZERO
var is_target_heavy: bool = true

func _ready() -> void:
	if not cable_mesh:
		cable_mesh = MeshInstance3D.new()
		cable_mesh.name = "WristCableVisual"
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.03
		cyl.height = 1.0
		cable_mesh.mesh = cyl
		
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.92, 0.96, 1.0)
		mat.metallic = 0.95
		mat.roughness = 0.2
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.7, 1.0, 1.0)
		mat.emission_energy_multiplier = 1.8
		cable_mesh.material_override = mat
		
		cable_mesh.visible = false
		add_child(cable_mesh)

func _process(_delta: float) -> void:
	if is_grappling and cable_mesh:
		var start_pos: Vector3 = global_position
		var end_pos: Vector3 = get_current_target_position()
		var to_target: Vector3 = end_pos - start_pos
		var dist: float = to_target.length()
		
		if dist > 0.1:
			cable_mesh.visible = true
			cable_mesh.global_position = start_pos + (to_target * 0.5)
			cable_mesh.look_at(end_pos, Vector3.UP)
			cable_mesh.rotation.x += PI * 0.5
			cable_mesh.scale = Vector3(0.06, dist, 0.06)
		else:
			cable_mesh.visible = false
	elif cable_mesh:
		cable_mesh.visible = false

## Returns current real-time world position of the moving or static grapple target
func get_current_target_position() -> Vector3:
	if target_anchor and is_instance_valid(target_anchor):
		return target_anchor.get_global_anchor_position()
	if target_node and is_instance_valid(target_node):
		return target_node.global_transform * local_hit_offset
	if target_rigid_body and is_instance_valid(target_rigid_body):
		return target_rigid_body.global_transform * local_hit_offset
	return target_anchor_pos

func fire_grapple(origin_pos: Vector3, look_dir: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	if is_grappling:
		release_grapple()
		return false
	
	# 1. First search for grapple anchors in forward cone
	var best_anchor: GrappleAnchorComponent = null
	var best_dist: float = max_range_meters
	
	var anchors: Array[Node] = get_tree().get_nodes_in_group(&"grapple_anchors") if is_inside_tree() else []
	for node: Node in anchors:
		if node is GrappleAnchorComponent and node.is_grappleable and is_instance_valid(node):
			var a_pos: Vector3 = node.get_global_anchor_position()
			var to_a: Vector3 = a_pos - origin_pos
			var dist: float = to_a.length()
			if dist <= max_range_meters and dist < best_dist:
				var angle: float = rad_to_deg(look_dir.angle_to(to_a))
				if angle <= 65.0:
					best_dist = dist
					best_anchor = node
	
	if best_anchor:
		target_anchor = best_anchor
		target_node = null
		target_rigid_body = null
		is_target_heavy = true
		target_anchor_pos = best_anchor.get_global_anchor_position()
		is_grappling = true
		grapple_fired.emit(target_anchor_pos)
		grapple_latched.emit(target_anchor_pos, is_target_heavy)
		return true
	
	# 2. Raycast fallback against physical structures, train cars, sled, and crates
	if space_state:
		var ray_end: Vector3 = origin_pos + (look_dir.normalized() * max_range_meters)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin_pos, ray_end)
		var result: Dictionary = space_state.intersect_ray(query)
		
		if not result.is_empty():
			var hit_pos: Vector3 = result.position
			var collider: Object = result.collider
			target_anchor = null
			
			if collider is RigidBody3D:
				target_rigid_body = collider as RigidBody3D
				target_node = target_rigid_body
				local_hit_offset = target_rigid_body.global_transform.affine_inverse() * hit_pos
				is_target_heavy = target_rigid_body.mass > 80.0
			elif collider is Node3D:
				target_rigid_body = null
				target_node = collider as Node3D
				local_hit_offset = target_node.global_transform.affine_inverse() * hit_pos
				is_target_heavy = true
			else:
				target_rigid_body = null
				target_node = null
				target_anchor_pos = hit_pos
				is_target_heavy = true
				
			target_anchor_pos = hit_pos
			is_grappling = true
			grapple_fired.emit(target_anchor_pos)
			grapple_latched.emit(target_anchor_pos, is_target_heavy)
			return true
	
	return false

func process_grapple(delta: float, pilot_global_pos: Vector3) -> Vector3:
	if not is_grappling:
		return Vector3.ZERO
	
	var cur_target_pos: Vector3 = get_current_target_position()
	var to_target: Vector3 = cur_target_pos - pilot_global_pos
	var dist: float = to_target.length()
	
	# Host velocity (e.g. moving train speed ~14m/s or moving sled speed)
	var host_velocity: Vector3 = Vector3.ZERO
	if target_anchor and is_instance_valid(target_anchor):
		host_velocity = target_anchor.get_parent_body_velocity()
	elif target_node and is_instance_valid(target_node):
		if "velocity" in target_node:
			host_velocity = target_node.velocity
		elif "forward_speed_ms" in target_node and "global_transform" in target_node:
			var fwd: Vector3 = -target_node.global_transform.basis.z.normalized()
			host_velocity = fwd * float(target_node.get("forward_speed_ms"))
	
	# Arrival / Boarding Threshold (within 2.0m of target anchor or roof)
	if dist <= 2.0:
		var is_roof_boarding: bool = false
		var is_sled_target: bool = false
		if target_anchor:
			if target_anchor.is_roof_boarding_anchor:
				is_roof_boarding = true
			elif target_anchor.anchor_type == GrappleAnchorClass.AnchorType.DYNAMIC_VEHICLE or (target_anchor.get_parent() and target_anchor.get_parent().is_in_group(&"player_sled")):
				is_sled_target = true
		elif target_node and (target_node is AnimatableBody3D or target_node.is_in_group(&"train_convoy")):
			is_roof_boarding = true
			
		release_grapple()
		if is_roof_boarding:
			# Upward landing hop onto moving train roof
			return host_velocity + Vector3(0, 3.4, 0)
		elif is_sled_target:
			# Match sled velocity upon landing next to chassis
			return host_velocity + Vector3(0, 1.0, 0)
		return host_velocity + Vector3(0, 1.2, 0)
	
	if dist > (max_range_meters * 1.6):
		release_grapple()
		return Vector3.ZERO
	
	var dir: Vector3 = to_target.normalized()
	
	if is_target_heavy:
		# Rapid precision direct-line transit pull directly to target coordinates + host velocity
		var effective_speed: float = maxf(pull_speed_ms, dist * 6.5)
		return (dir * effective_speed) + host_velocity
	elif target_rigid_body and is_instance_valid(target_rigid_body):
		# Pull lightweight crate toward pilot
		var pull_crate_dir: Vector3 = (pilot_global_pos - target_rigid_body.global_position).normalized()
		target_rigid_body.apply_central_force(pull_crate_dir * crate_drag_force * delta * 60.0)
		return Vector3.ZERO
	
	return Vector3.ZERO

func release_grapple() -> void:
	if not is_grappling:
		return
	is_grappling = false
	target_anchor = null
	target_node = null
	target_rigid_body = null
	if cable_mesh:
		cable_mesh.visible = false
	grapple_released.emit()
