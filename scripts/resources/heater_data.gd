class_name HeaterData
extends Resource

@export_group("Identification")
@export var heater_id: StringName = &"basic_hearth_core"
@export var heater_name: String = "Basic Thermite Hearth"

@export_group("Thermal Shielding")
@export_range(10.0, 200.0, 5.0) var shield_capacity: float = 100.0
@export_range(1.0, 20.0, 0.5) var radiation_radius_meters: float = 6.0
@export_range(1.0, 25.0, 0.5) var shield_recharge_rate_per_sec: float = 8.0

@export_group("Efficiency")
@export_range(0.05, 2.0, 0.05) var fuel_consumption_per_sec: float = 0.25
@export_range(0.5, 3.0, 0.1) var cold_drain_mitigation_factor: float = 1.0
