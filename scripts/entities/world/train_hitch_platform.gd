class_name TrainHitchPlatform
extends TrainCar

@export var lead_car: TrainCar = null
@export var trailing_car: TrainCar = null

func _ready() -> void:
	super._ready()
	car_length_m = 2.8
	car_width_m = 2.8
	car_height_m = 1.8

## Overrides uncouple to disconnect trailing train cars when this hitch is severed
func uncouple_car() -> void:
	if not is_coupled:
		return
	is_coupled = false
	is_coasting = true
	
	if coupler_hurtbox:
		coupler_hurtbox.is_invulnerable = true
	
	if coupler_vis:
		var red_mat: StandardMaterial3D = StandardMaterial3D.new()
		red_mat.albedo_color = Color(0.15, 0.15, 0.15, 1)
		red_mat.emission_enabled = true
		red_mat.emission = Color(0.3, 0.1, 0.1, 1)
		red_mat.emission_energy_multiplier = 0.5
		coupler_vis.material_override = red_mat
	
	decoupled.emit(car_index)
	GlobalEvents.emit_train_car_decoupled(car_index)
	
	if is_instance_valid(trailing_car):
		trailing_car.uncouple_car()
