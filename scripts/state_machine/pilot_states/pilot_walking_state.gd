class_name PilotWalkingState
extends State

@export var pilot: CharacterBody3D
@export var jetpack: JetpackComponent
@export var grapple: PilotGrappleComponent
@export var weapon_socket: WeaponSocketComponent

const TrainHitchPlatformClass = preload("res://scripts/entities/world/train_hitch_platform.gd")

var _prev_riding_car: TrainCar = null

func physics_update(delta: float) -> void:
	if not pilot:
		return
	
	var riding_car: TrainCar = _get_riding_train_car()
	
	# State transition: Just landed on moving train roof or interior floor from air/grapple
	if riding_car and not _prev_riding_car:
		# Reset horizontal velocity to local frame (standing still on train platform)
		pilot.velocity.x = 0.0
		pilot.velocity.z = 0.0
		pilot.velocity.y = -2.0
	
	# State transition: Just stepped or fell off the train into open air
	if not riding_car and _prev_riding_car and delta > 0.0:
		# Transfer full train forward velocity into the air
		pilot.velocity += (_prev_riding_car.delta_displacement / delta)
		
	_prev_riding_car = riding_car
	
	# Check jetpack / jump trigger
	if Input.is_action_pressed(&"pilot_jump_jetpack") and jetpack and jetpack.has_fuel():
		if riding_car and delta > 0.0:
			# Impart full train platform momentum when launching off the moving platform
			pilot.velocity += (riding_car.delta_displacement / delta)
			_prev_riding_car = null
		transition_requested.emit(&"JetpackState")
		return
	
	# Check grapple trigger (G or RMB)
	if (Input.is_action_just_pressed(&"pilot_wrist_grapple") or Input.is_action_just_pressed(&"winch_quick")) and grapple:
		var cam: Camera3D = pilot.get_viewport().get_camera_3d() if (pilot.is_inside_tree() and pilot.get_viewport()) else null
		var look_dir: Vector3 = -cam.global_transform.basis.z if (cam and cam.is_inside_tree()) else -pilot.global_transform.basis.z
		if grapple.fire_grapple(pilot.global_position + Vector3(0, 1.0, 0), look_dir, pilot.get_world_3d().direct_space_state):
			transition_requested.emit(&"GrapplingState")
			return
		else:
			# Remote Sled Winch Detach trigger while on foot (G or RMB when not grappling onto an anchor)
			var sleds: Array[Node] = pilot.get_tree().get_nodes_in_group(&"player_sled") if pilot.is_inside_tree() else []
			for s_node: Node in sleds:
				var w_comp: Node = s_node.get_node_or_null("SledWinchComponent")
				if w_comp and w_comp.get("is_tethered") == true and w_comp.has_method("detach_tether"):
					w_comp.call("detach_tether")
	
	# Hold-to-Interact Channel (E / F / LMB) for Crates, Doors, and Couplers
	var is_interact_held: bool = (
		Input.is_action_pressed(&"pilot_interact") or 
		Input.is_action_pressed(&"pilot_mount_dismount") or 
		Input.is_action_pressed(&"pilot_melee_breach")
	)
	var donut: ActionProgressDonut = _get_action_donut()
	
	if is_interact_held:
		if donut and not donut.is_channeling:
			var target_interactable: Node = _find_nearby_interact_target()
			if target_interactable:
				if target_interactable is GroundCrate:
					var crate: GroundCrate = target_interactable as GroundCrate
					var inv_ui: HexInventoryUI = _get_inventory_ui()
					crate.interact_loot(pilot, donut, func() -> void:
						if inv_ui:
							inv_ui.open_contextual_inventory()
					)
				elif target_interactable.has_method("interact_plasma_torch"):
					target_interactable.call("interact_plasma_torch", pilot, donut)
	else:
		# Released interact/attack button while channeling -> cancel and reset donut to 0
		if donut and donut.is_channeling:
			donut.cancel_channel()
	
	# Melee weapon slash trigger (tap LMB when not channeling)
	if Input.is_action_just_pressed(&"pilot_melee_breach") and weapon_socket and (not donut or not donut.is_channeling):
		weapon_socket.trigger_attack()
	
	# Query backpack mass and center-of-mass offset
	var backpack_mass: float = 0.0
	var com_offset: Vector2 = Vector2.ZERO
	var backpack: HexInventoryComponent = pilot.get_node_or_null("BackpackInventoryComponent") as HexInventoryComponent
	if backpack:
		backpack_mass = backpack.get_total_items_mass()
		com_offset = backpack.get_com_offset_2d()
	
	# 1. Base movement speed scaling
	var base_walk_speed: float = 5.5
	if backpack_mass > 30.0:
		var extra_mass: float = backpack_mass - 30.0
		base_walk_speed = maxf(2.2, base_walk_speed - (extra_mass * 0.045))
	
	var move_speed: float = base_walk_speed
	# Sprint allowed only if not overburdened (< 65kg backpack)
	if Input.is_action_pressed(&"sprint") and backpack_mass < 65.0:
		move_speed = base_walk_speed * 1.5
	
	var input_dir: Vector2 = Input.get_vector(&"steer_left", &"steer_right", &"brake_reverse", &"accelerate")
	var actual_move_vec: Vector3 = Vector3.ZERO
	
	if input_dir.length() > 0.05:
		var cam: Camera3D = pilot.get_viewport().get_camera_3d() if (pilot.is_inside_tree() and pilot.get_viewport()) else null
		var cam_forward: Vector3 = -cam.global_transform.basis.z if (cam and cam.is_inside_tree()) else Vector3(0, 0, -1)
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
		var cam_right: Vector3 = cam.global_transform.basis.x if (cam and cam.is_inside_tree()) else Vector3(1, 0, 0)
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		
		var intended_move_dir: Vector3 = ((cam_right * input_dir.x) + (cam_forward * input_dir.y)).normalized()
		var char_right: Vector3 = Vector3(-intended_move_dir.z, 0.0, intended_move_dir.x).normalized()
		
		# Imbalance lateral veer (only active when weight is laterally off-center)
		var pull_strength: float = clampf((backpack_mass / 70.0) * 0.35, 0.0, 0.45)
		var body_imbalance_pull: Vector3 = char_right * (com_offset.x / 0.20) * pull_strength
		
		actual_move_vec = (intended_move_dir + body_imbalance_pull).normalized()
		pilot.rotation.y = lerp_angle(pilot.rotation.y, atan2(-actual_move_vec.x, -actual_move_vec.z), 14.0 * delta)
	
	# 2. Moving Train Platform Delta Kinematics
	if riding_car:
		# Delta carry with moving train platform
		if delta > 0.0:
			pilot.global_position += riding_car.delta_displacement
			if absf(riding_car.delta_yaw_rad) > 0.00001:
				pilot.rotate_y(riding_car.delta_yaw_rad)
		
		# Relative locomotion along moving train roof or interior floor
		if input_dir.length() > 0.05:
			var target_vx: float = actual_move_vec.x * move_speed
			var target_vz: float = actual_move_vec.z * move_speed
			pilot.velocity.x = move_toward(pilot.velocity.x, target_vx, 25.0 * delta)
			pilot.velocity.z = move_toward(pilot.velocity.z, target_vz, 25.0 * delta)
		else:
			# Standing still relative to train floor
			pilot.velocity.x = move_toward(pilot.velocity.x, 0.0, 35.0 * delta)
			pilot.velocity.z = move_toward(pilot.velocity.z, 0.0, 35.0 * delta)
		
		pilot.velocity.y = -3.5 # Downward floor snap
		if jetpack:
			jetpack.process_jetpack(delta, false, true, Vector3.ZERO)
			
	else:
		# 3. Ground / Airborne Locomotion (Off Train)
		if not pilot.is_on_floor():
			# Airborne ballistic trajectory
			if input_dir.length() > 0.05:
				pilot.velocity.x += actual_move_vec.x * 12.0 * delta
				pilot.velocity.z += actual_move_vec.z * 12.0 * delta
			pilot.velocity.x = move_toward(pilot.velocity.x, 0.0, 0.8 * delta)
			pilot.velocity.z = move_toward(pilot.velocity.z, 0.0, 0.8 * delta)
			pilot.velocity.y -= 9.81 * delta
		else:
			# On ground snow
			if input_dir.length() > 0.05:
				var target_vx: float = actual_move_vec.x * move_speed
				var target_vz: float = actual_move_vec.z * move_speed
				pilot.velocity.x = move_toward(pilot.velocity.x, target_vx, 18.0 * delta)
				pilot.velocity.z = move_toward(pilot.velocity.z, target_vz, 18.0 * delta)
			else:
				pilot.velocity.x = move_toward(pilot.velocity.x, 0.0, 10.0 * delta)
				pilot.velocity.z = move_toward(pilot.velocity.z, 0.0, 10.0 * delta)
			
			pilot.velocity.y = 0.0
			if jetpack:
				jetpack.process_jetpack(delta, false, true, Vector3.ZERO)
	
	# 4. Procedural Torso Lean:
	var visual_model: Node3D = pilot.get_node_or_null("VisualModel") as Node3D
	if visual_model:
		var target_lean_z: float = -(com_offset.x / 0.20) * deg_to_rad(14.0) * clampf(backpack_mass / 30.0, 0.0, 1.5)
		var top_heavy_amount: float = maxf(0.0, -com_offset.y)
		var target_lean_x: float = (top_heavy_amount / 0.20) * deg_to_rad(12.0) * clampf(backpack_mass / 30.0, 0.0, 1.5)
		visual_model.rotation.z = lerpf(visual_model.rotation.z, target_lean_z, 10.0 * delta)
		visual_model.rotation.x = lerpf(visual_model.rotation.x, target_lean_x, 10.0 * delta)
	
	pilot.move_and_slide()

