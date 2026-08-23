class_name GlobalEvents
extends Node

static var instance: GlobalEvents

func _init() -> void:
	instance = self

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

## Vitality, Thermal and Health Signals
signal vitality_changed(current: float, max_vitality: float)
signal heat_changed(current: float, max_heat: float)
signal frostbite_updated(frostbite_percent: float)

## Sled Kinematics and Equilibrium Signals
signal sled_roll_angle_changed(roll_degrees: float, instability_factor: float)
signal sled_tipping_warning(is_imminent: bool)
signal sled_impact_occurred(intensity: float, hit_position: Vector3)

## Winch & Tether Signals
signal winch_attached(anchor_pos: Vector3, is_dynamic: bool)
signal winch_detached()
signal winch_tension_updated(current_tension: float, max_tension: float)

## Pilot & Mobility Signals
signal jetpack_fuel_changed(current_fuel: float, max_fuel: float)
signal pilot_mounted_sled(sled: Node)
signal pilot_dismounted_sled(sled: Node)
signal train_car_decoupled(car_index: int)
signal crate_breached(crate: Node)

## Inventory & Extraction Signals
signal inventory_updated(container_id: StringName, total_mass: float, com_offset: Vector2)
signal cargo_flared(container_id: StringName, item_id: StringName)
signal emergency_flare_fired()

# Static Safe Emitters
static func emit_vitality_changed(current: float, max_vitality: float) -> void:
	if instance: instance.vitality_changed.emit(current, max_vitality)

static func emit_heat_changed(current: float, max_heat: float) -> void:
	if instance: instance.heat_changed.emit(current, max_heat)

static func emit_sled_impact(intensity: float, hit_position: Vector3) -> void:
	if instance: instance.sled_impact_occurred.emit(intensity, hit_position)

static func emit_sled_tipping(is_imminent: bool) -> void:
	if instance: instance.sled_tipping_warning.emit(is_imminent)

static func emit_winch_attached(anchor_pos: Vector3, is_dynamic: bool) -> void:
	if instance: instance.winch_attached.emit(anchor_pos, is_dynamic)

static func emit_winch_detached() -> void:
	if instance: instance.winch_detached.emit()

static func emit_winch_tension(current_tension: float, max_tension: float) -> void:
	if instance: instance.winch_tension_updated.emit(current_tension, max_tension)

static func emit_jetpack_fuel_changed(current_fuel: float, max_fuel: float) -> void:
	if instance: instance.jetpack_fuel_changed.emit(current_fuel, max_fuel)

static func emit_pilot_mounted_sled(sled: Node) -> void:
	if instance: instance.pilot_mounted_sled.emit(sled)

static func emit_pilot_dismounted_sled(sled: Node) -> void:
	if instance: instance.pilot_dismounted_sled.emit(sled)

static func emit_train_car_decoupled(car_index: int) -> void:
	if instance: instance.train_car_decoupled.emit(car_index)

static func emit_crate_breached(crate: Node) -> void:
	if instance: instance.crate_breached.emit(crate)

static func emit_inventory_updated(container_id: StringName, total_mass: float, com_offset: Vector2) -> void:
	if instance: instance.inventory_updated.emit(container_id, total_mass, com_offset)

# Static Safe Subscriptions
static func subscribe_sled_impact(callable: Callable) -> void:
	if instance:
		instance.sled_impact_occurred.connect(callable)

static func subscribe_train_car_decoupled(callable: Callable) -> void:
	if instance:
		instance.train_car_decoupled.connect(callable)
