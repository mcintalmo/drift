# GDScript 4.7+ Engineering Standards and Style Guide

This document establishes the official engineering standards for GDScript development in Godot 4.7+. Godot 4 introduced a complete redesign of GDScript; legacy Godot 3 patterns must not be used.

## Static Typing and Type Safety

All GDScript code must use strict static typing for variables, constants, function signatures, and return values. Static typing enables compile-time optimizations, eliminates runtime type errors, and unlocks IDE code completion.

### Variable and Constant Declarations

```gdscript
# Standard typed primitives
var current_health: int = 100
var move_speed: float = 250.0
var character_name: String = "Player"
var is_grounded: bool = true
var look_direction: Vector2 = Vector2.ZERO
var velocity_3d: Vector3 = Vector3.FORWARD

# Typed arrays and dictionaries
var inventory_items: Array[Resource] = []
var nearby_enemies: Array[CharacterBody3D] = []
var spawn_chances: Dictionary = {"common": 0.70, "rare": 0.25, "legendary": 0.05}

# Typed constants
const GRAVITY_DEFAULT: float = 980.0
const MAX_INVENTORY_SLOTS: int = 30
```

### Function Signatures

Every function must declare typed parameters and an explicit return type (use `void` if no value is returned):

```gdscript
func apply_damage(amount: int, damage_type: StringName = &"physical") -> bool:
    if amount <= 0:
        return false
    current_health = maxi(0, current_health - amount)
    health_changed.emit(current_health, max_health)
    if current_health == 0:
        _handle_death()
    return true

func get_movement_vector() -> Vector2:
    return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
```

## Godot 4 Annotations Reference

Use Godot 4 `@` annotations exclusively. Legacy Godot 3 export and modifier keywords are prohibited.

| Annotation | Purpose | Example |
| --- | --- | --- |
| `@export` | Exposes a variable to the Godot Inspector. | `@export var max_health: int = 100` |
| `@export_range(min, max, step)` | Adds a slider control in the Inspector. | `@export_range(0.0, 1000.0, 10.0) var speed: float = 200.0` |
| `@export_enum("A", "B", "C")` | Exposes an enumerated dropdown list. | `@export_enum("Melee", "Ranged", "Magic") var weapon_type: String` |
| `@export_group("Name")` | Groups related inspector properties under a header. | `@export_group("Movement Settings")` |
| `@export_subgroup("Name")` | Nests properties under a sub-header. | `@export_subgroup("Air Control")` |
| `@export_file("*.tscn")` | File path selector restricted to extensions. | `@export_file("*.tscn") var spawn_scene: String` |
| `@onready` | Initializes variable when the node enters the scene tree. | `@onready var sprite: Sprite2D = $Sprite2D` |
| `@icon("res://icon.svg")` | Assigns a custom class icon in the node selector. | `@icon("res://assets/icons/player.svg")` |
| `@tool` | Enables execution inside the Godot Editor viewport. | Placed on line 1 of script |
| `@rpc("any_peer", "call_local")` | Configures multiplayer Remote Procedure Calls. | `@rpc("authority", "call_remote", "reliable")` |
| `@warning_ignore("code")` | Suppresses specific linter/compiler warnings. | `@warning_ignore("unused_parameter")` |

## Godot 3 Syntax to Godot 4 Replacements

| Legacy Godot 3 Syntax | Modern Godot 4 Syntax | Notes |
| --- | --- | --- |
| `yield(target, "signal")` | `await target.signal_name` | GDScript 4 uses native async/await coroutines. |
| `yield(get_tree().create_timer(1.0), "timeout")` | `await get_tree().create_timer(1.0).timeout` | Modern timer suspension. |
| `KinematicBody2D` / `KinematicBody` | `CharacterBody2D` / `CharacterBody3D` | Replaced by unified CharacterBody nodes. |
| `Spatial` | `Node3D` | Renamed for 2D/3D naming parity. |
| `move_and_slide(velocity)` | `velocity = ...; move_and_slide()` | Velocity is now an internal property. |
| `is_on_floor()` with custom normal | Built-in `up_direction` and `floor_normal` | Configured on CharacterBody properties. |
| `instance()` | `instantiate()` | Method renamed on PackedScene. |
| `PoolVector2Array`, `PoolIntArray` | `PackedVector2Array`, `PackedInt32Array` | Renamed to Packed Arrays. |
| `String` literals for actions | `&"action_name"` (`StringName`) | Use StringName literals (`&"..."`) for performance. |
| `connect("signal", target, "method")` | `signal_name.connect(callable)` | Callables are first-class objects. |
| `disconnect("signal", target, "method")` | `signal_name.disconnect(callable)` | Disconnect using Callable references. |

## Signal Declaration and Dispatch

Signals must be declared with explicit parameter types. Always use first-class `Callable` bindings and the `.emit()` method.

```gdscript
class_name HealthComponent
extends Node

# Declare typed signals
signal health_depleted
signal health_modified(current: int, maximum: int, delta: int)

func _ready() -> void:
    # Connect using Callable syntax
    health_modified.connect(_on_health_modified)

func take_damage(amount: int) -> void:
    current_health = maxi(0, current_health - amount)
    health_modified.emit(current_health, max_health, -amount)
    if current_health == 0:
        health_depleted.emit()

func _on_health_modified(current: int, maximum: int, delta: int) -> void:
    print_debug("Health changed by %d to %d/%d" % [delta, current, maximum])
```

## Lambda Functions and Callables

GDScript 4 supports inline anonymous lambdas and first-class callables:

```gdscript
func setup_buttons() -> void:
    for i: int in range(button_container.get_child_count()):
        var btn: Button = button_container.get_child(i) as Button
        if btn:
            btn.pressed.connect(func() -> void: _on_slot_selected(i))

func filter_living_enemies(enemies: Array[Enemy]) -> Array[Enemy]:
    return enemies.filter(func(e: Enemy) -> bool: return e.is_alive())
```

## Memory Management: Nodes vs RefCounted

- **`Node` subclasses** (Node, Node2D, Node3D, Control): Managed manually by the scene tree. Use `queue_free()` to safely delete nodes at the end of the current frame. Never call `free()` directly on nodes during active physics/draw processing.
- **`RefCounted` subclasses** (Resource, Custom Resources, Data Objects): Automatically garbage-collected when all references go out of scope. Do not call `queue_free()` on `RefCounted` objects.
