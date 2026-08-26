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
		var look_dir: Vector3 = -pilot.global_transform.basis.z
		if grapple.fire_grapple(pilot.global_position + Vector3(0, 1.0, 0), look_dir, pilot.get_world_3d().direct_space_state):
			transition_requested.emit(&"GrapplingState")
			return
			
	# Remote Sled Winch Detach trigger while on foot (G or RMB when not grappling)
	if Input.is_action_just_pressed(&"winch_quick") or Input.is_action_just_pressed(&"pilot_wrist_grapple"):
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
	
	# 2. Locomotion Kinematics & Momentum Preservation
	if not pilot.is_on_floor():
		# AIRBORNE (Ballistic trajectory from dismount, jump, or ramp)
		if input_dir.length() > 0.05:
			pilot.velocity.x += actual_move_vec.x * 12.0 * delta
			pilot.velocity.z += actual_move_vec.z * 12.0 * delta
		# Low aerodynamic drag preserves high-speed dismount momentum
		pilot.velocity.x = move_toward(pilot.velocity.x, 0.0, 0.8 * delta)
		pilot.velocity.z = move_toward(pilot.velocity.z, 0.0, 0.8 * delta)
		pilot.velocity.y -= 9.81 * delta
	else:
		# ON GROUND (Smooth slide friction when landing at high speed)
		if input_dir.length() > 0.05:
			var target_vx: float = actual_move_vec.x * move_speed
			var target_vz: float = actual_move_vec.z * move_speed
			pilot.velocity.x = move_toward(pilot.velocity.x, target_vx, 18.0 * delta)
			pilot.velocity.z = move_toward(pilot.velocity.z, target_vz, 18.0 * delta)
		else:
			# Snow surface sliding deceleration
			pilot.velocity.x = move_toward(pilot.velocity.x, 0.0, 10.0 * delta)
			pilot.velocity.z = move_toward(pilot.velocity.z, 0.0, 10.0 * delta)
		
		pilot.velocity.y = 0.0
		if jetpack:
			jetpack.process_jetpack(delta, false, true, Vector3.ZERO)
	
	# 3. Procedural Torso Lean:
	var visual_model: Node3D = pilot.get_node_or_null("VisualModel") as Node3D
	if visual_model:
		var target_lean_z: float = -(com_offset.x / 0.20) * deg_to_rad(14.0) * clampf(backpack_mass / 30.0, 0.0, 1.5)
		var top_heavy_amount: float = maxf(0.0, -com_offset.y)
		var target_lean_x: float = (top_heavy_amount / 0.20) * deg_to_rad(12.0) * clampf(backpack_mass / 30.0, 0.0, 1.5)
		visual_model.rotation.z = lerpf(visual_model.rotation.z, target_lean_z, 10.0 * delta)
		visual_model.rotation.x = lerpf(visual_model.rotation.x, target_lean_x, 10.0 * delta)
	
	pilot.move_and_slide()
