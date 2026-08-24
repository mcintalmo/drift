class_name DynamicWeatherManager
extends Node3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")
const ThermalVentClass = preload("res://scripts/world/thermal_vent.gd")

enum WeatherState {
	CLEAR_FLURRY = 0,
	GALE_STORM = 1,
	WHITEOUT_BLIZZARD = 2,
	TOXIC_SMOG_FRONT = 3
}

signal weather_state_changed(new_state: WeatherState, state_name: StringName)
signal wind_updated(wind_vector: Vector3, wind_speed_ms: float)
signal ambient_temperature_changed(current_temp_c: float)

@export_group("Current Simulation State")
@export var current_weather_state: WeatherState = WeatherState.CLEAR_FLURRY
@export var is_dynamic_cycle_enabled: bool = true
@export var current_ambient_temp_c: float = -14.0
@export var current_wind_speed_ms: float = 6.0
@export var current_wind_heading_deg: float = 45.0 # Angle in degrees
@export var smog_index: float = 0.0

@export_group("Dependencies")
@export var world_environment: WorldEnvironment
@export var directional_light: DirectionalLight3D
@export var snow_particles: CPUParticles3D

# Internal State Timers
var _state_timer_sec: float = 0.0
var _target_state_duration_sec: float = 60.0
var _current_fog_density: float = 0.002
var _target_fog_density: float = 0.002
var _wind_turbulence_timer: float = 0.0

func _ready() -> void:
	add_to_group(&"weather_manager")
	_apply_weather_parameters(current_weather_state)

func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	
	if is_dynamic_cycle_enabled:
		_state_timer_sec += delta
		if _state_timer_sec >= _target_state_duration_sec:
			_state_timer_sec = 0.0
			_transition_to_next_weather_state()
	
	# Wind turbulence simulation
	_wind_turbulence_timer += delta
	var gust: float = sin(_wind_turbulence_timer * 0.8) * 3.0
	var eff_wind_speed: float = maxf(1.0, current_wind_speed_ms + gust)
	var wind_rad: float = deg_to_rad(current_wind_heading_deg)
	var wind_vec: Vector3 = Vector3(cos(wind_rad), 0.0, sin(wind_rad)).normalized() * eff_wind_speed
	wind_updated.emit(wind_vec, eff_wind_speed)
	
	# Smooth fog and particle transitions
	if world_environment and world_environment.environment:
		var env: Environment = world_environment.environment
		if env.volumetric_fog_enabled or env.fog_enabled:
			_current_fog_density = lerpf(_current_fog_density, _target_fog_density, 1.5 * delta)
			env.fog_density = _current_fog_density
	
	# Update snow particle velocity & direction
	if snow_particles:
		snow_particles.direction = Vector3(wind_vec.x * 0.4, -1.0, wind_vec.z * 0.4).normalized()
		snow_particles.initial_velocity_min = eff_wind_speed * 0.8
		snow_particles.initial_velocity_max = eff_wind_speed * 1.4

func set_weather_state(new_state: WeatherState) -> void:
	current_weather_state = new_state
	_state_timer_sec = 0.0
	_apply_weather_parameters(new_state)

func _transition_to_next_weather_state() -> void:
	var next_val: int = (int(current_weather_state) + 1) % 4
	set_weather_state(next_val as WeatherState)

func _apply_weather_parameters(state: WeatherState) -> void:
	var state_name: StringName = &"Clear Flurry"
	match state:
		WeatherState.CLEAR_FLURRY:
			state_name = &"Clear Flurry"
			current_ambient_temp_c = -12.0
			current_wind_speed_ms = 5.0
			_target_fog_density = 0.003
			smog_index = 0.05
			_target_state_duration_sec = 80.0
			if snow_particles:
				snow_particles.amount = 64
				snow_particles.emitting = true
		WeatherState.GALE_STORM:
			state_name = &"Gale Storm"
			current_ambient_temp_c = -26.0
			current_wind_speed_ms = 18.0
			_target_fog_density = 0.015
			smog_index = 0.15
			_target_state_duration_sec = 60.0
			if snow_particles:
				snow_particles.amount = 256
				snow_particles.emitting = true
		WeatherState.WHITEOUT_BLIZZARD:
			state_name = &"Whiteout Blizzard"
			current_ambient_temp_c = -42.0
			current_wind_speed_ms = 32.0
			_target_fog_density = 0.045
			smog_index = 0.25
			_target_state_duration_sec = 45.0
			if snow_particles:
				snow_particles.amount = 512
				snow_particles.emitting = true
		WeatherState.TOXIC_SMOG_FRONT:
			state_name = &"Toxic Smog Front"
			current_ambient_temp_c = -28.0
			current_wind_speed_ms = 12.0
			_target_fog_density = 0.035
			smog_index = 0.85
			_target_state_duration_sec = 50.0
			if snow_particles:
				snow_particles.amount = 128
				snow_particles.emitting = true
	
	weather_state_changed.emit(current_weather_state, state_name)
	ambient_temperature_changed.emit(current_ambient_temp_c)

## Queries total ambient temperature at a world position, taking into account weather, wind chill, and geothermal vents
func get_temperature_at_position(global_pos: Vector3) -> float:
	var eff_temp: float = current_ambient_temp_c - (current_wind_speed_ms * 0.25)
	
	# Sample all nearby thermal vents
	var vents: Array = []
	if is_inside_tree() and get_tree():
		vents = get_tree().get_nodes_in_group(&"thermal_vents")
	if vents.is_empty() and get_parent():
		for child: Node in get_parent().get_children():
			if child.is_in_group(&"thermal_vents") or child.has_method("get_temperature_contribution"):
				vents.append(child)
	
	var max_vent_warmth: float = 0.0
	for v: Variant in vents:
		if v and is_instance_valid(v) and (v as Object).has_method("get_temperature_contribution"):
			var warmth: float = (v as Object).call("get_temperature_contribution", global_pos)
			max_vent_warmth = maxf(max_vent_warmth, warmth)
	
	if max_vent_warmth > 0.0:
		eff_temp = maxf(eff_temp, max_vent_warmth)
	
	return eff_temp

func get_current_wind_vector() -> Vector3:
	var wind_rad: float = deg_to_rad(current_wind_heading_deg)
	return Vector3(cos(wind_rad), 0.0, sin(wind_rad)).normalized() * current_wind_speed_ms
