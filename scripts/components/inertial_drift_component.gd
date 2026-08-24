class_name InertialDriftComponent
extends Node

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal surface_changed(new_surface: StringName, friction_vector: Vector2)
signal drift_started
signal drift_ended
signal linear_speed_changed(current_speed_kmh: float)
signal sled_roll_updated(roll_angle_deg: float)
signal sled_pitch_updated(pitch_angle_deg: float)

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
@export var is_grounded: bool = true

var velocity_3d: Vector3 = Vector3.ZERO
var heading_angle_rad: float = 0.0
var roll_angle_rad: float = 0.0
var pitch_angle_rad: float = 0.0
var current_total_mass_kg: float = 250.0
var external_com_lateral_offset_m: float = 0.0
var external_com_height_m: float = 0.25
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
	
	# Ground Contact & Surface Normal Detection
	var ground_normal: Vector3 = Vector3.UP
	is_grounded = false
	if ground_raycast and ground_raycast.is_colliding():
		ground_normal = ground_raycast.get_collision_normal()
		is_grounded = true
	elif target_body.is_on_floor():
		ground_normal = target_body.get_floor_normal()
		is_grounded = true
	
	# 1. Update Drift State
	var was_drifting: bool = is_drifting
	is_drifting = drift_input and is_grounded
	if is_drifting != was_drifting:
		if is_drifting:
			drift_started.emit()
		else:
			drift_ended.emit()
	
	# 2. Heading and Steering Yaw Integration
	var current_friction: Vector2 = _get_current_friction()
	var base_steer_speed: float = deg_to_rad(stats.steer_speed_deg_per_sec if stats else 95.0)
	var effective_steer_speed: float = base_steer_speed
	
	if not is_grounded:
		effective_steer_speed *= 0.4 # Reduced steering authority in air
	elif is_drifting and stats:
		effective_steer_speed *= stats.drift_yaw_multiplier
	
	if runners:
		effective_steer_speed *= runners.steering_bite_multiplier
	
	# Asymmetrical mass drag yaw bias
	var speed_mag: float = velocity_3d.length()
	var yaw_bias: float = (external_com_lateral_offset_m / 0.25) * deg_to_rad(3.5) * clampf(speed_mag / 12.0, 0.0, 1.5)
	
	heading_angle_rad -= (steer_input * effective_steer_speed + yaw_bias) * delta
	
	var forward_yaw: Vector3 = Vector3(-sin(heading_angle_rad), 0.0, -cos(heading_angle_rad)).normalized()
	var right_yaw: Vector3 = Vector3(cos(heading_angle_rad), 0.0, -sin(heading_angle_rad)).normalized()
	
	# 3. Slope-Aligned Coordinate Frame
	var forward_slope: Vector3 = forward_yaw
	var right_slope: Vector3 = right_yaw
	
	if is_grounded and ground_normal.y > 0.3:
		forward_slope = (forward_yaw - ground_normal * forward_yaw.dot(ground_normal)).normalized()
		right_slope = (right_yaw - ground_normal * right_yaw.dot(ground_normal)).normalized()
	
	if is_grounded:
		# === GROUND DRIVING & SLOPE KINEMATICS ===
		# Thrust Force along slope plane
		var thrust_force: Vector3 = Vector3.ZERO
		if engine:
			if throttle_input > 0.0:
				var forward_thrust: float = engine.max_forward_thrust * throttle_input
				if is_boosting:
					forward_thrust *= engine.boost_multiplier
				thrust_force = forward_slope * forward_thrust
			elif throttle_input < 0.0:
				var reverse_thrust: float = engine.max_reverse_thrust * absf(throttle_input)
				thrust_force = -forward_slope * reverse_thrust
		
		# Decompose velocity in slope frame
		var forward_speed: float = velocity_3d.dot(forward_slope)
		var lateral_speed: float = velocity_3d.dot(right_slope)
		
		# Longitudinal rolling drag
		var longitudinal_drag: Vector3 = -forward_slope * (forward_speed * current_friction.y * 25.0)
		
		# Lateral slip friction
		var lateral_friction_coeff: float = current_friction.x
		if is_drifting:
			lateral_friction_coeff *= 0.25 # Break traction during handbrake
		
		var max_lateral_grip: float = lateral_friction_coeff * current_total_mass_kg * GRAVITY
		var desired_lateral_braking: float = -(lateral_speed * current_total_mass_kg) / delta
		var clamped_lateral_force: float = clampf(desired_lateral_braking, -max_lateral_grip, max_lateral_grip)
		var lateral_friction: Vector3 = right_slope * clamped_lateral_force
		
		# Gravity slope pull: pulling down hills naturally
		var gravity_slope_force: Vector3 = Vector3.DOWN * (current_total_mass_kg * GRAVITY)
		var gravity_along_slope: Vector3 = gravity_slope_force - ground_normal * gravity_slope_force.dot(ground_normal)
		
		# Total Forces
		var total_forces: Vector3 = thrust_force + longitudinal_drag + lateral_friction + gravity_along_slope + external_force
		var accel: Vector3 = total_forces / maxf(1.0, current_total_mass_kg)
		
		velocity_3d += accel * delta
		
		# Coasting deceleration
		if is_zero_approx(throttle_input):
			var coast_friction: float = current_friction.y * 3.0
			velocity_3d = velocity_3d.move_toward(Vector3.ZERO, coast_friction * GRAVITY * delta)
		
		var max_speed: float = engine.top_speed_ms if engine else 38.0
		if is_boosting:
			max_speed *= 1.35
		if velocity_3d.length() > max_speed:
			velocity_3d = velocity_3d.normalized() * max_speed
			
	else:
		# === AIRBORNE BALLISTIC FLIGHT (RAMP LAUNCH) ===
		# In air, preserve 3D launch momentum and apply true downward gravity
		velocity_3d.y -= GRAVITY * delta
		velocity_3d += (external_force / maxf(1.0, current_total_mass_kg)) * delta
		
		# Gentle airborne aerodynamic drag
		velocity_3d.x = move_toward(velocity_3d.x, 0.0, 0.5 * delta)
		velocity_3d.z = move_toward(velocity_3d.z, 0.0, 0.5 * delta)
	
	target_body.velocity = velocity_3d
	target_body.move_and_slide()
	velocity_3d = target_body.velocity
	
	# 7. Attitude Dynamics (Roll & Slope/Airborne Pitch)
	_update_attitude_dynamics(delta, forward_yaw, ground_normal)
	
	# 8. Signals
	var speed_kmh: float = velocity_3d.length() * 3.6
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

