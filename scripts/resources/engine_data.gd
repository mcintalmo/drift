class_name EngineData
extends Resource

@export_group("Identification")
@export var engine_id: StringName = &"standard_engine"
@export var engine_name: String = "Standard Kerosene Thruster"

@export_group("Thrust Dynamics")
@export_range(10.0, 100.0, 1.0) var max_forward_thrust: float = 38.0
@export_range(5.0, 50.0, 1.0) var max_reverse_thrust: float = 14.0
@export_range(1.0, 3.0, 0.05) var boost_multiplier: float = 1.65
@export_range(5.0, 60.0, 1.0) var top_speed_ms: float = 32.0

@export_group("Fuel & Thermal Characteristics")
@export_range(0.1, 5.0, 0.1) var fuel_burn_rate_per_sec: float = 0.8
@export_range(1.0, 10.0, 0.5) var boost_fuel_multiplier: float = 2.5
@export_range(1.0, 10.0, 0.5) var smog_emission_rate: float = 1.0
