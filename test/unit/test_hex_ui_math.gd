class_name TestHexUIMath
extends RefCounted

const HexGridControl = preload("res://scripts/ui/hex_grid_control.gd")
const HexItemData = preload("res://scripts/resources/hex_item_data.gd")

func run_tests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_test_axial_to_pixel_roundtrip())
	results.append(_test_six_step_rotation_closure())
	results.append(_test_hex_polygon_vertices_count())
	return results

func _test_axial_to_pixel_roundtrip() -> Dictionary:
	var grid_control: HexGridControl = HexGridControl.new()
	grid_control.size = Vector2(300, 300)
	grid_control.cell_radius = 25.0
	
	var test_coords: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(2, -3),
		Vector2i(-4, -2)
	]
	
	var all_matched: bool = true
	for coord: Vector2i in test_coords:
		var px: Vector2 = grid_control.hex_to_pixel(coord) + (grid_control.size * 0.5)
		var converted_back: Vector2i = grid_control.pixel_to_hex(px)
		if converted_back != coord:
			all_matched = false
			break
	
	grid_control.free()
	return {
		"name": "test_axial_to_pixel_roundtrip",
		"passed": all_matched,
		"message": "Axial coordinates successfully round-tripped through pixel space"
	}

func _test_six_step_rotation_closure() -> Dictionary:
	var item: HexItemData = HexItemData.new()
	# Asymmetric L-shape footprint
	item.hex_footprint = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	
	var initial_footprint: Array[Vector2i] = item.get_rotated_footprint(0)
	var rotated_6_times: Array[Vector2i] = item.get_rotated_footprint(6)
	
	var passed: bool = (initial_footprint == rotated_6_times)
	
	return {
		"name": "test_six_step_rotation_closure",
		"passed": passed,
		"message": "6-step 60-degree rotation exhibits closed 360-degree symmetry"
	}

func _test_hex_polygon_vertices_count() -> Dictionary:
	var grid_control: HexGridControl = HexGridControl.new()
	grid_control.cell_radius = 20.0
	
	var poly: PackedVector2Array = grid_control.get_hex_polygon(Vector2(50, 50), 20.0)
	
	var passed: bool = poly.size() == 6
	for pt: Vector2 in poly:
		var dist: float = pt.distance_to(Vector2(50, 50))
		if not is_equal_approx(dist, 20.0):
			passed = false
			break
	
	grid_control.free()
	return {
		"name": "test_hex_polygon_vertices_count",
		"passed": passed,
		"message": "Generated hexagon has exactly 6 vertices equidistant (20.0 px) from center"
	}
