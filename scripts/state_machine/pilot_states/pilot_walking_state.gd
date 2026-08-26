class_name PilotWalkingState
extends State

@export var pilot: CharacterBody3D
@export var jetpack: JetpackComponent
@export var grapple: PilotGrappleComponent
@export var weapon_socket: WeaponSocketComponent

func physics_update(delta: float) -> void:
	if not pilot:
		return
	
	# Check jetpack trigger
	if Input.is_action_pressed(&"pilot_jump_jetpack") and jetpack and jetpack.has_fuel():
		transition_requested.emit(&"JetpackState")
		return
	
	# Check grapple trigger (G or RMB)
	if (Input.is_action_just_pressed(&"pilot_wrist_grapple") or Input.is_action_just_pressed(&"winch_quick")) and grapple:
		var cam: Camera3D = pilot.get_viewport().get_camera_3d() if (pilot.is_inside_tree() and pilot.get_viewport()) else null
		var look_dir: Vector3 = -cam.global_transform.basis.z if (cam and cam.is_inside_tree()) else -pilot.global_transform.basis.z
		if grapple.fire_grapple(pilot.global_position + Vector3(0, 1.0, 0), look_dir, pilot.get_world_3d().direct_space_state):
			transition_requested.emit(&"GrapplingState")
			return
		else:
			# Remote Sled Winch Detach trigger while on foot (G or RMB when not grappling onto an anchor)
			var sleds: Array[Node] = pilot.get_tree().get_nodes_in_group(&"player_sled") if pilot.is_inside_tree() else []
			for s_node: Node in sleds:
				var w_comp: Node = s_node.get_node_or_null("SledWinchComponent")
				if w_comp and w_comp.get("is_tethered") == true and w_comp.has_method("detach_tether"):
					w_comp.call("detach_tether")
	
	# Check attack / breach trigger
	if Input.is_action_just_pressed(&"pilot_melee_breach") and weapon_socket:
		weapon_socket.trigger_attack()
	
	# Query backpack mass and center-of-mass offset
	var backpack_mass: float = 0.0
	var com_offset: Vector2 = Vector2.ZERO
	var backpack: HexInventoryComponent = pilot.get_node_or_null("BackpackInventoryComponent") as HexInventoryComponent
	if backpack:
		backpack_mass = backpack.get_total_items_mass()
		com_offset = backpack.get_com_offset_2d()
	
	# 1. Base movement speed scaling
	var base_walk_speed: float = 6.0
	if backpack_mass > 30.0:
		var extra_mass: float = backpack_mass - 30.0
		base_walk_speed = maxf(2.2, base_walk_speed - (extra_mass * 0.045))
	
	var move_speed: float = base_walk_speed
	# Sprint allowed only if not overburdened (< 65kg backpack)
	if Input.is_action_pressed(&"sprint") and backpack_mass < 65.0:
		move_speed = base_walk_speed * 1.6
	
	var input_dir: Vector2 = Input.get_vector(&"steer_left", &"steer_right", &"brake_reverse", &"accelerate")
	var actual_move_vec: Vector3 = Vector3.ZERO
	
	if input_dir.length() > 0.05:
		var cam: Camera3D = pilot.get_viewport().get_camera_3d() if (pilot.is_inside_tree() and pilot.get_viewport()) else null
		var cam_forward: Vector3 = -cam.global_transform.basis.z if (cam and cam.is_inside_tree()) else Vector3(0, 0, -1)
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
		var cam_right: Vector3 = cam.global_transform.basis.x if (cam and cam.is_inside_tree()) else Vector3(1, 0, 0)
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		
		var intended_move_dir: Vector3 = ((cam_right * input_dir.x) + (cam_forward * input_dir.y)).normalized()
		
		# Compute character's local right shoulder vector based on active movement direction
		var char_right: Vector3 = Vector3(-intended_move_dir.z, 0.0, intended_move_dir.x).normalized()
		
		# Imbalance lateral veer (only active when weight is laterally off-center)
		var pull_strength: float = clampf((backpack_mass / 70.0) * 0.35, 0.0, 0.45)
		var body_imbalance_pull: Vector3 = char_right * (com_offset.x / 0.20) * pull_strength
		
		actual_move_vec = (intended_move_dir + body_imbalance_pull).normalized()
		pilot.rotation.y = lerp_angle(pilot.rotation.y, atan2(-actual_move_vec.x, -actual_move_vec.z), 14.0 * delta)
	
	# 2. Moving Platform Velocity Query (Train Roof & Sled Coupling)
	var platform_vel: Vector3 = _get_current_platform_velocity()
	var is_on_moving_platform: bool = platform_vel.length_squared() > 0.5
	
	# 3. Locomotion Kinematics & Momentum Preservation
	if not pilot.is_on_floor() and not is_on_moving_platform:
		# AIRBORNE (Ballistic trajectory from dismount, jump, or ramp)
		if input_dir.length() > 0.05:
			pilot.velocity.x += actual_move_vec.x * 12.0 * delta
			pilot.velocity.z += actual_move_vec.z * 12.0 * delta
		# Low aerodynamic drag preserves high-speed dismount momentum
		pilot.velocity.x = move_toward(pilot.velocity.x, 0.0, 0.8 * delta)
		pilot.velocity.z = move_toward(pilot.velocity.z, 0.0, 0.8 * delta)
		pilot.velocity.y -= 9.81 * delta
	else:
		# ON GROUND OR STANDING ON MOVING TRAIN/SLED ROOF PLATFORM
		if input_dir.length() > 0.05:
			var target_vx: float = platform_vel.x + (actual_move_vec.x * move_speed)
			var target_vz: float = platform_vel.z + (actual_move_vec.z * move_speed)
			pilot.velocity.x = move_toward(pilot.velocity.x, target_vx, 30.0 * delta)
			pilot.velocity.z = move_toward(pilot.velocity.z, target_vz, 30.0 * delta)
		else:
			# Firm coupling to platform: standing on moving roof travels seamlessly with train
			pilot.velocity.x = move_toward(pilot.velocity.x, platform_vel.x, 35.0 * delta)
			pilot.velocity.z = move_toward(pilot.velocity.z, platform_vel.z, 35.0 * delta)
		
		if is_on_moving_platform:
			pilot.velocity.y = platform_vel.y
		else:
			pilot.velocity.y = 0.0
			
		if jetpack:
			jetpack.process_jetpack(delta, false, true, Vector3.ZERO)
	
	# 4. Procedural Torso Lean:
	var visual_model: Node3D = pilot.get_node_or_null("VisualModel") as Node3D
	if visual_model:
		var target_lean_z: float = -(com_offset.x / 0.20) * deg_to_rad(14.0) * clampf(backpack_mass / 30.0, 0.0, 1.5)
		var top_heavy_amount: float = maxf(0.0, -com_offset.y)
		var target_lean_x: float = (top_heavy_amount / 0.20) * deg_to_rad(12.0) * clampf(backpack_mass / 30.0, 0.0, 1.5)
		visual_model.rotation.z = lerpf(visual_model.rotation.z, target_lean_z, 10.0 * delta)
		visual_model.rotation.x = lerpf(visual_model.rotation.x, target_lean_x, 10.0 * delta)
	
	pilot.move_and_slide()

