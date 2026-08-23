class_name PilotGrapplingState
extends State

@export var pilot: CharacterBody3D
@export var grapple: PilotGrappleComponent

func physics_update(delta: float) -> void:
	if not pilot or not grapple or not grapple.is_grappling:
		transition_requested.emit(&"WalkingState")
		return
	
	if Input.is_action_just_pressed(&"pilot_wrist_grapple") or Input.is_action_just_pressed(&"pilot_jump_jetpack"):
		grapple.release_grapple()
		transition_requested.emit(&"WalkingState")
		return
	
	var pull_velocity: Vector3 = grapple.process_grapple(delta, pilot.global_position)
	if pull_velocity != Vector3.ZERO:
		pilot.velocity = pull_velocity
		pilot.move_and_slide()
	else:
		pilot.move_and_slide()
