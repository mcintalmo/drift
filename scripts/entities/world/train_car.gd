class_name TrainCar
extends CharacterBody3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal decoupled(car_index: int)
signal side_doors_breached

@export var car_index: int = 0
@export var is_coupled: bool = true
@export var coupler_health: float = 80.0
@export var doors_locked: bool = true

var trailing_cars: Array[TrainCar] = []
var forward_speed_ms: float = 0.0

@onready var coupler_health_comp: HealthComponent = $CouplerHealthComponent
@onready var coupler_hurtbox: HurtboxComponent = $CouplerHurtbox
@onready var cargo_inventory: HexInventoryComponent = $CargoInventoryComponent
@onready var grapple_anchor: GrappleAnchorComponent = $GrappleAnchorComponent
@onready var coupler_vis: MeshInstance3D = get_node_or_null("VisualModel/CouplerVisual") as MeshInstance3D

func _ready() -> void:
	if coupler_health_comp:
		coupler_health_comp.max_health = coupler_health
		coupler_health_comp.current_health = coupler_health
		coupler_health_comp.health_changed.connect(func(_cur: float, _max: float, _delta: float) -> void:
			_flash_coupler()
		)
		coupler_health_comp.died.connect(uncouple_car)

func _physics_process(delta: float) -> void:
	if not is_coupled and forward_speed_ms > 0.0:
		# Decoupled car gradually slows down from rail drag
		forward_speed_ms = maxf(0.0, forward_speed_ms - 4.5 * delta)
		var basis_z: Vector3 = global_transform.basis.z if is_inside_tree() else transform.basis.z
		velocity = -basis_z * forward_speed_ms
		if is_inside_tree():
			move_and_slide()

func _flash_coupler() -> void:
	if coupler_vis:
		var mat: StandardMaterial3D = coupler_vis.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 10.0
			get_tree().create_timer(0.08).timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.emission_energy_multiplier = 4.0
			)

func uncouple_car() -> void:
	if not is_coupled:
		return
	is_coupled = false
	if coupler_hurtbox:
		coupler_hurtbox.is_invulnerable = true
	
	if coupler_vis:
		var red_mat: StandardMaterial3D = StandardMaterial3D.new()
		red_mat.albedo_color = Color(0.1, 0.1, 0.1, 1)
		red_mat.emission_enabled = true
		red_mat.emission = Color(0.2, 0.2, 0.2, 1)
		red_mat.emission_energy_multiplier = 0.5
		coupler_vis.material_override = red_mat
	
	decoupled.emit(car_index)
	GlobalEvents.emit_train_car_decoupled(car_index)
	
	# Uncouple all attached trailing cars
	for child_car: TrainCar in trailing_cars:
		if is_instance_valid(child_car):
			child_car.uncouple_car()

func set_train_speed(speed: float) -> void:
	if is_coupled:
		forward_speed_ms = speed
		var basis_z: Vector3 = global_transform.basis.z if is_inside_tree() else transform.basis.z
		velocity = -basis_z * forward_speed_ms
