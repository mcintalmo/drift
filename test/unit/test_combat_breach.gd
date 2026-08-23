class_name TestCombatBreach
extends RefCounted

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_plasma_cutter_breach_multiplier())
	results.append(_test_sealed_crate_unlocks_on_breach())
	results.append(_test_hitbox_deals_damage_to_hurtbox())
	return results

func _test_plasma_cutter_breach_multiplier() -> Dictionary:
	var health_comp: HealthComponent = HealthComponent.new()
	health_comp.max_health = 100.0
	health_comp.current_health = 100.0
	
	var hurtbox: HurtboxComponent = HurtboxComponent.new()
	hurtbox.health_component = health_comp
	hurtbox.is_breach_target = true # Breach target receives 3x multiplier
	
	var hitbox: HitboxComponent = HitboxComponent.new()
	hitbox.damage_amount = 30.0
	hitbox.breach_multiplier = 3.0
	hitbox.damage_type = &"plasma"
	
	# Manually simulate hit calculation
	var effective_damage: float = hitbox.damage_amount * (hitbox.breach_multiplier if hurtbox.is_breach_target else 1.0)
	var dealt: float = hurtbox.receive_hit(effective_damage, hitbox.damage_type, Vector3.ZERO)
	var final_hp: float = health_comp.current_health
	
	var passed: bool = (dealt == 90.0) and (final_hp == 10.0)
	
	health_comp.free()
	hurtbox.free()
	hitbox.free()
	return {
		"name": "test_plasma_cutter_breach_multiplier",
		"passed": passed,
		"message": "Plasma breach inflicted %f damage (30 * 3x = 90), HP reduced to %f" % [dealt, final_hp]
	}

func _test_sealed_crate_unlocks_on_breach() -> Dictionary:
	var crate: GroundCrate = GroundCrate.new()
	crate.lock_health = 50.0
	
	var lock_health_comp: HealthComponent = HealthComponent.new()
	lock_health_comp.max_health = 50.0
	lock_health_comp.current_health = 50.0
	crate.add_child(lock_health_comp)
	crate.lock_health_component = lock_health_comp
	lock_health_comp.died.connect(crate._on_lock_breached)
	
	# Inflict lethal damage to lock
	lock_health_comp.apply_damage(50.0, &"plasma")
	
	var passed: bool = not crate.is_locked
	
	crate.free()
	return {
		"name": "test_sealed_crate_unlocks_on_breach",
		"passed": passed,
		"message": "Sealed crate successfully unlocked upon lock health depletion"
	}

func _test_hitbox_deals_damage_to_hurtbox() -> Dictionary:
	var health_comp: HealthComponent = HealthComponent.new()
	health_comp.max_health = 100.0
	health_comp.current_health = 100.0
	health_comp.armor_mitigation_percent = 0.2 # 20% armor mitigation
	
	var hurtbox: HurtboxComponent = HurtboxComponent.new()
	hurtbox.health_component = health_comp
	
	var dealt: float = hurtbox.receive_hit(50.0, &"kinetic", Vector3.ZERO)
	var final_hp: float = health_comp.current_health
	
	# 50 damage * (1 - 0.2) = 40 effective damage -> remaining HP = 60
	var passed: bool = (dealt == 40.0) and (final_hp == 60.0)
	
	health_comp.free()
	hurtbox.free()
	return {
		"name": "test_hitbox_deals_damage_to_hurtbox",
		"passed": passed,
		"message": "Armor mitigated damage: 50 -> %f, remaining HP = %f" % [dealt, final_hp]
	}
