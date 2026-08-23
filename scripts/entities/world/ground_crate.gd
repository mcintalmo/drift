class_name GroundCrate
extends StaticBody3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal crate_opened
signal lock_damaged(current_lock_hp: float)

@export var is_locked: bool = true
@export var lock_health: float = 60.0

@onready var inventory: HexInventoryComponent = $HexInventoryComponent
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
@onready var lock_health_component: HealthComponent = $LockHealthComponent
@onready var lid_mesh: MeshInstance3D = get_node_or_null("VisualModel/LidMesh") as MeshInstance3D
@onready var lock_mesh: MeshInstance3D = get_node_or_null("VisualModel/LockMesh") as MeshInstance3D

func _ready() -> void:
	if lock_health_component:
		lock_health_component.max_health = lock_health
		lock_health_component.current_health = lock_health
		lock_health_component.health_changed.connect(func(cur: float, _max: float, _delta: float) -> void:
			lock_damaged.emit(cur)
			_flash_damage()
		)
		lock_health_component.died.connect(_on_lock_breached)
	
	_populate_default_loot()

func _flash_damage() -> void:
	if lock_mesh:
		var mat: StandardMaterial3D = lock_mesh.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 10.0
			get_tree().create_timer(0.08).timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.emission_energy_multiplier = 3.0
			)

func _on_lock_breached() -> void:
	if not is_locked:
		return
	is_locked = false
	if hurtbox:
		hurtbox.is_invulnerable = true
	
	# Rotate lid open
	if lid_mesh:
		lid_mesh.rotation_degrees.x = -55.0
		lid_mesh.position.y = 1.3
		lid_mesh.position.z = -0.3
	
	# Turn lock light green
	if lock_mesh:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.9, 0.3, 1)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 1.0, 0.4, 1)
		mat.emission_energy_multiplier = 4.0
		lock_mesh.material_override = mat
	
	crate_opened.emit()
	GlobalEvents.emit_crate_breached(self)

func _populate_default_loot() -> void:
	if inventory:
		var scrap_item: HexItemData = HexItemData.new()
		scrap_item.item_id = &"item_scrap_metal"
		scrap_item.mass_kg = 8.0
		scrap_item.hex_footprint = [Vector2i(0, 0)]
		inventory.place_item(scrap_item, Vector2i(0, 0))
