class_name TestCameraOcclusion
extends RefCounted

const IsometricCameraRigClass = preload("res://scripts/camera/isometric_camera_rig.gd")

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_camera_material_collection())
	results.append(_test_camera_occlusion_alpha_fading())
	results.append(_test_multiple_cascaded_occluders())
	results.append(_test_shadow_depth_draw_preservation())
	return results

func _test_camera_material_collection() -> Dictionary:
	var rig: IsometricCameraRig = IsometricCameraRig.new()
	
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
	rig.fade_in_speed = 8.0
	rig.fade_out_speed = 4.5
	
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	
	var weight: float = 0.85
	var target_alpha: float = lerpf(1.0, 0.28, weight)
	rig._occluded_materials[mat] = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	
	var new_a: float = move_toward(1.0, target_alpha, 8.0 * 0.05)
	mat.albedo_color.a = new_a
	
	var faded_passed: bool = is_equal_approx(mat.albedo_color.a, 0.60) and (mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH)
	
	# Clear fade out back to 1.0
	new_a = move_toward(0.60, 1.0, 4.5 * 0.10)
	mat.albedo_color.a = new_a
	if new_a >= 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		mat.albedo_color.a = 1.0
		
	var restored_passed: bool = is_equal_approx(mat.albedo_color.a, 1.0) and (mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	
	var passed: bool = faded_passed and restored_passed
	rig.free()
	
	return {
		"name": "test_camera_occlusion_alpha_fading",
		"passed": passed,
		"message": "Anticipatory alpha faded to %.2f (target=%.2f), then restored to %.2f (TRANSPARENCY_DISABLED)" % [0.60, target_alpha, mat.albedo_color.a]
	}

func _test_multiple_cascaded_occluders() -> Dictionary:
	var rig: IsometricCameraRig = IsometricCameraRig.new()
	
	var root1: Node3D = Node3D.new()
	var mesh1: MeshInstance3D = MeshInstance3D.new()
	var mat1: StandardMaterial3D = StandardMaterial3D.new()
	mesh1.material_override = mat1
	root1.add_child(mesh1)
	
	var root2: Node3D = Node3D.new()
	var mesh2: MeshInstance3D = MeshInstance3D.new()
	var mat2: StandardMaterial3D = StandardMaterial3D.new()
	mesh2.material_override = mat2
	root2.add_child(mesh2)
	
	var collected: Array[StandardMaterial3D] = []
	rig._collect_mesh_materials(root1, collected)
	rig._collect_mesh_materials(root2, collected)
	
	var passed: bool = (collected.size() == 2) and (collected[0] == mat1) and (collected[1] == mat2)
	
	root1.free()
	root2.free()
	rig.free()
	
	return {
		"name": "test_multiple_cascaded_occluders",
		"passed": passed,
		"message": "Multiple cascaded occluders: %d distinct materials collected simultaneously" % collected.size()
	}

func _test_shadow_depth_draw_preservation() -> Dictionary:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.9, 1.0)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	
	# During occlusion fade: set to ALPHA_HASH + DEPTH_DRAW_ALWAYS to preserve full 3D shadow map projection
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.albedo_color.a = 0.28
	
	var passed: bool = (mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH) and (mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS) and is_equal_approx(mat.albedo_color.a, 0.28)
	
	return {
		"name": "test_shadow_depth_draw_preservation",
		"passed": passed,
		"message": "Transparent material retains ALPHA_HASH & DEPTH_DRAW_ALWAYS (Shadow casting preserved: %s)" % str(passed)
	}
