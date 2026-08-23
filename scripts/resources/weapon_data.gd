class_name WeaponData
extends Resource

enum WeaponType {
	MELEE_BREACH,
	RANGED_KINETIC,
	RANGED_ENERGY
}

@export_group("Identification")
@export var weapon_id: StringName = &"plasma_cutter"
@export var weapon_name: String = "High-Frequency Plasma Cutter"
@export var weapon_type: WeaponType = WeaponType.MELEE_BREACH

@export_group("Combat Stats")
@export_range(5.0, 200.0, 1.0) var base_damage: float = 45.0
@export var damage_type: StringName = &"plasma"
@export_range(0.1, 5.0, 0.05) var attack_cooldown_sec: float = 0.45
@export_range(1.0, 50.0, 1.0) var vitality_stamina_cost: float = 12.0
@export_range(0.5, 30.0, 0.5) var effective_range_meters: float = 2.2
@export_range(15.0, 180.0, 5.0) var attack_arc_degrees: float = 120.0

@export_group("Breaching Power")
@export_range(1.0, 10.0, 0.5) var breach_multiplier: float = 3.0
@export var can_cut_train_couplers: bool = true
@export var can_breach_security_locks: bool = true
