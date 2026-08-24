class_name TestTrainDecoupling
extends RefCounted

const MovingTrainClass = preload("res://scripts/entities/world/moving_train.gd")
const TrainCarClass = preload("res://scripts/entities/world/train_car.gd")
const GroundCrateClass = preload("res://scripts/entities/world/ground_crate.gd")
const ActionProgressDonutClass = preload("res://scripts/ui/action_progress_donut.gd")

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_train_car_initial_coupled_state())
	results.append(_test_train_car_uncoupling_cascades_to_trailing_cars())
	results.append(_test_decoupled_car_decelerates())
	results.append(_test_train_spline_path_following())
	results.append(_test_boxcar_plasma_breach_sliding_doors())
	results.append(_test_first_time_container_looting_channel())
	return results

func _test_train_car_initial_coupled_state() -> Dictionary:
	var car: TrainCar = TrainCarClass.new()
	car.is_coupled = true
	car.set_train_speed(18.0)
	
	var passed: bool = car.is_coupled and (car.forward_speed_ms == 18.0)
	
	car.free()
	return {
		"name": "test_train_car_initial_coupled_state",
		"passed": passed,
		"message": "Train car initialized coupled and moving at 18.0 m/s"
	}

func _test_train_car_uncoupling_cascades_to_trailing_cars() -> Dictionary:
	var car_lead: TrainCar = TrainCarClass.new()
	var car_mid: TrainCar = TrainCarClass.new()
	var car_rear: TrainCar = TrainCarClass.new()
	
	car_lead.car_index = 0
	car_mid.car_index = 1
	car_rear.car_index = 2
	
	car_lead.trailing_cars = [car_mid, car_rear]
	car_mid.trailing_cars = [car_rear]
	
	# Uncouple mid car
	car_mid.uncouple_car()
	
	var passed: bool = car_lead.is_coupled and not car_mid.is_coupled and not car_rear.is_coupled
	
	car_lead.free()
	car_mid.free()
	car_rear.free()
	return {
		"name": "test_train_car_uncoupling_cascades_to_trailing_cars",
		"passed": passed,
		"message": "Uncoupling mid car cascaded to rear car while lead car remained coupled"
	}

func _test_decoupled_car_decelerates() -> Dictionary:
	var car: TrainCar = TrainCarClass.new()
	car.is_coupled = false
	car.forward_speed_ms = 20.0
	
	# Simulate 1 second of rail drag deceleration
	car._physics_process(1.0)
	
	var final_speed: float = car.forward_speed_ms
	var passed: bool = final_speed < 20.0 and is_equal_approx(final_speed, 15.5)
	
	car.free()
	return {
		"name": "test_decoupled_car_decelerates",
		"passed": passed,
		"message": "Decoupled car speed dropped from 20.0 -> %f m/s after 1.0s" % final_speed
	}

func _test_train_spline_path_following() -> Dictionary:
	var train: MovingTrain = MovingTrainClass.new()
	var car1: TrainCar = TrainCarClass.new()
	var car2: TrainCar = TrainCarClass.new()
	
	var curve: Curve3D = Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(50, 2, 0))
	curve.add_point(Vector3(100, 0, 0))
	
	train.cruise_speed_ms = 15.0
	train.start_delay_seconds = 0.0 # Instant start for test
	train.car_spacing_m = 10.0
	train.initialize_train_on_path(curve, [car1, car2])
	train.current_speed_ms = 15.0 # Set speed for constant speed test
	
	# Advance 2 seconds at 15m/s (30m progress)
	train._physics_process(2.0)
	
	var lead_pos: Vector3 = car1.global_position if car1.is_inside_tree() else car1.position
	var passed: bool = lead_pos.x > 25.0 and lead_pos.x < 35.0 and car1.forward_speed_ms > 0.0
	
	car1.free()
	car2.free()
	train.free()
	return {
		"name": "test_train_spline_path_following",
		"passed": passed,
		"message": "Train convoy progressed along 3D Curve3D spline to X=%.1fm (speed=15m/s)" % lead_pos.x
	}

func _test_boxcar_plasma_breach_sliding_doors() -> Dictionary:
	var car: TrainCar = TrainCarClass.new()
	car.doors_locked = true
	
	car.breach_doors()
	
	var passed: bool = not car.doors_locked
	car.free()
	return {
		"name": "test_boxcar_plasma_breach_sliding_doors",
		"passed": passed,
		"message": "Boxcar magnetic lock breached and sliding doors unlocked (passed: %s)" % str(passed)
	}

func _test_first_time_container_looting_channel() -> Dictionary:
	var crate: GroundCrate = GroundCrateClass.new()
	var donut: Control = ActionProgressDonutClass.new()
	
	var state: Dictionary = {"opened": false}
	crate.interact_loot(null, donut, func() -> void:
		state["opened"] = true
	)
	
	# Simulate completion of channel
	if donut.has_method("complete_channel"):
		donut.complete_channel()
	
	var passed: bool = crate.is_searched and state["opened"] and not crate.is_locked
	var msg: String = "Loot channel: searched=%s, opened=%s, locked=%s" % [str(crate.is_searched), str(state["opened"]), str(crate.is_locked)]
	
	crate.free()
	donut.free()
	return {
		"name": "test_first_time_container_looting_channel",
		"passed": passed,
		"message": msg
	}
