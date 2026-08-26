class_name PilotGrappleComponent
extends Node3D

const GrappleAnchorClass = preload("res://scripts/components/grapple_anchor_component.gd")

signal grapple_fired(target_pos: Vector3)
signal grapple_latched(target_pos: Vector3, is_heavy: bool)
signal grapple_released

@export var max_range_meters: float = 30.0
@export var pull_speed_ms: float = 24.0
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

## Validates whether a physics collider represents a valid grapple-able structure (trees, train cars, sleds, pylons, crates)
func is_collider_grappleable(collider: Object) -> bool:
	if not collider or not (collider is Node):
		return false
		
	var node: Node = collider as Node
	
	# Explicitly reject ground / hex terrain surfaces
	if node.is_in_group(&"terrain") or node.name.begins_with("HexTile") or node.name.begins_with("Terrain") or node.name.begins_with("Ground") or node.name.begins_with("RailSubPiece"):
		return false
		
	# 1. Has GrappleAnchorComponent or is in grapple_anchors group
	if node.is_in_group(&"grapple_anchors") or node.has_node("GrappleAnchorComponent") or node.has_node("SledGrappleAnchor"):
		return true
		
	# 2. Check node and its parent hierarchy for valid interactive structure groups
	var cur: Node = node
	var depth: int = 0
	while cur and depth < 6:
		if cur.is_in_group(&"grapple_anchors") or cur.is_in_group(&"train_convoy") or cur.is_in_group(&"player_sled") or cur.is_in_group(&"trees") or cur.is_in_group(&"boulders") or cur.is_in_group(&"loot_crates") or cur.is_in_group(&"props"):
			return true
		if cur.name.begins_with("ArmoredLocomotive") or cur.name.begins_with("ArmoredBoxcar") or cur.name.begins_with("SledChassis") or cur.name.begins_with("PetrifiedPine") or cur.name.begins_with("GlacialBoulder") or cur.name.begins_with("AbandonedRailCar") or cur.name.begins_with("GroundCrate"):
			return true
		cur = cur.get_parent()
		depth += 1
		
	if node is RigidBody3D:
		return true
		
	return false

func fire_grapple(origin_pos: Vector3, look_dir: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	if is_grappling:
		release_grapple()
		return false
	
	# 1. Search for grapple anchors in forward camera cone
	var best_anchor: GrappleAnchorComponent = null
	var best_score: float = -9999.0
	
	var anchors: Array[Node] = get_tree().get_nodes_in_group(&"grapple_anchors") if is_inside_tree() else []
	for node: Node in anchors:
		if node is GrappleAnchorComponent and node.is_grappleable and is_instance_valid(node):
			var a_pos: Vector3 = node.get_global_anchor_position()
			var to_a: Vector3 = a_pos - origin_pos
			var dist: float = to_a.length()
			if dist <= max_range_meters and dist > 1.0:
				var dir_to_a: Vector3 = to_a.normalized()
				var dot: float = look_dir.dot(dir_to_a)
				if dot >= 0.50: # Wide ~60-degree lock cone
					# Line-of-sight check
					var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin_pos, a_pos)
					var res: Dictionary = space_state.intersect_ray(query) if space_state else {}
					var hit_col: Object = res.get("collider")
					var is_clear: bool = res.is_empty() or hit_col == node or hit_col == node.get_parent() or (hit_col is Node and (hit_col.is_in_group(&"train_convoy") or hit_col.is_in_group(&"player_sled")))
					
					if is_clear:
						var score: float = (dot * 50.0) - dist
						if score > best_score:
							best_score = score
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
	
	# 2. Raycast fallback against physical structures (trains, trees, boulders, crates, sleds) - NEVER ground
	if space_state:
		var ray_end: Vector3 = origin_pos + (look_dir.normalized() * max_range_meters)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin_pos, ray_end)
		var result: Dictionary = space_state.intersect_ray(query)
		
		if not result.is_empty():
			var collider: Object = result.collider
			if is_collider_grappleable(collider):
				var hit_pos: Vector3 = result.position
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
