class_name JetpackData
extends Resource

@export_group("Identification")
@export var jetpack_id: StringName = &"standard_jetpack"
@export var jetpack_name: String = "Vector-Thruster Jetpack Harness"

@export_group("Thrust & Fuel Dynamics")
@export_range(5.0, 50.0, 1.0) var vertical_thrust_force: float = 24.0
@export_range(1.0, 30.0, 1.0) var forward_boost_force: float = 12.0
@export_range(10.0, 100.0, 5.0) var max_fuel_capacity: float = 100.0
@export_range(5.0, 50.0, 1.0) var fuel_burn_rate_per_sec: float = 25.0
@export_range(5.0, 50.0, 1.0) var fuel_recharge_rate_per_sec: float = 18.0

@export_group("Hover Gliding Dynamics")
@export_range(0.1, 5.0, 0.1) var hover_gravity_reduction: float = 0.2
@export_range(0.5, 10.0, 0.5) var hover_horizontal_drag: float = 2.5
