class_name HitboxComponent
extends Area3D

signal hit_landed(target_hurtbox: HurtboxComponent, damage_dealt: float)

@export var damage_amount: float = 25.0
@export var damage_type: StringName = &"kinetic"
@export var breach_multiplier: float = 1.0
@export var knockback_force: float = 5.0
@export var is_active: bool = true

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area3D) -> void:
	if not is_active:
		return
	
	if area is HurtboxComponent and area.is_invulnerable == false:
		var effective_damage: float = damage_amount
		if area.is_breach_target:
			effective_damage *= breach_multiplier
		
		var dealt: float = area.receive_hit(effective_damage, damage_type, global_position)
		hit_landed.emit(area, dealt)
