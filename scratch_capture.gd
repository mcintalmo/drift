extends SceneTree

var _frame_count: int = 0

func _initialize() -> void:
	var sandbox_scene: PackedScene = load("res://scenes/world/ProceduralSectorSandbox.tscn")
	var root_node: Node = sandbox_scene.instantiate()
	root.add_child(root_node)

func _process(delta: float) -> bool:
	_frame_count += 1
	if _frame_count == 35:
		var capture_path: String = "/Users/mcint/.gemini/antigravity-ide/brain/b05a58c6-3635-460a-9bea-deb6cb3bfc68/sector_gameplay_view.png"
		var img: Image = root.get_viewport().get_texture().get_image()
		if img:
			img.save_png(capture_path)
			print("SUCCESS_CAPTURED: ", capture_path)
		quit(0)
		return true
	return false
