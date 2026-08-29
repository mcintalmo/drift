class_name TrainHitchPlatform
extends TrainCar

@export var lead_car: TrainCar = null
@export var trailing_car: TrainCar = null

func _ready() -> void:
	super._ready()
	car_length_m = 3.2
	car_width_m = 3.2
	car_height_m = 2.0

## Precision hold-to-interact cutting of the magnetic coupler mechanism
func interact_plasma_torch(player: Node3D, donut: Node) -> void:
	if not is_coupled:
		return
		
	if donut and donut.has_method("start_channel"):
		donut.start_channel(
			"Cutting Magnetic Coupler Lock...",
			2.0,
			func() -> void:
				uncouple_car(),
			func() -> void:
				pass, # Cancelled on button release
			coupler_vis if coupler_vis else self,
			player,
			4.5
		)
	else:
		uncouple_car()

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
