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
	if p is Node3D:
		var drift_comp: Node = p.get_node_or_null("InertialDriftComponent")
		if drift_comp and "velocity_3d" in drift_comp:
			var d_vel: Vector3 = drift_comp.get("velocity_3d")
			if d_vel.length_squared() > 0.01:
				return d_vel
		if "forward_speed_ms" in p:
			var fwd: Vector3 = -p.global_transform.basis.z.normalized() if p.is_inside_tree() else -p.transform.basis.z.normalized()
			return fwd * float(p.get("forward_speed_ms"))
	if "velocity" in p:
		return p.velocity
	return Vector3.ZERO
