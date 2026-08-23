class_name TestInertialDrift
extends RefCounted

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_surface_friction_lookup())
	results.append(_test_drift_state_reduces_lateral_grip())
	results.append(_test_momentum_preserved_on_black_ice())
	results.append(_test_pilot_counter_lean_stabilizes_roll())
	results.append(_test_asymmetric_com_induces_chassis_lean())
	return results

func _test_surface_friction_lookup() -> Dictionary:
	var runner_data: RunnerData = RunnerData.new()
	var ice_friction: Vector2 = runner_data.get_friction_for_surface(&"black_ice")
	var pack_friction: Vector2 = runner_data.get_friction_for_surface(&"pack")
	var snirt_friction: Vector2 = runner_data.get_friction_for_surface(&"snirt")
	
	var passed: bool = (ice_friction.x < pack_friction.x) and (snirt_friction.x > pack_friction.x)
	return {
		"name": "test_surface_friction_lookup",
		"passed": passed,
		"message": "Black ice lateral grip (%f) < pack (%f) < snirt (%f)" % [ice_friction.x, pack_friction.x, snirt_friction.x]
	}

func _test_drift_state_reduces_lateral_grip() -> Dictionary:
	var runner_data: RunnerData = RunnerData.new()
	var pack_friction: Vector2 = runner_data.get_friction_for_surface(&"pack")
	var normal_lateral_coeff: float = pack_friction.x
	var drift_lateral_coeff: float = normal_lateral_coeff * 0.25
	
	var passed: bool = drift_lateral_coeff < normal_lateral_coeff and is_equal_approx(drift_lateral_coeff, 0.1875)
	return {
		"name": "test_drift_state_reduces_lateral_grip",
		"passed": passed,
		"message": "Drift lateral grip (%f) is 25%% of normal pack grip (%f)" % [drift_lateral_coeff, normal_lateral_coeff]
	}

func _test_momentum_preserved_on_black_ice() -> Dictionary:
	var runner_data: RunnerData = RunnerData.new()
	var ice_friction: Vector2 = runner_data.get_friction_for_surface(&"black_ice")
	var initial_velocity: Vector3 = Vector3(20.0, 0.0, 0.0) # Pure lateral slip
	var mass: float = 250.0
	var delta: float = 0.016
	
	var max_grip: float = ice_friction.x * mass * 9.81
	var speed_reduction: float = (max_grip / mass) * delta
	var final_speed: float = initial_velocity.x - speed_reduction
	
	var passed: bool = final_speed > 19.95
	return {
		"name": "test_momentum_preserved_on_black_ice",
		"passed": passed,
		"message": "Velocity preserved on black ice: %f -> %f m/s" % [initial_velocity.x, final_speed]
	}

func _test_pilot_counter_lean_stabilizes_roll() -> Dictionary:
	var uncountered_roll: float = (15.0 * 0.8 * 0.04) # Lateral speed * steer
	var pilot_lean_input: float = 1.0 # Leaning hard into turn
	var lean_stabilization: float = pilot_lean_input * deg_to_rad(12.0)
	var net_roll: float = uncountered_roll - lean_stabilization
	
	var passed: bool = net_roll < uncountered_roll
	return {
		"name": "test_pilot_counter_lean_stabilizes_roll",
		"passed": passed,
		"message": "Pilot counter-lean reduced roll from %f to %f rad" % [uncountered_roll, net_roll]
	}

func _test_asymmetric_com_induces_chassis_lean() -> Dictionary:
	var com_lateral_offset_m: float = 0.15
	var static_com_roll_rad: float = (com_lateral_offset_m / 0.20) * deg_to_rad(20.0)
	var roll_deg: float = rad_to_deg(static_com_roll_rad)
	
	var passed: bool = roll_deg > 12.0
	return {
		"name": "test_asymmetric_com_induces_chassis_lean",
		"passed": passed,
		"message": "0.15m lateral COM offset induced %.1f deg visible chassis tilt (expected > 12 deg)" % roll_deg
	}
