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
	
	# Check grapple trigger
	if Input.is_action_just_pressed(&"pilot_wrist_grapple") and grapple:
		var look_dir: Vector3 = -pilot.global_transform.basis.z
		if grapple.fire_grapple(pilot.global_position + Vector3(0, 1.0, 0), look_dir, pilot.get_world_3d().direct_space_state):
			transition_requested.emit(&"GrapplingState")
			return
	
	# Check attack / breach trigger
	if Input.is_action_just_pressed(&"pilot_melee_breach") and weapon_socket:
		weapon_socket.trigger_attack()
	
	# Calculate dynamic backpack encumbrance
	var backpack_mass: float = 0.0
	var backpack: HexInventoryComponent = pilot.get_node_or_null("BackpackInventoryComponent") as HexInventoryComponent
	if backpack:
		backpack_mass = backpack.get_total_items_mass()
	
	var base_walk_speed: float = 6.0
	if backpack_mass > 30.0:
		var extra_mass: float = backpack_mass - 30.0
		base_walk_speed = maxf(2.2, base_walk_speed - (extra_mass * 0.045))
	
	var move_speed: float = base_walk_speed
	# Sprint allowed only if not overburdened (< 65kg backpack)
	if Input.is_action_pressed(&"sprint") and backpack_mass < 65.0:
		move_speed = base_walk_speed * 1.6
	
	var input_dir: Vector2 = Input.get_vector(&"steer_left", &"steer_right", &"brake_reverse", &"accelerate")
	var move_vec: Vector3 = Vector3.ZERO
	if input_dir.length() > 0.05:
		var cam: Camera3D = pilot.get_viewport().get_camera_3d() if (pilot.is_inside_tree() and pilot.get_viewport()) else null
		var cam_forward: Vector3 = -cam.global_transform.basis.z if (cam and cam.is_inside_tree()) else Vector3(0, 0, -1)
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
		var cam_right: Vector3 = cam.global_transform.basis.x if (cam and cam.is_inside_tree()) else Vector3(1, 0, 0)
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		
		move_vec = (cam_right * input_dir.x) + (cam_forward * input_dir.y)
		move_vec = move_vec.normalized()
		
		pilot.rotation.y = lerp_angle(pilot.rotation.y, atan2(-move_vec.x, -move_vec.z), 14.0 * delta)
		pilot.velocity.x = move_vec.x * move_speed
		pilot.velocity.z = move_vec.z * move_speed
	else:
		pilot.velocity.x = move_toward(pilot.velocity.x, 0.0, 25.0 * delta)
		pilot.velocity.z = move_toward(pilot.velocity.z, 0.0, 25.0 * delta)
	
	# Gravity & ground check
	if not pilot.is_on_floor():
		pilot.velocity.y -= 9.81 * delta
	else:
		pilot.velocity.y = 0.0
		if jetpack:
			jetpack.process_jetpack(delta, false, true, Vector3.ZERO)
	
	pilot.move_and_slide()
