class_name SledTetheredState
extends State

@export var sled_chassis: SledChassis
@export var drift_component: InertialDriftComponent
@export var winch_component: SledWinchComponent

func physics_update(delta: float) -> void:
	if not drift_component or not winch_component:
		return
	
	var is_driven: bool = sled_chassis.is_occupied if sled_chassis else true
	
	if not winch_component.is_tethered:
		var drift: bool = Input.is_action_pressed(&"handbrake_drift") if is_driven else false
		if drift:
			transition_requested.emit(&"DriftingState")
		else:
			transition_requested.emit(&"CruisingState")
		return
	
	var throttle: float = Input.get_axis(&"brake_reverse", &"accelerate") if is_driven else 0.0
	var steer: float = Input.get_axis(&"steer_left", &"steer_right") if is_driven else 0.0
	var drift: bool = Input.is_action_pressed(&"handbrake_drift") if is_driven else false
	var lean: float = Input.get_axis(&"pilot_lean_left", &"pilot_lean_right") if is_driven else 0.0
	
	# Reel in input
	var is_reeling: bool = Input.is_action_pressed(&"winch_reel") if is_driven else false
	winch_component.set_reeling(is_reeling)
	
	# Calculate spring tension force from cable
	var spring_force: Vector3 = winch_component.compute_tether_force(delta, drift_component.velocity_3d)
	
	# Apply physics with external spring force
	drift_component.update_physics(delta, throttle, steer, drift, lean, spring_force)
