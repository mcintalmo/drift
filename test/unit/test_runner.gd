extends SceneTree

const TestInertialDrift = preload("res://test/unit/test_inertial_drift.gd")
const TestCenterOfMass = preload("res://test/unit/test_center_of_mass.gd")
const TestHexInventory = preload("res://test/unit/test_hex_inventory.gd")
const TestPseudoGravity = preload("res://test/unit/test_pseudo_gravity.gd")
const TestSledWinch = preload("res://test/unit/test_sled_winch.gd")
const TestPilotLocomotion = preload("res://test/unit/test_pilot_locomotion.gd")
const TestCombatBreach = preload("res://test/unit/test_combat_breach.gd")
const TestTrainDecoupling = preload("res://test/unit/test_train_decoupling.gd")
const TestHexUIMath = preload("res://test/unit/test_hex_ui_math.gd")

func _init() -> void:
	print("==================================================")
	print("  DRIFT ENGINE - HEADLESS AUTOMATED TEST RUNNER   ")
	print("==================================================")
	
	var total_tests: int = 0
	var passed_tests: int = 0
	var failed_tests: int = 0
	
	var test_suites: Array = [
		{"name": "Inertial Drift & Multi-Surface Physics", "instance": TestInertialDrift.new()},
		{"name": "Center of Mass & Tipping Dynamics", "instance": TestCenterOfMass.new()},
		{"name": "Hexagonal Spatial Inventory", "instance": TestHexInventory.new()},
		{"name": "Pseudo-Gravity Hex Settling Physics", "instance": TestPseudoGravity.new()},
		{"name": "Sled Heavy Winch & Spring Mechanics", "instance": TestSledWinch.new()},
		{"name": "Pilot Locomotion & Jetpack Mobility", "instance": TestPilotLocomotion.new()},
		{"name": "Combat Damage & Plasma Breaching", "instance": TestCombatBreach.new()},
		{"name": "Train Car Decoupling & Rail Dynamics", "instance": TestTrainDecoupling.new()},
		{"name": "Hexagonal 2D UI Math & Axial Symmetry", "instance": TestHexUIMath.new()}
	]
	
	for suite: Dictionary in test_suites:
		print("\n--- Running Suite: %s ---" % suite["name"])
		var suite_instance: RefCounted = suite["instance"]
		var results: Array[Dictionary] = suite_instance.run_tests()
		
		for res: Dictionary in results:
			total_tests += 1
			if res["passed"]:
				passed_tests += 1
				print("  [PASS] %s: %s" % [res["name"], res["message"]])
			else:
				failed_tests += 1
				print("  [FAIL] %s: %s" % [res["name"], res["message"]])
	
	print("\n==================================================")
	print("  TEST RESULTS: %d Passed, %d Failed, %d Total" % [passed_tests, failed_tests, total_tests])
	print("==================================================")
	
	if failed_tests == 0:
		print("All Drift unit tests passed successfully.")
		quit(0)
	else:
		print("Test failures detected.")
		quit(1)
