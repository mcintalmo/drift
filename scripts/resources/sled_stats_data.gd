class_name SledStatsData
extends Resource

@export_group("Chassis Identification")
@export var chassis_id: StringName = &"drift_sled_mk1"
@export var chassis_name: String = "Drift Sled Mk I"

@export_group("Base Mass & Inertia")
@export_range(50.0, 1000.0, 10.0) var chassis_base_mass_kg: float = 220.0
@export var chassis_com_offset: Vector3 = Vector3(0.0, 0.25, 0.0)

@export_group("Steering & Dynamics")
@export_range(10.0, 90.0, 1.0) var max_steer_angle_deg: float = 38.0
@export_range(1.0, 20.0, 0.5) var steer_speed_deg_per_sec: float = 8.5
@export_range(0.5, 3.0, 0.1) var drift_yaw_multiplier: float = 1.75
@export_range(1.0, 10.0, 0.2) var linear_dampening: float = 0.4

@export_group("Roll Stability & Tipping")
@export_range(5.0, 45.0, 1.0) var tipping_angle_threshold_deg: float = 28.0
@export_range(10.0, 500.0, 10.0) var max_stabilizing_lean_torque: float = 160.0
@export_range(0.1, 5.0, 0.1) var roll_restoring_stiffness: float = 4.5
