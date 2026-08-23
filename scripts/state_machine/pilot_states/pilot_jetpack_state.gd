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
	
	var input_dir: Vector2 = Input.get_vector(&"steer_left", &"steer_right", &"brake_reverse", &"accelerate")
	var heading_dir: Vector3 = Vector3.ZERO
	if input_dir.length() > 0.05:
		var cam: Camera3D = pilot.get_viewport().get_camera_3d() if (pilot.is_inside_tree() and pilot.get_viewport()) else null
		var cam_forward: Vector3 = -cam.global_transform.basis.z if (cam and cam.is_inside_tree()) else Vector3(0, 0, -1)
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
		var cam_right: Vector3 = cam.global_transform.basis.x if (cam and cam.is_inside_tree()) else Vector3(1, 0, 0)
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		heading_dir = ((cam_right * input_dir.x) + (cam_forward * input_dir.y)).normalized()
	
	var jet_accel: Vector3 = jetpack.process_jetpack(delta, true, false, heading_dir)
	
	# Apply jetpack forces with hover gravity reduction
	pilot.velocity.y += jet_accel.y * delta - (9.81 * 0.2 * delta)
	pilot.velocity.y = clampf(pilot.velocity.y, -12.0, 15.0)
	
	if heading_dir.length() > 0.1:
		pilot.rotation.y = lerp_angle(pilot.rotation.y, atan2(-heading_dir.x, -heading_dir.z), 8.0 * delta)
		pilot.velocity.x += jet_accel.x * delta
		pilot.velocity.z += jet_accel.z * delta
	
	# Apply hover air drag
	pilot.velocity.x = lerpf(pilot.velocity.x, 0.0, 2.0 * delta)
	pilot.velocity.z = lerpf(pilot.velocity.z, 0.0, 2.0 * delta)
	
	pilot.move_and_slide()
	
	if pilot.is_on_floor() and not is_holding_jetpack:
		transition_requested.emit(&"WalkingState")
