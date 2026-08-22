# Project Structure and Resource Conventions

Standards for organizing files, folders, and resources in Godot 4 projects.

## Standard Directory Layout

```text
res://
├── assets/                  # Raw binary assets and art files
│   ├── audio/
│   │   ├── music/           # Background music tracks (.ogg, .mp3)
│   │   └── sfx/             # Sound effects (.wav)
│   ├── fonts/               # Font files (.ttf, .otf)
│   ├── models/              # 3D source models (.glb, .gltf)
│   ├── shaders/             # Custom shader files (.gdshader)
│   └── textures/            # Sprites, UI textures, and material maps (.png, .webp)
├── scenes/                  # Packed scene files (.tscn)
│   ├── characters/          # Player, NPC, and enemy scenes
│   ├── components/          # Reusable component scenes (hitboxes, health bars)
│   ├── levels/              # Playable world scenes and stage maps
│   ├── ui/                  # HUD, menus, pause screens, and dialogue boxes
│   └── vfx/                 # Particle emitters and visual effect scenes
├── scripts/                 # Standalone GDScript source files (.gd)
│   ├── autoloads/           # Global singletons (GameManager, AudioManager)
│   ├── components/          # Component script implementations
│   ├── resources/           # Custom Resource class definitions (Data schemas)
│   └── state_machine/       # State machine base and state scripts
└── resources/               # Instantiated resource files (.tres)
    ├── abilities/
    ├── items/
    ├── materials/
    └── themes/
```

## Naming Conventions

| Entity Type | Convention | Example |
| --- | --- | --- |
| Files and Directories | `snake_case` | `player_controller.gd`, `main_menu.tscn`, `iron_sword.tres` |
| Global Classes (`class_name`) | `PascalCase` | `class_name PlayerController extends CharacterBody3D` |
| Autoload Singletons | `PascalCase` | `GameManager`, `AudioManager`, `EventBus` |
| Signals | `snake_case` | `signal health_changed`, `signal item_equipped` |
| Methods and Variables | `snake_case` | `func calculate_damage()`, `var current_velocity` |
| Private / Internal Members | `_snake_case` | `func _update_physics()`, `var _internal_timer` |
| Constants and Enums | `UPPER_SNAKE_CASE` | `const MAX_SPEED = 500.0`, `enum State { IDLE, RUN, JUMP }` |

## Resource Management and Persistent UIDs

Godot 4 utilizes persistent `uid://` identifiers to track asset moves and renames without breaking scene dependencies.

1. **Avoid Hardcoded File Strings**: Reference custom resources and scenes through typed `@export` variables rather than hardcoded string paths in code.
2. **Move Files Inside the Godot FileSystem Dock**: Renaming or moving assets within Godot updates UID mappings across all referencing `.tscn` and `.tres` files automatically.
3. **Use `.tres` for Shared Data**: Store item data, enemy stats, weapon configurations, and dialog trees as custom `Resource` scripts instantiated as `.tres` files.
