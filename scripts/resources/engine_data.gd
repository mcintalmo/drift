class_name EngineData
extends Resource

@export_group("Identification")
@export var engine_id: StringName = &"standard_engine"
@export var engine_name: String = "Standard Kerosene Thruster"

@export_group("Thrust Dynamics")
## Forward thrust in Newtons (e.g. 4500 N produces ~18 m/s^2 on a 250 kg chassis)
@export_range(500.0, 15000.0, 100.0) var max_forward_thrust: float = 4500.0
## Reverse and active braking thrust in Newtons
@export_range(200.0, 8000.0, 100.0) var max_reverse_thrust: float = 2400.0
## Multiplier applied to forward thrust when holding boost
@export_range(1.0, 3.5, 0.05) var boost_multiplier: float = 1.75
## Maximum theoretical top speed in m/s (38 m/s ≈ 137 km/h)
@export_range(10.0, 80.0, 1.0) var top_speed_ms: float = 38.0

@export_group("Fuel & Thermal Characteristics")
@export_range(0.1, 5.0, 0.1) var fuel_burn_rate_per_sec: float = 0.8
@export_range(1.0, 10.0, 0.5) var boost_fuel_multiplier: float = 2.5
@export_range(1.0, 10.0, 0.5) var smog_emission_rate: float = 1.0
