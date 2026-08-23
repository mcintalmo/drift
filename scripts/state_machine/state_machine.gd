class_name StateMachine
extends Node

signal state_changed(from_state: StringName, to_state: StringName)

@export var initial_state: State

var current_state: State
var _states: Dictionary = {}

func _ready() -> void:
	# Index all child State nodes
	for child: Node in get_children():
		if child is State:
			_states[child.name] = child
			child.state_machine = self
			child.transition_requested.connect(transition_to)
	
	if initial_state:
		transition_to(initial_state.name)
	elif get_child_count() > 0 and get_child(0) is State:
		transition_to(get_child(0).name)

func transition_to(target_state_name: StringName) -> bool:
	if not _states.has(target_state_name):
		push_warning("StateMachine: state '%s' not found." % target_state_name)
		return false
	
	var from_name: StringName = current_state.name if current_state else &""
	if current_state:
		current_state.exit()
	
	current_state = _states[target_state_name]
	current_state.enter()
	state_changed.emit(from_name, target_state_name)
	return true

func handle_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

func update(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func physics_update(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func get_current_state_name() -> StringName:
	return current_state.name if current_state else &""
