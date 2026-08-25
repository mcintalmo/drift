class_name SledWinchComponent
extends Node3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal tether_attached(anchor_pos: Vector3, is_dynamic: bool)
signal tether_detached
signal tension_updated(current_tension_n: float, max_tension_n: float)

@export_group("Dependencies")
@export var winch_data: WinchData
@export var parent_body: CharacterBody3D
@export var cable_mesh: MeshInstance3D

@export_group("State")
@export var is_tethered: bool = false
@export var current_target_pos: Vector3 = Vector3.ZERO
@export var current_tension_force: float = 0.0

var _target_anchor: GrappleAnchorComponent = null
var _rest_cable_length_m: float = 0.0
var _is_reeling_in: bool = false

func _ready() -> void:
	if not winch_data:
		winch_data = preload("res://resources/winches/standard_winch.tres")
	if not parent_body and get_parent() is CharacterBody3D:
		parent_body = get_parent() as CharacterBody3D
		
	if not cable_mesh:
		cable_mesh = MeshInstance3D.new()
		cable_mesh.name = "WinchCableVisual"
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.04
		cyl.height = 1.0
		cable_mesh.mesh = cyl
		
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.9, 0.95, 1.0)
		mat.metallic = 0.95
		mat.roughness = 0.2
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.6, 1.0, 1.0)
		mat.emission_energy_multiplier = 1.4
		cable_mesh.material_override = mat
		
		cable_mesh.visible = false
		add_child(cable_mesh)

func _process(_delta: float) -> void:
	if is_tethered and cable_mesh:
		var start_pos: Vector3 = get_winch_position()
		var end_pos: Vector3 = _target_anchor.get_global_anchor_position() if (_target_anchor and is_instance_valid(_target_anchor)) else current_target_pos
		var to_anchor: Vector3 = end_pos - start_pos
		var dist: float = to_anchor.length()
		
		if dist > 0.1:
			cable_mesh.visible = true
			cable_mesh.global_position = start_pos + (to_anchor * 0.5)
			cable_mesh.look_at(end_pos, Vector3.UP)
			# Rotate CylinderMesh so length aligns with look direction (Z axis)
			cable_mesh.rotation.x += PI * 0.5
			cable_mesh.scale = Vector3(0.08, dist, 0.08)
		else:
			cable_mesh.visible = false
	elif cable_mesh:
		cable_mesh.visible = false

func fire_quick_cone(forward_dir: Vector3) -> bool:
	if is_tethered:
		detach_tether()
		return false
	
	var origin: Vector3 = global_position
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	if not space_state:
		return false
		
	var cam: Camera3D = get_viewport().get_camera_3d() if (is_inside_tree() and get_viewport()) else null
	var cam_forward: Vector3 = -cam.global_transform.basis.z.normalized() if (cam and cam.is_inside_tree()) else forward_dir
	
	var cone_angle_deg: float = winch_data.quick_cone_angle_degrees if winch_data else 60.0
	var min_dot: float = cos(deg_to_rad(cone_angle_deg))
	var best_dist: float = winch_data.max_lock_range_meters if winch_data else 50.0
	var best_anchor: GrappleAnchorComponent = null
	var best_score: float = -9999.0
	
	var anchors: Array[Node] = get_tree().get_nodes_in_group(&"grapple_anchors") if is_inside_tree() else []
	for node: Node in anchors:
		if node is GrappleAnchorComponent and node.is_grappleable and is_instance_valid(node):
			var anchor_pos: Vector3 = node.get_global_anchor_position()
			var to_anchor: Vector3 = anchor_pos - origin
			var dist: float = to_anchor.length()
			
			if dist <= best_dist and dist > 1.0:
				var dir_to_anchor: Vector3 = to_anchor.normalized()
				var dot_fwd: float = forward_dir.dot(dir_to_anchor)
				var dot_cam: float = cam_forward.dot(dir_to_anchor)
				var max_dot: float = maxf(dot_fwd, dot_cam)
				
				if max_dot >= min_dot:
					# Check line-of-sight raycast (exclude sled)
					var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, anchor_pos)
					query.exclude = [parent_body.get_rid()] if parent_body else []
					var result: Dictionary = space_state.intersect_ray(query)
					
					var hit_collider: Object = result.get("collider")
					var is_valid_hit: bool = result.is_empty() or hit_collider == node or hit_collider == node.get_parent()
					if not is_valid_hit and hit_collider is Node:
						var hit_node: Node = hit_collider as Node
						if hit_node.is_in_group(&"train_convoy") or (hit_node.get_parent() and hit_node.get_parent().is_in_group(&"train_convoy")):
							is_valid_hit = true
					
					if is_valid_hit:
						var score: float = (max_dot * 50.0) - dist
						if score > best_score:
							best_score = score
							best_anchor = node
	
	if best_anchor:
		attach_to_anchor(best_anchor)
		return true
	
	return false

func get_winch_position() -> Vector3:
	if is_inside_tree():
		return global_position
	return position

func attach_to_anchor(anchor: GrappleAnchorComponent) -> void:
	_target_anchor = anchor
	is_tethered = true
	current_target_pos = anchor.get_global_anchor_position()
	_rest_cable_length_m = (current_target_pos - get_winch_position()).length()
	
	var is_dynamic: bool = anchor.anchor_type != GrappleAnchorComponent.AnchorType.STATIC_PYLON
	tether_attached.emit(current_target_pos, is_dynamic)
	GlobalEvents.emit_winch_attached(current_target_pos, is_dynamic)

func detach_tether() -> void:
	if not is_tethered:
		return
	is_tethered = false
	_target_anchor = null
	current_tension_force = 0.0
	_is_reeling_in = false
	if cable_mesh:
		cable_mesh.visible = false
	
	tether_detached.emit()
	GlobalEvents.emit_winch_detached()

func set_reeling(is_reeling: bool) -> void:
	_is_reeling_in = is_reeling

## Computes spring force vector exerted on the sled by the cable
func compute_tether_force(delta: float, current_velocity: Vector3) -> Vector3:
	if not is_tethered:
		return Vector3.ZERO
		
	if _target_anchor and is_instance_valid(_target_anchor):
		current_target_pos = _target_anchor.get_global_anchor_position()
		
	var to_anchor: Vector3 = current_target_pos - get_winch_position()
	var current_len: float = to_anchor.length()
	
	# Reel in cable: rapidly shortens down to 2.5 meters when actively reeling
	if _is_reeling_in and winch_data:
		_rest_cable_length_m = maxf(2.5, _rest_cable_length_m - (winch_data.reel_in_speed_ms * 1.5) * delta)
	
	var stretch: float = current_len - _rest_cable_length_m
	if stretch <= 0.0:
		current_tension_force = 0.0
		tension_updated.emit(0.0, 99999.0)
		return Vector3.ZERO
	
	var cable_dir: Vector3 = to_anchor.normalized()
	var spring_k: float = (winch_data.spring_constant_k if winch_data else 650.0) * 1.5
	var damp_c: float = (winch_data.damping_coefficient_c if winch_data else 28.0) * 1.2
	
	var spring_force_mag: float = spring_k * stretch
	
	# Compute relative separation velocity including moving anchor speed
	var host_vel: Vector3 = _target_anchor.get_parent_body_velocity() if (_target_anchor and is_instance_valid(_target_anchor)) else Vector3.ZERO
	var relative_vel: Vector3 = host_vel - current_velocity
	var separation_velocity: float = relative_vel.dot(cable_dir)
	
	var damping_force_mag: float = damp_c * separation_velocity
	var total_tension: float = maxf(0.0, spring_force_mag + damping_force_mag)
	
	# Extra active reeling pull force when reeling in
	if _is_reeling_in:
		total_tension += 900.0
	
	current_tension_force = total_tension
	tension_updated.emit(current_tension_force, 99999.0)
	GlobalEvents.emit_winch_tension(current_tension_force, 99999.0)
	
	return cable_dir * total_tension
