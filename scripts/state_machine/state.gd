class_name State
extends Node

signal state_entered
signal state_exited
signal transition_requested(target_state_name: StringName)

var state_machine: StateMachine

func enter() -> void:
	state_entered.emit()

func exit() -> void:
	state_exited.emit()

func handle_input(_event: InputEvent) -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass
