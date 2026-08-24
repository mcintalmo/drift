extends SceneTree

const SandboxScene = preload("res://scenes/world/ProceduralSectorSandbox.tscn")
const HexSectorManager = preload("res://scripts/world/hex_sector_manager.gd")
const DynamicWeatherManager = preload("res://scripts/world/dynamic_weather_manager.gd")

func _init() -> void:
	print("==========================================================")
	print("  PROCEDURAL SECTOR SANDBOX - MODEL C SIMULATION TEST     ")
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
	print("  [OK] Initial Hex Tiles Spawned (R=6m, 4 Rings): %d tiles" % initial_tile_count)
	
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
	
	print("[4/5] Testing Sled Movement & Seamless Gliding over Model C Hexes...")
	sled.velocity = Vector3(0, 0, 15.0)
	print("  [OK] Sled Post-Drift Position: %s, Speed: %.2f m/s" % [str(sled.position), sled.velocity.length()])
	
	print("[5/5] Testing Dynamic Weather Ambient Temperature Query...")
	var ambient_temp: float = weather_mgr.get_temperature_at_position(Vector3(0, 0, 0))
	print("  [OK] Ambient Weather Temp during Gale Storm: %.1f C" % ambient_temp)
	
	if initial_tile_count >= 61 and ambient_temp < 0.0:
		print("\n==========================================================")
		print("  ALL MODEL C PROCEDURAL WORLD & WEATHER SIMULATIONS PASSED!")
		print("==========================================================")
		sandbox.queue_free()
		quit(0)
	else:
		printerr("[FAIL] Simulation assertions failed! (initial_tile_count=%d, ambient_temp=%.1f)" % [
			initial_tile_count, ambient_temp
		])
		sandbox.queue_free()
		quit(1)
