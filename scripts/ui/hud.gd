class_name HUD
extends CanvasLayer

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

@onready var hp_bar: ProgressBar = get_node_or_null("Control/MarginContainer/VBoxContainer/HealthBar") as ProgressBar
@onready var fuel_bar: ProgressBar = get_node_or_null("Control/MarginContainer/VBoxContainer/FuelBar") as ProgressBar
@onready var banner_label: Label = get_node_or_null("Control/BannerLabel") as Label

# Train Directional Indicator Controls
var train_tracker_panel: PanelContainer
var train_tracker_label: Label
var train_tracker_arrow: Control
var _banner_timer: float = 0.0

var active_train_ref: Node = null
var active_camera_ref: Camera3D = null

func _ready() -> void:
	if GlobalEvents.instance:
		GlobalEvents.instance.vitality_changed.connect(func(cur: float, max_hp: float) -> void:
			if hp_bar:
				hp_bar.max_value = max_hp
				hp_bar.value = cur
		)
		GlobalEvents.instance.jetpack_fuel_changed.connect(func(cur: float, max_fuel: float) -> void:
			if fuel_bar:
				fuel_bar.max_value = max_fuel
				fuel_bar.value = cur
		)
		GlobalEvents.instance.crate_breached.connect(func(_crate: Node) -> void:
			show_banner("CRATE BREACHED - LOOT EXPOSED!")
		)
		GlobalEvents.instance.train_car_decoupled.connect(func(car_idx: int) -> void:
			show_banner("TRAIN CAR #%d DECOUPLED!" % car_idx)
		)
		GlobalEvents.instance.pilot_mounted_sled.connect(func(_sled: Node) -> void:
			show_banner("MOUNTED IN SLED - [W/A/S/D] DRIVE - [SPACE] DRIFT - [G / RMB] WINCH - [F] DISMOUNT")
		)
		GlobalEvents.instance.pilot_dismounted_sled.connect(func(_sled: Node) -> void:
			show_banner("ON FOOT - [SPACE] JETPACK - [LMB] BREACH - [G / RMB] GRAPPLE - [F] MOUNT")
		)
		
	_setup_train_tracker_ui()

func _setup_train_tracker_ui() -> void:
	var root: Control = get_node_or_null("Control") as Control
	if not root:
		return
		
	train_tracker_panel = PanelContainer.new()
	train_tracker_panel.name = "TrainTrackerPanel"
	
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.16, 0.85)
	style.border_color = Color(0.2, 1.0, 0.45, 0.9) # Glowing green Corpo tracking border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	train_tracker_panel.add_theme_stylebox_override(&"panel", style)
	
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 8)
	train_tracker_panel.add_child(hbox)
	
	train_tracker_arrow = Control.new()
	train_tracker_arrow.custom_minimum_size = Vector2(18, 18)
	train_tracker_arrow.draw.connect(_on_draw_tracker_arrow)
	hbox.add_child(train_tracker_arrow)
	
	train_tracker_label = Label.new()
	train_tracker_label.text = "TRAIN: --m | EXT: --:--"
	train_tracker_label.add_theme_color_override(&"font_color", Color(0.25, 1.0, 0.5, 1.0))
	train_tracker_label.add_theme_font_size_override(&"font_size", 14)
	hbox.add_child(train_tracker_label)
	
	root.add_child(train_tracker_panel)
	train_tracker_panel.visible = false

var _arrow_angle_rad: float = 0.0

func _on_draw_tracker_arrow() -> void:
	if not train_tracker_arrow:
		return
	var center: Vector2 = Vector2(9, 9)
	var arrow_pts: PackedVector2Array = [
		center + Vector2(7, 0).rotated(_arrow_angle_rad),
		center + Vector2(-6, -5).rotated(_arrow_angle_rad),
		center + Vector2(-3, 0).rotated(_arrow_angle_rad),
		center + Vector2(-6, 5).rotated(_arrow_angle_rad)
	]
	train_tracker_arrow.draw_colored_polygon(arrow_pts, Color(0.2, 1.0, 0.45, 1.0))

func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)
		if _banner_timer <= 0.0 and banner_label:
			banner_label.visible = false
			
	_update_train_tracking()

func _update_train_tracking() -> void:
	if not train_tracker_panel:
		return
		
	if not active_train_ref or not is_instance_valid(active_train_ref):
		var trains: Array[Node] = get_tree().get_nodes_in_group(&"train_convoy")
		if not trains.is_empty():
			active_train_ref = trains[0].get_parent() if trains[0].get_parent() is MovingTrain else trains[0]
			
	if not active_train_ref or not is_instance_valid(active_train_ref):
		train_tracker_panel.visible = false
		return
		
	if not active_camera_ref or not is_instance_valid(active_camera_ref):
		active_camera_ref = get_viewport().get_camera_3d()
		
	if not active_camera_ref:
		train_tracker_panel.visible = false
		return
		
	train_tracker_panel.visible = true
	
	var train_pos: Vector3 = Vector3.ZERO
	if active_train_ref.has_method("get_train_lead_position"):
		train_pos = active_train_ref.get_train_lead_position()
	elif active_train_ref is Node3D:
		train_pos = (active_train_ref as Node3D).global_position
		
	var cam_pos: Vector3 = active_camera_ref.global_position
	var dist_m: float = cam_pos.distance_to(train_pos)
	
	var time_sec: float = 0.0
	if active_train_ref.has_method("get_time_until_extraction_seconds"):
		time_sec = active_train_ref.get_time_until_extraction_seconds()
	var mins: int = int(time_sec) / 60
	var secs: int = int(time_sec) % 60
	
	if train_tracker_label:
		train_tracker_label.text = "TRAIN: %dm | EXT: %02d:%02d" % [int(dist_m), mins, secs]
		
	# Calculate Screen Position / Screen-Edge Clamp
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var screen_pos: Vector2 = active_camera_ref.unproject_position(train_pos)
	var is_behind: bool = active_camera_ref.is_position_behind(train_pos)
	
	var margin: float = 40.0
	var min_x: float = margin
	var max_x: float = viewport_rect.size.x - train_tracker_panel.size.x - margin
	var min_y: float = margin + 30.0
	var max_y: float = viewport_rect.size.y - train_tracker_panel.size.y - margin
	
	var screen_center: Vector2 = viewport_rect.size * 0.5
	if is_behind:
		screen_pos = screen_center - (screen_pos - screen_center)
		
	var clamped_x: float = clampf(screen_pos.x - train_tracker_panel.size.x * 0.5, min_x, max_x)
	var clamped_y: float = clampf(screen_pos.y - train_tracker_panel.size.y * 0.5, min_y, max_y)
	train_tracker_panel.position = Vector2(clamped_x, clamped_y)
	
	# Arrow Direction Vector
	var dir_to_train: Vector2 = (screen_pos - (train_tracker_panel.position + train_tracker_panel.size * 0.5)).normalized()
	_arrow_angle_rad = atan2(dir_to_train.y, dir_to_train.x)
	if train_tracker_arrow:
		train_tracker_arrow.queue_redraw()

func show_banner(text: String) -> void:
	if banner_label:
		banner_label.text = text
		banner_label.visible = true
		_banner_timer = 3.0