## Finds nearest interactable crate, door, or coupler within interaction range
func _find_nearby_interact_target() -> Node:
	if not pilot or not pilot.is_inside_tree():
		return null
		
	var p_pos: Vector3 = pilot.global_position
	var min_dist: float = 4.5
	var best_target: Node = null
	
	# 1. Prioritize nearby loot crates inside boxcar or on ground (only if interactable)
	var crates: Array[Node] = pilot.get_tree().get_nodes_in_group(&"loot_crates")
	for c_node: Node in crates:
		if is_instance_valid(c_node) and c_node is GroundCrate:
			var crate: GroundCrate = c_node as GroundCrate
			if crate.crate_state != GroundCrate.CrateState.NON_INTERACTABLE:
				var c_pos: Vector3 = crate.global_position if crate.is_inside_tree() else crate.position
				var dist: float = p_pos.distance_to(c_pos)
				if dist < 3.5 and dist < min_dist:
					min_dist = dist
					best_target = crate
				
	if best_target:
		return best_target
	
	# 2. Check train convoy nodes (Hitch platforms and Boxcars)
	var convoy: Array[Node] = pilot.get_tree().get_nodes_in_group(&"train_convoy")
	for node: Node in convoy:
		if is_instance_valid(node) and node is Node3D:
			var node_3d: Node3D = node as Node3D
			var dist: float = 999.0
			
			if node is TrainCar:
				var car: TrainCar = node as TrainCar
				var p_local: Vector3 = car.global_transform.affine_inverse() * p_pos if car.is_inside_tree() else p_pos - car.position
				# Check proximity to Left door (X=-2.18), Right door (X=+2.18), and coupler/platform center
				var d_left: float = p_local.distance_to(Vector3(-2.18, 2.0, 0.0))
				var d_right: float = p_local.distance_to(Vector3(2.18, 2.0, 0.0))
				var d_center: float = p_local.distance_to(Vector3(0.0, 0.5, 0.0))
				dist = minf(d_left, minf(d_right, d_center))
			else:
				var n_pos: Vector3 = node_3d.global_position if node_3d.is_inside_tree() else node_3d.position
				dist = p_pos.distance_to(n_pos)
				
			if dist < min_dist:
				min_dist = dist
				best_target = node
				
	return best_target

