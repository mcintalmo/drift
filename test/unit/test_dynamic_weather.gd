class_name TestDynamicWeather
extends RefCounted

const DynamicWeatherManager = preload("res://scripts/world/dynamic_weather_manager.gd")
const ThermalVent = preload("res://scripts/world/thermal_vent.gd")
const ThermalReceiverComponent = preload("res://scripts/components/thermal_receiver_component.gd")

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_weather_state_parameters())
	results.append(_test_wind_vector_calculation())
	results.append(_test_thermal_vent_temperature_override())
	results.append(_test_thermal_receiver_blizzard_depletion_and_thaw())
	return results

func _test_weather_state_parameters() -> Dictionary:
	var weather: DynamicWeatherManager = DynamicWeatherManager.new()
	weather.is_dynamic_cycle_enabled = false
	
	weather.set_weather_state(DynamicWeatherManager.WeatherState.CLEAR_FLURRY)
	var clear_temp: float = weather.current_ambient_temp_c
	var clear_wind: float = weather.current_wind_speed_ms
	
	weather.set_weather_state(DynamicWeatherManager.WeatherState.WHITEOUT_BLIZZARD)
	var whiteout_temp: float = weather.current_ambient_temp_c
	var whiteout_wind: float = weather.current_wind_speed_ms
	
	var passed: bool = (clear_temp == -12.0) and (clear_wind == 5.0) and (whiteout_temp == -42.0) and (whiteout_wind == 32.0)
	
	weather.free()
	return {
		"name": "test_weather_state_parameters",
		"passed": passed,
		"message": "Clear: %.1f C (%.1f m/s) -> Whiteout: %.1f C (%.1f m/s)" % [
			clear_temp, clear_wind, whiteout_temp, whiteout_wind
		]
	}

func _test_wind_vector_calculation() -> Dictionary:
	var weather: DynamicWeatherManager = DynamicWeatherManager.new()
	weather.current_wind_speed_ms = 10.0
	weather.current_wind_heading_deg = 0.0 # Points along +X
	
	var wind_vec: Vector3 = weather.get_current_wind_vector()
	var passed: bool = is_equal_approx(wind_vec.x, 10.0) and is_zero_approx(wind_vec.z) and is_zero_approx(wind_vec.y)
	
	weather.free()
	return {
		"name": "test_wind_vector_calculation",
		"passed": passed,
		"message": "0 deg wind vector = %s (speed = %.1f m/s)" % [str(wind_vec), wind_vec.length()]
	}

func _test_thermal_vent_temperature_override() -> Dictionary:
	var vent: ThermalVent = ThermalVent.new()
	vent.position = Vector3(0, 0, 0)
	vent.warmth_radius_m = 10.0
	vent.vent_temperature_c = 40.0
	
	var center_warmth: float = vent.get_temperature_contribution(Vector3(0, 0, 0))
	var mid_warmth: float = vent.get_temperature_contribution(Vector3(5, 0, 0))
	var outside_warmth: float = vent.get_temperature_contribution(Vector3(15, 0, 0))
	
	var passed: bool = (center_warmth == 40.0) and (mid_warmth == 20.0) and (outside_warmth == 0.0)
	
	vent.free()
	return {
		"name": "test_thermal_vent_temperature_override",
		"passed": passed,
		"message": "Vent warmth: center=%.1f C, 5m=%.1f C, 15m=%.1f C" % [
			center_warmth, mid_warmth, outside_warmth
		]
	}

func _test_thermal_receiver_blizzard_depletion_and_thaw() -> Dictionary:
	var receiver: ThermalReceiverComponent = ThermalReceiverComponent.new()
	receiver.max_thermal_shield = 100.0
	receiver.current_thermal_shield = 100.0
	receiver.base_ambient_chill_rate = 10.0
	receiver.wind_chill_multiplier = 2.0 # Net cold = 20.0/sec
	
	# Process 2.0 seconds in blizzard without heater
	receiver.update_thermal_state(2.0, 0.0)
	var chilled_shield: float = receiver.current_thermal_shield
	
	# Enter thermal vent (+40.0 warmth/sec)
	receiver.set_warmth_zone(true, 40.0)
	receiver.update_thermal_state(2.0, 0.0)
	var warmed_shield: float = receiver.current_thermal_shield
	
	var passed: bool = is_equal_approx(chilled_shield, 60.0) and is_equal_approx(warmed_shield, 100.0)
	
	receiver.free()
	return {
		"name": "test_thermal_receiver_blizzard_depletion_and_thaw",
		"passed": passed,
		"message": "Shield: 100 -> %.1f (after cold) -> %.1f (after vent warmth)" % [
			chilled_shield, warmed_shield
		]
	}
