class_name InertialDriftComponent
extends Node

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal surface_changed(new_surface: StringName, friction_vector: Vector2)
signal drift_started
signal drift_ended
signal linear_speed_changed(current_speed_kmh: float)
signal sled_roll_updated(roll_angle_deg: float)

@export_group("Dependencies")
@export var target_body: CharacterBody3D
@export var ground_raycast: RayCast3D
@export var runners: RunnerData
@export var engine: EngineData
@export var stats: SledStatsData

@export_group("Runtime State")
@export var current_surface: StringName = &"pack"
@export var is_drifting: bool = false
@export var is_boosting: bool = false

var velocity_3d: Vector3 = Vector3.ZERO
var heading_angle_rad: float = 0.0
var roll_angle_rad: float = 0.0
var current_total_mass_kg: float = 250.0
var external_com_lateral_offset_m: float = 0.0
var pilot_lean_axis: float = 0.0 # Range [-1.0, 1.0]

const GRAVITY: float = 9.81

func _ready() -> void:
	if not target_body and get_parent() is CharacterBody3D:
		target_body = get_parent() as CharacterBody3D
	
	if target_body:
		heading_angle_rad = target_body.rotation.y

func update_physics(
	delta: float,
	throttle_input: float,      # Range [-1.0, 1.0]
	steer_input: float,         # Range [-1.0, 1.0]
	drift_input: bool,          # Handbrake
	lean_input: float,          # Pilot weight shift [-1.0, 1.0]
	external_force: Vector3 = Vector3.ZERO
) -> void:
	if not target_body or delta <= 0.0:
		return
	
	pilot_lean_axis = clampf(lean_input, -1.0, 1.0)
	_update_surface_detection()
	
	# 1. Update Drift State
	var was_drifting: bool = is_drifting
	is_drifting = drift_input and ground_raycast and ground_raycast.is_colliding()
	if is_drifting != was_drifting:
		if is_drifting:
			drift_started.emit()
		else:
			drift_ended.emit()
	
	# 2. Heading and Steering Yaw Integration
	var current_friction: Vector2 = _get_current_friction()
	var base_steer_speed: float = deg_to_rad(stats.steer_speed_deg_per_sec if stats else 95.0)
	var effective_steer_speed: float = base_steer_speed
	
	if is_drifting and stats:
		effective_steer_speed *= stats.drift_yaw_multiplier
	
	if runners:
		effective_steer_speed *= runners.steering_bite_multiplier
	
	# Asymmetrical mass drag yaw bias (sled pulls toward heavy side)
	var forward_velocity: float = velocity_3d.length()
	var yaw_bias: float = (external_com_lateral_offset_m / 0.25) * deg_to_rad(3.5) * clampf(forward_velocity / 12.0, 0.0, 1.5)
	
	heading_angle_rad -= (steer_input * effective_steer_speed + yaw_bias) * delta
	
	var forward_dir: Vector3 = Vector3(-sin(heading_angle_rad), 0.0, -cos(heading_angle_rad)).normalized()
	var right_dir: Vector3 = Vector3(cos(heading_angle_rad), 0.0, -sin(heading_angle_rad)).normalized()
	
	# 3. Thrust Force Calculation
	var thrust_force: Vector3 = Vector3.ZERO
	if engine:
		if throttle_input > 0.0:
			var forward_thrust: float = engine.max_forward_thrust * throttle_input
			if is_boosting:
				forward_thrust *= engine.boost_multiplier
			thrust_force += forward_dir * forward_thrust
		elif throttle_input < 0.0:
			var reverse_thrust: float = engine.max_reverse_thrust * absf(throttle_input)
			thrust_force -= forward_dir * reverse_thrust
	
	# 4. Momentum & Friction Decomposition (XZ Plane)
	var horizontal_velocity: Vector3 = Vector3(velocity_3d.x, 0.0, velocity_3d.z)
	var forward_speed: float = horizontal_velocity.dot(forward_dir)
	var lateral_speed: float = horizontal_velocity.dot(right_dir)
	
	# Longitudinal rolling drag
	var longitudinal_drag_force: Vector3 = -forward_dir * (forward_speed * current_friction.y * 30.0)
	
	# Lateral slip friction
	var lateral_friction_coeff: float = current_friction.x
	if is_drifting:
		lateral_friction_coeff *= 0.25 # Break traction during handbrake
	
	var max_lateral_grip_force: float = lateral_friction_coeff * current_total_mass_kg * GRAVITY
	var desired_lateral_braking_force: float = -(lateral_speed * current_total_mass_kg) / delta
	var clamped_lateral_force_mag: float = clampf(desired_lateral_braking_force, -max_lateral_grip_force, max_lateral_grip_force)
	var lateral_friction_force: Vector3 = right_dir * clamped_lateral_force_mag
	
	# 5. Integrate Accelerations
	var total_horizontal_forces: Vector3 = thrust_force + longitudinal_drag_force + lateral_friction_force + Vector3(external_force.x, 0.0, external_force.z)
	var horizontal_accel: Vector3 = total_horizontal_forces / maxf(1.0, current_total_mass_kg)
	
	horizontal_velocity += horizontal_accel * delta
	
	# Coasting deceleration when no throttle is pressed
	if is_zero_approx(throttle_input):
		var coast_friction: float = current_friction.y * 2.5
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, coast_friction * GRAVITY * delta)
	
	var max_speed: float = engine.top_speed_ms if engine else 38.0
	if is_boosting:
		max_speed *= 1.35
	if horizontal_velocity.length() > max_speed:
		horizontal_velocity = horizontal_velocity.normalized() * max_speed
	
	# 6. Vertical Gravity Integration
	var vertical_velocity_y: float = velocity_3d.y
	if ground_raycast and ground_raycast.is_colliding():
		vertical_velocity_y = 0.0
	else:
		vertical_velocity_y -= GRAVITY * delta
	vertical_velocity_y += (external_force.y / maxf(1.0, current_total_mass_kg)) * delta
	
	velocity_3d = Vector3(horizontal_velocity.x, vertical_velocity_y, horizontal_velocity.z)
	target_body.velocity = velocity_3d
	target_body.move_and_slide()
	velocity_3d = target_body.velocity
	
	# 7. Roll Angle & Tipping Dynamics (Basis Transformation)
	_update_roll_dynamics(delta, lateral_speed, steer_input, horizontal_velocity.length())
	
	# 8. Signals
	var speed_kmh: float = horizontal_velocity.length() * 3.6
	linear_speed_changed.emit(speed_kmh)

