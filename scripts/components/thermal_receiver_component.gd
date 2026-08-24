class_name ThermalReceiverComponent
extends Node

const DynamicWeatherManagerClass = preload("res://scripts/world/dynamic_weather_manager.gd")

signal thermal_shield_changed(current_heat: float, max_heat: float)
signal frostbite_changed(frostbite_amount: float, frostbite_percent: float)
signal frostbite_critical(is_critical: bool)

@export var max_thermal_shield: float = 100.0
@export var current_thermal_shield: float = 100.0
@export var frostbite_buildup: float = 0.0
@export var max_frostbite_limit: float = 100.0

@export_group("Environmental Rates")
@export var base_ambient_chill_rate: float = 3.5
@export var wind_chill_multiplier: float = 1.0
@export var frostbite_accumulation_rate: float = 2.0
@export var heat_thaw_multiplier: float = 5.0

var _is_in_warmth_zone: bool = false
var _external_warmth_rate: float = 0.0

func _ready() -> void:
	current_thermal_shield = clampf(current_thermal_shield, 0.0, max_thermal_shield)

func update_thermal_state(delta: float, heater_output: float = 0.0) -> void:
	# Check thermal vent meta
	if has_meta(&"near_thermal_vent") and get_meta(&"near_thermal_vent") == true:
		_is_in_warmth_zone = true
		_external_warmth_rate = 25.0
	
	# Sample dynamic weather manager if present in tree
	if is_inside_tree():
		var weather_nodes: Array[Node] = get_tree().get_nodes_in_group(&"weather_manager")
		if not weather_nodes.is_empty():
			var weather: Node = weather_nodes[0]
			if weather and is_instance_valid(weather) and weather.has_method("get_temperature_at_position"):
				var parent_node: Node3D = get_parent() as Node3D
				var global_pos: Vector3 = parent_node.global_position if parent_node else Vector3.ZERO
				var local_temp: float = weather.get_temperature_at_position(global_pos)
				
				if local_temp > 0.0:
					_is_in_warmth_zone = true
					_external_warmth_rate = maxf(_external_warmth_rate, local_temp * 0.8)
				else:
					var severe_cold: float = absf(local_temp) / 10.0
					base_ambient_chill_rate = severe_cold * 1.5
					var wind_speed: float = weather.get("current_wind_speed_ms") if "current_wind_speed_ms" in weather else 5.0
					wind_chill_multiplier = 1.0 + (wind_speed / 15.0)
	
	var total_warmth_rate: float = heater_output + (_external_warmth_rate if _is_in_warmth_zone else 0.0)
	var net_environmental_cold: float = base_ambient_chill_rate * wind_chill_multiplier
	
	if total_warmth_rate > net_environmental_cold:
		# Warming up: recharge thermal shield and melt frostbite
		var heat_gain: float = (total_warmth_rate - net_environmental_cold) * delta
		current_thermal_shield = minf(max_thermal_shield, current_thermal_shield + heat_gain)
		
		if frostbite_buildup > 0.0:
			var thaw_amount: float = heat_gain * heat_thaw_multiplier
			frostbite_buildup = maxf(0.0, frostbite_buildup - thaw_amount)
			_emit_frostbite_signals()
	else:
		# Chilling down: drain heat shield first
		var net_cold_drain: float = (net_environmental_cold - total_warmth_rate) * delta
		if current_thermal_shield > 0.0:
			current_thermal_shield = maxf(0.0, current_thermal_shield - net_cold_drain)
		else:
			# Shield depleted: accumulate frostbite
			frostbite_buildup = minf(max_frostbite_limit, frostbite_buildup + (net_cold_drain * frostbite_accumulation_rate))
			_emit_frostbite_signals()
	
	thermal_shield_changed.emit(current_thermal_shield, max_thermal_shield)

func set_warmth_zone(is_inside: bool, warmth_potency: float = 15.0) -> void:
	_is_in_warmth_zone = is_inside
	_external_warmth_rate = warmth_potency if is_inside else 0.0

func get_effective_vitality_cap(base_max_vitality: float) -> float:
	var frostbite_ratio: float = frostbite_buildup / maxf(1.0, max_frostbite_limit)
	return maxf(10.0, base_max_vitality * (1.0 - (frostbite_ratio * 0.85)))

func _emit_frostbite_signals() -> void:
	var ratio: float = frostbite_buildup / maxf(1.0, max_frostbite_limit)
	frostbite_changed.emit(frostbite_buildup, ratio)
	frostbite_critical.emit(ratio >= 0.75)
