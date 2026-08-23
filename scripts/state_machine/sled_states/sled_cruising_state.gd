class_name SledCruisingState
extends State

@export var sled_chassis: SledChassis
@export var drift_component: InertialDriftComponent
@export var winch_component: SledWinchComponent

func physics_update(delta: float) -> void:
	if not drift_component:
		return
	
	# Check for airborne
	if drift_component.ground_raycast and not drift_component.ground_raycast.is_colliding():
		transition_requested.emit(&"AirborneState")
		return
	
	# Check for tethered state
	if winch_component and winch_component.is_tethered:
		transition_requested.emit(&"TetheredState")
		return
	
	var is_driven: bool = sled_chassis.is_occupied if sled_chassis else true
	
	var throttle: float = Input.get_axis(&"brake_reverse", &"accelerate") if is_driven else 0.0
	var steer: float = Input.get_axis(&"steer_left", &"steer_right") if is_driven else 0.0
	var drift: bool = Input.is_action_pressed(&"handbrake_drift") if is_driven else false
	var lean: float = Input.get_axis(&"pilot_lean_left", &"pilot_lean_right") if is_driven else 0.0
	
	if drift:
		transition_requested.emit(&"DriftingState")
		return
	
	drift_component.update_physics(delta, throttle, steer, false, lean)
