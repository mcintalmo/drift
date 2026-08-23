class_name HealthComponent
extends Node

signal health_changed(current: float, max_hp: float, delta: float)
signal damage_taken(amount: float, damage_type: StringName)
signal healed(amount: float)
signal died

@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var armor_mitigation_percent: float = 0.0
@export var invulnerability_duration_sec: float = 0.0

var _is_invulnerable: bool = false
var _invuln_timer: float = 0.0

func _ready() -> void:
	current_health = clampf(current_health, 0.0, max_health)

func _process(delta: float) -> void:
	if _is_invulnerable:
		_invuln_timer -= delta
		if _invuln_timer <= 0.0:
			_is_invulnerable = false

func apply_damage(raw_amount: float, damage_type: StringName = &"kinetic") -> float:
	if raw_amount <= 0.0 or _is_invulnerable or current_health <= 0.0:
		return 0.0
	
	var effective_damage: float = raw_amount * (1.0 - clampf(armor_mitigation_percent, 0.0, 0.9))
	current_health = maxf(0.0, current_health - effective_damage)
	
	if invulnerability_duration_sec > 0.0:
		_is_invulnerable = true
		_invuln_timer = invulnerability_duration_sec
	
	damage_taken.emit(effective_damage, damage_type)
	health_changed.emit(current_health, max_health, -effective_damage)
	
	if current_health <= 0.0:
		died.emit()
	
	return effective_damage

func apply_healing(amount: float) -> float:
	if amount <= 0.0 or current_health <= 0.0:
		return 0.0
	
	var previous_hp: float = current_health
	current_health = minf(max_health, current_health + amount)
	var healed_amount: float = current_health - previous_hp
	
	if healed_amount > 0.0:
		healed.emit(healed_amount)
		health_changed.emit(current_health, max_health, healed_amount)
	
	return healed_amount

func is_alive() -> bool:
	return current_health > 0.0

func get_health_percentage() -> float:
	return current_health / maxf(1.0, max_health)
