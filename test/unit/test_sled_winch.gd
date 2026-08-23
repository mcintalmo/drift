class_name TestSledWinch
extends RefCounted

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_spring_force_zero_at_rest_length())
	results.append(_test_spring_force_proportional_to_stretch())
	results.append(_test_tensile_break_threshold())
	return results

func _test_spring_force_zero_at_rest_length() -> Dictionary:
	var winch: SledWinchComponent = SledWinchComponent.new()
	winch.winch_data = WinchData.new()
	winch.winch_data.spring_constant_k = 100.0
	
	var anchor: GrappleAnchorComponent = GrappleAnchorComponent.new()
	anchor.position = Vector3(0.0, 0.0, 10.0) # 10m away
	winch.attach_to_anchor(anchor)
	
	# Compute force when cable length is exactly at rest length (10m)
	var force: Vector3 = winch.compute_tether_force(0.016, Vector3.ZERO)
	var passed: bool = force.length() == 0.0
	
	winch.free()
	anchor.free()
	return {
		"name": "test_spring_force_zero_at_rest_length",
		"passed": passed,
		"message": "Spring force at rest length is 0.0 N"
	}

func _test_spring_force_proportional_to_stretch() -> Dictionary:
	var winch: SledWinchComponent = SledWinchComponent.new()
	winch.winch_data = WinchData.new()
	winch.winch_data.spring_constant_k = 100.0
	winch.winch_data.damping_coefficient_c = 0.0
	
	var anchor: GrappleAnchorComponent = GrappleAnchorComponent.new()
	anchor.position = Vector3(0.0, 0.0, 10.0)
	winch.attach_to_anchor(anchor)
	
	# Sled drifts further away to 15m (5m stretch)
	winch.position = Vector3(0.0, 0.0, -5.0)
	var force: Vector3 = winch.compute_tether_force(0.016, Vector3.ZERO)
	
	# Expected force: 100 N/m * 5m = 500 N pointing towards anchor (+Z)
	var passed: bool = is_equal_approx(force.length(), 500.0) and force.z > 0.0
	
	winch.free()
	anchor.free()
	return {
		"name": "test_spring_force_proportional_to_stretch",
		"passed": passed,
		"message": "5m stretch produced %f N (expected 500.0 N)" % force.length()
	}

func _test_tensile_break_threshold() -> Dictionary:
	var winch: SledWinchComponent = SledWinchComponent.new()
	winch.winch_data = WinchData.new()
	winch.winch_data.spring_constant_k = 100.0
	winch.winch_data.tensile_limit_force = 400.0 # Limit 400 N
	
	var anchor: GrappleAnchorComponent = GrappleAnchorComponent.new()
	anchor.position = Vector3(0.0, 0.0, 10.0)
	winch.attach_to_anchor(anchor)
	
	# Sled stretches 6m (600 N > 400 N limit)
	winch.position = Vector3(0.0, 0.0, -6.0)
	var _force: Vector3 = winch.compute_tether_force(0.016, Vector3.ZERO)
	
	# Winch should snap and detach
	var passed: bool = not winch.is_tethered
	
	winch.free()
	anchor.free()
	return {
		"name": "test_tensile_break_threshold",
		"passed": passed,
		"message": "Cable snapped and detached when tension exceeded tensile limit"
	}
