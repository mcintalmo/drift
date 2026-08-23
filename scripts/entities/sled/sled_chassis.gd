class_name SledChassis
extends CharacterBody3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal sled_damaged(new_hp: float, delta_hp: float)
signal sled_crashed(impact_force: float)

@export_group("Pilot State")
@export var is_occupied: bool = true

@export_group("Hardware Configuration")
@export var sled_stats: SledStatsData
@export var installed_runners: RunnerData
@export var installed_engine: EngineData
@export var installed_heater: HeaterData
@export var installed_winch: WinchData

@onready var drift_component: InertialDriftComponent = $InertialDriftComponent
@onready var com_component: CenterOfMassComponent = $CenterOfMassComponent
@onready var winch_component: SledWinchComponent = $SledWinchComponent
@onready var health_component: HealthComponent = $HealthComponent
@onready var thermal_receiver: ThermalReceiverComponent = $ThermalReceiverComponent
@onready var state_machine: StateMachine = $StateMachine
@onready var ground_raycast: RayCast3D = $GroundRayCast3D

func _ready() -> void:
	_apply_hardware_configuration()
	
	if health_component:
		health_component.health_changed.connect(func(cur: float, max_hp: float, delta: float) -> void:
			sled_damaged.emit(cur, delta)
			GlobalEvents.emit_vitality_changed(cur, max_hp)
		)
	
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
		if winch_component:
			winch_component.fire_quick_cone(forward_dir)

func _physics_process(delta: float) -> void:
	if state_machine:
		state_machine.physics_update(delta)
	
	# Update thermal shield
	if thermal_receiver:
		var heater_output: float = installed_heater.shield_recharge_rate_per_sec if installed_heater else 0.0
		thermal_receiver.update_thermal_state(delta, heater_output)
	
	# Check for high-speed collision impacts
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
		drift_component.stats = sled_stats
		drift_component.runners = installed_runners
		drift_component.engine = installed_engine
		drift_component.ground_raycast = ground_raycast
		drift_component.target_body = self
	
	if com_component:
		com_component.sled_stats = sled_stats
		com_component.drift_component = drift_component
	
	if winch_component:
		winch_component.winch_data = installed_winch
		winch_component.parent_body = self

func _handle_collision_impacts() -> void:
	var slide_count: int = get_slide_collision_count()
	for i: int in range(slide_count):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		
		# Check if struck a barrier with speed
		var normal: Vector3 = collision.get_normal()
		var impact_speed: float = absf(velocity.dot(normal))
		
		if impact_speed > 8.0:
			var damage: float = (impact_speed - 8.0) * 4.5
			if health_component:
				health_component.apply_damage(damage, &"collision")
			
			GlobalEvents.emit_sled_impact(impact_speed, collision.get_position())
			sled_crashed.emit(impact_speed)
			
			# Chance for shock damage to internal components
			if impact_speed > 16.0:
				var shock_roll: float = randf()
				if shock_roll < 0.35 and winch_component and winch_component.is_tethered:
					winch_component.detach_tether()
