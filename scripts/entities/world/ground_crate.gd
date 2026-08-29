class_name GroundCrate
extends StaticBody3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal crate_opened
signal lock_damaged(current_lock_hp: float)
signal loot_search_started
signal loot_search_completed
signal crate_state_changed(new_state: CrateState)

enum CrateState {
	NON_INTERACTABLE = 0,
	LOCKED = 1,
	UNLOOTED = 2
}

@export var crate_state: CrateState = CrateState.LOCKED
@export var search_duration: float = 1.2
@export var lock_health: float = 60.0
@export var crate_variant: int = 1

var is_locked: bool:
	get:
		return crate_state != CrateState.UNLOOTED
	set(val):
		if not val:
			set_crate_state(CrateState.UNLOOTED)
		else:
			if crate_state == CrateState.UNLOOTED:
				set_crate_state(CrateState.LOCKED)

var is_searched: bool:
	get:
		return crate_state == CrateState.UNLOOTED
	set(val):
		if val:
			set_crate_state(CrateState.UNLOOTED)

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
	
	# If parent is a locked train car, initialize in NON_INTERACTABLE state
	var parent_node: Node = get_parent()
	if parent_node and parent_node.get("car_state") != null:
		if int(parent_node.get("car_state")) == 0: # CarState.LOCKED
			set_crate_state(CrateState.NON_INTERACTABLE)
		else:
			set_crate_state(CrateState.LOCKED)
	else:
		set_crate_state(crate_state)

## Updates crate state and synchronizes visuals, physics, and interactions
func set_crate_state(new_state: CrateState) -> void:
	crate_state = new_state
	
	match crate_state:
		CrateState.NON_INTERACTABLE:
			visible = false
			process_mode = Node.PROCESS_MODE_DISABLED
			if hurtbox:
				hurtbox.is_invulnerable = true
			if lock_mesh:
				# Dim lock in non-interactable mode
				var mat: StandardMaterial3D = StandardMaterial3D.new()
				mat.albedo_color = Color(0.15, 0.15, 0.15, 1.0)
				mat.emission_enabled = false
				lock_mesh.material_override = mat
				
		CrateState.LOCKED:
			visible = true
			process_mode = Node.PROCESS_MODE_INHERIT
			if hurtbox:
				hurtbox.is_invulnerable = false
			if lock_mesh:
				# Active red magnetic lock
				var mat: StandardMaterial3D = StandardMaterial3D.new()
				mat.albedo_color = Color(0.95, 0.2, 0.1, 1.0)
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.2, 0.1, 1.0)
				mat.emission_energy_multiplier = 4.0
				lock_mesh.material_override = mat
				
		CrateState.UNLOOTED:
			visible = true
			process_mode = Node.PROCESS_MODE_INHERIT
			if hurtbox:
				hurtbox.is_invulnerable = true
			if lock_mesh:
				# Unlocked green lock
				var mat: StandardMaterial3D = StandardMaterial3D.new()
				mat.albedo_color = Color(0.2, 0.9, 0.3, 1.0)
				mat.emission_enabled = true
				mat.emission = Color(0.3, 1.0, 0.4, 1.0)
				mat.emission_energy_multiplier = 4.0
				lock_mesh.material_override = mat
			if lid_mesh:
				if is_inside_tree():
					var tw: Tween = create_tween()
					if tw:
						tw.tween_property(lid_mesh, "rotation_degrees:x", -65.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
						tw.parallel().tween_property(lid_mesh, "position:y", 1.25, 0.4)
						tw.parallel().tween_property(lid_mesh, "position:z", -0.35, 0.4)
				else:
					lid_mesh.rotation_degrees.x = -65.0
					lid_mesh.position.y = 1.25
					lid_mesh.position.z = -0.35
					
	crate_state_changed.emit(crate_state)

## Handles player hold-to-interact looting and unlocking channel based on state machine
func interact_loot(player: Node3D, donut: Node, on_open_inventory: Callable) -> void:
	if crate_state == CrateState.NON_INTERACTABLE:
		return
		
	if crate_state == CrateState.UNLOOTED:
		# In UNLOOTED state: instant access (0s donut time)
		loot_search_started.emit()
		loot_search_completed.emit()
		if on_open_inventory.is_valid():
			on_open_inventory.call()
		return
		
	# In LOCKED state: 1.2s channel to unlock -> transitions to UNLOOTED
	if donut and donut.has_method("start_channel"):
		loot_search_started.emit()
		donut.start_channel(
			"Unlocking Crate...",
			search_duration,
			func() -> void:
				set_crate_state(CrateState.UNLOOTED)
				crate_opened.emit()
				GlobalEvents.emit_crate_breached(self)
				loot_search_completed.emit()
				if on_open_inventory.is_valid():
					on_open_inventory.call(),
			func() -> void:
				pass, # Cancelled
			lock_mesh if lock_mesh else self,
			player,
			3.8
		)
	else:
		# Fallback if no donut provided
		set_crate_state(CrateState.UNLOOTED)
		crate_opened.emit()
		GlobalEvents.emit_crate_breached(self)
		loot_search_completed.emit()
		if on_open_inventory.is_valid():
			on_open_inventory.call()

func _flash_damage() -> void:
	if lock_mesh and crate_state == CrateState.LOCKED:
		var mat: StandardMaterial3D = lock_mesh.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 10.0
			get_tree().create_timer(0.08).timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.emission_energy_multiplier = 4.0
			)

func _on_lock_breached() -> void:
	if crate_state == CrateState.UNLOOTED:
		return
	set_crate_state(CrateState.UNLOOTED)
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
