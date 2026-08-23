class_name TestPilotLocomotion
extends RefCounted

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_jetpack_thrust_and_fuel_consumption())
	results.append(_test_jetpack_recharges_on_ground())
	results.append(_test_pilot_mount_dismount_sled())
	return results

func _test_jetpack_thrust_and_fuel_consumption() -> Dictionary:
	var jetpack: JetpackComponent = JetpackComponent.new()
	jetpack.jetpack_data = JetpackData.new()
	jetpack.jetpack_data.max_fuel_capacity = 100.0
	jetpack.jetpack_data.fuel_burn_rate_per_sec = 20.0
	jetpack.jetpack_data.vertical_thrust_force = 25.0
	jetpack.current_fuel = 100.0
	
	# Process 1 second of jetpack activation
	var accel: Vector3 = jetpack.process_jetpack(1.0, true, false, Vector3.FORWARD)
	
	var final_fuel: float = jetpack.current_fuel
	var is_thrusting: bool = jetpack.is_thrusting
	var passed: bool = (final_fuel == 80.0) and (accel.y == 25.0) and is_thrusting
	
	jetpack.free()
	return {
		"name": "test_jetpack_thrust_and_fuel_consumption",
		"passed": passed,
		"message": "Fuel burned: 100 -> %f, Vertical Lift = %f m/s^2" % [final_fuel, accel.y]
	}

func _test_jetpack_recharges_on_ground() -> Dictionary:
	var jetpack: JetpackComponent = JetpackComponent.new()
	jetpack.jetpack_data = JetpackData.new()
	jetpack.jetpack_data.max_fuel_capacity = 100.0
	jetpack.jetpack_data.fuel_recharge_rate_per_sec = 15.0
	jetpack.current_fuel = 50.0
	
	# Process 2 seconds grounded without activation
	jetpack.process_jetpack(2.0, false, true, Vector3.ZERO)
	
	var final_fuel: float = jetpack.current_fuel
	var is_thrusting: bool = jetpack.is_thrusting
	var passed: bool = (final_fuel == 80.0) and not is_thrusting
	
	jetpack.free()
	return {
		"name": "test_jetpack_recharges_on_ground",
		"passed": passed,
		"message": "Fuel recharged from 50 -> %f on ground" % final_fuel
	}

func _test_pilot_mount_dismount_sled() -> Dictionary:
	var pilot: Pilot = Pilot.new()
	var sled: CharacterBody3D = CharacterBody3D.new()
	sled.position = Vector3(10.0, 0.0, 5.0)
	
	pilot.mount_into_sled(sled)
	var mounted_success: bool = pilot.is_mounted_in_sled and (pilot.current_sled == sled)
	
	pilot.dismount_from_sled()
	var dismount_success: bool = not pilot.is_mounted_in_sled and (pilot.current_sled == null)
	
	var passed: bool = mounted_success and dismount_success
	
	pilot.free()
	sled.free()
	return {
		"name": "test_pilot_mount_dismount_sled",
		"passed": passed,
		"message": "Pilot mounted and dismounted sled successfully"
	}
