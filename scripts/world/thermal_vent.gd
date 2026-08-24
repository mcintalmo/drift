class_name ThermalVent
extends Node3D

@export var warmth_radius_m: float = 12.0
@export var vent_temperature_c: float = 35.0
@export var is_active: bool = true

@onready var heat_area: Area3D = $HeatArea
@onready var steam_particles: CPUParticles3D = $SteamParticles
@onready var omni_light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	add_to_group(&"thermal_vents")
	if heat_area:
		heat_area.body_entered.connect(_on_body_entered)
		heat_area.body_exited.connect(_on_body_exited)
		var col: CollisionShape3D = heat_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col and col.shape is SphereShape3D:
			(col.shape as SphereShape3D).radius = warmth_radius_m

func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return
	var thermal_comp: ThermalReceiverComponent = body.get_node_or_null("ThermalReceiverComponent") as ThermalReceiverComponent
	if thermal_comp:
		thermal_comp.set_meta(&"near_thermal_vent", true)

func _on_body_exited(body: Node3D) -> void:
	var thermal_comp: ThermalReceiverComponent = body.get_node_or_null("ThermalReceiverComponent") as ThermalReceiverComponent
	if thermal_comp:
		thermal_comp.set_meta(&"near_thermal_vent", false)

## Queries temperature contribution at a given world position
func get_temperature_contribution(pos: Vector3) -> float:
	if not is_active:
		return 0.0
	var origin: Vector3 = global_position if is_inside_tree() else position
	var dist: float = origin.distance_to(pos)
	if dist <= warmth_radius_m:
		var falloff: float = 1.0 - (dist / warmth_radius_m)
		return vent_temperature_c * falloff
	return 0.0
