class_name TestTrainDecoupling
extends RefCounted

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_train_car_initial_coupled_state())
	results.append(_test_train_car_uncoupling_cascades_to_trailing_cars())
	results.append(_test_decoupled_car_decelerates())
	return results

func _test_train_car_initial_coupled_state() -> Dictionary:
	var car: TrainCar = TrainCar.new()
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
	var car_lead: TrainCar = TrainCar.new()
	var car_mid: TrainCar = TrainCar.new()
	var car_rear: TrainCar = TrainCar.new()
	
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
	var car: TrainCar = TrainCar.new()
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
