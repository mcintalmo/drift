class_name WinchData
extends Resource

@export_group("Identification")
@export var winch_id: StringName = &"standard_winch"
@export var winch_name: String = "Heavy Magnetic Harpoon Winch"

@export_group("Cable & Spring Dynamics")
@export_range(10.0, 120.0, 5.0) var max_cable_length_meters: float = 48.0
@export_range(50.0, 2000.0, 25.0) var spring_constant_k: float = 650.0
@export_range(1.0, 100.0, 1.0) var damping_coefficient_c: float = 28.0
@export_range(500.0, 15000.0, 100.0) var tensile_limit_force: float = 5500.0
@export_range(5.0, 60.0, 1.0) var reel_in_speed_ms: float = 22.0

@export_group("Targeting Parameters")
@export_range(15.0, 90.0, 5.0) var quick_cone_angle_degrees: float = 60.0
@export_range(10.0, 100.0, 5.0) var max_lock_range_meters: float = 50.0
