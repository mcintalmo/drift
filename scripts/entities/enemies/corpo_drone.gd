class_name CorpoDrone
extends CharacterBody3D

signal drone_destroyed

@export var patrol_radius: float = 8.0
@export var hover_height: float = 3.5
@export var move_speed: float = 7.0
@export var detection_range: float = 24.0

var _target_player: Node3D = null
var _origin_position: Vector3 = Vector3.ZERO
var _fire_timer: float = 0.0

@onready var health_comp: HealthComponent = $HealthComponent
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var drone_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D

func _ready() -> void:
	_origin_position = global_position
	if health_comp:
		health_comp.health_changed.connect(func(_cur: float, _max: float, _delta: float) -> void:
			_flash_hit()
		)
		health_comp.died.connect(func() -> void:
			drone_destroyed.emit()
			queue_free()
		)

func _physics_process(delta: float) -> void:
	_update_target_detection()
	
	if _target_player:
		# Pursue player
		var to_player: Vector3 = _target_player.global_position - global_position
		to_player.y = 0.0 # Maintain hover plane
		var dir: Vector3 = to_player.normalized()
		velocity = dir * move_speed
		
		# Face player
		if dir.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 6.0 * delta)
		
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = 1.4
			if hitbox:
				hitbox.is_active = true
				_flash_attack()
				get_tree().create_timer(0.15).timeout.connect(func() -> void:
					if is_instance_valid(hitbox):
						hitbox.is_active = false
				)
	else:
		# Return toward origin
		var to_origin: Vector3 = _origin_position - global_position
		if to_origin.length() > 1.0:
			velocity = to_origin.normalized() * (move_speed * 0.5)
		else:
			velocity = Vector3.ZERO
	
	# Hover oscillation
	global_position.y = _origin_position.y + sin(Time.get_ticks_msec() * 0.003) * 0.4
	move_and_slide()

func _flash_hit() -> void:
	if drone_mesh:
		var white_mat: StandardMaterial3D = StandardMaterial3D.new()
		white_mat.albedo_color = Color(1, 1, 1, 1)
		white_mat.emission_enabled = true
		white_mat.emission = Color(1, 1, 1, 1)
		white_mat.emission_energy_multiplier = 5.0
		drone_mesh.material_override = white_mat
		get_tree().create_timer(0.08).timeout.connect(func() -> void:
			if is_instance_valid(drone_mesh):
				drone_mesh.material_override = null
		)

func _flash_attack() -> void:
	if drone_mesh:
		var red_mat: StandardMaterial3D = StandardMaterial3D.new()
		red_mat.albedo_color = Color(1, 0.2, 0.2, 1)
		red_mat.emission_enabled = true
		red_mat.emission = Color(1, 0.2, 0.2, 1)
		red_mat.emission_energy_multiplier = 4.0
		drone_mesh.material_override = red_mat
		get_tree().create_timer(0.15).timeout.connect(func() -> void:
			if is_instance_valid(drone_mesh):
				drone_mesh.material_override = null
		)

func _update_target_detection() -> void:
	if not is_inside_tree() or not get_tree():
		_target_player = null
		return
	
	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group(&"player_pilot"))
	candidates.append_array(get_tree().get_nodes_in_group(&"player_sled"))
	
	for c: Node in candidates:
		if c is Node3D and is_instance_valid(c):
			var dist: float = (c.global_position - global_position).length()
			if dist <= detection_range:
				_target_player = c
				return
	_target_player = null
