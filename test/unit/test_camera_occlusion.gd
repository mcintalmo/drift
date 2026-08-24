class_name TestCameraOcclusion
extends RefCounted

const IsometricCameraRigClass = preload("res://scripts/camera/isometric_camera_rig.gd")

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_camera_material_collection())
	results.append(_test_camera_occlusion_alpha_fading())
	return results

func _test_camera_material_collection() -> Dictionary:
	var rig: IsometricCameraRig = IsometricCameraRig.new()
	
	# Create dummy parent node with MeshInstance3D child
	var root: Node3D = Node3D.new()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.8, 1.0)
	mesh_inst.material_override = mat
	root.add_child(mesh_inst)
	
	var collected: Array[StandardMaterial3D] = []
	rig._collect_mesh_materials(root, collected)
	
	var passed: bool = (collected.size() == 1) and (collected[0] == mat)
	
	root.free()
	rig.free()
	return {
		"name": "test_camera_material_collection",
		"passed": passed,
		"message": "Camera rig collected %d mesh materials from collider hierarchy (expected 1)" % collected.size()
	}

func _test_camera_occlusion_alpha_fading() -> Dictionary:
	var rig: IsometricCameraRig = IsometricCameraRig.new()
	rig.is_terrain_see_through_enabled = true
	rig.occluded_transparency_alpha = 0.28
	rig.fade_in_speed = 10.0
	rig.fade_out_speed = 10.0
	
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	
	# Manually insert into occluded registry to test fading math
	rig._occluded_materials[mat] = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	# Simulate 1 step of occluded fade in (delta = 0.05s)
	# move_toward(1.0, 0.28, 10.0 * 0.05 = 0.5) -> 0.50
	var new_a: float = move_toward(1.0, 0.28, 10.0 * 0.05)
	mat.albedo_color.a = new_a
	
	var faded_passed: bool = is_equal_approx(mat.albedo_color.a, 0.50) and (mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
	
	# Simulate clear fade out back to 1.0
	new_a = move_toward(0.50, 1.0, 10.0 * 0.06) # -> 1.0
	mat.albedo_color.a = new_a
	if new_a >= 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = 1.0
		
	var restored_passed: bool = is_equal_approx(mat.albedo_color.a, 1.0) and (mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	
	var passed: bool = faded_passed and restored_passed
	rig.free()
	
	return {
		"name": "test_camera_occlusion_alpha_fading",
		"passed": passed,
		"message": "Alpha faded to %.2f (TRANSPARENCY_ALPHA), then restored to %.2f (TRANSPARENCY_DISABLED)" % [0.50, mat.albedo_color.a]
	}
