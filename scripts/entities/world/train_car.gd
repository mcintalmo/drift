class_name TrainCar
extends AnimatableBody3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal decoupled(car_index: int)
signal side_doors_breached
signal door_breach_started
signal door_breach_completed

enum CarState {
	LOCKED = 0,
	UNLOCKED = 1
}

@export var car_state: CarState = CarState.LOCKED
@export var car_index: int = 0
@export var is_coupled: bool = true
@export var coupler_health: float = 80.0
@export var door_joint_health: float = 60.0
@export var car_length_m: float = 8.5
@export var car_width_m: float = 3.2
@export var car_height_m: float = 3.6

var doors_locked: bool:
	get:
		return car_state == CarState.LOCKED
	set(val):
		set_car_state(CarState.LOCKED if val else CarState.UNLOCKED)

var trailing_cars: Array[TrainCar] = []
var forward_speed_ms: float = 0.0
var distance_along_track: float = 0.0
var is_coasting: bool = false

# Real-time platform kinematics for riding characters
var prev_global_pos: Vector3 = Vector3.ZERO
var delta_displacement: Vector3 = Vector3.ZERO
var delta_yaw_rad: float = 0.0
var prev_yaw_rad: float = 0.0

# Sub-nodes
@onready var coupler_health_comp: HealthComponent = get_node_or_null("CouplerHealthComponent") as HealthComponent
@onready var coupler_hurtbox: HurtboxComponent = get_node_or_null("CouplerHurtbox") as HurtboxComponent
@onready var door_health_comp: HealthComponent = get_node_or_null("DoorHealthComponent") as HealthComponent
@onready var door_hurtbox: HurtboxComponent = get_node_or_null("DoorHurtbox") as HurtboxComponent
@onready var grapple_anchor: GrappleAnchorComponent = get_node_or_null("GrappleAnchorComponent") as GrappleAnchorComponent
@onready var left_door: Node3D = get_node_or_null("VisualModel/LeftSlidingDoor") as Node3D
@onready var right_door: Node3D = get_node_or_null("VisualModel/RightSlidingDoor") as Node3D
@onready var left_lock_vis: MeshInstance3D = get_node_or_null("VisualModel/LeftLock") as MeshInstance3D
@onready var right_lock_vis: MeshInstance3D = get_node_or_null("VisualModel/RightLock") as MeshInstance3D
@onready var lock_vis: MeshInstance3D = get_node_or_null("VisualModel/MagneticLock") as MeshInstance3D
@onready var coupler_vis: MeshInstance3D = get_node_or_null("VisualModel/CouplerVisual") as MeshInstance3D

func _ready() -> void:
	sync_to_physics = false
	
	# Setup Coupler Health
	if coupler_health_comp:
		coupler_health_comp.max_health = coupler_health
		coupler_health_comp.current_health = coupler_health
		coupler_health_comp.health_changed.connect(func(_cur: float, _max: float, _delta: float) -> void:
			_flash_coupler()
		)
		coupler_health_comp.died.connect(uncouple_car)
		
	# Setup Door Lock Health (High-destruction weapon path)
	if door_health_comp:
		door_health_comp.max_health = door_joint_health
		door_health_comp.current_health = door_joint_health
		door_health_comp.health_changed.connect(func(_cur: float, _max: float, _delta: float) -> void:
			_flash_door_lock()
		)
		door_health_comp.died.connect(breach_doors)
		
	_setup_geometry_if_missing()
	_update_child_crates_state()

func set_car_state(new_state: CarState) -> void:
	car_state = new_state
	_update_child_crates_state()

func _update_child_crates_state() -> void:
	for child: Node in find_children("*", "", true, false):
		if child.has_method("set_crate_state"):
			if car_state == CarState.LOCKED:
				child.call("set_crate_state", 0) # CrateState.NON_INTERACTABLE
			else:
				if int(child.get("crate_state")) == 0:
					child.call("set_crate_state", 1) # CrateState.LOCKED

func _physics_process(delta: float) -> void:
	if not is_coupled and forward_speed_ms > 0.0:
		# Decoupled car gradually coasts to a halt along rails
		forward_speed_ms = maxf(0.0, forward_speed_ms - 4.5 * delta)
		distance_along_track += forward_speed_ms * delta

## Sets platform position and orientation while tracking exact displacement delta for characters
func set_platform_transform(new_pos: Vector3, new_rot: Vector3, delta: float) -> void:
	if prev_global_pos != Vector3.ZERO and delta > 0.0:
		delta_displacement = new_pos - prev_global_pos
		delta_yaw_rad = wrapf(new_rot.y - prev_yaw_rad, -PI, PI)
		forward_speed_ms = delta_displacement.length() / delta
	else:
		delta_displacement = Vector3.ZERO
		delta_yaw_rad = 0.0
		
	prev_global_pos = new_pos
	prev_yaw_rad = new_rot.y
	
	if is_inside_tree():
		global_position = new_pos
	else:
		position = new_pos
	rotation = new_rot

