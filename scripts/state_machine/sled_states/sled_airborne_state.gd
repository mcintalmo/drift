class_name SledAirborneState
extends State

@export var sled_chassis: SledChassis
@export var drift_component: InertialDriftComponent

func physics_update(delta: float) -> void:
	if not drift_component:
		return
	
	var is_driven: bool = sled_chassis.is_occupied if sled_chassis else true
	
	# Check for ground contact
	if drift_component.ground_raycast and drift_component.ground_raycast.is_colliding():
		var drift: bool = Input.is_action_pressed(&"handbrake_drift") if is_driven else false
		if drift:
			transition_requested.emit(&"DriftingState")
		else:
			transition_requested.emit(&"CruisingState")
		return
	
	var throttle: float = Input.get_axis(&"brake_reverse", &"accelerate") if is_driven else 0.0
	var steer: float = Input.get_axis(&"steer_left", &"steer_right") if is_driven else 0.0
	var lean: float = Input.get_axis(&"pilot_lean_left", &"pilot_lean_right") if is_driven else 0.0
	
	# In air, reduced steering and momentum preservation
	drift_component.update_physics(delta, throttle * 0.25, steer * 0.5, false, lean)
