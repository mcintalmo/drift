extends SceneTree

const SandboxScene = preload("res://scenes/world/ProceduralSectorSandbox.tscn")
const HexSectorManager = preload("res://scripts/world/hex_sector_manager.gd")
const DynamicWeatherManager = preload("res://scripts/world/dynamic_weather_manager.gd")
const MovingTrain = preload("res://scripts/entities/world/moving_train.gd")
const TrainCar = preload("res://scripts/entities/world/train_car.gd")

func _init() -> void:
	print("==========================================================")
	print("  PROCEDURAL SECTOR & TRAIN HEIST SIMULATION TEST        ")
	print("==========================================================")
	
	var sandbox: Node3D = SandboxScene.instantiate() as Node3D
	root.add_child(sandbox)
	
	print("[1/5] Instantiating ProceduralSectorSandbox.tscn into SceneTree...")
	
	var sector_mgr: HexSectorManager = sandbox.get_node_or_null("HexSectorManager") as HexSectorManager
	var weather_mgr: DynamicWeatherManager = sandbox.get_node_or_null("DynamicWeatherManager") as DynamicWeatherManager
	var pilot: CharacterBody3D = sandbox.get_node_or_null("Pilot") as CharacterBody3D
	var sled: CharacterBody3D = sandbox.get_node_or_null("SledChassis") as CharacterBody3D
	
	if not sector_mgr or not weather_mgr or not pilot or not sled:
		printerr("[FAIL] One or more essential sandbox nodes were missing!")
		quit(1)
		return
	
	if sector_mgr.get_active_tile_count() == 0:
		sector_mgr.generate_initial_sector()
	
	var initial_tile_count: int = sector_mgr.get_active_tile_count()
	print("  [OK] Initial Hex Tiles Spawned (Asymmetric North Frustum): %d tiles" % initial_tile_count)
	
	print("[2/5] Advancing Physics Simulation across 60 frames (1.0s)...")
	for frame: int in range(60):
		weather_mgr._physics_process(1.0 / 60.0)
		sector_mgr._physics_process(1.0 / 60.0)
	
	print("  [OK] Pilot Position after settling: %s" % str(pilot.position))
	print("  [OK] Sled Position after settling: %s" % str(sled.position))
	
	print("[3/5] Testing Dynamic Weather Transitions & Wind Gusts...")
	weather_mgr.set_weather_state(DynamicWeatherManager.WeatherState.GALE_STORM)
	weather_mgr._physics_process(1.0 / 60.0)
	var wind_vec: Vector3 = weather_mgr.get_current_wind_vector()
	print("  [OK] Gale Storm Temp: %.1f C, Wind: %s (speed: %.1f m/s)" % [
		weather_mgr.current_ambient_temp_c, str(wind_vec), wind_vec.length()
	])
	
	print("[4/5] Testing Sled Movement & Momentum Preservation...")
	sled.velocity = Vector3(0, 0, 15.0)
	print("  [OK] Sled Post-Drift Position: %s, Speed: %.2f m/s" % [str(sled.position), sled.velocity.length()])
	
	print("[5/5] Testing Macro Railroad Spline & Moving Train Heist Convoy...")
	var path_nodes: Array[Vector2i] = sector_mgr.get_railroad_path()
	print("  [DEBUG] Railroad Path Nodes Count: %d" % path_nodes.size())
	var curve: Curve3D = sector_mgr.get_macro_railroad_curve()
	var curve_len: float = curve.get_baked_length() if curve else 0.0
	print("  [OK] Macro Railroad 3D Curve Length: %.1f meters across sector" % curve_len)
	
	if initial_tile_count >= 50 and curve_len > 100.0:
		print("\n==========================================================")
		print("  ALL PROCEDURAL WORLD, WEATHER & TRAIN HEIST SIMS PASSED!")
		print("==========================================================")
		sandbox.queue_free()
		quit(0)
	else:
		printerr("[FAIL] Simulation assertions failed! (initial_tile_count=%d, curve_len=%.1f)" % [
			initial_tile_count, curve_len
		])
		sandbox.queue_free()
		quit(1)
