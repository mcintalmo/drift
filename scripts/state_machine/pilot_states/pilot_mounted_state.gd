class_name PilotMountedState
extends State

@export var pilot: CharacterBody3D

func enter() -> void:
	super.enter()
	if pilot:
		pilot.visible = false
		pilot.set_collision_layer_value(3, false) # Disable on-foot collision layer

func exit() -> void:
	super.exit()
	if pilot:
		pilot.visible = true
		pilot.set_collision_layer_value(3, true)

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pilot_mount_dismount") and pilot:
		pilot.dismount_from_sled()

func dismount(dismount_pos: Vector3, dismount_velocity: Vector3) -> void:
	if pilot:
		if pilot.is_inside_tree():
			pilot.global_position = dismount_pos
		else:
			pilot.position = dismount_pos
		pilot.velocity = dismount_velocity
	transition_requested.emit(&"WalkingState")
