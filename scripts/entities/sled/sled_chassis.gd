class_name SledChassis
extends CharacterBody3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")
const SledStatsData = preload("res://scripts/resources/sled_stats_data.gd")
const RunnerData = preload("res://scripts/resources/runner_data.gd")
const EngineData = preload("res://scripts/resources/engine_data.gd")
const HeaterData = preload("res://scripts/resources/heater_data.gd")
const WinchData = preload("res://scripts/resources/winch_data.gd")
const InertialDriftComponent = preload("res://scripts/components/inertial_drift_component.gd")
const CenterOfMassComponent = preload("res://scripts/components/center_of_mass_component.gd")
const SledWinchComponent = preload("res://scripts/components/sled_winch_component.gd")
const ThermalReceiverComponent = preload("res://scripts/components/thermal_receiver_component.gd")
const HealthComponent = preload("res://scripts/components/health_component.gd")
const HexInventoryComponent = preload("res://scripts/components/hex_inventory_component.gd")
const StateMachine = preload("res://scripts/state_machine/state_machine.gd")

signal sled_crashed(impact_intensity: float)
signal surface_friction_updated(surface_type: StringName)

@export_group("Hardware Loadout")
@export var installed_runners: Resource
@export var installed_engine: Resource
@export var installed_heater: Resource
@export var installed_winch: Resource
@export var sled_stats: Resource

@export_group("Components")
@onready var drift_component: Node = get_node_or_null("InertialDriftComponent")
@onready var com_component: Node = get_node_or_null("CenterOfMassComponent")
@onready var winch_component: Node = get_node_or_null("SledWinchComponent")
@onready var thermal_receiver: Node = get_node_or_null("ThermalReceiverComponent")
@onready var health_component: Node = get_node_or_null("HealthComponent")
@onready var storage_inventory: Node = get_node_or_null("CenterOfMassComponent/CargoPodInventory")
@onready var state_machine: Node = get_node_or_null("StateMachine")
@onready var ground_raycast: RayCast3D = get_node_or_null("GroundRayCast3D") as RayCast3D

@export var is_occupied: bool = false

func _ready() -> void:
	_apply_hardware_configuration()
	
	if GlobalEvents.instance:
		GlobalEvents.instance.pilot_mounted_sled.connect(func(sled: Node) -> void:
			if sled == self:
				is_occupied = true
		)
		GlobalEvents.instance.pilot_dismounted_sled.connect(func(sled: Node) -> void:
			if sled == self:
				is_occupied = false
		)

func _unhandled_input(event: InputEvent) -> void:
	if not is_occupied:
		return
	if event.is_action_pressed(&"winch_quick"):
		var forward_dir: Vector3 = -global_transform.basis.z.normalized()
		if winch_component and winch_component.has_method("fire_quick_cone"):
			winch_component.call("fire_quick_cone", forward_dir)

func _physics_process(delta: float) -> void:
	if state_machine and state_machine.has_method("physics_update"):
		state_machine.call("physics_update", delta)
	
	# Update thermal shield
	if thermal_receiver and thermal_receiver.has_method("update_thermal_state"):
		var heater_output: float = installed_heater.get("shield_recharge_rate_per_sec") if installed_heater else 0.0
		thermal_receiver.call("update_thermal_state", delta, heater_output)
	
	# Check for high-speed obstacle collisions (boulders, trees, cliff walls)
	_handle_collision_impacts()

func _apply_hardware_configuration() -> void:
	if not sled_stats:
		sled_stats = SledStatsData.new()
	if not installed_runners:
		installed_runners = preload("res://resources/runners/default_pack_runners.tres")
	if not installed_engine:
		installed_engine = preload("res://resources/engines/standard_engine.tres")
	if not installed_heater:
		installed_heater = preload("res://resources/heaters/basic_heater.tres")
	if not installed_winch:
		installed_winch = preload("res://resources/winches/standard_winch.tres")
	
	if drift_component:
		drift_component.set("stats", sled_stats)
		drift_component.set("runners", installed_runners)
		drift_component.set("engine", installed_engine)
		if ground_raycast:
			drift_component.set("ground_raycast", ground_raycast)
		drift_component.set("target_body", self)
	
	if com_component:
		com_component.set("sled_stats", sled_stats)
		com_component.set("drift_component", drift_component)
	
	if winch_component:
		winch_component.set("winch_data", installed_winch)
		winch_component.set("parent_body", self)

func _handle_collision_impacts() -> void:
	var slide_count: int = get_slide_collision_count()
	for i: int in range(slide_count):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var normal: Vector3 = collision.get_normal()
		
		# Ignore ground / slope floor contacts (normal.y > 0.45): driving slopes causes ZERO damage!
		if normal.y > 0.45:
			continue
			
		# Measure horizontal impact speed against vertical obstacles (boulders, trees, cliff walls)
		var horiz_vel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		var horiz_normal: Vector3 = Vector3(normal.x, 0.0, normal.z).normalized()
		var impact_speed: float = absf(horiz_vel.dot(horiz_normal))
		
		if impact_speed > 10.0:
			var damage: float = (impact_speed - 10.0) * 5.0
			if health_component and health_component.has_method("apply_damage"):
				health_component.call("apply_damage", damage, &"collision")
			
			GlobalEvents.emit_sled_impact(impact_speed, collision.get_position())
			sled_crashed.emit(impact_speed)
			
			# Chance for shock damage to internal components
			if impact_speed > 18.0:
				var shock_roll: float = randf()
				if shock_roll < 0.35 and winch_component and winch_component.get("is_tethered") == true:
					if winch_component.has_method("detach_tether"):
						winch_component.call("detach_tether")
