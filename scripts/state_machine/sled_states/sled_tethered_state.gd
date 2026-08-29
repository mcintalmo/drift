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
	
	# Dedicated Reel-In: Hold [R], [Shift], or [RMB] to winch right up to the train car
	var is_reeling: bool = Input.is_action_pressed(&"winch_reel") or Input.is_action_pressed(&"sprint") if is_driven else false
	winch_component.set_reeling(is_reeling)
	
	# Calculate rigid towing tension force from cable
	var spring_force: Vector3 = winch_component.compute_tether_force(delta, drift_component.velocity_3d)
	
	# Towing alignment: tension pulls sled heading in the direction of the cable
	if spring_force.length() > 40.0:
		var pull_dir_horiz: Vector3 = Vector3(spring_force.x, 0.0, spring_force.z).normalized()
		var target_yaw: float = atan2(-pull_dir_horiz.x, -pull_dir_horiz.z)
		drift_component.heading_angle_rad = lerp_angle(drift_component.heading_angle_rad, target_yaw, 4.0 * delta)
	
	# Apply physics with external towing force
	drift_component.update_physics(delta, throttle, steer, drift, lean, spring_force)
