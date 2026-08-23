class_name WeaponSocketComponent
extends Node3D

signal weapon_swung(weapon: WeaponData)
signal weapon_fired(weapon: WeaponData)

@export var equipped_weapon: WeaponData
@export var hitbox: HitboxComponent
@export var raycast: RayCast3D
@export var slash_fx_mesh: MeshInstance3D

var _cooldown_timer: float = 0.0
var _slash_timer: float = 0.0

func _ready() -> void:
	if not equipped_weapon:
		equipped_weapon = preload("res://resources/weapons/plasma_cutter.tres")
	_apply_weapon_stats()
	if slash_fx_mesh:
		slash_fx_mesh.visible = false

func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	
	if _slash_timer > 0.0:
		_slash_timer = maxf(0.0, _slash_timer - delta)
		if slash_fx_mesh:
			slash_fx_mesh.visible = true
			var t: float = 1.0 - (_slash_timer / 0.15)
			slash_fx_mesh.rotation.y = lerpf(deg_to_rad(-60.0), deg_to_rad(60.0), t)
			slash_fx_mesh.scale = Vector3.ONE * (1.0 + sin(t * PI) * 0.4)
		if _slash_timer <= 0.0 and slash_fx_mesh:
			slash_fx_mesh.visible = false

func equip_weapon(new_weapon: WeaponData) -> void:
	equipped_weapon = new_weapon
	_apply_weapon_stats()

func can_attack() -> bool:
	return _cooldown_timer <= 0.0 and equipped_weapon != null

func trigger_attack() -> bool:
	if not can_attack():
		return false
	
	_cooldown_timer = equipped_weapon.attack_cooldown_sec
	
	if equipped_weapon.weapon_type == WeaponData.WeaponType.MELEE_BREACH:
		_slash_timer = 0.15
		if hitbox:
			hitbox.is_active = true
			if is_inside_tree() and get_tree():
				get_tree().create_timer(0.15).timeout.connect(func() -> void:
					if is_instance_valid(hitbox):
						hitbox.is_active = false
				)
			else:
				hitbox.is_active = false
		weapon_swung.emit(equipped_weapon)
		return true
	else:
		# Ranged projectile / raycast
		if raycast:
			raycast.target_position = Vector3(0, 0, -equipped_weapon.effective_range_meters)
			raycast.force_raycast_update()
			if raycast.is_colliding():
				var collider: Object = raycast.get_collider()
				if collider is HurtboxComponent:
					(collider as HurtboxComponent).receive_hit(equipped_weapon.base_damage, equipped_weapon.damage_type, raycast.get_collision_point())
		weapon_fired.emit(equipped_weapon)
		return true

func _apply_weapon_stats() -> void:
	if not equipped_weapon or not hitbox:
		return
	hitbox.damage_amount = equipped_weapon.base_damage
	hitbox.damage_type = equipped_weapon.damage_type
	hitbox.breach_multiplier = equipped_weapon.breach_multiplier
