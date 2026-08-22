# Scene Architecture and Node Hierarchy Standards

This document specifies architectural rules for designing modular, scalable, and maintainable Godot 4 scenes.

## The Component Pattern (Composition Over Inheritance)

Deep class inheritance hierarchies create rigid coupling and brittle refactoring. Favor component nodes that encapsulate isolated behaviors.

### Component Design Pattern

A component is a lightweight Node attached as a child to an entity scene root:

```text
Player (CharacterBody2D) [Script: player.gd]
├── CollisionShape2D
├── AnimatedSprite2D
├── HealthComponent (Node) [Script: health_component.gd]
├── MovementComponent (Node) [Script: movement_component.gd]
├── HitboxComponent (Area2D) [Script: hitbox_component.gd]
│   └── CollisionShape2D
└── HurtboxComponent (Area2D) [Script: hurtbox_component.gd]
    └── CollisionShape2D
```

### Component Communication Rules

1. **Components manage their own state**: `HealthComponent` tracks HP and emits `health_depleted`; it does not directly delete the parent entity.
2. **Components read parent context via injection or lookup**: Components can read their parent (`get_parent()`) when explicitly designed to augment a parent node type.
3. **Entities coordinate components**: The entity script connects signals emitted by components and triggers animations, sound effects, or state machine transitions.

## Signal Decoupling: "Call Down, Signal Up"

Maintain strict hierarchical communication boundaries:

- **Calling Down**: A parent node may hold direct references to child nodes and call methods on them (`$HurtboxComponent.enable()`, `$AnimatedSprite2D.play("jump")`).
- **Signaling Up**: Child nodes must not make assumptions about ancestor hierarchy (never use `get_parent().get_parent().get_parent()`). Children emit signals with necessary payload data; ancestors listen and react.
- **Cross-Entity / Sibling Communication**: Entities that do not share a direct parent-child relationship communicate through a global **Event Bus Autoload** singleton or via shared **Custom Resources**.

## Dynamic Node Instantiation and Ownership

When dynamically adding nodes via code that must persist into saved scene files (`.tscn`), set the `owner` property:

```gdscript
func add_persistent_child(scene_root: Node, new_node: Node) -> void:
    scene_root.add_child(new_node)
    # The owner must be set AFTER add_child, pointing to the root of the edited scene
    new_node.owner = scene_root
```

Nodes added via `add_child()` without an assigned `owner` will exist at runtime but will be omitted when serializing the scene to disk.

## Scene Organization Rules

1. **Root Node Class**: The root node of a scene must represent its primary functional type (for example, `CharacterBody3D` for a player or enemy, `CanvasLayer` for a full-screen HUD, `Control` for a UI menu component).
2. **One Script Per Scene**: The root node houses the primary controller script. Child components possess their own dedicated scripts. Generic utility nodes (such as basic `Sprite2D` or `CollisionShape2D`) do not receive custom scripts.
3. **Encapsulation**: Treat scenes as black boxes. Expose clean public methods and signals on the scene root; do not permit external systems to access deep nested children directly.
