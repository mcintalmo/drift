class_name TestPilotLocomotion
extends RefCounted

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_jetpack_thrust_and_fuel_consumption())
	results.append(_test_jetpack_recharges_on_ground())
	results.append(_test_pilot_mount_dismount_sled())
	results.append(_test_pilot_dismount_momentum_inheritance())
	results.append(_test_pilot_backpack_imbalance_pull())
	results.append(_test_pilot_grapple_dynamic_tracking())
	results.append(_test_pilot_grapple_roof_boarding_boost())
	results.append(_test_pilot_moving_train_roof_physics_coupling())
	return results

func _test_jetpack_thrust_and_fuel_consumption() -> Dictionary:
	var jetpack: JetpackComponent = JetpackComponent.new()
	jetpack.jetpack_data = JetpackData.new()
	jetpack.jetpack_data.max_fuel_capacity = 100.0
	jetpack.jetpack_data.fuel_burn_rate_per_sec = 20.0
	jetpack.jetpack_data.vertical_thrust_force = 25.0
	jetpack.current_fuel = 100.0
	
	var accel: Vector3 = jetpack.process_jetpack(1.0, true, false, Vector3.FORWARD)
	
	var final_fuel: float = jetpack.current_fuel
	var is_thrusting: bool = jetpack.is_thrusting
	var passed: bool = (final_fuel == 80.0) and (accel.y == 25.0) and is_thrusting
	
	jetpack.free()
	return {
		"name": "test_jetpack_thrust_and_fuel_consumption",
		"passed": passed,
		"message": "Fuel burned: 100 -> %f, Vertical Lift = %f m/s^2" % [final_fuel, accel.y]
	}

func _test_jetpack_recharges_on_ground() -> Dictionary:
	var jetpack: JetpackComponent = JetpackComponent.new()
	jetpack.jetpack_data = JetpackData.new()
	jetpack.jetpack_data.max_fuel_capacity = 100.0
	jetpack.jetpack_data.fuel_recharge_rate_per_sec = 15.0
	jetpack.current_fuel = 50.0
	
	jetpack.process_jetpack(2.0, false, true, Vector3.ZERO)
	
	var final_fuel: float = jetpack.current_fuel
	var is_thrusting: bool = jetpack.is_thrusting
	var passed: bool = (final_fuel == 80.0) and not is_thrusting
	
	jetpack.free()
	return {
		"name": "test_jetpack_recharges_on_ground",
		"passed": passed,
		"message": "Fuel recharged from 50 -> %f on ground" % final_fuel
	}

func _test_pilot_mount_dismount_sled() -> Dictionary:
	var pilot: Pilot = Pilot.new()
	var sled: CharacterBody3D = CharacterBody3D.new()
	sled.position = Vector3(10.0, 0.0, 5.0)
	
	pilot.mount_into_sled(sled)
	var mounted_success: bool = pilot.is_mounted_in_sled and (pilot.current_sled == sled)
	
	pilot.dismount_from_sled()
	var dismount_success: bool = not pilot.is_mounted_in_sled and (pilot.current_sled == null)
	
	var passed: bool = mounted_success and dismount_success
	
	pilot.free()
	sled.free()
	return {
		"name": "test_pilot_mount_dismount_sled",
		"passed": passed,
		"message": "Pilot mounted and dismounted sled successfully"
	}

func _test_pilot_dismount_momentum_inheritance() -> Dictionary:
	var pilot: Pilot = Pilot.new()
	var sled: CharacterBody3D = CharacterBody3D.new()
	sled.position = Vector3(10.0, 0.0, 5.0)
	sled.velocity = Vector3(14.0, 0.0, -8.0) # Sled speeding at ~16 m/s alongside train
	
	pilot.mount_into_sled(sled)
	pilot.dismount_from_sled()
	
	# Pilot velocity should retain sled's horizontal velocity (14.0, -8.0) + upward jump
	var passed: bool = (pilot.velocity.x == 14.0) and (pilot.velocity.z == -8.0) and (pilot.velocity.y > 0.0)
	var vel_str: String = str(pilot.velocity)
	
	pilot.free()
	sled.free()
	return {
		"name": "test_pilot_dismount_momentum_inheritance",
		"passed": passed,
		"message": "Dismounted pilot inherited sled velocity: %s (passed: %s)" % [vel_str, str(passed)]
	}

