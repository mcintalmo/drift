class_name HexItemData
extends Resource

enum ItemCategory {
	MATERIAL,
	SUSTENANCE,
	ENERGY,
	WEAPON,
	INFORMATION,
	EXTRACTION
}

@export_group("Metadata")
@export var item_id: StringName = &"item_scrap_metal"
@export var item_name: String = "Scrap Metal Ingot"
@export var category: ItemCategory = ItemCategory.MATERIAL
@export_multiline var description: String = "Raw reclaimed alloy sheets."

@export_group("Physical Properties")
@export_range(0.1, 100.0, 0.1) var mass_kg: float = 5.0
@export var is_stackable: bool = false
@export var max_stack_size: int = 1

@export_group("Spatial Hex Footprint")
## Axial coordinate offsets Vector2i(q, r) that this item occupies relative to its anchor point (0, 0)
@export var hex_footprint: Array[Vector2i] = [Vector2i(0, 0)]
@export var rotation_step: int = 0
@export var root_slot: Vector2i = Vector2i.ZERO

@export_group("Visuals")
@export var item_color: Color = Color(0.7, 0.7, 0.8, 1.0)
@export var icon_path: String = ""

## Returns the rotated hex footprint around (0, 0) in 60-degree increments (0 to 5)
func get_rotated_footprint(rotation_steps: int) -> Array[Vector2i]:
	var steps: int = ((rotation_steps % 6) + 6) % 6
	if steps == 0:
		return hex_footprint.duplicate()
	
	var rotated: Array[Vector2i] = []
	for coord: Vector2i in hex_footprint:
		var q: int = coord.x
		var r: int = coord.y
		# Rotate in axial coords: (q, r) -> (-r, q + r)
		for _i: int in range(steps):
			var next_q: int = -r
			var next_r: int = q + r
			q = next_q
			r = next_r
		rotated.append(Vector2i(q, r))
	return rotated
