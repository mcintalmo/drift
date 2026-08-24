extends SceneTree

const ActiveHeistScene = preload("res://scenes/world/ActiveTrainHeistSector.tscn")
const HexSectorManager = preload("res://scripts/world/hex_sector_manager.gd")
const MovingTrain = preload("res://scripts/entities/world/moving_train.gd")
const TrainCar = preload("res://scripts/entities/world/train_car.gd")
const HexWorldTile = preload("res://scripts/world/hex_world_tile.gd")

func _init() -> void:
	print("==========================================================")
	print("  ACTIVE TRAIN HEIST LONG-SECTOR SIMULATION TEST         ")
	print("==========================================================")
	
	var heist_world: Node3D = ActiveHeistScene.instantiate() as Node3D
	root.add_child(heist_world)
	
	print("[1/6] Instantiating ActiveTrainHeistSector.tscn into SceneTree...")
	
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
	
	print("[2/6] Inspecting Long Winding Trans-Continental Mag-Rail...")
	var path_nodes: Array[Vector2i] = sector_mgr.get_railroad_path()
	var curve: Curve3D = sector_mgr.get_macro_railroad_curve()
	var track_len: float = curve.get_baked_length() if curve else 0.0
	print("  [OK] Railroad Path Hex Nodes: %d across canyon" % path_nodes.size())
	print("  [OK] Total 3D Curve Length: %.1f meters (Long Heist Map: >900m)" % track_len)
	
	print("[3/6] Inspecting Active Track Obstacle & Prop Clearance...")
	var props_on_rail_found: int = 0
	for coord in sector_mgr._active_tiles:
		var tile: Node3D = sector_mgr._active_tiles[coord]
		if tile is HexWorldTile:
			var hex_tile: HexWorldTile = tile as HexWorldTile
			if hex_tile.distance_to_rail_m < 5.0 and hex_tile.is_railroad_active:
				if not hex_tile._spawned_props.is_empty():
					props_on_rail_found += hex_tile._spawned_props.size()
					
	print("  [OK] Props / Crates Spawned on Active Track Line: %d (expected 0)" % props_on_rail_found)
	
	print("[4/6] Inspecting Moving Train Convoy & Locomotive Spawn...")
	var train: MovingTrain = sector_mgr.get_active_moving_train() as MovingTrain
	if not train:
		printerr("[FAIL] MovingTrainConvoy was not spawned on active heist map!")
		quit(1)
		return
		
	print("  [OK] Active Train Convoy spawned with %d cars (Locomotive + Boxcars)" % train.train_cars.size())
	var initial_train_pos: Vector3 = train.get_train_lead_position()
	print("  [OK] Initial Locomotive Position at Cave Mouth: %s" % str(initial_train_pos))
	
	print("[5/6] Advancing 6 Seconds of Physics (4s start delay + 2s acceleration)...")
	for sec: int in range(6):
		for frame: int in range(60):
			train._physics_process(1.0 / 60.0)
			
	var moving_train_pos: Vector3 = train.get_train_lead_position()
	var train_speed: float = train.current_speed_ms
	var time_left: float = train.get_time_until_extraction_seconds()
	print("  [OK] Post-Acceleration Speed: %.1f m/s (Cruise target: %.1f m/s)" % [train_speed, train.cruise_speed_ms])
	print("  [OK] New Locomotive Position: %s" % str(moving_train_pos))
	print("  [OK] Estimated Time to Extraction: %.1f seconds (%.1f minutes)" % [time_left, time_left / 60.0])
	
	print("[6/6] Testing Precision Breaching of Boxcar Magnetic Door Lock...")
	var boxcar: TrainCar = train.train_cars[1] as TrainCar
	print("  [OK] Boxcar 1 Initial Doors Locked: %s" % str(boxcar.doors_locked))
	boxcar.breach_doors()
	print("  [OK] Boxcar 1 Post-Breach Doors Locked: %s" % str(boxcar.doors_locked))
	
	if track_len > 800.0 and props_on_rail_found == 0 and train.train_cars.size() >= 3 and train_speed > 0.0 and not boxcar.doors_locked:
		print("\n==========================================================")
		print("  ALL ACTIVE TRAIN HEIST LONG-SECTOR SIMULATIONS PASSED! ")
		print("==========================================================")
		heist_world.queue_free()
		quit(0)
	else:
		printerr("[FAIL] Heist assertions failed! (track_len=%.1f, props=%d, cars=%d, speed=%.1f)" % [
			track_len, props_on_rail_found, train.train_cars.size(), train_speed
		])
		heist_world.queue_free()
		quit(1)