## Resolves moving train roof or sled platform velocity beneath the pilot's feet
func _get_current_platform_velocity() -> Vector3:
	if not pilot:
		return Vector3.ZERO
		
	# 1. Check direct slide collisions on floor
	if pilot.is_on_floor():
		for i: int in range(pilot.get_slide_collision_count()):
			var col: KinematicCollision3D = pilot.get_slide_collision(i)
			if col.get_normal().y > 0.4:
				var collider: Object = col.get_collider()
				if collider:
					var train_vel: Vector3 = _extract_body_velocity(collider)
					if train_vel.length_squared() > 0.01:
						return train_vel
						
	# 2. Downward probe raycast to detect moving roof or sled underneath (within 1.2m)
	var space_state: PhysicsDirectSpaceState3D = pilot.get_world_3d().direct_space_state if pilot.is_inside_tree() else null
	if space_state:
		var start: Vector3 = pilot.global_position + Vector3(0, 0.4, 0)
		var end: Vector3 = pilot.global_position + Vector3(0, -1.2, 0)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
		query.exclude = [pilot.get_rid()]
		var res: Dictionary = space_state.intersect_ray(query)
		if not res.is_empty():
			var collider: Object = res.get("collider")
			if collider:
				var train_vel: Vector3 = _extract_body_velocity(collider)
				if train_vel.length_squared() > 0.01:
					return train_vel
					
	return pilot.get_platform_velocity()

func _extract_body_velocity(collider: Object) -> Vector3:
	if not collider or not (collider is Node):
		return Vector3.ZERO
	var cur: Node = collider as Node
	var depth: int = 0
	while cur and depth < 6:
		if cur is TrainCar:
			var car: TrainCar = cur as TrainCar
			var fwd: Vector3 = -car.global_transform.basis.z.normalized() if car.is_inside_tree() else -car.transform.basis.z.normalized()
			return fwd * car.forward_speed_ms
		if cur is MovingTrain:
			var train: MovingTrain = cur as MovingTrain
			var fwd: Vector3 = -train.global_transform.basis.z.normalized() if train.is_inside_tree() else -train.transform.basis.z.normalized()
			return fwd * train.current_speed_ms
		if cur is CharacterBody3D and cur.is_in_group(&"player_sled"):
			var drift_comp: Node = cur.get_node_or_null("InertialDriftComponent")
			if drift_comp and "velocity_3d" in drift_comp:
				return drift_comp.get("velocity_3d")
			return (cur as CharacterBody3D).velocity
		cur = cur.get_parent()
		depth += 1
	return Vector3.ZERO