func _update_attitude_dynamics(delta: float, forward_yaw: Vector3, ground_normal: Vector3) -> void:
	var right_yaw: Vector3 = Vector3(forward_yaw.z, 0.0, -forward_yaw.x)
	var horiz_vel: Vector3 = Vector3(velocity_3d.x, 0.0, velocity_3d.z)
	var lateral_speed: float = horiz_vel.dot(right_yaw)
	var speed_mag: float = horiz_vel.length()
	
	# 1. Roll Dynamics (Static COM + Centrifugal - Pilot Lean)
	var static_com_roll: float = (external_com_lateral_offset_m / 0.20) * deg_to_rad(20.0)
	var height_factor: float = clampf(external_com_height_m / 0.25, 0.5, 2.5)
	var centrifugal_roll: float = (lateral_speed * 0.05) * height_factor
	var pilot_lean: float = pilot_lean_axis * deg_to_rad(18.0)
	
	var target_roll_rad: float = clampf(static_com_roll + centrifugal_roll - pilot_lean, deg_to_rad(-45.0), deg_to_rad(45.0))
	var restore_speed: float = stats.roll_restoring_stiffness if stats else 6.0
	roll_angle_rad = lerpf(roll_angle_rad, target_roll_rad, restore_speed * delta)
	
	# 2. Pitch Dynamics (Ground Slope or Airborne Flight Path)
	var target_pitch_rad: float = 0.0
	if is_grounded:
		# Downhill / Uphill slope alignment
		var slope_dot: float = forward_yaw.dot(ground_normal)
		target_pitch_rad = clampf(asin(-slope_dot), deg_to_rad(-40.0), deg_to_rad(40.0))
		pitch_angle_rad = lerpf(pitch_angle_rad, target_pitch_rad, 10.0 * delta)
	else:
		# Airborne trajectory alignment (points nose into flight path arc)
		if speed_mag > 3.0:
			var flight_pitch: float = atan2(velocity_3d.y, speed_mag)
			target_pitch_rad = clampf(flight_pitch, deg_to_rad(-45.0), deg_to_rad(40.0))
		pitch_angle_rad = lerpf(pitch_angle_rad, target_pitch_rad, 5.0 * delta)
	
	# Construct 3D Orthogonal Basis
	var heading_basis: Basis = Basis(Vector3.UP, heading_angle_rad)
	var pitch_basis: Basis = Basis(Vector3(1, 0, 0), pitch_angle_rad)
	var roll_basis: Basis = Basis(Vector3(0, 0, -1), roll_angle_rad)
	
	target_body.transform.basis = (heading_basis * pitch_basis * roll_basis).orthonormalized()
	
	sled_roll_updated.emit(rad_to_deg(roll_angle_rad))
	sled_pitch_updated.emit(rad_to_deg(pitch_angle_rad))
	
	var threshold_deg: float = stats.tipping_angle_threshold_deg if stats else 24.0
	var is_tipping_imminent: bool = absf(rad_to_deg(roll_angle_rad)) >= threshold_deg
	if is_tipping_imminent:
		GlobalEvents.emit_sled_tipping(true)
