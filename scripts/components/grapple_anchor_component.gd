class_name GrappleAnchorComponent
extends Node3D

enum AnchorType {
	STATIC_PYLON,
	DYNAMIC_VEHICLE,
	TRAIN_CAR,
	CRYO_BEAST
}

@export var anchor_type: AnchorType = AnchorType.STATIC_PYLON
@export var is_grappleable: bool = true
@export var local_tether_offset: Vector3 = Vector3.ZERO
@export var mass_kg: float = 10000.0 # High default for static objects

func get_global_anchor_position() -> Vector3:
	if is_inside_tree():
		return global_transform * local_tether_offset
	return position + local_tether_offset
