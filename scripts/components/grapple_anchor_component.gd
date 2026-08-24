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
@export var is_roof_boarding_anchor: bool = false
@export var local_tether_offset: Vector3 = Vector3.ZERO
@export var mass_kg: float = 10000.0 # High default for static objects

func _ready() -> void:
	add_to_group(&"grapple_anchors")

## Returns the current global world position of this grapple anchor
func get_global_anchor_position() -> Vector3:
	if is_inside_tree():
		return global_transform * local_tether_offset
	return position + local_tether_offset

## Returns the velocity of the parent body (e.g. TrainCar or Sled) if applicable
func get_parent_body_velocity() -> Vector3:
	var p: Node = get_parent()
	if not p:
		return Vector3.ZERO
	if "velocity" in p:
		return p.velocity
	if p is Node3D:
		# If parent is a TrainCar or moving body with train speed
		if "forward_speed_ms" in p:
			var fwd: Vector3 = -p.global_transform.basis.z.normalized() if p.is_inside_tree() else -p.transform.basis.z.normalized()
			return fwd * float(p.get("forward_speed_ms"))
	return Vector3.ZERO
