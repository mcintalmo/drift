class_name JetpackComponent
extends Node

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal fuel_changed(current_fuel: float, max_fuel: float)
signal thrust_started
signal thrust_ended
signal fuel_depleted

@export var jetpack_data: JetpackData
@export var current_fuel: float = 100.0
@export var is_thrusting: bool = false

func _ready() -> void:
	if not jetpack_data:
		jetpack_data = JetpackData.new()
	current_fuel = jetpack_data.max_fuel_capacity

## Updates jetpack physics and returns vertical + horizontal acceleration vector
func process_jetpack(delta: float, is_activating: bool, is_grounded: bool, heading_dir: Vector3) -> Vector3:
	if not jetpack_data:
		return Vector3.ZERO
	
	var accel: Vector3 = Vector3.ZERO
	var was_thrusting: bool = is_thrusting
	
	if is_activating and current_fuel > 0.0:
		is_thrusting = true
		var burn: float = jetpack_data.fuel_burn_rate_per_sec * delta
		current_fuel = maxf(0.0, current_fuel - burn)
		
		# Vertical lift
		accel.y += jetpack_data.vertical_thrust_force
		# Forward boost
		accel += Vector3(heading_dir.x, 0.0, heading_dir.z).normalized() * jetpack_data.forward_boost_force
		
		if not was_thrusting:
			thrust_started.emit()
		
		if current_fuel <= 0.0:
			fuel_depleted.emit()
			is_thrusting = false
	else:
		is_thrusting = false
		if was_thrusting:
			thrust_ended.emit()
		
		# Ground fuel recharge
		if is_grounded and current_fuel < jetpack_data.max_fuel_capacity:
			var recharge: float = jetpack_data.fuel_recharge_rate_per_sec * delta
			current_fuel = minf(jetpack_data.max_fuel_capacity, current_fuel + recharge)
	
	fuel_changed.emit(current_fuel, jetpack_data.max_fuel_capacity)
	GlobalEvents.emit_jetpack_fuel_changed(current_fuel, jetpack_data.max_fuel_capacity)
	
	return accel

func has_fuel() -> bool:
	return current_fuel > 0.0

func get_fuel_percentage() -> float:
	return current_fuel / maxf(1.0, jetpack_data.max_fuel_capacity if jetpack_data else 100.0)
