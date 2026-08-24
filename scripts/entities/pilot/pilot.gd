class_name Pilot
extends CharacterBody3D

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

signal pilot_damaged(current_hp: float, delta_hp: float)
signal mounted_sled_changed(is_mounted: bool)

@export var is_mounted_in_sled: bool = false
@export var current_sled: CharacterBody3D = null

@onready var health_component: HealthComponent = $HealthComponent
@onready var thermal_receiver: ThermalReceiverComponent = $ThermalReceiverComponent
@onready var jetpack_component: JetpackComponent = $JetpackComponent
@onready var grapple_component: PilotGrappleComponent = $PilotGrappleComponent
@onready var weapon_socket: WeaponSocketComponent = $WeaponSocketComponent
@onready var backpack_inventory: HexInventoryComponent = $BackpackInventoryComponent
@onready var state_machine: StateMachine = $StateMachine
@onready var hurtbox_component: HurtboxComponent = $HurtboxComponent

func _ready() -> void:
	if health_component:
		health_component.health_changed.connect(func(cur: float, max_hp: float, delta: float) -> void:
			pilot_damaged.emit(cur, delta)
			GlobalEvents.emit_vitality_changed(cur, max_hp)
		)

func _physics_process(delta: float) -> void:
	if is_mounted_in_sled:
		return
	
	if state_machine:
		state_machine.physics_update(delta)
	
	# Update thermal state while on foot
	if thermal_receiver:
		thermal_receiver.update_thermal_state(delta, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pilot_mount_dismount"):
		if is_mounted_in_sled and current_sled:
			dismount_from_sled()
		else:
			_try_mount_nearby_sled()

func mount_into_sled(sled: CharacterBody3D) -> void:
	current_sled = sled
	is_mounted_in_sled = true
	if sled:
		if "is_occupied" in sled:
			sled.set("is_occupied", true)
		var com_comp: CenterOfMassComponent = sled.get_node_or_null("CenterOfMassComponent") as CenterOfMassComponent
		if com_comp:
			com_comp.set_mounted_pilot(self)
			
	if state_machine:
		state_machine.transition_to(&"MountedState")
	GlobalEvents.emit_pilot_mounted_sled(sled)
	mounted_sled_changed.emit(true)

func dismount_from_sled() -> void:
	if not current_sled:
		return
	
	var prev_sled: CharacterBody3D = current_sled
	var sled_base_pos: Vector3 = prev_sled.global_position if prev_sled.is_inside_tree() else prev_sled.position
	var sled_basis_x: Vector3 = prev_sled.global_transform.basis.x if prev_sled.is_inside_tree() else Vector3.RIGHT
	var dismount_pos: Vector3 = sled_base_pos + Vector3(0, 1.2, 0) + (sled_basis_x * 1.5)
	var sled_vel: Vector3 = prev_sled.velocity
	
	is_mounted_in_sled = false
	if prev_sled:
		if "is_occupied" in prev_sled:
			prev_sled.set("is_occupied", false)
		var com_comp: CenterOfMassComponent = prev_sled.get_node_or_null("CenterOfMassComponent") as CenterOfMassComponent
		if com_comp:
			com_comp.clear_mounted_pilot()
			
	current_sled = null
	
	if is_inside_tree():
		global_position = dismount_pos
	else:
		position = dismount_pos
	velocity = sled_vel + Vector3(0, 4.0, 0)
	
	if state_machine:
		var mounted_state: State = state_machine.get_node_or_null("MountedState") as State
		if mounted_state and mounted_state.has_method("dismount"):
			mounted_state.dismount(dismount_pos, velocity)
		else:
			state_machine.transition_to(&"WalkingState")
	
	GlobalEvents.emit_pilot_dismounted_sled(prev_sled)
	mounted_sled_changed.emit(false)

func _try_mount_nearby_sled() -> void:
	var sleds: Array[Node] = get_tree().get_nodes_in_group(&"player_sled")
	for node: Node in sleds:
		if node is CharacterBody3D:
			var dist: float = (node.global_position - global_position).length()
			if dist <= 3.5:
				mount_into_sled(node as CharacterBody3D)
				return
