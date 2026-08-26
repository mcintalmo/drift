class_name PilotJetpackState
extends State

@export var pilot: CharacterBody3D
@export var jetpack: JetpackComponent
@export var weapon_socket: WeaponSocketComponent

func physics_update(delta: float) -> void:
	if not pilot or not jetpack:
		return
	
	var is_holding_jetpack: bool = Input.is_action_pressed(&"pilot_jump_jetpack")
	if not is_holding_jetpack or not jetpack.has_fuel():
		transition_requested.emit(&"WalkingState")
		return
	
	if Input.is_action_just_pressed(&"pilot_melee_breach") and weapon_socket:
		weapon_socket.trigger_attack()
	
	# Query backpack imbalance
	var backpack_mass: float = 0.0
	var com_offset: Vector2 = Vector2.ZERO
	var backpack: HexInventoryComponent = pilot.get_node_or_null("BackpackInventoryComponent") as HexInventoryComponent
	if backpack:
		backpack_mass = backpack.get_total_items_mass()
		com_offset = backpack.get_com_offset_2d()
	
	var input_dir: Vector2 = Input.get_vector(&"steer_left", &"steer_right", &"brake_reverse", &"accelerate")
	var heading_dir: Vector3 = Vector3.ZERO
	
	var cam: Camera3D = pilot.get_viewport().get_camera_3d() if (pilot.is_inside_tree() and pilot.get_viewport()) else null
	var cam_forward: Vector3 = -cam.global_transform.basis.z if (cam and cam.is_inside_tree()) else Vector3(0, 0, -1)
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right: Vector3 = cam.global_transform.basis.x if (cam and cam.is_inside_tree()) else Vector3(1, 0, 0)
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	
	if input_dir.length() > 0.05:
		heading_dir = ((cam_right * input_dir.x) + (cam_forward * input_dir.y)).normalized()
	
	var jet_accel: Vector3 = jetpack.process_jetpack(delta, true, false, heading_dir)
	
	# Net vertical lift scaled by total payload mass
	var lift_mass_scaling: float = 1.0 / (1.0 + (backpack_mass / 60.0))
	pilot.velocity.y += (jet_accel.y * lift_mass_scaling * delta) - (9.81 * 0.2 * delta)
	pilot.velocity.y = clampf(pilot.velocity.y, -12.0, 15.0)
	
	# Character's local body right shoulder vector for airborne torque
	var char_right: Vector3 = pilot.global_transform.basis.x.normalized()
	
	# Airborne imbalance drift: strictly lateral when off-center
	var airborne_imbalance_drift: Vector3 = Vector3.ZERO
	if backpack_mass > 15.0 and absf(com_offset.x) > 0.01:
		var drift_force: float = (backpack_mass / 40.0) * 3.8
		airborne_imbalance_drift = char_right * (com_offset.x / 0.20) * drift_force
	
	if heading_dir.length() > 0.1:
		pilot.rotation.y = lerp_angle(pilot.rotation.y, atan2(-heading_dir.x, -heading_dir.z), 8.0 * delta)
		pilot.velocity.x += jet_accel.x * delta
		pilot.velocity.z += jet_accel.z * delta
	
	# Apply airborne imbalance force in body space
	pilot.velocity.x += airborne_imbalance_drift.x * delta
	pilot.velocity.z += airborne_imbalance_drift.z * delta
	
	# Visual model airborne tilt: only roll when off-center, only pitch when top-heavy
	var visual_model: Node3D = pilot.get_node_or_null("VisualModel") as Node3D
	if visual_model:
		var target_tilt_z: float = -(com_offset.x / 0.20) * deg_to_rad(18.0) * clampf(backpack_mass / 25.0, 0.0, 1.5)
		var top_heavy_amount: float = maxf(0.0, -com_offset.y)
		var target_tilt_x: float = (top_heavy_amount / 0.20) * deg_to_rad(10.0) * clampf(backpack_mass / 25.0, 0.0, 1.5)
		visual_model.rotation.z = lerpf(visual_model.rotation.z, target_tilt_z, 8.0 * delta)
		visual_model.rotation.x = lerpf(visual_model.rotation.x, target_tilt_x, 8.0 * delta)
	
	# Hover air drag (gentle to preserve ballistic / train momentum)
	pilot.velocity.x = lerpf(pilot.velocity.x, 0.0, 0.4 * delta)
	pilot.velocity.z = lerpf(pilot.velocity.z, 0.0, 0.4 * delta)
	
	pilot.move_and_slide()
	
	if pilot.is_on_floor() and not is_holding_jetpack:
		transition_requested.emit(&"WalkingState")
