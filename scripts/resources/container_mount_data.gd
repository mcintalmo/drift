class_name ContainerMountData
extends Resource

@export_group("Identification")
@export var container_id: StringName = &"cargo_pod_standard"
@export var container_name: String = "Standard Sled Cargo Pod"

@export_group("Physical Profile")
@export_range(1.0, 50.0, 0.5) var tare_mass_kg: float = 12.0
@export_range(5.0, 500.0, 5.0) var max_weight_capacity_kg: float = 200.0
@export var local_mount_offset: Vector2 = Vector2.ZERO

@export_group("Hex Spatial Shape")
## Axial coordinates Vector2i(q, r) defining the accessible slot layout of this container
@export var slot_layout: Array[Vector2i] = []

func _init() -> void:
	if slot_layout.is_empty():
		slot_layout = generate_hex_cluster(2) # Default 19-hex pod

## Generates concentric hexagonal rings of axial coordinates
static func generate_hex_cluster(radius: int) -> Array[Vector2i]:
	var slots: Array[Vector2i] = [Vector2i(0, 0)]
	for q: int in range(-radius, radius + 1):
		var r1: int = max(-radius, -q - radius)
		var r2: int = min(radius, -q + radius)
		for r: int in range(r1, r2 + 1):
			var pt: Vector2i = Vector2i(q, r)
			if not slots.has(pt):
				slots.append(pt)
	return slots

## Check if a specific axial coordinate exists in this container's layout
func has_slot(coord: Vector2i) -> bool:
	return coord in slot_layout