## Precision Stealth Plasma Torch Channel (Continuous welding interaction)
func interact_plasma_torch(player: Node3D, donut: Node) -> void:
	if car_state == CarState.UNLOCKED:
		return
		
	# Requirement: Train car must be decoupled from locomotive before sliding doors can be unlocked
	if is_coupled:
		if player and player.is_inside_tree():
			var huds: Array[Node] = player.get_tree().root.find_children("*HUD*", "HUD", true, false)
			if not huds.is_empty() and huds[0].has_method("show_banner"):
				huds[0].call("show_banner", "CAR MUST BE DECOUPLED FROM TRAIN FIRST!")
		return
		
	# Determine nearest door lock to player (Left lock at X=-2.18 vs Right lock at X=+2.18)
	var anchor_target: Node3D = self
	if player:
		var p_pos: Vector3 = player.global_position if player.is_inside_tree() else player.position
		var left_pos: Vector3 = left_lock_vis.global_position if (left_lock_vis and left_lock_vis.is_inside_tree()) else (global_position + Vector3(-2.18, 2.0, 0))
		var right_pos: Vector3 = right_lock_vis.global_position if (right_lock_vis and right_lock_vis.is_inside_tree()) else (global_position + Vector3(2.18, 2.0, 0))
		
		if p_pos.distance_to(left_pos) < p_pos.distance_to(right_pos):
			anchor_target = left_lock_vis if left_lock_vis else left_door if left_door else self
		else:
			anchor_target = right_lock_vis if right_lock_vis else right_door if right_door else self
	elif left_lock_vis:
		anchor_target = left_lock_vis
		
	if donut and donut.has_method("start_channel"):
		door_breach_started.emit()
		donut.start_channel(
			"Unlocking Sliding Doors...",
			1.5,
			func() -> void:
				breach_doors()
				door_breach_completed.emit(),
			func() -> void:
				pass, # Cancelled
			anchor_target,
			player,
			4.5
		)
	else:
		breach_doors()

## Opens sliding boxcar side doors revealing the interior vault and unlocks child crates
func breach_doors() -> void:
	if car_state == CarState.UNLOCKED:
		return
	set_car_state(CarState.UNLOCKED)
	
	if door_hurtbox:
		door_hurtbox.is_invulnerable = true
	var right_hurtbox: HurtboxComponent = get_node_or_null("RightDoorHurtbox") as HurtboxComponent
	if right_hurtbox:
		right_hurtbox.is_invulnerable = true
		
	var door_col: CollisionShape3D = get_node_or_null("DoorCollision") as CollisionShape3D
	if door_col:
		door_col.set_deferred("disabled", true)
	var left_col: CollisionShape3D = get_node_or_null("LeftDoorCollision") as CollisionShape3D
	if left_col:
		left_col.set_deferred("disabled", true)
	var right_col: CollisionShape3D = get_node_or_null("RightDoorCollision") as CollisionShape3D
	if right_col:
		right_col.set_deferred("disabled", true)
		
	# Slide Left & Right Doors Open
	if left_door:
		var tw_l: Tween = create_tween()
		if tw_l:
			tw_l.tween_property(left_door, "position:z", left_door.position.z + 3.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if right_door:
		var tw_r: Tween = create_tween()
		if tw_r:
			tw_r.tween_property(right_door, "position:z", right_door.position.z - 3.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
	# Turn lock lights green
	var green_mat: StandardMaterial3D = StandardMaterial3D.new()
	green_mat.albedo_color = Color(0.1, 0.9, 0.3, 1)
	green_mat.emission_enabled = true
	green_mat.emission = Color(0.2, 1.0, 0.3, 1)
	green_mat.emission_energy_multiplier = 4.0
	
	if left_lock_vis:
		left_lock_vis.material_override = green_mat
	if right_lock_vis:
		right_lock_vis.material_override = green_mat
	if lock_vis:
		lock_vis.material_override = green_mat
		
	side_doors_breached.emit()

func _flash_coupler() -> void:
	if coupler_vis:
		var mat: StandardMaterial3D = coupler_vis.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 10.0
			get_tree().create_timer(0.08).timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.emission_energy_multiplier = 4.0
			)

func _flash_door_lock() -> void:
	if lock_vis:
		var mat: StandardMaterial3D = lock_vis.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 10.0
			get_tree().create_timer(0.08).timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.emission_energy_multiplier = 3.0
			)

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
	
	# Cascade uncouple to all trailing attached cars
	for child_car: TrainCar in trailing_cars:
		if is_instance_valid(child_car):
			child_car.uncouple_car()

func set_train_speed(speed: float) -> void:
	if is_coupled:
		forward_speed_ms = speed

func _setup_geometry_if_missing() -> void:
	if get_node_or_null("BoxcarCollision") or get_node_or_null("FloorCollision") or get_node_or_null("LocoCollision") or get_node_or_null("HitchCollision"):
		return
		
	# Solid Boxcar Platform Collision (Floor + Roof + Walls)
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "BoxcarCollision"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(car_width_m, car_height_m, car_length_m)
	col.shape = box
	col.position.y = car_height_m * 0.5
	add_child(col)
