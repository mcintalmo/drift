class_name RunnerData
extends Resource

@export_group("Identification")
@export var runner_id: StringName = &"default_pack"
@export var runner_name: String = "Standard Pack Runners"

@export_group("Surface Friction Matrix (Lateral Grip, Longitudinal Drag)")
## Black Ice: near-zero lateral grip, near-zero longitudinal drag
@export var friction_black_ice: Vector2 = Vector2(0.05, 0.02)

## Packed Snow: standard cruising grip, low drag
@export var friction_pack: Vector2 = Vector2(0.75, 0.15)

## Powder: moderate grip, high rolling drag
@export var friction_powder: Vector2 = Vector2(0.45, 0.55)

## Slush: low grip, high variable drag
@export var friction_slush: Vector2 = Vector2(0.30, 0.40)

## Snirt (Snow + Industrial Grit): sharp aggressive bite, moderate drag
@export var friction_snirt: Vector2 = Vector2(0.85, 0.35)

## Permafrost Scree: bumpy grip, low drag
@export var friction_scree: Vector2 = Vector2(0.60, 0.25)

@export_group("Handling Adjustments")
@export_range(0.5, 2.0, 0.05) var steering_bite_multiplier: float = 1.0
@export_range(0.0, 0.1, 0.005) var wear_rate_per_km: float = 0.01

## Returns Vector2(lateral_friction, longitudinal_drag) for a surface type string
func get_friction_for_surface(surface_type: StringName) -> Vector2:
	match surface_type:
		&"black_ice":
			return friction_black_ice
		&"powder":
			return friction_powder
		&"slush":
			return friction_slush
		&"snirt":
			return friction_snirt
		&"scree":
			return friction_scree
		_:
			return friction_pack
