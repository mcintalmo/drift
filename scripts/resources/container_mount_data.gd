class_name ContainerMountData
extends Resource

@export_group("Identification")
@export var container_id: StringName = &"cargo_pod_standard"
@export var container_name: String = "Standard Sled Cargo Pod"

@export_group("Physical Profile")
@export_range(1.0, 50.0, 0.5) var tare_mass_kg: float = 12.0
@export_range(5.0, 300.0, 5.0) var max_weight_capacity_kg: float = 80.0
@export var local_mount_offset: Vector2 = Vector2.ZERO

@export_group("Hex Spatial Shape")
## Axial coordinates Vector2i(q, r) defining the accessible slot layout of this container
@export var slot_layout: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(0, -1),
	Vector2i(1, -1)
]

## Check if a specific axial coordinate exists in this container's layout
func has_slot(coord: Vector2i) -> bool:
	return coord in slot_layout
