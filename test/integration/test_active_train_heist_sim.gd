extends SceneTree

const ActiveHeistScene = preload("res://scenes/world/ActiveTrainHeistSector.tscn")
const HexSectorManager = preload("res://scripts/world/hex_sector_manager.gd")
const MovingTrain = preload("res://scripts/entities/world/moving_train.gd")
const TrainCar = preload("res://scripts/entities/world/train_car.gd")
const HexWorldTile = preload("res://scripts/world/hex_world_tile.gd")
const PilotClass = preload("res://scripts/entities/pilot/pilot.gd")
const SledClass = preload("res://scripts/entities/sled/sled_chassis.gd")
const GrappleAnchorClass = preload("res://scripts/components/grapple_anchor_component.gd")

func _init() -> void:
	print("==========================================================")
	print("  ACTIVE TRAIN HEIST LONG-SECTOR SIMULATION TEST         ")
	print("==========================================================")
	
	var heist_world: Node3D = ActiveHeistScene.instantiate() as Node3D
	root.add_child(heist_world)
	
	print("[1/7] Instantiating ActiveTrainHeistSector.tscn into SceneTree...")
	
	var sector_mgr: HexSectorManager = heist_world.get_node_or_null("HexSectorManager") as HexSectorManager
	var pilot: CharacterBody3D = heist_world.get_node_or_null("Pilot") as CharacterBody3D
	var sled: CharacterBody3D = heist_world.get_node_or_null("SledChassis") as CharacterBody3D
	
	if not sector_mgr or not pilot or not sled:
		printerr("[FAIL] One or more essential nodes missing!")
		quit(1)
		return
		
	if sector_mgr.get_active_tile_count() == 0:
		sector_mgr.generate_initial_sector()
		
	var initial_tiles: int = sector_mgr.get_active_tile_count()
	print("  [OK] Initial Hex Tiles: %d" % initial_tiles)
	
	print("[2/7] Inspecting Long Winding Trans-Continental Mag-Rail...")
	var path_nodes: Array[Vector2i] = sector_mgr.get_railroad_path()
	var curve: Curve3D = sector_mgr.get_macro_railroad_curve()
	var track_len: float = curve.get_baked_length() if curve else 0.0
	print("  [OK] Railroad Path Hex Nodes: %d across canyon" % path_nodes.size())
	print("  [OK] Total 3D Curve Length: %.1f meters (Long Heist Map: >900m)" % track_len)
	
	print("[3/7] Inspecting Active Track Obstacle & Prop Clearance...")
	var props_on_rail_found: int = 0
	for coord in sector_mgr._active_tiles:
		var tile: Node3D = sector_mgr._active_tiles[coord]
		if tile is HexWorldTile:
			var hex_tile: HexWorldTile = tile as HexWorldTile
			if hex_tile.distance_to_rail_m < 5.0 and hex_tile.is_railroad_active:
				if not hex_tile._spawned_props.is_empty():
					props_on_rail_found += hex_tile._spawned_props.size()
					
	print("  [OK] Props / Crates Spawned on Active Track Line: %d (expected 0)" % props_on_rail_found)
	
	print("[4/7] Advancing Moving Train Physics (4s start delay + 3s acceleration)...")
	var train: MovingTrain = sector_mgr.get_active_moving_train() as MovingTrain
	if not train:
		printerr("[FAIL] MovingTrainConvoy was not spawned on active heist map!")
		quit(1)
		return
		
	for sec: int in range(7):
		for frame: int in range(60):
			train._physics_process(1.0 / 60.0)
			
	var train_speed: float = train.current_speed_ms
	var moving_train_pos: Vector3 = train.get_train_lead_position()
	print("  [OK] Locomotive Speed: %.1f m/s, Position: %s" % [train_speed, str(moving_train_pos)])
	
	print("[5/7] Testing Sled Winch Towing to Moving Boxcar Coupler Anchor...")
	var boxcar1: TrainCar = train.train_cars[1] as TrainCar
	var coupler_anchor: GrappleAnchorComponent = boxcar1.get_node_or_null("CouplerGrappleAnchor") as GrappleAnchorComponent
	var sled_winch = sled.get_node_or_null("SledWinchComponent")
	
	if coupler_anchor and sled_winch:
		sled_winch.attach_to_anchor(coupler_anchor)
		if sled.is_inside_tree():
			sled.global_position = coupler_anchor.get_global_anchor_position() + Vector3(0, 0, 10.0)
		else:
			sled.position = coupler_anchor.get_global_anchor_position() + Vector3(0, 0, 10.0)
		var tow_force: Vector3 = sled_winch.compute_tether_force(0.016, Vector3.ZERO)
		print("  [OK] Sled Tethered: %s, Tow Force: %.1f N" % [str(sled_winch.is_tethered), tow_force.length()])
	else:
		printerr("[FAIL] Coupler anchor or sled winch missing!")
		quit(1)
		return
		
	print("[6/7] Testing Pilot Dismount Momentum Inheritance & Wrist Grapple Boarding...")
	sled.velocity = Vector3(0, 0, -train_speed)
	if pilot.has_method("mount_into_sled") and pilot.has_method("dismount_from_sled"):
		pilot.mount_into_sled(sled)
		pilot.dismount_from_sled()
		print("  [OK] Pilot Dismount Velocity: %s (Horiz speed: %.1f m/s)" % [
			str(pilot.velocity), Vector2(pilot.velocity.x, pilot.velocity.z).length()
		])
		
	var roof_anchor: GrappleAnchorComponent = boxcar1.get_node_or_null("RoofGrappleAnchor") as GrappleAnchorComponent
	var pilot_grapple = pilot.get_node_or_null("PilotGrappleComponent")
	
	var boarded_roof: bool = false
	if roof_anchor and pilot_grapple:
		pilot_grapple.target_anchor = roof_anchor
		pilot_grapple.is_grappling = true
		pilot_grapple.is_target_heavy = true
		
		# Pilot approaches roof anchor
		var board_impulse: Vector3 = pilot_grapple.process_grapple(0.016, roof_anchor.get_global_anchor_position() + Vector3(0, 1.0, 1.0))
		boarded_roof = (not pilot_grapple.is_grappling)
		print("  [OK] Wrist Grapple Roof Arrival: Landing impulse: %s, Grapple released: %s" % [
			str(board_impulse), str(not pilot_grapple.is_grappling)
		])
		
	print("[7/7] Testing Precision Breaching of Boxcar Magnetic Door Lock & Remote Detach...")
	print("  [OK] Boxcar 1 Initial Doors Locked: %s" % str(boxcar1.doors_locked))
	boxcar1.breach_doors()
	print("  [OK] Boxcar 1 Post-Breach Doors Locked: %s" % str(boxcar1.doors_locked))
	
	sled_winch.detach_tether()
	print("  [OK] Sled Winch Remote Detached: %s" % str(not sled_winch.is_tethered))
	
	if track_len > 800.0 and props_on_rail_found == 0 and train_speed > 0.0 and boarded_roof and not boxcar1.doors_locked and not sled_winch.is_tethered:
		print("\n==========================================================")
		print("  ALL ACTIVE TRAIN HEIST & BOARDING SIMULATIONS PASSED!  ")
		print("==========================================================")
		heist_world.queue_free()
		quit(0)
	else:
		printerr("[FAIL] Heist assertions failed! (track_len=%.1f, props=%d, speed=%.1f, boarded=%s)" % [
			track_len, props_on_rail_found, train_speed, str(boarded_roof)
		])
		heist_world.queue_free()
		quit(1)