func _test_pilot_backpack_imbalance_pull() -> Dictionary:
	var inv: HexInventoryComponent = HexInventoryComponent.new()
	var mount: ContainerMountData = ContainerMountData.new()
	mount.tare_mass_kg = 5.0
	mount.slot_layout = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	inv.container_mount = mount
	
	var heavy_item: HexItemData = HexItemData.new()
	heavy_item.item_id = &"heavy_load"
	heavy_item.mass_kg = 45.0
	heavy_item.hex_footprint = [Vector2i(0, 0)]
	inv.place_item(heavy_item, Vector2i(2, 0))
	
	var com: Vector2 = inv.get_com_offset_2d()
	var mass: float = inv.get_total_items_mass()
	
	# Calculate imbalance pull force
	var pull_strength: float = (mass / 45.0) * 1.6
	var lateral_pull: float = (com.x / 0.20) * pull_strength
	
	var passed: bool = (mass == 45.0) and (com.x > 0.4) and (lateral_pull > 2.0)
	
	inv.free()
	return {
		"name": "test_pilot_backpack_imbalance_pull",
		"passed": passed,
		"message": "45kg asymmetric backpack produced lateral imbalance pull of %.2f (expected > 2.0)" % lateral_pull
	}

func _test_pilot_grapple_dynamic_tracking() -> Dictionary:
	var grapple: PilotGrappleComponent = PilotGrappleComponent.new()
	var anchor: GrappleAnchorComponent = GrappleAnchorComponent.new()
	anchor.anchor_type = GrappleAnchorComponent.AnchorType.TRAIN_CAR
	anchor.position = Vector3(0.0, 3.6, 10.0)
	
	grapple.target_anchor = anchor
	grapple.is_grappling = true
	grapple.is_target_heavy = true
	
	# Moving train moves anchor +5m forward (Z=15.0)
	anchor.position = Vector3(0.0, 3.6, 15.0)
	var tracked_pos: Vector3 = grapple.get_current_target_position()
	
	var passed: bool = is_equal_approx(tracked_pos.z, 15.0) and is_equal_approx(tracked_pos.y, 3.6)
	
	grapple.free()
	anchor.free()
	return {
		"name": "test_pilot_grapple_dynamic_tracking",
		"passed": passed,
		"message": "Wrist grapple tracked moving train anchor to: %s (passed: %s)" % [str(tracked_pos), str(passed)]
	}

func _test_pilot_grapple_roof_boarding_boost() -> Dictionary:
	var grapple: PilotGrappleComponent = PilotGrappleComponent.new()
	var anchor: GrappleAnchorComponent = GrappleAnchorComponent.new()
	anchor.anchor_type = GrappleAnchorComponent.AnchorType.TRAIN_CAR
	anchor.is_roof_boarding_anchor = true
	anchor.position = Vector3(0.0, 3.6, 10.0)
	
	grapple.target_anchor = anchor
	grapple.is_grappling = true
	grapple.is_target_heavy = true
	
	# Pilot arrives within 1.5m of roof anchor (pilot at Y=3.0, Z=9.0)
	var landing_impulse: Vector3 = grapple.process_grapple(0.016, Vector3(0.0, 3.0, 9.0))
	var is_still_grappling: bool = grapple.is_grappling
	
	# Grapple should release and grant gentle settling landing
	var passed: bool = (not is_still_grappling) and is_equal_approx(landing_impulse.y, -1.0)
	
	grapple.free()
	anchor.free()
	return {
		"name": "test_pilot_grapple_roof_boarding_boost",
		"passed": passed,
		"message": "Landing vector upon roof arrival: %s, released=%s (passed: %s)" % [
			str(landing_impulse), str(not is_still_grappling), str(passed)
		]
	}

const PilotWalkingStateClass = preload("res://scripts/state_machine/pilot_states/pilot_walking_state.gd")

func _test_pilot_moving_train_roof_physics_coupling() -> Dictionary:
	var car: TrainCar = TrainCar.new()
	car.forward_speed_ms = 14.5
	car.rotation = Vector3.ZERO
	
	var walk_state: PilotWalkingState = PilotWalkingStateClass.new()
	var extracted_vel: Vector3 = walk_state._extract_body_velocity(car)
	
	# Moving train velocity along forward vector -Z (0, 0, -14.5)
	var passed: bool = is_equal_approx(extracted_vel.z, -14.5) and is_equal_approx(extracted_vel.x, 0.0)
	
	car.free()
	walk_state.free()
	return {
		"name": "test_pilot_moving_train_roof_physics_coupling",
		"passed": passed,
		"message": "Moving train roof velocity coupled to pilot: %s (expected 14.5 m/s forward) [passed: %s]" % [
			str(extracted_vel), str(passed)
		]
	}
