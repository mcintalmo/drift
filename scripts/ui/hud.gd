class_name HUD
extends CanvasLayer

const GlobalEvents = preload("res://scripts/autoloads/global_events.gd")

@onready var hp_bar: ProgressBar = get_node_or_null("Control/MarginContainer/VBoxContainer/HealthBar") as ProgressBar
@onready var fuel_bar: ProgressBar = get_node_or_null("Control/MarginContainer/VBoxContainer/FuelBar") as ProgressBar
@onready var banner_label: Label = get_node_or_null("Control/BannerLabel") as Label

var _banner_timer: float = 0.0

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
			show_banner("MOUNTED IN SLED - [Q/E] LEAN - [SPACE] DRIFT - [F] DISMOUNT")
		)
		GlobalEvents.instance.pilot_dismounted_sled.connect(func(_sled: Node) -> void:
			show_banner("ON FOOT - [SPACE] JETPACK - [LMB] BREACH - [G] GRAPPLE")
		)

func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)
		if _banner_timer <= 0.0 and banner_label:
			banner_label.visible = false

func show_banner(text: String) -> void:
	if banner_label:
		banner_label.text = text
		banner_label.visible = true
		_banner_timer = 3.0