func _update_surface_detection() -> void:
	if not ground_raycast or not ground_raycast.is_colliding():
		return
	
	var collider: Object = ground_raycast.get_collider()
	var detected_surface: StringName = &"pack"
	
	if collider and collider.has_meta(&"surface_type"):
		detected_surface = collider.get_meta(&"surface_type")
	
	if detected_surface != current_surface:
		current_surface = detected_surface
		surface_changed.emit(current_surface, _get_current_friction())

func _get_current_friction() -> Vector2:
	if runners:
		return runners.get_friction_for_surface(current_surface)
	return Vector2(0.75, 0.15)

func _update_roll_dynamics(delta: float, lateral_speed: float, steer_input: float, speed_mag: float) -> void:
	# 1. Static gravity tilt from lateral COM offset
	var static_com_roll: float = (external_com_lateral_offset_m / 0.20) * deg_to_rad(20.0)
	
	# 2. Dynamic centrifugal roll during turns
	var centrifugal_roll: float = (lateral_speed * 0.05) + (steer_input * (speed_mag / 16.0) * deg_to_rad(14.0))
	
	# 3. Pilot counter-lean stabilization (Q / E)
	var pilot_lean: float = pilot_lean_axis * deg_to_rad(18.0)
	
	var target_roll_rad: float = clampf(static_com_roll + centrifugal_roll - pilot_lean, deg_to_rad(-45.0), deg_to_rad(45.0))
	var restore_speed: float = stats.roll_restoring_stiffness if stats else 6.0
	roll_angle_rad = lerpf(roll_angle_rad, target_roll_rad, restore_speed * delta)
	
	# Apply combined Heading (Y) and Roll (Z in local vehicle space) Basis to chassis
	var heading_basis: Basis = Basis(Vector3.UP, heading_angle_rad)
	var roll_basis: Basis = Basis(Vector3(0, 0, -1), roll_angle_rad)
	target_body.transform.basis = heading_basis * roll_basis
	
	sled_roll_updated.emit(rad_to_deg(roll_angle_rad))
	
	var threshold_deg: float = stats.tipping_angle_threshold_deg if stats else 24.0
	var is_tipping_imminent: bool = absf(rad_to_deg(roll_angle_rad)) >= threshold_deg
	if is_tipping_imminent:
		GlobalEvents.emit_sled_tipping(true)
