class_name WinchData
extends Resource

@export_group("Identification")
@export var winch_id: StringName = &"standard_winch"
@export var winch_name: String = "Heavy Magnetic Harpoon Winch"

@export_group("Cable & Spring Dynamics")
@export_range(10.0, 120.0, 5.0) var max_cable_length_meters: float = 48.0
@export_range(50.0, 5000.0, 50.0) var spring_constant_k: float = 1800.0
@export_range(1.0, 1000.0, 10.0) var damping_coefficient_c: float = 420.0
@export_range(500.0, 25000.0, 100.0) var tensile_limit_force: float = 99999.0
@export_range(5.0, 60.0, 1.0) var reel_in_speed_ms: float = 26.0

@export_group("Targeting Parameters")
@export_range(15.0, 90.0, 5.0) var quick_cone_angle_degrees: float = 60.0
@export_range(10.0, 100.0, 5.0) var max_lock_range_meters: float = 50.0
