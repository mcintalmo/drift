class_name WinchData
extends Resource

@export_group("Identification")
@export var winch_id: StringName = &"standard_winch"
@export var winch_name: String = "Heavy Magnetic Harpoon Winch"

@export_group("Cable & Spring Dynamics")
@export_range(10.0, 100.0, 5.0) var max_cable_length_meters: float = 38.0
@export_range(20.0, 500.0, 10.0) var spring_constant_k: float = 140.0
@export_range(1.0, 50.0, 1.0) var damping_coefficient_c: float = 9.0
@export_range(100.0, 2000.0, 50.0) var tensile_limit_force: float = 650.0
@export_range(5.0, 50.0, 1.0) var reel_in_speed_ms: float = 18.0

@export_group("Targeting Parameters")
@export_range(15.0, 90.0, 5.0) var quick_cone_angle_degrees: float = 45.0
@export_range(10.0, 80.0, 5.0) var max_lock_range_meters: float = 42.0
