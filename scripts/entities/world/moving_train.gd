class_name MovingTrain
extends Node3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")
const TrainCarClass = preload("res://scripts/entities/world/train_car.gd")

signal train_started_moving
signal train_escaped_into_exit_tunnel
signal car_decoupled(car_index: int)

@export var cruise_speed_ms: float = 14.0
@export var acceleration_ms2: float = 3.5
@export var start_delay_seconds: float = 4.0
@export var car_spacing_m: float = 10.0
@export var train_cars: Array[TrainCar] = []

var curve_3d: Curve3D
var total_track_length_m: float = 0.0
var lead_progress_m: float = 0.0
var current_speed_ms: float = 0.0
var delay_timer: float = 0.0
var has_started: bool = false
var has_escaped: bool = false

func _ready() -> void:
	delay_timer = start_delay_seconds
	_link_cars()

func initialize_train_on_path(path_curve: Curve3D, cars: Array[TrainCar] = []) -> void:
	curve_3d = path_curve
	total_track_length_m = curve_3d.get_baked_length() if curve_3d else 1000.0
	lead_progress_m = 0.0
	current_speed_ms = 0.0
	has_started = false
	has_escaped = false
	delay_timer = start_delay_seconds
	
	if not cars.is_empty():
		train_cars = cars
	_link_cars()
	_update_car_positions(0.0)

func _link_cars() -> void:
	for i: int in range(train_cars.size()):
		var car: TrainCar = train_cars[i]
		if is_instance_valid(car):
			car.car_index = i
			var trailing: Array[TrainCar] = []
			for j: int in range(i + 1, train_cars.size()):
				if is_instance_valid(train_cars[j]):
					trailing.append(train_cars[j])
			car.trailing_cars = trailing
			car.decoupled.connect(func(c_idx: int) -> void:
				car_decoupled.emit(c_idx)
			)

func _physics_process(delta: float) -> void:
	if not curve_3d or has_escaped:
		return
		
	# 1. Preparation Delay in Entrance Cave
	if delay_timer > 0.0:
		delay_timer -= delta
		if delay_timer <= 0.0:
			has_started = true
			train_started_moving.emit()
		return
		
	# 2. Acceleration to Cruise Speed
	if current_speed_ms < cruise_speed_ms:
		current_speed_ms = minf(cruise_speed_ms, current_speed_ms + acceleration_ms2 * delta)
		
	# 3. Advance Lead Locomotive along 3D Track Spline
	lead_progress_m += current_speed_ms * delta
	
	_update_car_positions(delta)
	
	# 4. Exit Tunnel Escape Check
	if lead_progress_m >= total_track_length_m + (float(train_cars.size()) * car_spacing_m):
		has_escaped = true
		train_escaped_into_exit_tunnel.emit()

func _update_car_positions(_delta: float) -> void:
	if not curve_3d:
		return
		
	for i: int in range(train_cars.size()):
		var car: TrainCar = train_cars[i]
		if not is_instance_valid(car):
			continue
			
		var target_s: float = 0.0
		if car.is_coupled:
			target_s = lead_progress_m - (float(i) * car_spacing_m)
			car.distance_along_track = target_s
			car.set_train_speed(current_speed_ms)
		else:
			# Decoupled car progresses by its own coasting distance
			target_s = car.distance_along_track
			
		if target_s >= 0.0:
			var clamped_s: float = clampf(target_s, 0.0, total_track_length_m)
			var pos_3d: Vector3 = curve_3d.sample_baked(clamped_s)
			var next_s: float = clampf(clamped_s + 0.6, 0.0, total_track_length_m)
			var next_pos: Vector3 = curve_3d.sample_baked(next_s)
			
			var dir_3d: Vector3 = (next_pos - pos_3d).normalized()
			if dir_3d.length_squared() < 0.01:
				dir_3d = Vector3(0, 0, -1)
				
			var rot_y: float = atan2(dir_3d.x, dir_3d.z)
			var pitch_x: float = -asin(clampf(dir_3d.y, -0.9, 0.9))
			
			if car.is_inside_tree():
				car.global_position = pos_3d
			else:
				car.position = pos_3d
			car.rotation = Vector3(pitch_x, rot_y, 0.0)

## Returns estimated time remaining in seconds until the train enters the exit tunnel
func get_time_until_extraction_seconds() -> float:
	if has_escaped:
		return 0.0
	if current_speed_ms <= 0.1:
		return (total_track_length_m / cruise_speed_ms) + delay_timer
	var remaining_dist: float = maxf(0.0, total_track_length_m - lead_progress_m)
	return remaining_dist / current_speed_ms

## Returns current world 3D position of the lead locomotive
func get_train_lead_position() -> Vector3:
	if not train_cars.is_empty() and is_instance_valid(train_cars[0]):
		return train_cars[0].global_position if train_cars[0].is_inside_tree() else train_cars[0].position
	if curve_3d and total_track_length_m > 0.0:
		return curve_3d.sample_baked(clampf(lead_progress_m, 0.0, total_track_length_m))
	return Vector3.ZERO
