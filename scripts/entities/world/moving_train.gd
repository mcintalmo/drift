class_name MovingTrain
extends Node3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")
const TrainCarClass = preload("res://scripts/entities/world/train_car.gd")
const TrainHitchPlatformClass = preload("res://scripts/entities/world/train_hitch_platform.gd")

signal train_started_moving
signal train_escaped_into_exit_tunnel
signal car_decoupled(car_index: int)

@export var cruise_speed_ms: float = 14.0
@export var acceleration_ms2: float = 3.5
@export var start_delay_seconds: float = 4.0
@export var car_spacing_m: float = 15.0
@export var bogie_wheelbase_m: float = 7.5
@export var train_cars: Array[TrainCar] = []
@export var hitch_platforms: Array[TrainCar] = []

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

func initialize_train_on_path(path_curve: Curve3D, cars: Array = [], hitches: Array = []) -> void:
	curve_3d = path_curve
	total_track_length_m = curve_3d.get_baked_length() if curve_3d else 1000.0
	lead_progress_m = 0.0
	current_speed_ms = 0.0
	has_started = false
	has_escaped = false
	delay_timer = start_delay_seconds
	
	if not cars.is_empty():
		train_cars.clear()
		for c in cars:
			if c is TrainCar:
				train_cars.append(c as TrainCar)
	if not hitches.is_empty():
		hitch_platforms.clear()
		for h in hitches:
			if h is TrainCar:
				hitch_platforms.append(h as TrainCar)
	else:
		_auto_spawn_hitch_platforms_if_needed()
		
	_link_cars()
	_update_car_positions(0.0)

func _auto_spawn_hitch_platforms_if_needed() -> void:
	if not hitch_platforms.is_empty() or train_cars.size() < 2:
		return
		
	var hitch_scene: PackedScene = load("res://scenes/entities/train/CircularHitchPlatform.tscn")
	if not hitch_scene:
		return
		
	for i: int in range(train_cars.size()):
		var hitch: TrainCar = hitch_scene.instantiate() as TrainCar
		hitch.name = "HitchPlatform_%d" % i
		hitch.car_index = i
		hitch.set("lead_car", train_cars[i])
		if i + 1 < train_cars.size():
			hitch.set("trailing_car", train_cars[i + 1])
		add_child(hitch)
		hitch_platforms.append(hitch)

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
			
	for hitch: TrainCar in hitch_platforms:
		if is_instance_valid(hitch):
			hitch.decoupled.connect(func(c_idx: int) -> void:
				car_decoupled.emit(c_idx)
			)

func _physics_process(delta: float) -> void:
	if not curve_3d or has_escaped:
		return
		
	# 1. Preparation Delay in Entrance Cave
	if delay_timer > 0.0:
		delay_timer -= delta
		_update_car_positions(delta)
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
	if lead_progress_m >= total_track_length_m + (float(train_cars.size() + 1) * car_spacing_m):
		has_escaped = true
		train_escaped_into_exit_tunnel.emit()

## Samples continuous 3D track position with linear tunnel extensions at endpoints
func _sample_track_point(s: float) -> Vector3:
	if not curve_3d or total_track_length_m <= 0.0:
		return Vector3.ZERO
		
	var start_pt: Vector3 = curve_3d.sample_baked(0.0)
	var next_start_pt: Vector3 = curve_3d.sample_baked(minf(1.0, total_track_length_m))
	var start_dir: Vector3 = (next_start_pt - start_pt).normalized()
	if start_dir.length_squared() < 0.01:
		start_dir = Vector3(0, 0, 1)
		
	var end_pt: Vector3 = curve_3d.sample_baked(total_track_length_m)
	var prev_end_pt: Vector3 = curve_3d.sample_baked(maxf(0.0, total_track_length_m - 1.0))
	var end_dir: Vector3 = (end_pt - prev_end_pt).normalized()
	if end_dir.length_squared() < 0.01:
		end_dir = Vector3(0, 0, 1)
		
	if s < 0.0:
		return start_pt + (start_dir * s)
	elif s > total_track_length_m:
		return end_pt + (end_dir * (s - total_track_length_m))
	else:
		return curve_3d.sample_baked(s)

func _update_car_positions(_delta: float) -> void:
	if not curve_3d or total_track_length_m <= 0.0:
		return

	var half_wheelbase: float = bogie_wheelbase_m * 0.5

	# 1. Update Main Train Cars
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
			target_s = car.distance_along_track
			
		# Dual-point contact (front bogie and rear bogie)
		var front_pos: Vector3 = _sample_track_point(target_s + half_wheelbase)
		var rear_pos: Vector3 = _sample_track_point(target_s - half_wheelbase)
		
		# Center position is the midpoint between front and rear wheelsets
		var center_pos: Vector3 = (front_pos + rear_pos) * 0.5
		
		# Direction is the tangent line connecting rear to front wheelset
		var car_dir: Vector3 = (front_pos - rear_pos).normalized()
		if car_dir.length_squared() < 0.01:
			car_dir = Vector3.FORWARD
			
		var rot_y: float = atan2(-car_dir.x, -car_dir.z)
		var pitch_x: float = asin(clampf(car_dir.y, -0.9, 0.9))
		
		var is_car_active: bool = (target_s >= -4.5) and (target_s <= total_track_length_m + 4.5)
		car.visible = is_car_active
		car.process_mode = Node.PROCESS_MODE_INHERIT if is_car_active else Node.PROCESS_MODE_DISABLED
		
		car.set_platform_transform(center_pos, Vector3(pitch_x, rot_y, 0.0), _delta)

	# 2. Update Independent Circular Hitch Platforms (Centered directly on track curve midpoint)
	for i: int in range(hitch_platforms.size()):
		var hitch: TrainCar = hitch_platforms[i]
		if not is_instance_valid(hitch):
			continue
			
		var target_s: float = 0.0
		if hitch.is_coupled:
			target_s = lead_progress_m - (float(i) * car_spacing_m) - (car_spacing_m * 0.5)
			hitch.distance_along_track = target_s
			hitch.set_train_speed(current_speed_ms)
		else:
			target_s = hitch.distance_along_track
			
		var hitch_pos: Vector3 = _sample_track_point(target_s)
		var next_pt: Vector3 = _sample_track_point(target_s + 0.6)
		var prev_pt: Vector3 = _sample_track_point(target_s - 0.6)
		var hitch_dir: Vector3 = (next_pt - prev_pt).normalized()
		if hitch_dir.length_squared() < 0.01:
			hitch_dir = Vector3.FORWARD
			
		var rot_y: float = atan2(-hitch_dir.x, -hitch_dir.z)
		var pitch_x: float = asin(clampf(hitch_dir.y, -0.9, 0.9))
		
		var is_hitch_active: bool = (target_s >= -3.5) and (target_s <= total_track_length_m + 3.5)
		hitch.visible = is_hitch_active
		hitch.process_mode = Node.PROCESS_MODE_INHERIT if is_hitch_active else Node.PROCESS_MODE_DISABLED
		
		hitch.set_platform_transform(hitch_pos, Vector3(pitch_x, rot_y, 0.0), _delta)

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
