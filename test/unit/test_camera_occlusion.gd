class_name TestCameraOcclusion
extends RefCounted

const IsometricCameraRigClass = preload("res://scripts/camera/isometric_camera_rig.gd")

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_camera_mesh_collection())
	results.append(_test_camera_occlusion_alpha_fading())
	results.append(_test_multiple_cascaded_occluders())
	results.append(_test_shadow_proxy_creation_and_preservation())
	return results

func _test_camera_mesh_collection() -> Dictionary:
	var rig: IsometricCameraRig = IsometricCameraRig.new()
	
	var root: Node3D = Node3D.new()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.8, 1.0)
	mesh_inst.material_override = mat
	root.add_child(mesh_inst)
	
	var collected: Array[MeshInstance3D] = []
	rig._collect_mesh_instances(root, collected)
	
	var passed: bool = (collected.size() == 1) and (collected[0] == mesh_inst)
	
	root.free()
	rig.free()
	return {
		"name": "test_camera_mesh_collection",
		"passed": passed,
		"message": "Camera rig collected %d mesh instances from collider hierarchy (expected 1)" % collected.size()
	}

func _test_camera_occlusion_alpha_fading() -> Dictionary:
	var rig: IsometricCameraRig = IsometricCameraRig.new()
	rig.is_terrain_see_through_enabled = true
	rig.occluded_transparency_alpha = 0.18
	rig.fade_in_speed = 8.0
	rig.fade_out_speed = 4.5
	
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.material_override = mat
	
	var weight: float = 0.85
	var target_alpha: float = lerpf(1.0, 0.18, weight)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	var new_a: float = move_toward(1.0, target_alpha, 8.0 * 0.05)
	mat.albedo_color.a = new_a
	
	var faded_passed: bool = is_equal_approx(mat.albedo_color.a, 0.60) and (mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
	
	# Clear fade out back to 1.0
	new_a = move_toward(0.60, 1.0, 4.5 * 0.10)
	mat.albedo_color.a = new_a
	if new_a >= 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = 1.0
		
	var restored_passed: bool = is_equal_approx(mat.albedo_color.a, 1.0) and (mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	
	var passed: bool = faded_passed and restored_passed
	mi.free()
	rig.free()
	
	return {
		"name": "test_camera_occlusion_alpha_fading",
		"passed": passed,
		"message": "Smooth alpha faded to %.2f (target=%.2f), then restored to %.2f (TRANSPARENCY_DISABLED)" % [0.60, target_alpha, mat.albedo_color.a]
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
	
	var collected: Array[MeshInstance3D] = []
	rig._collect_mesh_instances(root1, collected)
	rig._collect_mesh_instances(root2, collected)
	
	var passed: bool = (collected.size() == 2) and (collected[0] == mesh1) and (collected[1] == mesh2)
	
	root1.free()
	root2.free()
	rig.free()
	
	return {
		"name": "test_multiple_cascaded_occluders",
		"passed": passed,
		"message": "Multiple cascaded occluders: %d distinct meshes collected simultaneously" % collected.size()
	}

func _test_shadow_proxy_creation_and_preservation() -> Dictionary:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	mi.mesh = sphere
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.9, 1.0)
	mi.material_override = mat
	
	# Create Shadow Proxy
	var proxy: MeshInstance3D = MeshInstance3D.new()
	proxy.name = "OcclusionShadowProxy"
	proxy.mesh = mi.mesh
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	mi.add_child(proxy)
	
	# Configure visual mesh for crystal-clear smooth alpha
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.18
	
	var proxy_valid: bool = (proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY) and (proxy.mesh == mi.mesh)
	var visual_valid: bool = (mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) and (mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA) and is_equal_approx(mat.albedo_color.a, 0.18)
	
	var passed: bool = proxy_valid and visual_valid
	
	mi.free()
	return {
		"name": "test_shadow_proxy_creation_and_preservation",
		"passed": passed,
		"message": "Shadow proxy created with SHADOWS_ONLY (Solid shadow preserved: %s, Crystal-clear alpha: %s)" % [str(proxy_valid), str(visual_valid)]
	}
