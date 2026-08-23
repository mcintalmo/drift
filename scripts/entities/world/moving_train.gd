class_name MovingTrain
extends Node3D

@export var cruise_speed_ms: float = 12.0
@export var train_cars: Array[TrainCar] = []
@export var loop_boundary_z: float = -200.0
@export var loop_reset_z: float = 180.0

func _ready() -> void:
	# Link train cars sequentially
	for i: int in range(train_cars.size()):
		var car: TrainCar = train_cars[i]
		car.car_index = i
		# Assign trailing cars
		var trailing: Array[TrainCar] = []
		for j: int in range(i + 1, train_cars.size()):
			trailing.append(train_cars[j])
		car.trailing_cars = trailing

func _physics_process(delta: float) -> void:
	for car: TrainCar in train_cars:
		if is_instance_valid(car) and car.is_coupled:
			car.set_train_speed(cruise_speed_ms)
			car.move_and_slide()
			
			# Wrap around for infinite heist loop testing
			if car.global_position.z < loop_boundary_z:
				car.global_position.z += (loop_reset_z - loop_boundary_z)
