class_name GroundCrate
extends StaticBody3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal crate_opened
signal lock_damaged(current_lock_hp: float)
signal loot_search_started
signal loot_search_completed

@export var is_locked: bool = true
@export var is_searched: bool = false
@export var search_duration: float = 1.2
@export var lock_health: float = 60.0
@export var crate_variant: int = 1

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
	
	_populate_loot()

## Handles player interaction with first-time loot channel
func interact_loot(player: Node3D, donut: Node, on_open_inventory: Callable) -> void:
	if is_searched and not is_locked:
		# Already unlocked and searched: instant access
		if on_open_inventory.is_valid():
			on_open_inventory.call()
		return
		
	if donut and donut.has_method("start_channel"):
		loot_search_started.emit()
		donut.start_channel(
			"Searching Crate...",
			search_duration,
			func() -> void:
				is_searched = true
				_on_lock_breached()
				loot_search_completed.emit()
				if on_open_inventory.is_valid():
					on_open_inventory.call(),
			func() -> void:
				pass, # Cancelled
			self,
			player,
			3.5
		)
	else:
		# Fallback if no donut provided
		is_searched = true
		_on_lock_breached()
		if on_open_inventory.is_valid():
			on_open_inventory.call()

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
	is_searched = true
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

func _populate_loot() -> void:
	if not inventory:
		return
	
	if crate_variant == 1:
		var scrap: HexItemData = preload("res://resources/items/scrap_ingot.tres").duplicate()
		var fuel: HexItemData = preload("res://resources/items/dual_fuel_rod.tres").duplicate()
		var boom: HexItemData = preload("res://resources/items/plasma_boomerang.tres").duplicate()
		
		inventory.place_item(scrap, Vector2i(0, 0))
		inventory.place_item(fuel, Vector2i(1, -1))
		inventory.place_item(boom, Vector2i(-1, 0))
	else:
		var steel: HexItemData = preload("res://resources/items/steel_rail_bar.tres").duplicate()
		var core: HexItemData = preload("res://resources/items/heavy_reactor_core.tres").duplicate()
		
		inventory.place_item(steel, Vector2i(0, -1))
		inventory.place_item(core, Vector2i(-1, 1))
