class_name HurtboxComponent
extends Area3D

signal hit_received(amount: float, damage_type: StringName, hit_from_pos: Vector3)

@export var health_component: HealthComponent
@export var is_breach_target: bool = false # True for train couplers, locked crates, vault doors
@export var is_invulnerable: bool = false

func receive_hit(amount: float, damage_type: StringName, hit_from_pos: Vector3) -> float:
	if is_invulnerable or amount <= 0.0:
		return 0.0
	
	var damage_dealt: float = amount
	if health_component:
		damage_dealt = health_component.apply_damage(amount, damage_type)
	
	hit_received.emit(damage_dealt, damage_type, hit_from_pos)
	return damage_dealt
