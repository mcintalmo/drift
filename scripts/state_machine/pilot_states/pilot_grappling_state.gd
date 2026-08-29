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
		
	# Board sled directly when close enough to chassis
	if Input.is_action_just_pressed(&"pilot_mount_dismount") or Input.is_action_just_pressed(&"pilot_interact") or Input.is_action_just_pressed(&"interact"):
		var sleds: Array[Node] = pilot.get_tree().get_nodes_in_group(&"player_sled") if pilot.is_inside_tree() else []
		for s_node: Node in sleds:
			if s_node is CharacterBody3D and is_instance_valid(s_node):
				var sled: CharacterBody3D = s_node as CharacterBody3D
				var s_pos: Vector3 = sled.global_position if sled.is_inside_tree() else sled.position
				if pilot.global_position.distance_to(s_pos) <= 4.5:
					grapple.release_grapple()
					if pilot.has_method("mount_into_sled"):
						pilot.mount_into_sled(sled)
					return
	
	var pull_velocity: Vector3 = grapple.process_grapple(delta, pilot.global_position)
	if pull_velocity != Vector3.ZERO:
		pilot.velocity = pull_velocity
		pilot.move_and_slide()
	else:
		pilot.move_and_slide()