func _get_action_donut() -> ActionProgressDonut:
	if not pilot or not pilot.is_inside_tree():
		return null
	var donuts: Array[Node] = pilot.get_tree().get_nodes_in_group(&"action_donut")
	if not donuts.is_empty() and donuts[0] is ActionProgressDonut:
		return donuts[0] as ActionProgressDonut
	return null

func _get_inventory_ui() -> HexInventoryUI:
	if not pilot or not pilot.is_inside_tree():
		return null
	var uis: Array[Node] = pilot.get_tree().root.find_children("*HexInventoryUI*", "HexInventoryUI", true, false)
	if not uis.is_empty() and uis[0] is HexInventoryUI:
		return uis[0] as HexInventoryUI
	return null

## Detects if the pilot is standing on or riding a TrainCar, CircularHitchPlatform, or inside Boxcar
func _get_riding_train_car() -> TrainCar:
	if not pilot or not pilot.is_inside_tree():
		return null
		
	# 1. Check direct slide collisions on floor
	if pilot.is_on_floor():
		for i: int in range(pilot.get_slide_collision_count()):
			var col: KinematicCollision3D = pilot.get_slide_collision(i)
			if col.get_normal().y > 0.4:
				var collider: Object = col.get_collider()
				var car: TrainCar = _find_train_car(collider)
				if car:
					return car
					
	# 2. Downward probe raycast (within 1.2m below feet)
	var space_state: PhysicsDirectSpaceState3D = pilot.get_world_3d().direct_space_state
	if space_state:
		var start: Vector3 = pilot.global_position + Vector3(0, 0.4, 0)
		var end: Vector3 = pilot.global_position + Vector3(0, -1.2, 0)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
		query.exclude = [pilot.get_rid()]
		var res: Dictionary = space_state.intersect_ray(query)
		if not res.is_empty():
			var norm: Vector3 = res.get("normal", Vector3.UP)
			if norm.y > 0.4:
				var collider: Object = res.get("collider")
				var car: TrainCar = _find_train_car(collider)
				if car:
					return car
				
	# 3. Proximity check within train car roof or interior cabin floor (strictly above platform floor height)
	var convoy: Array[Node] = pilot.get_tree().get_nodes_in_group(&"train_convoy")
	for node: Node in convoy:
		if node is TrainCar and node.visible:
			var car: TrainCar = node as TrainCar
			var local_pos: Vector3 = car.global_transform.affine_inverse() * pilot.global_position
			if car is TrainHitchPlatformClass or car.name.begins_with("CircularHitch") or car.name.begins_with("Hitch"):
				# Hitch turntable circular platform: standing surface at Y >= 0.75
				if Vector2(local_pos.x, local_pos.z).length() <= 1.65 and local_pos.y >= 0.75 and local_pos.y <= 2.8:
					return car
			else:
				# Boxcar / Locomotive: inside cabin (X in [-2.0, 2.0], Z in [-4.6, 4.6], Y in [0.2, 4.0]) or on roof (Y in [4.1, 5.8])
				var is_inside_cabin: bool = absf(local_pos.x) <= 2.0 and absf(local_pos.z) <= 4.6 and local_pos.y >= 0.2 and local_pos.y <= 4.0
				var is_on_roof: bool = absf(local_pos.x) <= 2.2 and absf(local_pos.z) <= 5.0 and local_pos.y >= 4.1 and local_pos.y <= 5.8
				if is_inside_cabin or is_on_roof:
					return car
				
	return null

func _find_train_car(collider: Object) -> TrainCar:
	if not collider or not (collider is Node):
		return null
	var cur: Node = collider as Node
	var depth: int = 0
	while cur and depth < 6:
		if cur is TrainCar:
			return cur as TrainCar
		cur = cur.get_parent()
		depth += 1
	return null

func _extract_body_velocity(collider: Object) -> Vector3:
	var car: TrainCar = _find_train_car(collider)
	if car:
		var fwd: Vector3 = -car.global_transform.basis.z.normalized() if car.is_inside_tree() else -car.transform.basis.z.normalized()
		return fwd * car.forward_speed_ms
	return Vector3.ZERO
